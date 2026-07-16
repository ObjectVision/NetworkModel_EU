# ============================================================================
# cap_scenario.jl — ladder rungs A/B/C WITHOUT a cost function (doc/topics.md,
# refined per the Lewis/Bernhard scenario definitions).
# ----------------------------------------------------------------------------
# Two scenarios, each minimised over an explicit catchment constraint rather
# than a facility-cost weight w (that is Option D / the lambda sweep):
#
#   S1 "reduce travel, keep #facilities constant": place a FIXED number of
#      pharmacies (TARGET_COUNT, default = today's) to MINIMISE travel, subject
#      to a max catchment cap so the optimum doesn't collapse every dense cell
#      to one pharmacy and scatter the rest across the countryside.
#
#   S2 "reduce #facilities, keep travel constant": MINIMISE the number of
#      pharmacies subject to a MIN catchment threshold (each open pharmacy needs
#      enough customers to be viable) and the same max cap; travel is reported
#      against today and may optionally be hard-bounded (TRAVEL_SLACK).
#
# Rungs (set by the s1_cap.jl / s2_cap.jl drivers via PER_CELL + URBAN_POP):
#   A  multiple pharmacies per grid cell allowed  -> x[j] integer >= 0
#   B  at most one pharmacy per grid cell         -> x[j] in {0,1}
#   C  urban-centre pharmacies held FIXED, only the rest is modelled
#      -> cells whose own population >= URBAN_POP are fixed open (one per cell)
#         and excluded from the optimisation (for S1 this is rung C; for S2 this
#         is rung B "reduce only outside urban centres").
#
# The candidate set is one inhabited cell per row (every inhabited cell is a
# candidate), so "which pharmacies are used" (all / rural-only) is still chosen
# by CANDIDATE_DIR; the A/B multi-vs-one distinction is the x[j] upper bound,
# and urban is derived from each cell's own population (a coordinate join to the
# client table) — no extra GeoDMS export needed.
#
# Reuses settings.jl / lp_run.jl (CountryData, c(t), Arrow loaders); controlled
# entirely by environment variables, like lambda_sweep.jl.
#
# Environment variables
#   COUNTRIES       study areas (default from settings.jl)
#   CANDIDATE_DIR   candidate pharmacy data dir (default <proj>/NewPharmacies);
#                   point at a rural-only export to scope the analysis
#   EXISTING_DIR    observed-pharmacy dir for the baseline (default ExistingPharmacies)
#   SCENARIO        S1 | S2   (objective; also the output label)
#   PER_CELL        multi | one   (rung A vs B; S2 normally one)
#   URBAN_POP       cell own-population threshold for "urban" (0 = off = rung A/B;
#                   >0 = rung C/S2-B: fix urban cells, model the rest)
#   MAX_CAP         max catchment per pharmacy, residents ("Inf" = off; list = sweep)
#   MIN_CAP         min catchment per pharmacy, residents (S2; "0" = off; list = sweep)
#   TARGET_COUNT    S1 fixed pharmacy count (default = baseline cells used; for
#                   rung A set it to the raw pharmacy count to allow real packing)
#   TRAVEL_SLACK    S2 optional hard bound: served travel <= baseline*(1+slack)
#                   ("" = off, report only)
#   MULTI_MAX       rung-A cap on pharmacies per cell (default 8)
#   TRAVEL_FUNC     travel-cost function c(t) via settings.jl
#   WRITE_ARROW     "1" to write open-set + per-client traveltime arrows (default 1)
# ============================================================================

include("lp_run.jl")          # -> settings.jl (c, CountryData, COUNTRIES, paths)

using LinearAlgebra
LinearAlgebra.BLAS.set_num_threads(Sys.CPU_THREADS)

pln(args...) = (println(args...); flush(stdout))

