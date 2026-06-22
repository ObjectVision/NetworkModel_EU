# ============================================================================
# cap_scenario.jl — capacitated min-count facility location (ladder rungs A/B)
# ----------------------------------------------------------------------------
# This is the *primary* ladder mechanism from doc/topics.md, NOT the Option-D
# lambda sweep. Instead of trading travel against a facility-cost weight w, it
# answers: "how FEW pharmacies do we need so that everyone is served and no
# pharmacy's catchment exceeds MAX_CAP residents (S1) — and, for S2, no open
# pharmacy serves fewer than MIN_CAP residents either?"
#
# It is controlled exactly like lambda_sweep.jl — through environment variables,
# reusing settings.jl / lp_run.jl (CountryData, the c(t) travel-cost function,
# the Arrow loaders). The two scenario drivers s1_cap.jl / s2_cap.jl just set
# scenario-appropriate defaults and `include` this file; run_cap_scenarios.bat
# drives them for the Netherlands.
#
# Environment variables
#   COUNTRIES       space-separated study areas (default from settings.jl)
#   CANDIDATE_DIR   pharmacy candidate-data dir (default <proj>/NewPharmacies).
#                   *** This is how "which pharmacies are used" is controlled ***:
#                   point it at an all-pharmacies export, or at a rural-only
#                   export, or at a one-per-cell (rung B) vs multi-per-cell
#                   (rung A) export. The script just optimises over whatever
#                   <country>_{od,i,j}.arrow it finds there.
#   EXISTING_DIR    observed-pharmacy dir for the baseline reference
#                   (default <proj>/ExistingPharmacies)
#   MIN_CAP         min catchment (residents) per OPEN pharmacy — hard threshold.
#                   "0" = off (S1). Space-separated list = sweep several values.
#   MAX_CAP         max catchment (residents) per pharmacy — the cap. "Inf" = off.
#                   Space-separated list = sweep several values.
#   SCENARIO        label used in console output + arrow output paths (e.g. S1/S2)
#   TRAVEL_FUNC     travel-cost function c(t), via settings.jl (LINEAR/LOGISTIC/…)
#   REPAIR_ITERS    max capacity-repair LP re-solves after rounding (default 40)
#   WRITE_ARROW     "1" to also write an open-set + per-client traveltime arrow
#                   for mapping (default "1")
# ============================================================================

include("lp_run.jl")          # -> settings.jl (c, CountryData, COUNTRIES, paths)

using LinearAlgebra
LinearAlgebra.BLAS.set_num_threads(Sys.CPU_THREADS)

pln(args...) = (println(args...); flush(stdout))

const PROJ            = LOCAL_DATA_PROJ_DIR
const CANDIDATE_DIR   = get(ENV, "CANDIDATE_DIR", joinpath(PROJ, "NewPharmacies"))
const EXISTING_DIR    = get(ENV, "EXISTING_DIR",  joinpath(PROJ, "ExistingPharmacies"))
const SCENARIO        = get(ENV, "SCENARIO", "cap")
const REPAIR_ITERS    = parse(Int,     get(ENV, "REPAIR_ITERS", "40"))
const WRITE_ARROW     = get(ENV, "WRITE_ARROW", "1") == "1"

parse_cap(s) = (uppercase(strip(s)) in ("INF", "INFINITY")) ? Inf : parse(Float64, s)
caplist(envname, default) = parse_cap.(split(get(ENV, envname, default)))

const MIN_CAPS = caplist("MIN_CAP", "0")
const MAX_CAPS = caplist("MAX_CAP", "Inf")

# --- loaders (dir-based, mirroring lambda_sweep.jl) --------------------------
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

    return CountryData(N, M, facilities, wpop, clients_col, t_ij_col, facilities_col,
                       locations, facility_rows, client_pop, nearest_facility)
end

# Baseline: each client served by its nearest OBSERVED pharmacy (the reference
# the S1/S2 results are compared against — same as lambda_sweep.jl).
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

# Silence the bundled IPX solver, which prints to stdout even with HiGHS'
# output_flag/log_to_console off. Restores stdout even if optimize! throws.
solve_quiet!(model) = redirect_stdout(devnull) do; optimize!(model); end

