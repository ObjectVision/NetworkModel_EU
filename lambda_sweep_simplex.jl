include("lp_run.jl")

pln(args...) = (println(args...); flush(stdout))

# Sequential warm-start sweep using HiGHS dual simplex. One JuMP model per
# country, reused across all w values; HiGHS warm-starts each subsequent
# solve from the previous optimal basis. No parallelism, no MAX_PARALLEL.

const RAW_PHARMACY_COUNTS = Dict("Netherlands" => 1992)
const EXISTING_PATH = joinpath(LOCAL_DATA_PROJ_DIR, "ExistingPharmacies")
const NEW_PATH      = joinpath(LOCAL_DATA_PROJ_DIR, "NewPharmacies")

# --- Spatially-explicit output for MapView -----------------------------------
# Each sweep point persists two Arrow files under a folder tagged with the
# travel-cost function and λ, so scenarios never overwrite each other and the
# LINEAR/QUADRATIC/LOGISTIC variants stay separable. The full path carries
# FacilityType (the ExistingPharmacies/NewPharmacies leaf of base_dir),
# StudyArea (country), travel-cost function and lambda (the w-tagged folder):
#   <base_dir>\<country>\lambda_sweep\<travel_func>\<w_label>\assignment.arrow  (id, open)
#   <base_dir>\<country>\lambda_sweep\<travel_func>\<w_label>\traveltime.arrow  (id, t_ij)
# w_label is "w=<w>" for sweep points and "baseline" for the existing situation.
# λ = w * FACILITY_MIN_COSTS (linear); folders are keyed by w as the primary knob.
function sweep_dir(base_dir, country, w_label)
    dir = joinpath(base_dir, country, "lambda_sweep", travel_func_name, w_label)
    mkpath(dir)
    return dir
end

# Facility openness (id, open): open=1 for facilities in open_set, else 0.
# (Inf-min_clients / nearest case here, so no <min_clients tier as in lp.jl.)
function write_assignment_arrow(dir, facilities, open_set)
    open_vec = [j in open_set ? 1 : 0 for j in facilities]
    Arrow.write(joinpath(dir, "assignment.arrow"), (id = facilities, open = open_vec))
end

# Per-client travel time (id = location/client_rel id, t_ij = minutes to its
# assigned open facility). Sorted by id to match lp.jl's convention.
function write_traveltime_arrow(dir, t_ij_col, assigned_k)
    sorted_ids = sort(collect(keys(assigned_k)))
    Arrow.write(joinpath(dir, "traveltime.arrow"), (
        id   = sorted_ids,
        t_ij = [t_ij_col[assigned_k[i]] for i in sorted_ids],
    ))
end

# Write a scenario result (r carries open_set + assigned_k) under a label folder.
function write_scenario_arrows(country, new_data, r, label)
    dir = sweep_dir(NEW_PATH, country, label)
    write_assignment_arrow(dir, new_data.facilities, r.open_set)
    write_traveltime_arrow(dir, new_data.t_ij_col, r.assigned_k)
end

# New-pharmacy sweep point: openness over candidate facilities + per-client time.
write_sweep_arrows(country, new_data, r) = write_scenario_arrows(country, new_data, r, "w=$(r.w)")

# Baseline (existing pharmacies, each client → nearest existing pharmacy by time).
# Mirrors baseline_metrics: nearest by raw travel time, not c(t).
function write_baseline_arrows(country, existing)
    dir = sweep_dir(EXISTING_PATH, country, "baseline")
    used       = Set{Int}()
    assigned_k = Dict{Int, Int}()
    for (i, rows) in existing.locations
        best_k = rows[argmin(existing.t_ij_col[k] for k in rows)]
        push!(used, existing.facilities_col[best_k])
        assigned_k[i] = best_k
    end
    write_assignment_arrow(dir, existing.facilities, used)
    write_traveltime_arrow(dir, existing.t_ij_col, assigned_k)
end