const PROJ          = LOCAL_DATA_PROJ_DIR
const CANDIDATE_DIR = get(ENV, "CANDIDATE_DIR", joinpath(PROJ, "NewPharmacies"))
const EXISTING_DIR  = get(ENV, "EXISTING_DIR",  joinpath(PROJ, "ExistingPharmacies"))
const SCENARIO      = uppercase(get(ENV, "SCENARIO", "S1"))
const PER_CELL      = Symbol(lowercase(get(ENV, "PER_CELL", SCENARIO == "S1" ? "multi" : "one")))
const URBAN_POP     = parse(Float64, get(ENV, "URBAN_POP", "0"))
const MULTI_MAX     = parse(Int,     get(ENV, "MULTI_MAX", "8"))
const WRITE_ARROW   = get(ENV, "WRITE_ARROW", "1") == "1"
const TRAVEL_SLACK  = haskey(ENV, "TRAVEL_SLACK") && ENV["TRAVEL_SLACK"] != "" ?
                          parse(Float64, ENV["TRAVEL_SLACK"]) : nothing

parse_cap(s) = (uppercase(strip(s)) in ("INF", "INFINITY")) ? Inf : parse(Float64, s)
caplist(name, default) = parse_cap.(split(get(ENV, name, default)))
const MIN_CAPS = caplist("MIN_CAP", "0")
const MAX_CAPS = caplist("MAX_CAP", "Inf")

# --- loaders (dir-based, mirroring lambda_sweep.jl) + per-cell population -----
function load_dir(dir, country; apply_factor::Bool)
    od  = Arrow.Table(joinpath(dir, "$(country)_od.arrow"))
    loc = Arrow.Table(joinpath(dir, "$(country)_i.arrow"))
    fac = Arrow.Table(joinpath(dir, "$(country)_j.arrow"))

    factor         = apply_factor ? LOCATION_SELECTION_FACTOR : 1
    facilities_all = Int.(fac[:id])
    facilities     = facilities_all[1:factor:length(facilities_all)]
    fset           = Set(facilities)
    od_facrel_all  = Int.(od[:facility_rel])
    mask           = factor == 1 ? trues(length(od_facrel_all)) :
                                   [f in fset for f in od_facrel_all]

    clients_col    = Int.(od[:client_rel])[mask]
    facilities_col = od_facrel_all[mask]
    t_ij_col       = (od[:t_ij] ./ 60)[mask]
    population     = client_weight_col(loc)

    N = length(clients_col)
    M = length(facilities)
    wpop = [population[clients_col[k]+1] for k in 1:N]

    locations = Dict{Int, Vector{Int}}()
    for k in 1:N
        i = clients_col[k]
        haskey(locations, i) ? push!(locations[i], k) : (locations[i] = [k])
    end
    facility_rows = Dict{Int, Vector{Int}}()
    for k in 1:N
        j = facilities_col[k]
        haskey(facility_rows, j) || (facility_rows[j] = Int[])
        push!(facility_rows[j], k)
    end
    for j in facilities
        haskey(facility_rows, j) || (facility_rows[j] = Int[])
    end
    client_pop = Dict(i => population[i+1] for i in keys(locations))

    nearest_facility = Dict{Int, Int}()
    for (i, rows) in locations
        best_k = rows[argmin(c(t_ij_col[k]) for k in rows)]
        nearest_facility[i] = facilities_col[best_k]
    end

    data = CountryData(N, M, facilities, wpop, clients_col, t_ij_col, facilities_col,
                       locations, facility_rows, client_pop, nearest_facility)

    # own-cell population per candidate cell, by (x,y) join to the client table
    # (used to classify urban cells for rung C). Candidates with no co-located
    # client (uninhabited reachable cells) get 0 -> always rural.
    fjx, fjy = Float64.(fac[:x]), Float64.(fac[:y])
    cix, ciy = Float64.(loc[:x]), Float64.(loc[:y])
    cpop     = Float64.(loc[:total_pop])
    popxy    = Dict((cix[k], ciy[k]) => cpop[k] for k in 1:length(cix))
    fac_id   = Int.(fac[:id])
    own_pop  = Dict(fac_id[k] => get(popxy, (fjx[k], fjy[k]), 0.0) for k in 1:length(fac_id))
    return data, own_pop
end