function check_status(model, min_cap, max_cap)
    ts = termination_status(model)
    if ts in (INFEASIBLE, INFEASIBLE_OR_UNBOUNDED)
        error("infeasible at max_cap=$max_cap, min_cap=$min_cap — the caps cannot be met " *
              "for all reachable demand. Raise MAX_CAP / lower MIN_CAP, or enrich candidates.")
    elseif ts ∉ (OPTIMAL, LOCALLY_SOLVED, ALMOST_OPTIMAL)
        error("cap LP (min_cap=$min_cap, max_cap=$max_cap) did not solve (status=$ts).")
    end
end

# --- phase 1: capacitated min-count placement (lexicographic, two solves) ----
# Solve A — minimise the facility COUNT (+ stranded-demand penalty).
# Solve B — minimise TRAVEL among solutions using no more facilities than A.
# Both objectives are single-scale, so the LP stays well-conditioned (no tiny
# tie-break weight): A places no premium on travel, B then picks, of all
# minimum-count covers, the one with the least travel — "as few as the cap
# allows, placed optimally". A stranded slack s[i] (priced at BIG = c(t_max))
# makes the model ALWAYS feasible: demand that cannot be served within
# [min_cap, max_cap] (a dense cell above the cap, or a remote cluster too small
# to clear the min threshold) is stranded rather than crashing the LP, and
# surfaces as the reported strand%.
function solve_cap_relax(data, min_cap, max_cap)
    (; N, facilities, wpop, t_ij_col, facilities_col, locations, facility_rows, client_pop) = data

    BIG        = c(maximum(t_ij_col))
    client_ids = collect(keys(locations))

    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "presolve", "on")
    set_optimizer_attribute(model, "output_flag", false)
    set_optimizer_attribute(model, "log_to_console", false)
    set_optimizer_attribute(model, "solver", "ipm")
    set_optimizer_attribute(model, "run_crossover", "on")

    @variable(model, 0 <= y[1:N] <= 1)
    @variable(model, 0 <= x[j in facilities] <= 1)
    @variable(model, 0 <= s[i in client_ids] <= 1)   # stranded fraction of client i

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
        isfinite(max_cap) && @constraint(model, load_j <= max_cap * x[j])
        min_cap > 0        && @constraint(model, load_j >= min_cap * x[j])
    end

    # Solve A: minimum count (stranding dominates so coverage comes first).
    @objective(model, Min, nfac + strand)
    solve_quiet!(model); check_status(model, min_cap, max_cap)
    K = clamp(ceil(Int, value(nfac) - 1e-6), 1, length(facilities))

    # Solve B: minimum travel, using no more than K facilities (warm-started).
    @constraint(model, nfac <= K)
    @objective(model, Min, travel + strand)
    solve_quiet!(model); check_status(model, min_cap, max_cap)

    x_relaxed = value.(x)
    tol = 1e-6
    sum_x        = sum(x_relaxed[j] for j in facilities)
    travel_relax = value(travel)
    n_frac       = sum(tol < x_relaxed[j] < 1 - tol for j in facilities)
    return (x_relaxed=x_relaxed, sum_x=sum_x, travel_relax=travel_relax, n_frac=n_frac, K=K)
end