function load_from(dir, country; apply_factor::Bool=true)::CountryData
    od  = Arrow.Table(joinpath(dir, "$(country)_od.arrow"))
    loc = Arrow.Table(joinpath(dir, "$(country)_i.arrow"))
    fac = Arrow.Table(joinpath(dir, "$(country)_j.arrow"))

    factor         = apply_factor ? LOCATION_SELECTION_FACTOR : 1
    facilities_all = Int.(fac[:id])
    facilities     = facilities_all[1:factor:length(facilities_all)]
    fset           = Set(facilities)
    od_facrel_all  = Int.(od[:facility_rel])
    mask           = factor == 1 ? trues(length(od_facrel_all)) :
                                   [f ∈ fset for f in od_facrel_all]

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

# Coverage-consistent baseline (doc/todo.md B3). Clients that cannot reach ANY
# existing pharmacy within the OD (present in the candidate-side OD, absent from the
# existing-side OD) are priced exactly like the scenario calculations price stranding:
# BIG = 1.0 for LOGISTIC (the saturation value), c(t_max of the data) otherwise
# (LINEAR: c_max = t_max). Their travel time enters at t_max. This puts the baseline ★
# on the same problem as the frontier — previously those clients were silently dropped
# (DK ~11%, ITG ~15% of residents), understating baseline travel and letting the ★
# sit below/left of the LP bound. Clients absent from BOTH ODs stay invisible.
function baseline_metrics(existing, new_data)
    total_c = 0.0
    total_t = 0.0
    used = Set{Int}()
    for (i, rows) in existing.locations
        best_k = rows[argmin(existing.t_ij_col[k] for k in rows)]
        total_c += c(existing.t_ij_col[best_k]) * existing.wpop[best_k]
        total_t += existing.t_ij_col[best_k] * existing.wpop[best_k]
        push!(used, existing.facilities_col[best_k])
    end
    covered_pop = sum(existing.wpop[rows[1]] for (_, rows) in existing.locations)
    t_max = maximum(new_data.t_ij_col)
    BIG   = travel_func == FUNC_LOGISTIC ? 1.0 : c(t_max)
    stranded_pop = 0.0
    n_stranded   = 0
    for (i, _) in new_data.locations
        haskey(existing.locations, i) && continue
        p = new_data.client_pop[i]
        stranded_pop += p
        n_stranded   += 1
        total_c += BIG * p
        total_t += t_max * p
    end
    total_pop = covered_pop + stranded_pop
    return (cost_c=total_c, time_total=total_t, mean_t=total_t/total_pop,
            n_used=length(used), total_pop=total_pop,
            n_stranded=n_stranded, stranded_pop=stranded_pop, big=BIG)
end

function find_bracket(results, target, getter, descending)
    for i in 1:length(results)-1
        a, b = getter(results[i]), getter(results[i+1])
        lo, hi = descending ? (b, a) : (a, b)
        if lo <= target <= hi
            return (results[i].w, results[i+1].w)
        end
    end
    return nothing
end

function print_sweep_header(target_raw)
    pln(rpad("w", 12), rpad("λ (€)", 14), rpad("sum_x", 12),
        rpad("travel_relax", 16), rpad("travel_topp", 16), rpad("travel_greedy", 16), rpad("travel_multi", 16),
        rpad("n_open", 10), rpad("fac_€", 14),
        rpad("mean_t", 10), rpad("frac_x", 10),
        rpad("n-cells", 10),
        target_raw === nothing ? "" : "n-raw")
end

function print_sweep_row(r, target_cells, target_raw)
    fac_eur = r.sum_x * FACILITY_MIN_COSTS
    n_raw_delta = target_raw === nothing ? "" : string(r.n_open - target_raw)
    pln(rpad(round(r.w, sigdigits=5), 12), rpad(round(r.λ, digits=2), 14), rpad(round(r.sum_x, digits=2), 12),
        rpad(round(r.travel_relax, digits=0), 16),
        rpad(round(r.travel_c_topp, digits=0), 16),
        rpad(round(r.travel_c_greedy, digits=0), 16),
        rpad(round(r.travel_c_multi, digits=0), 16),
        rpad(r.n_open, 10), rpad(round(fac_eur, digits=0), 14),
        rpad(round(r.mean_t, digits=4), 10), rpad(r.n_frac, 10),
        rpad(r.n_open - target_cells, 10),
        n_raw_delta)
end