function baseline_metrics(data)
    total_c = 0.0; total_t = 0.0; used = Set{Int}()
    for (_, rows) in data.locations
        best_k = rows[argmin(data.t_ij_col[k] for k in rows)]
        total_c += c(data.t_ij_col[best_k]) * data.wpop[best_k]
        total_t += data.t_ij_col[best_k] * data.wpop[best_k]
        push!(used, data.facilities_col[best_k])
    end
    total_pop = sum(data.wpop[rows[1]] for (_, rows) in data.locations)
    return (cost_c=total_c, time_total=total_t, mean_t=total_t/total_pop,
            n_used=length(used), total_pop=total_pop)
end

pctile(sorted, p) = isempty(sorted) ? 0.0 :
    sorted[clamp(round(Int, p * (length(sorted) - 1)) + 1, 1, length(sorted))]

# Silence the bundled IPX solver (prints even with output_flag off); restores
# stdout even if optimize! throws.
solve_quiet!(model) = redirect_stdout(devnull) do; optimize!(model); end

function check_status(model, tag)
    ts = termination_status(model)
    if ts in (INFEASIBLE, INFEASIBLE_OR_UNBOUNDED)
        error("$tag infeasible — relax the caps / target, or enrich candidates.")
    elseif ts ∉ (OPTIMAL, LOCALLY_SOLVED, ALMOST_OPTIMAL)
        error("$tag did not solve (status=$ts).")
    end
end

# --- the LP relaxation -------------------------------------------------------
# Shared structure for S1 and S2. x[j] upper bound encodes rung A (multi: <=
# MULTI_MAX) vs B (one: <= 1); urban-fixed cells are pinned to x[j] == 1. A
# stranded slack s[i] (priced at BIG = big_cost(), the same stranded-client price
# as the λ-sweep; earlier NL ladder runs used the region's c(t_max)) keeps the model feasible and
# turns "the cap forbids serving this demand" into a reported strand% instead of
# an infeasible LP.
#   S1: minimise travel (+ strand) s.t. sum(x) == target_count.
#   S2: lexicographic — minimise count (+ strand), then travel at that count;
#       optional served-travel <= travel_bound.
function solve_relax(data, own_pop, min_cap, max_cap, target_count, travel_bound)
    (; N, facilities, wpop, t_ij_col, facilities_col, locations, facility_rows, client_pop) = data

    BIG        = big_cost()
    client_ids = collect(keys(locations))
    urban      = URBAN_POP > 0 ? Set(j for j in facilities if get(own_pop, j, 0.0) >= URBAN_POP) :
                                 Set{Int}()
    # Per-cell pharmacy ceiling. Rung A (multi) lets a cell hold as many pharmacies
    # as its OWN population needs under the cap — ceil(pop/cap) — so a cell only
    # ever gets a 2nd pharmacy when one genuinely can't cover it. This avoids the
    # LP degenerately doubling cells the cap doesn't bind (which made A strand more
    # and look worse than B). One-per-cell rungs and the Inf cap stay at 1.
    ubound(j)  = j in urban ? 1 :
                 (PER_CELL == :multi && isfinite(max_cap) ?
                     clamp(ceil(Int, get(own_pop, j, 0.0) / max_cap), 1, MULTI_MAX) : 1)

    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "presolve", "on")
    set_optimizer_attribute(model, "output_flag", false)
    set_optimizer_attribute(model, "log_to_console", false)
    set_optimizer_attribute(model, "solver", "ipm")
    set_optimizer_attribute(model, "run_crossover", "on")

    @variable(model, 0 <= y[1:N] <= 1)
    @variable(model, x[j in facilities])
    @variable(model, 0 <= s[i in client_ids] <= 1)
    for j in facilities
        set_lower_bound(x[j], j in urban ? 1.0 : 0.0)   # urban fixed open
        set_upper_bound(x[j], Float64(ubound(j)))
    end

    @expression(model, strand, sum(s[i] * BIG * client_pop[i] for i in client_ids))
    @expression(model, travel, sum(y[k] * c(t_ij_col[k]) * wpop[k] for k in 1:N))
    @expression(model, nfac,   sum(x[j] for j in facilities))

    for (i, rows) in locations
        @constraint(model, sum(y[k] for k in rows) + s[i] == 1)
    end
    for k in 1:N
        @constraint(model, y[k] <= x[facilities_col[k]])
    end
    for j in facilities
        isempty(facility_rows[j]) && continue
        load_j = @expression(model, sum(y[k] * wpop[k] for k in facility_rows[j]))
        isfinite(max_cap)          && @constraint(model, load_j <= max_cap * x[j])
        (min_cap > 0 && !(j in urban)) && @constraint(model, load_j >= min_cap * x[j])
    end
    travel_bound === nothing || @constraint(model, travel <= travel_bound)

    if SCENARIO == "S1"
        @constraint(model, nfac == target_count)
        @objective(model, Min, travel + strand)
        solve_quiet!(model); check_status(model, "S1 LP")
    else
        @objective(model, Min, nfac + strand)
        solve_quiet!(model); check_status(model, "S2 count LP")
        K = clamp(ceil(Int, value(nfac) - 1e-6), 1, MULTI_MAX * length(facilities))
        @constraint(model, nfac <= K)
        @objective(model, Min, travel + strand)
        solve_quiet!(model); check_status(model, "S2 travel LP")
    end

    x_relaxed = Dict(j => value(x[j]) for j in facilities)
    return (x_relaxed=x_relaxed, sum_x=value(nfac), travel_relax=value(travel), urban=urban)
