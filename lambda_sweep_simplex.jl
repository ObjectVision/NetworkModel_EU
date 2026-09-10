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

    # ALWAYS keep candidate cells that coincide with an existing (baseline) pharmacy
    # when subsampling — a blind stride drops most baseline locations (FRI factor=3 kept
    # only 35%), so the frontier can no longer reproduce the current network, stops
    # dominating the baseline, and S1/S2 land on the wrong side. Only non-baseline extras
    # are strided. Env PROTECT_BASELINE=0 restores the blind stride. (This is the loader
    # the sweep actually uses — the settings.jl load_country has the same guard.)
    factor         = apply_factor ? LOCATION_SELECTION_FACTOR : 1
    # Region exclusion (issue #49): drop candidate locations in NUTS regions that the
    # rule below excludes, so an uncoverable region contributes neither demand nor supply.
    excl, excl_level, _ = excluded_nuts_regions(country)
    facilities_all = Int.(fac[:id])
    if !isempty(excl)
        facmask = in_excluded_region(fac, excl, excl_level)
        facilities_all = facilities_all[.!facmask]
    end
    expath         = joinpath(LOCAL_DATA_PROJ_DIR, "ExistingPharmacies", "$(country)_j.arrow")
    if factor > 1 && get(ENV, "PROTECT_BASELINE", "1") == "1" &&
       isfile(expath) && (:x in propertynames(fac))
        exj  = Arrow.Table(expath)
        base = Set(zip(Int.(round.(collect(exj.x))), Int.(round.(collect(exj.y)))))
        fx   = Int.(round.(collect(fac[:x]))); fy = Int.(round.(collect(fac[:y])))
        isb  = [(fx[i], fy[i]) in base for i in eachindex(facilities_all)]
        rest = facilities_all[.!isb]
        facilities = sort(unique(vcat(facilities_all[isb], rest[1:factor:end])))
        @info "load_from($country): protected $(count(isb)) baseline candidates; kept " *
              "$(length(facilities)) of $(length(facilities_all)) (factor=$factor)"
    else
        facilities = facilities_all[1:factor:length(facilities_all)]
    end
    fset           = Set(facilities)
    od_facrel_all  = Int.(od[:facility_rel])
    # The factor==1 shortcut assumed `facilities` is the FULL candidate set. Region
    # exclusion (issue #49) also removes candidates, so OD rows may reference a
    # facility that is no longer in the LP's index set -- which surfaced as
    # KeyError(0) when building y[j]. Filter whenever the set was reduced at all.
    reduced        = factor != 1 || length(facilities) != length(Int.(fac[:id]))
    mask           = reduced ? [f ∈ fset for f in od_facrel_all] :
                               trues(length(od_facrel_all))

    clients_col    = Int.(od[:client_rel])[mask]
    facilities_col = od_facrel_all[mask]
    t_ij_col       = (od[:t_ij] ./ 60)[mask]
    population     = collect(client_weight_col(loc))
    if !isempty(excl)
        # zero the weight of every client in an excluded region: it then contributes
        # nothing to travel cost, nothing to the BIG penalty, and nothing to the
        # reported client population -- in the baseline and in the sweep alike.
        cmask = in_excluded_region(loc, excl, excl_level)
        population[cmask] .= 0
    end

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
    BIG   = big_cost()                    # fixed 120-min cutoff (LINEAR) / 1.0 (LOGISTIC)
    stranded_pop = 0.0
    n_stranded   = 0
    for (i, _) in new_data.locations
        haskey(existing.locations, i) && continue
        p = new_data.client_pop[i]
        # A cell with zero modelled demand is OUT OF SCOPE, not stranded: it is
        # either in a region the exclusion rule dropped (issue #49) or carries no
        # population. Counting it inflated the reported unreachable CELL count while
        # contributing nothing to cost, time or population -- so the cell figure
        # disagreed with the resident figure next to it.
        p == 0 && continue
        stranded_pop += p
        n_stranded   += 1
        total_c += BIG * p
        total_t += MAX_TRAVELTIME_MIN * p   # stranded clients enter mean-time at the 120-min cutoff
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
    pln(rpad("w", 12), rpad("λ (€)", 14), rpad("sum_y", 12),
        rpad("travel_relax", 16), rpad("travel_topp", 16), rpad("travel_greedy", 16), rpad("travel_multi", 16),
        rpad("n_open", 10), rpad("fac_€", 14),
        rpad("mean_t", 10), rpad("frac_y", 10),
        rpad("n-cells", 10),
        target_raw === nothing ? "" : "n-raw")