# --- phase 2: capacitated assignment LP for a FIXED open set ----------------
# Minimise served travel; a client with no open candidate within reach (or
# squeezed out by the cap) is priced at BIG = c(t_max) via a stranded slack, so
# the metric is coverage-honest and the LP is always feasible. Returns honest
# travel, served/stranded population, per-facility loads, mean travel time, the
# dominant per-client assignment, and the set of stranded clients.
function assign_capacitated(open_set, data, max_cap, BIG)
    (; wpop, t_ij_col, facilities_col, locations, facility_rows, client_pop) = data

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
    @variable(m, 0 <= s[i in client_ids] <= 1)      # stranded fraction of client i

    @objective(m, Min,
        sum(y[k] * c(t_ij_col[k]) * wpop[k] for k in open_rows) +
        sum(s[i] * BIG * client_pop[i] for i in client_ids))

    for (i, ro) in rows_open
        @constraint(m, sum(y[k] for k in ro) + s[i] == 1)
    end
    if isfinite(max_cap)
        for j in open_set
            isempty(facility_rows[j]) && continue
            @constraint(m, sum(y[k] * wpop[k] for k in facility_rows[j]) <= max_cap)
        end
    end

    solve_quiet!(m)
    ts = termination_status(m)
    ts in (OPTIMAL, LOCALLY_SOLVED, ALMOST_OPTIMAL) ||
        error("assignment LP did not solve (status=$ts).")

    yv = Dict(k => value(y[k]) for k in open_rows)
    loads = Dict(j => sum(yv[k] * wpop[k] for k in facility_rows[j] if haskey(yv, k); init=0.0)
                 for j in open_set)

    travel_served = sum(yv[k] * c(t_ij_col[k]) * wpop[k] for k in open_rows; init=0.0)
    served_pop    = sum(yv[k] * wpop[k] for k in open_rows; init=0.0)
    tw_time       = sum(yv[k] * t_ij_col[k] * wpop[k] for k in open_rows; init=0.0)
    mean_t        = served_pop > 0 ? tw_time / served_pop : 0.0

    stranded = Set{Int}(); stranded_pop = 0.0
    for i in client_ids
        si = value(s[i])
        if si > 1e-6
            push!(stranded, i)
            stranded_pop += si * client_pop[i]
        end
    end
    travel_honest = travel_served + stranded_pop * BIG

    # dominant assignment per (non-stranded) client, for the mapping arrow
    assigned_k = Dict{Int,Int}()
    for (i, ro) in rows_open
        isempty(ro) && continue
        best_k = ro[argmax(yv[k] for k in ro)]
        yv[best_k] > 1e-6 && (assigned_k[i] = best_k)
    end

    return (loads=loads, travel_served=travel_served, travel_honest=travel_honest,
            served_pop=served_pop, stranded_pop=stranded_pop, mean_t=mean_t,
            stranded=stranded, assigned_k=assigned_k)
end

# Cheap, LP-free pre-pass: ensure every client has at least one open, reachable
# facility (so the assignment LP usually runs once; residual capacity stranding
# is then handled by the repair loop below).
function ensure_coverage!(open_set, data, sorted_by_x)
    (; locations, facility_rows, clients_col) = data
    covered = Set{Int}()
    for j in open_set, k in facility_rows[j]
        push!(covered, clients_col[k])
    end
    uncovered = Set(i for i in keys(locations) if !(i in covered))
    for j in sorted_by_x
        isempty(uncovered) && break
        j in open_set && continue
        jc = Set(clients_col[k] for k in facility_rows[j])
        if !isdisjoint(jc, uncovered)
            push!(open_set, j); setdiff!(uncovered, jc)
        end
    end
    return open_set
end

# Round the relaxed x to an open set of the LP-relaxed size (the top round(sum_x)
# facilities by x — honouring phase-1's consolidation rather than flooding with
# small ones), then assign.
#
# force_coverage (S1, min_cap == 0): there is no reason to leave anyone unserved
# except a binding max cap, so add facilities for any unreachable client and run
# a repair loop that opens the closed candidate reaching the most stranded demand
# until no one is stranded (bounded by REPAIR_ITERS).
#
# NOT force_coverage (S2, min_cap > 0): stranding is a *legitimate* outcome — a
# remote cluster too small to clear the min threshold is meant to stay unserved
# rather than spawn a sub-threshold pharmacy. Forcing coverage here would re-open
# exactly the tiny facilities the min threshold is designed to prevent and blow
# the count past phase-1's consolidated size. So we round to round(sum_x) and
# assign once, honouring phase-1's stranding; below_min / strand% report the gap.
function round_and_assign(x_relaxed, sum_x, data, max_cap, BIG, force_coverage)
    (; facilities, facility_rows, clients_col, client_pop) = data
    sorted_by_x = sort(collect(facilities), by=j -> x_relaxed[j], rev=true)

    p_open   = clamp(round(Int, sum_x), 1, length(facilities))
    open_set = Set(sorted_by_x[1:p_open])

    if !force_coverage
        return open_set, assign_capacitated(open_set, data, max_cap, BIG)
    end

    ensure_coverage!(open_set, data, sorted_by_x)
    local res
    for _ in 0:REPAIR_ITERS
        res = assign_capacitated(open_set, data, max_cap, BIG)
        isempty(res.stranded) && break
        best_j, best_gain = -1, 0.0
        for j in sorted_by_x
            j in open_set && continue
            g = 0.0
            for k in facility_rows[j]
                clients_col[k] in res.stranded && (g += client_pop[clients_col[k]])
            end
            g > best_gain && ((best_j, best_gain) = (j, g))
        end
        best_j == -1 && break
        push!(open_set, best_j)
    end
    return open_set, res