end

# Round x to integer pharmacy counts per cell. urban cells stay >= 1. For S1 the
# total is forced to exactly target_count; for S2 it is round(sum_x).
function round_open(x_relaxed, data, urban, own_pop, max_cap, target_count)
    facs = data.facilities
    ub(j) = j in urban ? 1 :
            (PER_CELL == :multi && isfinite(max_cap) ?
                clamp(ceil(Int, get(own_pop, j, 0.0) / max_cap), 1, MULTI_MAX) : 1)

    # Largest-remainder rounding: floor(x) gives the integer part, then the
    # +1s go to the cells with the largest fractional remainder — preserving the
    # LP's spatial distribution. (The earlier "round then add to highest-x cells"
    # doubled up the densest cells, which for fixed-count multi-per-cell made A
    # WORSE than one-per-cell: a 2nd pharmacy in an already-served cell cuts no
    # travel, while opening a fresh cell does.)
    m = Dict{Int,Int}()
    for j in facs
        b = clamp(floor(Int, x_relaxed[j] + 1e-9), 0, ub(j))
        j in urban && (b = max(b, 1))
        m[j] = b
    end
    cur    = sum(values(m))
    target = target_count === nothing ? max(cur, round(Int, sum(x_relaxed[j] for j in facs))) : target_count

    if cur < target
        rema = sort([j for j in facs if m[j] < ub(j)], by = j -> x_relaxed[j] - floor(x_relaxed[j]), rev = true)
        for j in rema
            cur >= target && break
            m[j] += 1; cur += 1
        end
        if cur < target   # residuals exhausted (multi headroom) — top up by x desc
            for j in sort(facs, by = jj -> x_relaxed[jj], rev = true)
                cur >= target && break
                if m[j] < ub(j); m[j] += 1; cur += 1; end
            end
        end
    elseif cur > target   # over (can happen via urban pinning) — drop lowest-x non-urban
        for j in sort([jj for jj in facs if m[jj] > 0 && !(jj in urban)], by = jj -> x_relaxed[jj])
            cur <= target && break
            m[j] -= 1; cur -= 1
        end
    end
    return Dict(j => v for (j, v) in m if v > 0)
end

