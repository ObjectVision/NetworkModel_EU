include("lp_run.jl")

pln(args...) = (println(args...); flush(stdout))

# Sequential warm-start sweep using HiGHS dual simplex. One JuMP model per
# country, reused across all w values; HiGHS warm-starts each subsequent
# solve from the previous optimal basis. No parallelism, no MAX_PARALLEL.

const RAW_PHARMACY_COUNTS = Dict("Netherlands" => 1992)
const EXISTING_PATH = joinpath(LOCAL_DATA_PROJ_DIR, "ExistingPharmacies")
const NEW_PATH      = joinpath(LOCAL_DATA_PROJ_DIR, "NewPharmacies")

function load_from(dir, country)
    od  = Arrow.Table(joinpath(dir, "$(country)_od.arrow"))
    loc = Arrow.Table(joinpath(dir, "$(country)_i.arrow"))
    fac = Arrow.Table(joinpath(dir, "$(country)_j.arrow"))

    clients_col    = Int.(od[:client_rel])
    facilities_col = Int.(od[:facility_rel])
    t_ij_col       = od[:t_ij] ./ 60
    population     = client_weight_col(loc)
    facilities     = Int.(fac[:id])

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

    return (; N, M, facilities, wpop, clients_col, t_ij_col, facilities_col,
             locations, facility_rows, client_pop, nearest_facility)
end

function baseline_metrics(data)
    total_c = 0.0
    total_t = 0.0
    used = Set{Int}()
    for (i, rows) in data.locations
        best_k = rows[argmin(data.t_ij_col[k] for k in rows)]
        total_c += c(data.t_ij_col[best_k]) * data.wpop[best_k]
        total_t += data.t_ij_col[best_k] * data.wpop[best_k]
        push!(used, data.facilities_col[best_k])
    end
    total_pop = sum(data.wpop[rows[1]] for (_, rows) in data.locations)
    return (cost_c=total_c, time_total=total_t, mean_t=total_t/total_pop,
            n_used=length(used), total_pop=total_pop)
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
        rpad("travel_relax", 16), rpad("travel_c_ph2", 16),
        rpad("n_open", 10), rpad("fac_€", 14),
        rpad("mean_t", 10), rpad("frac_x", 10),
        rpad("n-cells", 10),
        target_raw === nothing ? "" : "n-raw")
end

function print_sweep_row(r, target_cells, target_raw)
    fac_eur = r.sum_x * FACILITY_MIN_COSTS
    n_raw_delta = target_raw === nothing ? "" : string(r.n_open - target_raw)
    pln(rpad(r.w, 12), rpad(r.λ, 14), rpad(round(r.sum_x, digits=2), 12),
        rpad(round(r.travel_relax, digits=0), 16), rpad(round(r.cost_c, digits=0), 16),
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
    existing = load_from(EXISTING_PATH, country)
    pln("  N=$(existing.N) OD rows, M=$(existing.M) facilities")

    pln("Loading NewPharmacies/$country ...")
    new_data = load_from(NEW_PATH, country)
    pln("  N=$(new_data.N) OD rows, M=$(new_data.M) candidate facilities")

    base = baseline_metrics(existing)
    target_cells = base.n_used
    target_raw   = get(RAW_PHARMACY_COUNTS, country, nothing)

    pln()
    pln("Baseline (ExistingPharmacies, each client → nearest pharmacy):")
    pln("  facilities used (cells):     $(target_cells) (of $(existing.M))")
    target_raw === nothing || pln("  raw pharmacy count:          $target_raw (external reference)")
    pln("  total travel cost(c):        $(round(base.cost_c, digits=0))")
    pln("  facility cost @ €$(FACILITY_MIN_COSTS) ea: $(round(target_cells * FACILITY_MIN_COSTS, digits=0))")
    pln("  mean travel time (min):      $(round(base.mean_t, digits=4))")
    pln("  total client population:     $(round(Int, base.total_pop))")

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
        return r
    end

    pln()
    pln("Coarse λ sweep (sequential warm-start simplex, 1-2-5 per decade, stop when travel_c > baseline):")
    print_sweep_header(target_raw)

    ws_coarse = Float64[]
    for decade in [1e-4, 1e-3, 1e-2, 1e-1, 1.0, 10.0, 100.0, 1000.0]
        for mult in (1.0, 2.0, 5.0)
            push!(ws_coarse, decade * mult)
        end
    end

    results = []
    for w in ws_coarse
        r = run_lp(w)
        r === nothing && continue
        push!(results, r)
        print_sweep_row(r, target_cells, target_raw)
        if r.cost_c > base.cost_c
            pln("  → travel_c=$(round(r.cost_c, digits=0)) > baseline=$(round(base.cost_c, digits=0)); stopping coarse sweep.")
            break
        end
    end
    sort!(results, by=x->x.w)

    bracket_S1 = find_bracket(results, target_cells, r -> r.sum_x, true)
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
    pln("  travel_relax  : $(round(s1.travel_relax, digits=0))     (LP-relaxed; baseline $(round(base.cost_c, digits=0)))")
    pln("  travel_c (ph2): $(round(s1.cost_c, digits=0))     (post-rounding; baseline $(round(base.cost_c, digits=0)))")
    pln("  travel change (ph2): $(round((s1.cost_c - base.cost_c)/base.cost_c * 100, digits=2))%")
    pln("  facility €    : $(round(s1.sum_x * FACILITY_MIN_COSTS, digits=0))     (baseline $(round(target_cells * FACILITY_MIN_COSTS, digits=0)))")
    pln("  mean t (min)  : $(round(s1.mean_t, digits=4))    (baseline $(round(base.mean_t, digits=4)))")

    s2 = closest(results, base.cost_c, :cost_c)
    pln("\nS2 — closest to travel_c (ph2) = $(round(base.cost_c, digits=0)) (baseline):")
    pln("  w = $(round(s2.w, sigdigits=5))   λ = $(round(s2.λ, digits=2)) €")
    pln("  sum_x         : $(round(s2.sum_x, digits=2))      (baseline cells $target_cells)")
    pln("  n_open        : $(s2.n_open)         frac_x: $(s2.n_frac)")
    pln("  travel_relax  : $(round(s2.travel_relax, digits=0))     (LP-relaxed; baseline $(round(base.cost_c, digits=0)))")
    pln("  travel_c (ph2): $(round(s2.cost_c, digits=0))     (post-rounding; baseline $(round(base.cost_c, digits=0)))")
    pln("  travel change (ph2): $(round((s2.cost_c - base.cost_c)/base.cost_c * 100, digits=2))%")
    pln("  facility €    : $(round(s2.sum_x * FACILITY_MIN_COSTS, digits=0))     (baseline $(round(target_cells * FACILITY_MIN_COSTS, digits=0)))")
    pln("  fewer than cells (by sum_x): $(round(target_cells - s2.sum_x, digits=2))  ($(round((target_cells - s2.sum_x)/target_cells * 100, digits=2))%)")
    if target_raw !== nothing
        pln("  fewer than raw   (by sum_x): $(round(target_raw - s2.sum_x, digits=2))  ($(round((target_raw - s2.sum_x)/target_raw * 100, digits=2))%)")
    end
    pln("  mean t (min)  : $(round(s2.mean_t, digits=4))    (baseline $(round(base.mean_t, digits=4)))")
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