end

# --- per-(country, cap-combo) driver ----------------------------------------
function header()
    pln(rpad("scenario", 10), rpad("min_cap", 10), rpad("max_cap", 10),
        rpad("n_open", 8), rpad("base_cells", 11), rpad("sum_x", 9),
        rpad("travel", 14), rpad("base_travel", 14), rpad("dtravel%", 10),
        rpad("mean_t", 8), rpad("strand%", 9), rpad("below_min", 10),
        rpad("load_p50", 10), rpad("load_p90", 10), rpad("load_max", 10))
end

function run_combo(country, data, base, min_cap, max_cap)
    BIG = c(maximum(data.t_ij_col))
    rel = solve_cap_relax(data, min_cap, max_cap)
    open_set, asg = round_and_assign(rel.x_relaxed, rel.sum_x, data, max_cap, BIG, min_cap == 0)

    loads_sorted = sort(collect(values(asg.loads)))
    n_below_min  = min_cap > 0 ? count(<(min_cap - 1e-6), loads_sorted) : 0
    strand_pct   = base.total_pop > 0 ? asg.stranded_pop / base.total_pop * 100 : 0.0
    dtravel_pct  = (asg.travel_honest - base.cost_c) / base.cost_c * 100

    pln(rpad(SCENARIO, 10),
        rpad(min_cap == 0 ? "-" : string(round(Int, min_cap)), 10),
        rpad(isfinite(max_cap) ? string(round(Int, max_cap)) : "Inf", 10),
        rpad(length(open_set), 8), rpad(base.n_used, 11),
        rpad(round(rel.sum_x, digits=1), 9),
        rpad(round(asg.travel_honest, digits=0), 14),
        rpad(round(base.cost_c, digits=0), 14),
        rpad(round(dtravel_pct, digits=2), 10),
        rpad(round(asg.mean_t, digits=3), 8),
        rpad(round(strand_pct, digits=3), 9),
        rpad(n_below_min, 10),
        rpad(round(pctile(loads_sorted, 0.50), digits=0), 10),
        rpad(round(pctile(loads_sorted, 0.90), digits=0), 10),
        rpad(round(isempty(loads_sorted) ? 0.0 : loads_sorted[end], digits=0), 10))

    if WRITE_ARROW
        outdir = joinpath(CANDIDATE_DIR, country, "cap",
                          "$(SCENARIO)_min$(round(Int,min_cap))_max$(isfinite(max_cap) ? round(Int,max_cap) : 0)")
        mkpath(outdir)
        open_vec = [j in open_set ? 1 : 0 for j in data.facilities]
        Arrow.write(joinpath(outdir, "assignment.arrow"),
                    (id = data.facilities, open = open_vec))
        ids = sort(collect(keys(asg.assigned_k)))
        Arrow.write(joinpath(outdir, "traveltime.arrow"),
                    (id = ids, t_ij = [data.t_ij_col[asg.assigned_k[i]] for i in ids]))
    end
    return (min_cap=min_cap, max_cap=max_cap, n_open=length(open_set),
            travel=asg.travel_honest, mean_t=asg.mean_t,
            stranded_pct=strand_pct, n_below_min=n_below_min, loads=loads_sorted)
end

function analyze_country(country)
    pln(); pln("=" ^ 100); pln("Country: $country   (scenario $SCENARIO)"); pln("=" ^ 100)
    pln("Candidates: $CANDIDATE_DIR")
    pln("Baseline:   $EXISTING_DIR")

    existing = load_dir(EXISTING_DIR,  country; apply_factor=false)
    data     = load_dir(CANDIDATE_DIR, country; apply_factor=true)
    base     = baseline_metrics(existing)
    pln("  candidates: N=$(data.N) OD rows, M=$(data.M) facilities")
    pln("  baseline:   $(base.n_used) pharmacies used, total pop $(round(Int, base.total_pop)), " *
        "travel(c) $(round(base.cost_c, digits=0)), mean_t $(round(base.mean_t, digits=3)) min")

    pln(); header()
    for max_cap in MAX_CAPS, min_cap in MIN_CAPS
        try
            run_combo(country, data, base, min_cap, max_cap)
        catch e
            pln("  [combo min_cap=$min_cap max_cap=$max_cap] FAILED: $(sprint(showerror, e))")
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