# --- assignment for a fixed open set (with per-cell multiplicity) ------------
# Minimise served travel; stranded demand priced at BIG. Capacity of an open
# cell = mult * max_cap (rung A lets a dense cell hold several pharmacies).
function assign(open_mult, data, max_cap, BIG)
    (; wpop, t_ij_col, facilities_col, locations, facility_rows, client_pop) = data
    open_set  = keys(open_mult)
    rows_open = Dict(i => [k for k in rows if facilities_col[k] in open_set]
                     for (i, rows) in locations)
    open_rows  = collect(Iterators.flatten(values(rows_open)))
    client_ids = collect(keys(locations))

    m = Model(HiGHS.Optimizer)
    set_optimizer_attribute(m, "presolve", "on")
    set_optimizer_attribute(m, "output_flag", false)
    set_optimizer_attribute(m, "log_to_console", false)
    set_optimizer_attribute(m, "solver", "ipm")
    set_optimizer_attribute(m, "run_crossover", "on")

    @variable(m, 0 <= y[k in open_rows] <= 1)
    @variable(m, 0 <= s[i in client_ids] <= 1)
    @objective(m, Min,
        sum(y[k] * c(t_ij_col[k]) * wpop[k] for k in open_rows) +
        sum(s[i] * BIG * client_pop[i] for i in client_ids))
    for (i, ro) in rows_open
        @constraint(m, sum(y[k] for k in ro) + s[i] == 1)
    end
    if isfinite(max_cap)
        for j in open_set
            isempty(facility_rows[j]) && continue
            @constraint(m, sum(y[k] * wpop[k] for k in facility_rows[j]) <= max_cap * open_mult[j])
        end
    end
    solve_quiet!(m); check_status(m, "assignment LP")

    yv    = Dict(k => value(y[k]) for k in open_rows)
    loads = Dict(j => sum(yv[k] * wpop[k] for k in facility_rows[j] if haskey(yv, k); init=0.0)
                 for j in open_set)
    travel_served = sum(yv[k] * c(t_ij_col[k]) * wpop[k] for k in open_rows; init=0.0)
    served_pop    = sum(yv[k] * wpop[k] for k in open_rows; init=0.0)
    tw_time       = sum(yv[k] * t_ij_col[k] * wpop[k] for k in open_rows; init=0.0)
    mean_t        = served_pop > 0 ? tw_time / served_pop : 0.0

    stranded_pop = 0.0
    for i in client_ids
        si = value(s[i]); si > 1e-6 && (stranded_pop += si * client_pop[i])
    end
    travel_honest = travel_served + stranded_pop * BIG

    assigned_k = Dict{Int,Int}()
    for (i, ro) in rows_open
        isempty(ro) && continue
        best_k = ro[argmax(yv[k] for k in ro)]
        yv[best_k] > 1e-6 && (assigned_k[i] = best_k)
    end
    return (loads=loads, travel_honest=travel_honest, stranded_pop=stranded_pop,
            mean_t=mean_t, assigned_k=assigned_k)
end

# --- per-(country, cap-combo) driver ----------------------------------------
function header()
    pln(rpad("scen", 6), rpad("rung", 6), rpad("min_cap", 9), rpad("max_cap", 9),
        rpad("n_pharm", 8), rpad("n_cells", 8), rpad("base", 7), rpad("sum_x", 8),
        rpad("travel", 13), rpad("base_trav", 13), rpad("dtravel%", 9),
        rpad("mean_t", 8), rpad("strand%", 8), rpad("urban_fx", 9),
        rpad("below_min", 10), rpad("load_p50", 9), rpad("load_p90", 9), rpad("load_max", 9))
end

function rung_label()
    if SCENARIO == "S1"
        URBAN_POP > 0 && return "C"            # urban fixed, model the rest
        return PER_CELL == :multi ? "A" : "B"  # multi vs one per cell
    else                                        # S2: A = global, B = outside urban only
        return URBAN_POP > 0 ? "B" : "A"
    end
end