end

function print_sweep_row(r, target_cells, target_raw)
    fac_eur = r.sum_y * FACILITY_MIN_COSTS
    n_raw_delta = target_raw === nothing ? "" : string(r.n_open - target_raw)
    pln(rpad(round(r.w, sigdigits=5), 12), rpad(round(r.λ, digits=2), 14), rpad(round(r.sum_y, digits=2), 12),
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

    # Fixed common grid PER TRAVEL FUNCTION. LINEAR and LOGISTIC live on ~100×-different λ
    # scales — logistic c(t)∈[0,1] makes the travel objective tiny, so facilities dominate at
    # far lower λ. 1-2-5 per decade from 1e-4 up to w_max, identical for every region ⇒ the
    # aggregate gets full common-λ support. Under SOFT coverage (2026-07-10) the frontier no
    # longer stops at a full-coverage floor — as λ rises the LP strands ever more remote
    # clients, so sum_y keeps falling toward 0 and the curve runs down past the existing-
    # facility count. w_max must therefore reach high enough λ that both S1 (baseline count)
    # and S2 (baseline cost) bracket even for the ex-"structural" regions (ITG/PT/PL8):
    # LINEAR 5.0 (ITG: sum_y 178 @ w5, cost 1.75e8 > baseline 1.4e8 ⇒ S2 brackets; S1 @ ~0.7),
    # LOGISTIC 0.5. Soft high-λ solves are CHEAP (few open facilities ⇒ small basis), so the
    # wide grid is affordable. Env override: SWEEP_WMAX.
    w_max = haskey(ENV, "SWEEP_WMAX") ? parse(Float64, ENV["SWEEP_WMAX"]) :
            travel_func == FUNC_LOGISTIC ? 0.5 : 5.0
    # Per-decade multipliers, env-overridable for Round-2 densification (e.g.
    # SWEEP_MULTS="1,1.5,2,3,5,7" halves the 0.2→0.5 λ gap where crossings cluster).
    mults = haskey(ENV, "SWEEP_MULTS") ?
            sort(parse.(Float64, split(ENV["SWEEP_MULTS"], ","))) : [1.0, 2.0, 5.0]
    d_hi = max(0, ceil(Int, log10(w_max)))
    ws_common = sort(unique(Float64[m * 10.0^d for d in -4:d_hi for m in mults
                                    if m * 10.0^d <= w_max * (1.0 + 1e-9)]))
    pln()
    pln("Common λ sweep ($travel_func_name): fixed grid 1-2-5/decade, 1e-4 … $w_max, warm-start dual simplex, no early stop.")
    print_sweep_header(target_raw)

    # --- S1/S2 refinement by bisection, interleaved with the coarse sweep (#52) --------
    # S1 = today's facility count (sum_y crosses target_cells; sum_y is the LP count and
    # falls monotonically with w), S2 = today's travel (cost_c crosses base.cost_c; the
    # multistart travel rises with w, up to rounding noise). The 1-2-5 grid is a factor
    # 2-2.5 in w per step and the count moves ~30% per step, so reading a scenario off the
    # nearest grid point put S1 up to 30% away from today's count and, in 5 areas, on the
    # same point as S2. Bisection inside the bracket pins each to REFINE_TOL.
    #
    # The bisection runs the moment its bracket closes, NOT after the sweep: the LP is
    # warm-started from the previous solve, and a solve far from the current basis on
    # the big regions (FRC 1.7M cols, SE2 3.4M) hits the 1 h time limit -- the previous
    # post-hoc S2 bisection timed out at its first point in 14 of 42 LINEAR areas, after
    # the sweep had moved on to w_max and three high-w solves had already timed out.
    # Solved here, right after the bracket's upper endpoint, every bisection point is a
    # near step (seconds to minutes on the big regions). After the detour the upper
    # endpoint is re-solved for its basis so the grid continues as if uninterrupted.
    # SWEEP_STOP_AFTER_REFINE=1 ends the sweep once both scenarios are pinned (the
    # refine-only rerun of an area whose frontier is already known).
    refine_tol   = parse(Float64, get(ENV, "REFINE_TOL", "0.002"))     # relative
    refine_iters = parse(Int,     get(ENV, "REFINE_ITERS", "8"))
    stop_after_refine = get(ENV, "SWEEP_STOP_AFTER_REFINE", "0") == "1"
    refined = Dict{String, Any}()

    # descending: the quantity FALLS with w (sum_y); ascending: it rises (cost_c)
    crosses(a, b, target, descending) = descending ? (b <= target <= a) : (a <= target <= b)

    function bisect!(label, lo_r, hi_r, getter, target, tol, descending)
        lo, hi = lo_r.w, hi_r.w
        best = abs(getter(lo_r) - target) <= abs(getter(hi_r) - target) ? lo_r : hi_r
        pln()
        pln("$label bisection over w in ($lo, $hi): pin $(label == "S1" ? "sum_y" : "cost_c") ≈ $(round(target, digits=2)) to ±$(round(tol, digits=2)) (≤$refine_iters solves)")
        print_sweep_header(target_raw)
        for _ in 1:refine_iters
            wmid = sqrt(lo * hi)                        # geometric midpoint
            r = run_lp(wmid)
            r === nothing && break
            push!(results, r)
            print_sweep_row(r, target_cells, target_raw)
            abs(getter(r) - target) < abs(getter(best) - target) && (best = r)
            abs(getter(r) - target) <= tol && break
            below = descending ? getter(r) > target : getter(r) < target
            below ? (lo = wmid) : (hi = wmid)
        end
        pln("  $label pinned at w=$(round(best.w, sigdigits=5)): $(label == "S1" ? "sum_y" : "cost_c")=$(round(getter(best), digits=2)) (target $(round(target, digits=2)))")
        return best
    end

    function refine_if_closed!(prev, r)
        prev === nothing && return false
        did = false
        if !haskey(refined, "S1") && crosses(prev.sum_y, r.sum_y, target_cells, true)
            refined["S1"] = bisect!("S1", prev, r, x -> x.sum_y, target_cells,
                                    max(1.0, refine_tol * target_cells), true)
            did = true
        end
        if !haskey(refined, "S2") && crosses(prev.cost_c, r.cost_c, base.cost_c, false)
            refined["S2"] = bisect!("S2", prev, r, x -> x.cost_c, base.cost_c,
                                    refine_tol * base.cost_c, false)
            did = true
        end
        if did
            t = @elapsed ts = resolve_for_basis!(state, r.w)
            pln("  basis restored at w=$(r.w) ($ts, $(round(t, digits=1)) s)")
            sort!(results, by=x->x.w)
        end
        return did
    end

    results = []
    prev = nothing
    for w in ws_common
        r = run_lp(w)
        if r === nothing                 # prev stays: the bracket then spans the failed point
            # A timed-out solve leaves the solver on an aborted basis, and every later grid
            # point then warm-starts far from optimal and times out as well (FRC LINEAR:
            # 1.0, 2.0 and 5.0 each burned the full hour). Once both scenarios are pinned
            # the tail only extends the frontier, so give it up at the first failure.
            if haskey(refined, "S1") && haskey(refined, "S2") && get(ENV, "SWEEP_STOP_AFTER_TAIL_FAIL", "1") == "1"
                pln("  both scenarios are pinned and w=$w timed out: the rest of the tail would start from the aborted basis; ending the sweep")
                break
            end
            continue
        end
        push!(results, r)
        print_sweep_row(r, target_cells, target_raw)
        refine_if_closed!(prev, r)
        prev = r
        if stop_after_refine && haskey(refined, "S1") && haskey(refined, "S2")
            pln("  both scenarios pinned; SWEEP_STOP_AFTER_REFINE=1 ends the sweep at w=$w")
            break
        end
    end
    sort!(results, by=x->x.w)

    bracket_S1 = find_bracket(results, target_cells, r -> r.sum_y, true)
    bracket_S2 = find_bracket(results, base.cost_c,  r -> r.cost_c, false)
    if bracket_S1 === nothing
        pln("  S1 (sum_y=$target_cells) not bracketed at w_max=$w_max: under soft coverage the frontier should pass the baseline count — check for skipped/timed-out points or extend SWEEP_WMAX; exact pin via soft-coverage MIP (todo #5).")
    end

    # Structural coverage-floor regions (ITG/Portugal/PL8): under the #3 coverage-consistent
    # baseline the stranded-client BIG penalties dominate, so the baseline cost/count fall
    # OUTSIDE the frontier's range and neither S1 nor S2 brackets. Do NOT return early — still
    # emit the Combined-sweep table (the frontier that build_deck_data/build_charts plot; an
    # early return left rows=[] → the region rendered empty). Skip only the fine sweep and the
    # S1/S2 summary+arrows (a nearest-point S1/S2 here would be a misleading frontier-edge
    # scenario); exact S1/S2 for these need the soft-coverage MIP (todo #5).
    do_fine = bracket_S1 !== nothing || bracket_S2 !== nothing
    if !do_fine
        pln("\nNeither S1 (sum_y=$target_cells) nor S2 (cost=$(round(base.cost_c,digits=0))) bracketed in coarse range (structural coverage-floor region).")
        pln("Emitting coarse frontier only; exact S1/S2 via soft-coverage MIP (todo #5).")
    end

    if do_fine
    candidate_los = filter(!isnothing, [bracket_S1 === nothing ? nothing : bracket_S1[1],
                                         bracket_S2 === nothing ? nothing : bracket_S2[1]])
    candidate_his = filter(!isnothing, [bracket_S1 === nothing ? nothing : bracket_S1[2],
                                         bracket_S2 === nothing ? nothing : bracket_S2[2]])
    w_lo = minimum(candidate_los)
    w_hi = maximum(candidate_his)

    pln()
    pln("Fine λ sweep over w in [$w_lo, $w_hi]")
    pln("  bracket S1 (sum_y=$target_cells): $(bracket_S1)")
    pln("  bracket S2 (cost=$(round(base.cost_c, digits=0))): $(bracket_S2)")
    print_sweep_header(target_raw)

    # 1-2-5 per partial decade across the bracket range (each w in (w_lo, w_hi) exclusive)
    log_lo = log10(w_lo); log_hi = log10(w_hi)
    ws_fine = Float64[]
    d = floor(Int, log_lo)
    while d <= ceil(Int, log_hi)
        for mult in mults
            w_candidate = mult * 10.0^d
            if w_lo < w_candidate < w_hi
                push!(ws_fine, w_candidate)
            end
        end
        d += 1
    end
    sort!(ws_fine)
    solved(w) = any(isapprox(w, r.w; rtol=1e-9) for r in results)
    filter!(w -> !solved(w), ws_fine)     # the default mults ARE the coarse grid: skip them
    for w in ws_fine
        r = run_lp(w)
        r === nothing && continue
        push!(results, r)
        print_sweep_row(r, target_cells, target_raw)
    end
    sort!(results, by=x->x.w)

    # --- fallback: a scenario bracketed but not yet pinned -------------------
    # Normally both were pinned inside the coarse loop above. This runs only when a
    # bracket closed across a failed (timed-out) grid point, or was first seen in the fine
    # sweep -- and it then carries the far-basis risk the interleaved version avoids.
    for (label, getter, target, tol, desc) in (
            ("S1", r -> r.sum_y,  target_cells, max(1.0, refine_tol * target_cells), true),
            ("S2", r -> r.cost_c, base.cost_c,  refine_tol * base.cost_c,            false))
        haskey(refined, label) && continue
        br = find_bracket(results, target, getter, desc)
        br === nothing && continue
        lo_r = results[findfirst(r -> r.w == br[1], results)]
        hi_r = results[findfirst(r -> r.w == br[2], results)]
        pln()
        pln("$label was bracketed but not pinned in the coarse loop (bracket spans a failed point?): post-hoc bisection")
        refined[label] = bisect!(label, lo_r, hi_r, getter, target, tol, desc)
        sort!(results, by=x->x.w)
    end
    end  # if do_fine (fine sweep + fallback bisection)

    pln()
    pln("Combined sweep, sorted by w:")
    print_sweep_header(target_raw)
    for r in results
        print_sweep_row(r, target_cells, target_raw)
    end

    if !do_fine
        return   # structural region: frontier emitted above, no bracketed S1/S2 to summarise
    end

    function closest(results, target, key)
        results[argmin(abs(getfield(r, key) - target) for r in results)]
    end

    pln()
    pln("=" ^ 90)
    pln("$country — scenario summary")
    pln("=" ^ 90)

    s1 = closest(results, target_cells, :sum_y)
    pln("\nS1 — closest to sum_y = $target_cells (baseline cells):")
    pln("  w = $(round(s1.w, sigdigits=5))   λ = $(round(s1.λ, digits=2)) €")
    pln("  sum_y         : $(round(s1.sum_y, digits=2))      (target $target_cells)")
    pln("  n_open        : $(s1.n_open)         frac_y: $(s1.n_frac)")
    pln("  travel_relax  : $(round(s1.travel_relax, digits=0))     (LP1 with all fractional x)")
    pln("  travel_topp   : $(round(s1.travel_c_topp, digits=0))   greedy: $(round(s1.travel_c_greedy, digits=0))   multi: $(round(s1.travel_c_multi, digits=0))")
    pln("  stranded      : topp $(s1.uncov_topp)   greedy $(s1.uncov_greedy)   multi $(s1.uncov_multi)")
    pln("  travel_c ($(s1.rounding)): $(round(s1.cost_c, digits=0))     (selected; baseline $(round(base.cost_c, digits=0)))")
    pln("  travel change (ph2): $(round((s1.cost_c - base.cost_c)/base.cost_c * 100, digits=2))%")
    pln("  facility €    : $(round(s1.sum_y * FACILITY_MIN_COSTS, digits=0))     (baseline $(round(target_cells * FACILITY_MIN_COSTS, digits=0)))")
    pln("  mean t (min)  : $(round(s1.mean_t, digits=4))    (baseline $(round(base.mean_t, digits=4)))")

    s2 = closest(results, base.cost_c, :cost_c)
    pln("\nS2 — closest to travel_c (ph2) = $(round(base.cost_c, digits=0)) (baseline):")
    pln("  w = $(round(s2.w, sigdigits=5))   λ = $(round(s2.λ, digits=2)) €")
    pln("  sum_y         : $(round(s2.sum_y, digits=2))      (baseline cells $target_cells)")
    pln("  n_open        : $(s2.n_open)         frac_y: $(s2.n_frac)")
    pln("  travel_relax  : $(round(s2.travel_relax, digits=0))     (LP1 with all fractional x)")
    pln("  travel_topp   : $(round(s2.travel_c_topp, digits=0))   greedy: $(round(s2.travel_c_greedy, digits=0))   multi: $(round(s2.travel_c_multi, digits=0))")
    pln("  stranded      : topp $(s2.uncov_topp)   greedy $(s2.uncov_greedy)   multi $(s2.uncov_multi)")
    pln("  travel_c ($(s2.rounding)): $(round(s2.cost_c, digits=0))     (selected; baseline $(round(base.cost_c, digits=0)))")
    pln("  travel change (ph2): $(round((s2.cost_c - base.cost_c)/base.cost_c * 100, digits=2))%")
    pln("  facility €    : $(round(s2.sum_y * FACILITY_MIN_COSTS, digits=0))     (baseline $(round(target_cells * FACILITY_MIN_COSTS, digits=0)))")
    pln("  fewer than cells (by sum_y): $(round(target_cells - s2.sum_y, digits=2))  ($(round((target_cells - s2.sum_y)/target_cells * 100, digits=2))%)")
    if target_raw !== nothing
        pln("  fewer than raw   (by sum_y): $(round(target_raw - s2.sum_y, digits=2))  ($(round((target_raw - s2.sum_y)/target_raw * 100, digits=2))%)")
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