function analyze_country(country)
    pln()
    pln("=" ^ 90)
    pln("Country: $country (warm-start simplex)")
    pln("=" ^ 90)

    pln("Loading ExistingPharmacies/$country ...")
    existing = load_from(EXISTING_PATH, country; apply_factor=false)
    pln("  N=$(existing.N) OD rows, M=$(existing.M) facilities")

    pln("Loading NewPharmacies/$country ...")
    new_data = load_from(NEW_PATH, country)
    pln("  N=$(new_data.N) OD rows, M=$(new_data.M) candidate facilities")

    base = baseline_metrics(existing, new_data)
    target_cells = base.n_used
    target_raw   = get(RAW_PHARMACY_COUNTS, country, nothing)

    pln()
    pln("Baseline (ExistingPharmacies, each client → nearest pharmacy; unreachable priced at BIG):")
    pln("  facilities used (cells):     $(target_cells) (of $(existing.M))")
    target_raw === nothing || pln("  raw pharmacy count:          $target_raw (external reference)")
    pln("  total travel cost(c):        $(round(base.cost_c, digits=0))")
    pln("  facility cost @ €$(FACILITY_MIN_COSTS) ea: $(round(target_cells * FACILITY_MIN_COSTS, digits=0))")
    pln("  mean travel time (min):      $(round(base.mean_t, digits=4))")
    pln("  total client population:     $(round(Int, base.total_pop))")
    pln("  unreachable clients:         $(base.n_stranded) cells / $(round(Int, base.stranded_pop)) residents priced at BIG=$(round(base.big, digits=4)) (coverage-consistent)")

    write_baseline_arrows(country, existing)
    pln("  baseline arrows → $(sweep_dir(EXISTING_PATH, country, "baseline"))")

    pln()
    pln("Building LP (once) ...")
    t_build = @elapsed state = build_lp_warmstart(new_data)
    pln("  built in $(round(t_build, digits=1)) s")

    function run_lp(w)
        t = @elapsed r = try
            solve_at_w!(state, w)
        catch e
            pln("  LP at w=$w FAILED: $(sprint(showerror, e))")
            return nothing
        end
        pln("  solved w=$w in $(round(t, digits=1)) s")
        write_sweep_arrows(country, new_data, r)
        return r
    end

    pln()
    pln("Common λ sweep (sequential warm-start simplex, 1-2-5 per decade, NO early stop):")
    pln("  the SAME grid is solved for every region so a full run gives the aggregate")
    pln("  frontier complete common-λ support (doc/todo.md B4).")
    print_sweep_header(target_raw)

    # Fixed common grid, identical for every region/country: 1-2-5 per decade,
    # 1e-4 … 5.0. Any region-dependent stopping rule (the old "stop when travel_c
    # exceeds baseline") truncates the intersection of swept λ's — one early-stopping
    # region (Belgium at w=0.1) capped the whole aggregate curve.
    ws_common = Float64[m * 10.0^d for d in -4:0 for m in (1.0, 2.0, 5.0)]

    results = []
    for w in ws_common
        r = run_lp(w)
        r === nothing && continue
        push!(results, r)
        print_sweep_row(r, target_cells, target_raw)
    end
    sort!(results, by=x->x.w)

    bracket_S1 = find_bracket(results, target_cells, r -> r.sum_x, true)

    # Region-specific upward extension if S1 is still unbracketed after the common
    # grid: raise λ (×2.5) while sum_x keeps decreasing materially. A plateau with
    # sum_x above the baseline count means the full-coverage floor exceeds today's
    # count — structural (needs the soft-coverage MIP, todo B5), not a grid problem.
    if bracket_S1 === nothing && !isempty(results)
        pln()
        pln("S1 (sum_x=$target_cells) not bracketed on the common grid — extending λ upward:")
        print_sweep_header(target_raw)
        w = maximum(getfield.(results, :w))
        prev_sx = minimum(getfield.(results, :sum_x))
        while w < 1000.0
            w *= 2.5
            r = run_lp(w)
            r === nothing && break
            push!(results, r)
            print_sweep_row(r, target_cells, target_raw)
            r.sum_x <= target_cells && break
            if prev_sx - r.sum_x < max(1.0, 0.001 * prev_sx)
                pln("  → sum_x plateaued at $(round(r.sum_x, digits=1)) > target $target_cells: full-coverage floor above the baseline count (structural).")
                break
            end
            prev_sx = r.sum_x
        end
        sort!(results, by=x->x.w)
        bracket_S1 = find_bracket(results, target_cells, r -> r.sum_x, true)
    end

    bracket_S2 = find_bracket(results, base.cost_c,  r -> r.cost_c, false)

    if bracket_S1 === nothing && bracket_S2 === nothing
        pln("\nNeither S1 (sum_x=$target_cells) nor S2 (cost=$(round(base.cost_c,digits=0))) found in coarse range.")
        pln("Skipping fine sweep for $country.")
        return
    end

    candidate_los = filter(!isnothing, [bracket_S1 === nothing ? nothing : bracket_S1[1],
                                         bracket_S2 === nothing ? nothing : bracket_S2[1]])
    candidate_his = filter(!isnothing, [bracket_S1 === nothing ? nothing : bracket_S1[2],
                                         bracket_S2 === nothing ? nothing : bracket_S2[2]])
    w_lo = minimum(candidate_los)
    w_hi = maximum(candidate_his)

    pln()
    pln("Fine λ sweep over w in [$w_lo, $w_hi]")
    pln("  bracket S1 (sum_x=$target_cells): $(bracket_S1)")
    pln("  bracket S2 (cost=$(round(base.cost_c, digits=0))): $(bracket_S2)")
    print_sweep_header(target_raw)

    # 1-2-5 per partial decade across the bracket range (each w in (w_lo, w_hi) exclusive)
    log_lo = log10(w_lo); log_hi = log10(w_hi)
    ws_fine = Float64[]
    d = floor(Int, log_lo)
    while d <= ceil(Int, log_hi)
        for mult in (1.0, 2.0, 5.0)
            w_candidate = mult * 10.0^d
            if w_lo < w_candidate < w_hi
                push!(ws_fine, w_candidate)
            end
        end
        d += 1
    end
    sort!(ws_fine)
    for w in ws_fine
        r = run_lp(w)
        r === nothing && continue
        push!(results, r)
        print_sweep_row(r, target_cells, target_raw)
    end
    sort!(results, by=x->x.w)

    # --- S2 bisection: resolve the baseline-travel crossing ------------------
    # The 1-2-5 grid is too coarse near cost_c ≈ base.cost_c, so under
    # multistart's lower travel S1 and S2 collapse onto the same sweep row.
    # Bisect the S2 bracket geometrically (cost_c rises with w) to land a row
    # with cost_c ≈ baseline, distinct from S1. Bisection (not a uniform dense
    # grid) keeps the count of expensive high-w solves small with early exit.
    bracket_S2_fine = find_bracket(results, base.cost_c, r -> r.cost_c, false)
    if bracket_S2_fine !== nothing
        lo, hi = bracket_S2_fine
        seen_ws = Set(round.(getfield.(results, :w), sigdigits=8))
        pln()
        pln("S2 bisection over w in ($lo, $hi) to resolve cost_c ≈ baseline=$(round(base.cost_c, digits=0)):")
        print_sweep_header(target_raw)
        for _ in 1:6
            wmid = sqrt(lo * hi)                       # geometric midpoint
            round(wmid, sigdigits=8) in seen_ws && break
            push!(seen_ws, round(wmid, sigdigits=8))
            r = run_lp(wmid)
            r === nothing && break
            push!(results, r)
            print_sweep_row(r, target_cells, target_raw)
            r.cost_c < base.cost_c ? (lo = wmid) : (hi = wmid)
            abs(r.cost_c - base.cost_c) / base.cost_c < 0.005 && break
        end
        sort!(results, by=x->x.w)
    end

    pln()
    pln("Combined sweep, sorted by w:")
    print_sweep_header(target_raw)
    for r in results
        print_sweep_row(r, target_cells, target_raw)
    end

    function closest(results, target, key)
        results[argmin(abs(getfield(r, key) - target) for r in results)]
    end

    pln()
    pln("=" ^ 90)
    pln("$country — scenario summary")
    pln("=" ^ 90)

    s1 = closest(results, target_cells, :sum_x)
    pln("\nS1 — closest to sum_x = $target_cells (baseline cells):")
    pln("  w = $(round(s1.w, sigdigits=5))   λ = $(round(s1.λ, digits=2)) €")
    pln("  sum_x         : $(round(s1.sum_x, digits=2))      (target $target_cells)")
    pln("  n_open        : $(s1.n_open)         frac_x: $(s1.n_frac)")
    pln("  travel_relax  : $(round(s1.travel_relax, digits=0))     (LP1 with all fractional x)")
    pln("  travel_topp   : $(round(s1.travel_c_topp, digits=0))   greedy: $(round(s1.travel_c_greedy, digits=0))   multi: $(round(s1.travel_c_multi, digits=0))")
    pln("  stranded      : topp $(s1.uncov_topp)   greedy $(s1.uncov_greedy)   multi $(s1.uncov_multi)")
    pln("  travel_c ($(s1.rounding)): $(round(s1.cost_c, digits=0))     (selected; baseline $(round(base.cost_c, digits=0)))")
    pln("  travel change (ph2): $(round((s1.cost_c - base.cost_c)/base.cost_c * 100, digits=2))%")
    pln("  facility €    : $(round(s1.sum_x * FACILITY_MIN_COSTS, digits=0))     (baseline $(round(target_cells * FACILITY_MIN_COSTS, digits=0)))")
    pln("  mean t (min)  : $(round(s1.mean_t, digits=4))    (baseline $(round(base.mean_t, digits=4)))")

    s2 = closest(results, base.cost_c, :cost_c)
    pln("\nS2 — closest to travel_c (ph2) = $(round(base.cost_c, digits=0)) (baseline):")
    pln("  w = $(round(s2.w, sigdigits=5))   λ = $(round(s2.λ, digits=2)) €")
    pln("  sum_x         : $(round(s2.sum_x, digits=2))      (baseline cells $target_cells)")
    pln("  n_open        : $(s2.n_open)         frac_x: $(s2.n_frac)")
    pln("  travel_relax  : $(round(s2.travel_relax, digits=0))     (LP1 with all fractional x)")
    pln("  travel_topp   : $(round(s2.travel_c_topp, digits=0))   greedy: $(round(s2.travel_c_greedy, digits=0))   multi: $(round(s2.travel_c_multi, digits=0))")
    pln("  stranded      : topp $(s2.uncov_topp)   greedy $(s2.uncov_greedy)   multi $(s2.uncov_multi)")
    pln("  travel_c ($(s2.rounding)): $(round(s2.cost_c, digits=0))     (selected; baseline $(round(base.cost_c, digits=0)))")
    pln("  travel change (ph2): $(round((s2.cost_c - base.cost_c)/base.cost_c * 100, digits=2))%")
    pln("  facility €    : $(round(s2.sum_x * FACILITY_MIN_COSTS, digits=0))     (baseline $(round(target_cells * FACILITY_MIN_COSTS, digits=0)))")
    pln("  fewer than cells (by sum_x): $(round(target_cells - s2.sum_x, digits=2))  ($(round((target_cells - s2.sum_x)/target_cells * 100, digits=2))%)")
    if target_raw !== nothing
        pln("  fewer than raw   (by sum_x): $(round(target_raw - s2.sum_x, digits=2))  ($(round((target_raw - s2.sum_x)/target_raw * 100, digits=2))%)")
    end
    pln("  mean t (min)  : $(round(s2.mean_t, digits=4))    (baseline $(round(base.mean_t, digits=4)))")

    # Stable S1/S2 folders so the .dms references labels, not region/func-specific w.
    write_scenario_arrows(country, new_data, s1, "S1")
    write_scenario_arrows(country, new_data, s2, "S2")
    pln("\n  S1 arrows → $(sweep_dir(NEW_PATH, country, "S1"))  (w=$(s1.w))")
    pln("  S2 arrows → $(sweep_dir(NEW_PATH, country, "S2"))  (w=$(s2.w))")
end

for country in COUNTRIES
    try
        analyze_country(country)
    catch e
        pln("\n$country — failed: $e")
        showerror(stdout, e, catch_backtrace())
        flush(stdout)
    end
end