function run_combo(country, data, own_pop, base, min_cap, max_cap, target_count)
    BIG = big_cost()
    travel_bound = (SCENARIO == "S2" && TRAVEL_SLACK !== nothing) ?
                       base.cost_c * (1 + TRAVEL_SLACK) : nothing
    rel = solve_relax(data, own_pop, min_cap, max_cap, target_count, travel_bound)
    open_mult = round_open(rel.x_relaxed, data, rel.urban, own_pop, max_cap,
                           SCENARIO == "S1" ? target_count : nothing)
    asg = assign(open_mult, data, max_cap, BIG)

    n_pharm = sum(values(open_mult))
    n_cells = length(open_mult)
    urban_fx = count(j -> j in rel.urban, keys(open_mult))
    # per-PHARMACY catchment (cell load split over its mult pharmacies) — this is
    # what the cap constrains, so the distribution/max stay <= max_cap.
    pploads = sort([asg.loads[j] / open_mult[j] for j in keys(open_mult)])
    n_below_min  = min_cap > 0 ? count(j -> !(j in rel.urban) && open_mult[j] == 1 &&
                                            asg.loads[j] < min_cap - 1e-6, keys(open_mult)) : 0
    strand_pct = base.total_pop > 0 ? asg.stranded_pop / base.total_pop * 100 : 0.0
    dtravel    = (asg.travel_honest - base.cost_c) / base.cost_c * 100

    pln(rpad(SCENARIO, 6), rpad(rung_label(), 6),
        rpad(min_cap == 0 ? "-" : string(round(Int, min_cap)), 9),
        rpad(isfinite(max_cap) ? string(round(Int, max_cap)) : "Inf", 9),
        rpad(n_pharm, 8), rpad(n_cells, 8), rpad(base.n_used, 7),
        rpad(round(rel.sum_x, digits=1), 8),
        rpad(round(asg.travel_honest, digits=0), 13),
        rpad(round(base.cost_c, digits=0), 13),
        rpad(round(dtravel, digits=2), 9),
        rpad(round(asg.mean_t, digits=3), 8),
        rpad(round(strand_pct, digits=3), 8),
        rpad(urban_fx, 9), rpad(n_below_min, 10),
        rpad(round(pctile(pploads, 0.50), digits=0), 9),
        rpad(round(pctile(pploads, 0.90), digits=0), 9),
        rpad(round(isempty(pploads) ? 0.0 : pploads[end], digits=0), 9))

    if WRITE_ARROW
        outdir = joinpath(CANDIDATE_DIR, country, "cap",
            "$(SCENARIO)_$(rung_label())_min$(round(Int,min_cap))_max$(isfinite(max_cap) ? round(Int,max_cap) : 0)")
        mkpath(outdir)
        Arrow.write(joinpath(outdir, "assignment.arrow"),
                    (id = data.facilities, open = [get(open_mult, j, 0) for j in data.facilities]))
        ids = sort(collect(keys(asg.assigned_k)))
        Arrow.write(joinpath(outdir, "traveltime.arrow"),
                    (id = ids, t_ij = [data.t_ij_col[asg.assigned_k[i]] for i in ids]))
    end
end

function analyze_country(country)
    pln(); pln("=" ^ 110)
    pln("Country: $country   scenario $SCENARIO   rung $(rung_label())   per_cell=$PER_CELL   urban_pop=$URBAN_POP")
    pln("=" ^ 110)
    pln("Candidates: $CANDIDATE_DIR")
    pln("Baseline:   $EXISTING_DIR")

    existing, _      = load_dir(EXISTING_DIR,  country; apply_factor=false)
    data, own_pop    = load_dir(CANDIDATE_DIR, country; apply_factor=true)
    base             = baseline_metrics(existing)
    target_count     = haskey(ENV, "TARGET_COUNT") ? parse(Int, ENV["TARGET_COUNT"]) : base.n_used
    pln("  candidates: N=$(data.N) OD rows, M=$(data.M) cells")
    pln("  baseline:   $(base.n_used) cells used, total pop $(round(Int, base.total_pop)), " *
        "travel(c) $(round(base.cost_c, digits=0)), mean_t $(round(base.mean_t, digits=3)) min")
    SCENARIO == "S1" && pln("  S1 target #pharmacies: $target_count")

    pln(); header()
    for max_cap in MAX_CAPS, min_cap in MIN_CAPS
        try
            run_combo(country, data, own_pop, base, min_cap, max_cap, target_count)
        catch e
            pln("  [min_cap=$min_cap max_cap=$max_cap] FAILED: $(sprint(showerror, e))")
        end
    end
end

for country in COUNTRIES
    try
        analyze_country(country)
    catch e
        pln("\n$country — failed: $e")
        showerror(stdout, e, catch_backtrace()); flush(stdout)
    end
end
