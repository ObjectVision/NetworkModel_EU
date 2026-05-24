include("lp_run.jl")

pln(args...) = (println(args...); flush(stdout))

const NL = "Netherlands"
const TARGET_N = 1992

function load_from(dir, country)
    od  = Arrow.Table(joinpath(dir, "$(country)_od.arrow"))
    loc = Arrow.Table(joinpath(dir, "$(country)_i.arrow"))
    fac = Arrow.Table(joinpath(dir, "$(country)_j.arrow"))

    clients_col    = Int.(od[:client_rel])
    facilities_col = Int.(od[:facility_rel])
    t_ij_col       = od[:t_ij] ./ 60
    population     = loc[:pop]
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
    return (cost_c=total_c, time_total=total_t, mean_t=total_t/total_pop, n_used=length(used))
end

const EXISTING_PATH = joinpath(LOCAL_DATA_PROJ_DIR, "ExistingPharmacies")
const NEW_PATH      = joinpath(LOCAL_DATA_PROJ_DIR, "NewPharmacies")

pln("Loading ExistingPharmacies/$NL ...")
existing = load_from(EXISTING_PATH, NL)
pln("  N=$(existing.N) OD rows, M=$(existing.M) facilities")

pln("Loading NewPharmacies/$NL ...")
new_data = load_from(NEW_PATH, NL)
pln("  N=$(new_data.N) OD rows, M=$(new_data.M) candidate facilities")

base = baseline_metrics(existing)
pln()
pln("Baseline (ExistingPharmacies, each client → nearest pharmacy):")
pln("  facilities used:             $(base.n_used) (of $(existing.M))")
pln("  total cost(c):               $(round(base.cost_c, digits=0))")
pln("  total travel time (pop*min): $(round(base.time_total, digits=0))")
pln("  mean travel time (min):      $(round(base.mean_t, digits=4))")

# LP wrapper: returns (n_open, cost_c, mean_t, n_frac)
function run_lp(w)
    out = run_scenario(new_data, Inf, w, false, true)
    open_set, _, _, n_open_full, n_open_small, mean_t, travel_c, _, _, _, _, _, _, n_frac = out
    return (n_open=n_open_full + n_open_small, cost_c=travel_c, mean_t=mean_t, n_frac=n_frac)
end

pln()
pln("λ sweep on NewPharmacies (min_clients=Inf, nearest assignment):")
pln(rpad("w", 12), rpad("λ", 14), rpad("n_open", 10), rpad("cost(c)", 18), rpad("mean_t", 10), rpad("frac_x", 10), "n - $TARGET_N")

ws_initial = [1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1.0, 10.0]
results = []
for w in ws_initial
    r = run_lp(w)
    push!(results, (w=w, λ=w*FACILITY_MIN_COSTS, n_open=r.n_open, cost_c=r.cost_c, mean_t=r.mean_t, n_frac=r.n_frac))
    pln(rpad(w, 12), rpad(w*FACILITY_MIN_COSTS, 14), rpad(r.n_open, 10),
            rpad(round(r.cost_c, digits=0), 18), rpad(round(r.mean_t, digits=4), 10),
            rpad(r.n_frac, 10), r.n_open - TARGET_N)
end

sort!(results, by=x->x.w)

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

function bisect(w_lo, w_hi, target, get_metric, descending; tol_rel=0.005, max_iter=14)
    for iter in 1:max_iter
        w_mid = sqrt(w_lo * w_hi)
        r = run_lp(w_mid)
        m = get_metric(r)
        pln("  iter $iter: w=$(round(w_mid, sigdigits=5)), n_open=$(r.n_open), cost(c)=$(round(r.cost_c, digits=0)), mean_t=$(round(r.mean_t, digits=4)), frac_x=$(r.n_frac)")
        if abs(m - target) / max(abs(target), 1) <= tol_rel
            return (w=w_mid, λ=w_mid*FACILITY_MIN_COSTS, r...)
        end
        if (descending && m > target) || (!descending && m < target)
            w_lo = w_mid
        else
            w_hi = w_mid
        end
    end
    r = run_lp(sqrt(w_lo * w_hi))
    return (w=sqrt(w_lo * w_hi), λ=sqrt(w_lo * w_hi)*FACILITY_MIN_COSTS, r...)
end

# Target A: n_open == TARGET_N (n_open is decreasing in w)
bracket_n = find_bracket(results, TARGET_N, r -> r.n_open, true)
if bracket_n === nothing
    pln("\nWarning: TARGET_N=$TARGET_N not in initial sweep range; widen and re-run.")
else
    pln("\nTarget A — bisecting w in $bracket_n for n_open = $TARGET_N:")
    res_a = bisect(bracket_n[1], bracket_n[2], TARGET_N, r -> r.n_open, true; tol_rel=0.01)
    pln()
    pln("=== A: NewPharmacies LP with n_open = $TARGET_N ===")
    pln("  w = $(res_a.w)   λ = $(round(res_a.λ, digits=2))")
    pln("  n_open       : $(res_a.n_open)         (target $TARGET_N)")
    pln("  cost(c)      : $(round(res_a.cost_c, digits=0))     (baseline $(round(base.cost_c, digits=0)))")
    pln("  cost reduction: $(round((base.cost_c - res_a.cost_c)/base.cost_c * 100, digits=2))%")
    pln("  mean t (min) : $(round(res_a.mean_t, digits=4))    (baseline $(round(base.mean_t, digits=4)))")
    pln("  fractional x[j]: $(res_a.n_frac)")
end

# Target B: cost_c == base.cost_c (cost_c is increasing in w)
bracket_cost = find_bracket(results, base.cost_c, r -> r.cost_c, false)
if bracket_cost === nothing
    pln("\nWarning: baseline cost not in initial sweep range; widen and re-run.")
else
    pln("\nTarget B — bisecting w in $bracket_cost for cost(c) = $(round(base.cost_c, digits=0)):")
    res_b = bisect(bracket_cost[1], bracket_cost[2], base.cost_c, r -> r.cost_c, false)
    pln()
    pln("=== B: NewPharmacies LP with cost(c) = baseline ===")
    pln("  w = $(res_b.w)   λ = $(round(res_b.λ, digits=2))")
    pln("  cost(c)      : $(round(res_b.cost_c, digits=0))     (baseline $(round(base.cost_c, digits=0)))")
    pln("  n_open       : $(res_b.n_open)         (vs $TARGET_N — that's $(TARGET_N - res_b.n_open) fewer, $(round((TARGET_N - res_b.n_open)/TARGET_N * 100, digits=2))%)")
    pln("  mean t (min) : $(round(res_b.mean_t, digits=4))    (baseline $(round(base.mean_t, digits=4)))")
    pln("  fractional x[j]: $(res_b.n_frac)")
end
