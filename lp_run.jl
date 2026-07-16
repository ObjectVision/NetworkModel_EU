include("settings.jl")

struct WarmStartState{TX, TY}
    model::Model
    x::TX
    y::TY
    data::CountryData
end

# --- LP-relaxation → integer open-set rounding ------------------------------
# Greedy alternative to top-p. Top-p ranks facilities purely by x_relaxed, so it
# starves regions the LP covered with many low-x substitutes (no single one
# clears the cutoff, yet together they hold ~1 facility's worth of demand). This
# instead seeds the open set with the x≈1 "must-open" facilities, then grabs the
# fractional facility whose opening most reduces total weighted travel cost,
# repeating until `p_open` are open — so a low-x facility that nonetheless slashes
# travel for an otherwise far-served cluster gets picked. Same count as top-p, so
# it stays an apples-to-apples Pareto point; only *which* facilities differ.
#
# Lazy/CELF greedy: marginal gains are submodular (opening a facility can only
# shrink another's gain), so after each pick we invalidate only the candidates
# sharing a now-better-served client and recompute their gain on demand.
function greedy_round(x_relaxed, data::CountryData, p_open; tol=1e-6)
    (; facilities, wpop, t_ij_col, facilities_col, locations, facility_rows, clients_col) = data

    must_open  = [j for j in facilities if x_relaxed[j] >= 1 - tol]
    fractional = [j for j in facilities if tol < x_relaxed[j] < 1 - tol]
    open_set   = Set(must_open)

    # best_cost[i] = cheapest c(t) from client i to any currently-open facility.
    best_cost = Dict(i => Inf for i in keys(locations))
    for j in must_open, k in facility_rows[j]
        i  = clients_col[k]
        ck = c(t_ij_col[k])
        ck < best_cost[i] && (best_cost[i] = ck)
    end

    function gain(j)
        g = 0.0
        for k in facility_rows[j]
            d = best_cost[clients_col[k]] - c(t_ij_col[k])
            d > 0 && (g += d * wpop[k])
        end
        return g
    end

    remaining = Set(fractional)
    gains     = Dict(j => gain(j) for j in fractional)
    fresh     = Dict(j => true     for j in fractional)

    while length(open_set) < p_open && !isempty(remaining)
        best_j, best_g = nothing, -Inf
        for j in remaining
            gains[j] > best_g && ((best_j, best_g) = (j, gains[j]))
        end
        best_j === nothing && break
        if !fresh[best_j]                 # stale upper bound — refresh and re-rank
            gains[best_j] = gain(best_j)
            fresh[best_j] = true
            continue
        end
        best_g <= 0 && break              # no remaining fractional facility helps

        push!(open_set, best_j)
        delete!(remaining, best_j)
        improved = Int[]
        for k in facility_rows[best_j]
            i  = clients_col[k]
            ck = c(t_ij_col[k])
            ck < best_cost[i] && (best_cost[i] = ck; push!(improved, i))
        end
        for i in improved, k in locations[i]   # invalidate only affected candidates
            j2 = facilities_col[k]
            j2 in remaining && (fresh[j2] = false)
        end
    end

    # Greedy can stall (all remaining gains ≤ 0) before reaching p_open; top up by
    # x_relaxed descending so n_open matches top-p exactly.
    if length(open_set) < p_open
        for j in sort([j for j in facilities if !(j in open_set)], by=j -> x_relaxed[j], rev=true)
            length(open_set) >= p_open && break
            push!(open_set, j)
        end
    end

    return open_set
end

# Deterministic nearest-open assignment + travel cost for a given open set.
function assign_nearest(open_set, data::CountryData)
    (; t_ij_col, facilities_col, locations, wpop) = data
    assigned_k = Dict{Int, Int}()
    for (i, rows) in locations
        candidates = [k for k in rows if facilities_col[k] in open_set]
        isempty(candidates) || (assigned_k[i] = candidates[argmin(c(t_ij_col[k]) for k in candidates)])
    end
    travel_c = isempty(assigned_k) ? 0.0 : sum(c(t_ij_col[k]) * wpop[k] for (_, k) in assigned_k)
    return assigned_k, travel_c
end

# --- Multi-start randomized rounding + swap local search ---------------------
# Far cheaper than the LP solve (the client/location count is small even when the
# OD matrix is huge), so this adds seconds, not hours. Seeds with top-p AND greedy
# (so the result can never be worse than the better of them) plus x-weighted random
# draws for diversity; each seed is polished by best-improving open↔closed swaps
# over the fractional set (must-opens stay open). Travel = Σ client_pop · nearest c(t),
# with any client left uncovered charged BIG (= max c(t)) so polishing covers it.

# Nearest / second-nearest open facility per client. b1=b2=BIG when none open.
function client_nearest(open_set, data::CountryData, BIG)
    (; locations, facilities_col, t_ij_col) = data
    d1 = Dict{Int,Float64}(); d2 = Dict{Int,Float64}(); phi1 = Dict{Int,Int}()
    for (i, rows) in locations
        b1 = BIG; b2 = BIG; f1 = -1
        for k in rows
            if facilities_col[k] in open_set
                ck = c(t_ij_col[k])
                if ck < b1
                    b2 = b1; b1 = ck; f1 = facilities_col[k]
                elseif ck < b2
                    b2 = ck
                end
            end
        end
        d1[i] = b1; d2[i] = b2; phi1[i] = f1
    end
    return d1, d2, phi1
end

# Coverage-honest travel: every client charged its nearest-open c(t); a client with
# NO open candidate (stranded by rounding) is charged BIG = big_cost(), the fixed
# stranded-client price (c(120 min) for linear-type costs, 1.0 for LOGISTIC — see
# settings.jl), so stranding the rural many-small-fraction clusters is never free.
# Returns (total weighted travel, #stranded); the count is also reported.
function travel_of(open_set, data::CountryData, BIG)
    d1, _, phi1 = client_nearest(open_set, data, BIG)
    t = 0.0; uncov = 0
    for i in keys(data.locations)
        t += d1[i] * data.client_pop[i]
        phi1[i] == -1 && (uncov += 1)
    end
    return t, uncov
end

# x-weighted random selection of exactly k fractionals (Efraimidis–Spirakis A-Res):
# log-key = log(rand)/x_j; take the k largest → favours high x_j but stochastic.
function randomized_seed(must_open, frac_js, xvals, k, rng)
    keys  = [log(rand(rng)) / xvals[t] for t in 1:length(frac_js)]
    order = sortperm(keys, rev=true)
    chosen = Set{Int}()
    for t in 1:min(k, length(frac_js))
        push!(chosen, frac_js[order[t]])
    end
    return chosen
end

# One best-improving swap (Resende–Werneck fast interchange): close one removable
# (∈ chosen) facility, open one candidate (∈ frac\chosen), if it lowers travel.
# profit(f,r) = gain(f) − loss(r) + extra(f,r). Mutates `chosen`; returns true if swapped.
function swap_round!(chosen, frac_set, data::CountryData, d1, d2, phi1)
    (; N, locations, facilities_col, t_ij_col, clients_col, client_pop) = data
    candidates = setdiff(frac_set, chosen)
    (isempty(chosen) || isempty(candidates)) && return false

    loss = Dict(r => 0.0 for r in chosen)
    for (i, _) in locations
        r = phi1[i]
        r in chosen && (loss[r] += (d2[i] - d1[i]) * client_pop[i])
    end

    gain  = Dict(f => 0.0 for f in candidates)
    extra = Dict{Int, Dict{Int,Float64}}()
    for k in 1:N
        f = facilities_col[k]
        f in candidates || continue
        i = clients_col[k]; cost = c(t_ij_col[k]); wt = client_pop[i]
        cost < d1[i] && (gain[f] += (d1[i] - cost) * wt)
        r = phi1[i]
        if r in chosen && cost < d2[i]
            ef = get!(extra, f, Dict{Int,Float64}())
            ef[r] = get(ef, r, 0.0) + (d2[i] - max(cost, d1[i])) * wt
        end
    end

    r0 = -1; minloss = Inf
    for (r, v) in loss
        v < minloss && (minloss = v; r0 = r)
    end

    best_profit = 1e-6; best_f = -1; best_r = -1
    for f in candidates
        bf = -minloss; br = r0
        if haskey(extra, f)
            for (r, val) in extra[f]
                cand = val - loss[r]
                cand > bf && (bf = cand; br = r)
            end
        end
        profit = gain[f] + bf
        profit > best_profit && (best_profit = profit; best_f = f; best_r = br)
    end

    if best_f != -1
        delete!(chosen, best_r); push!(chosen, best_f)
        return true
    end
    return false
end

function multistart_round(x_relaxed, data::CountryData, p_open, topp_set, greedy_set;
                          restarts=MS_RESTARTS, rounds=MS_ROUNDS, seed=MS_SEED, tol=1e-6)
    (; facilities, t_ij_col) = data
    must_open = [j for j in facilities if x_relaxed[j] >= 1 - tol]
    frac_js   = [j for j in facilities if tol < x_relaxed[j] < 1 - tol]
    frac_set  = Set(frac_js)
    xvals     = [x_relaxed[j] for j in frac_js]
    k         = clamp(p_open - length(must_open), 0, length(frac_js))
    fixed     = Set(must_open)
    BIG       = big_cost()   # fixed stranded-client price: c(120 min) linear / 1.0 logistic
    rng       = MersenneTwister(seed)

    seeds = Vector{Set{Int}}()
    push!(seeds, Set(intersect(topp_set,   frac_set)))
    push!(seeds, Set(intersect(greedy_set, frac_set)))
    for _ in 3:restarts
        push!(seeds, randomized_seed(must_open, frac_js, xvals, k, rng))
    end

    # Select the lowest-travel polished set. Because stranded clients are priced at
    # BIG = big_cost(), this single metric already prefers coverage; swap_round! also
    # avoids creating stranded clients (removing a sole provider costs BIG).
    best_set = union(fixed, seeds[1]); best_t = Inf
    for s in seeds
        chosen   = Set(s)
        open_set = union(fixed, chosen)
        for _ in 1:rounds
            d1, d2, phi1 = client_nearest(open_set, data, BIG)
            swap_round!(chosen, frac_set, data, d1, d2, phi1) || break
            open_set = union(fixed, chosen)
        end
        t, _ = travel_of(open_set, data, BIG)
        t < best_t && (best_t = t; best_set = open_set)
    end
    return best_set
end

function run_scenario(data::CountryData, min_clients, w, apply_threshold, nearest)
    (; N, facilities, wpop, t_ij_col, facilities_col, locations, facility_rows) = data

    λ = w * FACILITY_MIN_COSTS

    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "presolve", "on")
    set_optimizer_attribute(model, "output_flag", false)
    set_optimizer_attribute(model, "solver", "ipm")
    set_optimizer_attribute(model, "run_crossover", "on")

    @variable(model, 0 <= y[1:N] <= 1)
    @variable(model, 0 <= x[j in facilities] <= 1)

    if !isinf(min_clients)
        @variable(model, deficit[j in facilities] >= 0)
        @expression(model, load[j in facilities],
            sum(y[k] * wpop[k] for k in facility_rows[j])
        )
        @objective(model, Min,
            sum(y[k] * c(t_ij_col[k]) * wpop[k] for k in 1:N) +
            sum(deficit[j] * λ for j in facilities)
        )
        for j in facilities
            @constraint(model, deficit[j] >= min_clients * x[j] - load[j])
        end
    else
        @objective(model, Min,
            sum(y[k] * c(t_ij_col[k]) * wpop[k] for k in 1:N) +
            sum(x[j] * λ for j in facilities)
        )
    end

    for (_, rows) in locations
        @constraint(model, sum(y[k] for k in rows) == 1)
    end
    for k in 1:N
        @constraint(model, y[k] <= x[facilities_col[k]])
    end

    optimize!(model)

    ts = termination_status(model)
    if ts ∉ (OPTIMAL, LOCALLY_SOLVED, ALMOST_OPTIMAL)
        error("LP at w=$w did not solve (termination_status=$ts). " *
              "Likely IPM numerical issue at extreme λ. Skipping this point.")
    end

    # Capture LP-relaxed solution BEFORE fixing x and re-solving (if nearest=false).
    x_relaxed      = value.(x)
    y_relaxed      = value.(y)
    tol            = 1e-6
    fixed_open_set = Set([j for j in facilities if x_relaxed[j] >= 1 - tol])
    fractional     = [j for j in facilities if tol < x_relaxed[j] < 1 - tol]
    n_fractional_x = length(fractional)
    sum_x          = sum(x_relaxed[j] for j in facilities)
    travel_relax   = sum(y_relaxed[k] * c(t_ij_col[k]) * wpop[k] for k in 1:N)

    # open_set = top round(sum_x) facilities ranked by x_relaxed descending.
    # Avoids phantom-fractional facilities inflating routing choices when IPM/crossover
    # produces many tiny x[j] values at high w (LP-relaxation degeneracy).
    p_open      = clamp(round(Int, sum_x), 1, length(facilities))
    sorted_by_x = sort(collect(facilities), by=j -> x_relaxed[j], rev=true)
    open_set    = Set(sorted_by_x[1:p_open])

    # fix x based on first LP
    for j in facilities
        fix(x[j], j in open_set ? 1.0 : 0.0; force=true)
    end

    # assign clients to facilities
    assigned_k = Dict{Int, Int}()
    if nearest
        # nearest-open lookup: no second LP
        for (i, rows) in locations
            open_rows = [k for k in rows if facilities_col[k] in open_set]
            if apply_threshold
                within_60 = [k for k in open_rows if t_ij_col[k] <= 60.0]
                candidates = isempty(within_60) ? open_rows : within_60
            else
                candidates = open_rows
            end
            if !isempty(candidates)
                assigned_k[i] = candidates[argmin(c(t_ij_col[k]) for k in candidates)]
            end
        end
    else
        # apply 60-min cap and re-solve LP for assignments
        if apply_threshold
            for (_, rows) in locations
                open_rows_within_60 = [k for k in rows if facilities_col[k] in open_set && t_ij_col[k] <= 60.0]
                if !isempty(open_rows_within_60)
                    for k in rows
                        if t_ij_col[k] > 60.0
                            fix(y[k], 0.0; force=true)
                        end
                    end
                end
            end
        end

        optimize!(model)

        for (i, rows) in locations
            best_k, best_val = rows[1], value(y[rows[1]])
            for k in rows[2:end]
                v = value(y[k])
                if v > best_val
                    best_val = v; best_k = k
                end
            end
            assigned_k[i] = best_k
        end
    end

    fload = Dict(j => 0.0 for j in facilities)
    for (_, k) in assigned_k
        fload[facilities_col[k]] += wpop[k]
    end

    total_client_pop = sum(wpop[rows[1]] for (i, rows) in locations)
    mean_travel_min  = sum(t_ij_col[k] * wpop[k] for (i, k) in assigned_k) / total_client_pop

    b1 = sum(wpop[k] for (i, k) in assigned_k if t_ij_col[k] < 15;        init=0.0)
    b2 = sum(wpop[k] for (i, k) in assigned_k if 15 <= t_ij_col[k] < 30;  init=0.0)
    b3 = sum(wpop[k] for (i, k) in assigned_k if 30 <= t_ij_col[k] < 60;  init=0.0)
    b4 = sum(wpop[k] for (i, k) in assigned_k if t_ij_col[k] >= 60;       init=0.0)

    travel_lp      = sum(c(t_ij_col[k]) * wpop[k] for (i, k) in assigned_k)
    penalty_lp     = isinf(min_clients) ?
                         length(open_set) * FACILITY_MIN_COSTS * w :
                         sum(max(0.0, min_clients - fload[j]) * λ for j in open_set; init=0.0)
    raw_penalty_lp = isinf(min_clients) ?
                         length(open_set) * FACILITY_MIN_COSTS :
                         sum(max(0.0, min_clients - fload[j]) * FACILITY_MIN_COSTS for j in open_set; init=0.0)

    n_open_full  = isinf(min_clients) ? length(open_set) : sum(1 for j in open_set if fload[j] >= min_clients; init=0)
    n_open_small = isinf(min_clients) ? 0                : sum(1 for j in open_set if fload[j] < min_clients;  init=0)

    return open_set, fload, assigned_k, n_open_full, n_open_small, mean_travel_min, travel_lp, penalty_lp, raw_penalty_lp, b1, b2, b3, b4, n_fractional_x, sum_x, travel_relax
end


# --- Sequential warm-start variant (dual simplex) -----------------------------
# Build the LP once, then call solve_at_w! repeatedly with different w. HiGHS
# reuses the previous optimal basis as warm start, so subsequent solves are
# typically much cheaper than building a fresh model each time. Only valid for
# the min_clients=Inf, nearest=true case (no second LP, no deficit penalty).

function build_lp_warmstart(data::CountryData)
    (; N, facilities, wpop, t_ij_col, facilities_col, locations) = data

    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "presolve", "on")
    set_optimizer_attribute(model, "output_flag", true)  # show simplex progress live
    set_optimizer_attribute(model, "solver", "simplex")

    @variable(model, 0 <= y[1:N] <= 1)
    @variable(model, 0 <= x[j in facilities] <= 1)

    # SOFT coverage (agreed 2026-07-10): a client need NOT be assigned to a facility;
    # leaving it unserved costs BIG = big_cost() (the same price stranding gets in the
    # baseline and in travel_of). So Σy ≤ 1 (was ==1), and the objective adds the
    # unserved fraction × BIG. Writing the per-client cost as
    #   Σ_k y_k·c(t_k)·p_k + Σ_i p_i·(1 − Σ_k y_k)·BIG
    #   = Σ_k y_k·(c(t_k) − BIG)·p_k  +  BIG·Σ_i p_i        (constant dropped from argmin),
    # the y-coefficient is (c(t_k) − BIG)·p_k (≤ 0, constant across w); x-coeffs = λ are
    # set per w in solve_at_w!. This lets the LP CHOOSE to strand a remote client when a
    # facility that would serve it costs more than the BIG it saves — so the frontier
    # extends below the full-coverage floor, down to (and past) the existing-facility
    # count, and the baseline becomes a feasible point on/above it (never below).
    BIG = big_cost()
    @objective(model, Min, sum(y[k] * (c(t_ij_col[k]) - BIG) * wpop[k] for k in 1:N))

    for (_, rows) in locations
        @constraint(model, sum(y[k] for k in rows) <= 1)
    end
    for k in 1:N
        @constraint(model, y[k] <= x[facilities_col[k]])
    end

    return WarmStartState(model, x, y, data)
end

# Solver history: on 8-Jul the sweep moved to IPM + crossover because warm-started dual
# simplex degraded catastrophically on the big full-population HARD-coverage LPs (each λ
# step moves every x-coefficient by λ·Δ ~ 10^5-10^6, so the previous basis is far away and
# the massively degenerate re-solve cost hours — Netherlands w=5.0 took 16.7h). Under SOFT
# coverage (10-Jul) this reversed: solve_at_w! below uses simplex for BOTH travel functions
# — see the comment there. LP_TIME_LIMIT (1h default) makes any pathological point a
# skipped point, not a stall.
const LP_TIME_LIMIT = parse(Float64, get(ENV, "LP_TIME_LIMIT", "3600"))

function solve_at_w!(state::WarmStartState, w::Real)
    (; model, x, y, data) = state
    (; N, facilities, wpop, t_ij_col, facilities_col, locations) = data

    λ = w * FACILITY_MIN_COSTS

    # Update only the x[j] objective coefficients (constraints + y-coeffs unchanged).
    for j in facilities
        set_objective_coefficient(model, x[j], λ)
    end

    # Simplex for BOTH travel functions under SOFT coverage (2026-07-10). The old split
    # (LOGISTIC→IPM) was a hard-coverage workaround for warm-start-simplex degeneracy; under
    # soft coverage IPM fails outright on LOGISTIC (every ITG point returned OTHER_ERROR —
    # the (c(t)−BIG)·pop objective spans too wide a coefficient range for IPM), while simplex
    # is fast and robust for both (ITG LINEAR 4–8 s/point). Warm-started dual simplex steps
    # cheaply along the λ-grid, and soft high-λ points are cheap (few open facilities ⇒ small
    # basis), so the earlier high-λ blow-up that motivated IPM no longer applies.
    # Env SOLVER=ipm forces interior-point + crossover instead of the default
    # warm-start simplex. IPM is basis-distance-immune, so it clears the high-λ
    # simplex cliff on the big LINEAR regions (used for the Belgium/FRI aggregate-
    # S2 extension). Keep the default simplex for LOGISTIC — soft-coverage IPM
    # fails there (OTHER_ERROR: the tiny (c(t)−BIG) travel coefficients give too
    # wide a range). Crossover on for IPM so sum_x/frac_x and the rounding get a vertex.
    solver = get(ENV, "SOLVER", "simplex")
    set_optimizer_attribute(model, "solver", solver)
    set_optimizer_attribute(model, "run_crossover", solver == "ipm" ? "on" : "off")
    set_optimizer_attribute(model, "time_limit", LP_TIME_LIMIT)

    optimize!(model)

    ts = termination_status(model)
    if ts ∉ (OPTIMAL, LOCALLY_SOLVED, ALMOST_OPTIMAL)
        error("LP at w=$w did not solve (termination_status=$ts).")
    end

    x_relaxed      = value.(x)
    y_relaxed      = value.(y)
    tol            = 1e-6
    fractional     = [j for j in facilities if tol < x_relaxed[j] < 1 - tol]
    n_fractional_x = length(fractional)
    sum_x          = sum(x_relaxed[j] for j in facilities)
    # Coverage-honest LP lower bound (soft coverage): served travel + the unserved
    # fraction priced at BIG = big_cost(), matching the objective and travel_of. Under
    # Σy ≤ 1 a client may be only partly (or not) served in the relaxation; the dropped
    # fraction must be charged BIG or the bound would understate the integer cost.
    BIG_relax      = big_cost()
    served_relax   = sum(y_relaxed[k] * c(t_ij_col[k]) * wpop[k] for k in 1:N)
    stranded_relax = 0.0
    for (_, rows) in locations
        served_i = sum(y_relaxed[k] for k in rows)
        stranded_relax += BIG_relax * wpop[rows[1]] * (1.0 - served_i)
    end
    travel_relax   = served_relax + stranded_relax

    # Three roundings of the LP relaxation to the same count p_open = round(sum_x):
    #   topp       — the p_open facilities with the largest x_relaxed.
    #   greedy     — x≈1 seed + greedy marginal-travel grab from fractionals.
    #   multistart — randomized seeds + swap local search (≤ min(topp, greedy)).
    # The LP2 re-solve that used to run here (a second full optimize per w) is gone:
    # it cost as much as LP1 at extreme λ and the next w warm-starts cleaner without it.
    p_open      = clamp(round(Int, sum_x), 1, length(facilities))
    sorted_by_x = sort(collect(facilities), by=j -> x_relaxed[j], rev=true)
    topp_set    = Set(sorted_by_x[1:p_open])
    greedy_set  = greedy_round(x_relaxed, data, p_open)
    multi_set   = multistart_round(x_relaxed, data, p_open, topp_set, greedy_set)

    # One coverage-honest metric for all three: stranded clients priced at BIG = big_cost().
    BIG = big_cost()
    travel_c_topp,   uncov_topp   = travel_of(topp_set,   data, BIG)
    travel_c_greedy, uncov_greedy = travel_of(greedy_set, data, BIG)
    travel_c_multi,  uncov_multi  = travel_of(multi_set,  data, BIG)

    open_set, travel_c, uncov =
        ROUNDING == "greedy"     ? (greedy_set, travel_c_greedy, uncov_greedy) :
        ROUNDING == "multistart" ? (multi_set,  travel_c_multi,  uncov_multi)  :
                                   (topp_set,   travel_c_topp,   uncov_topp)

    # assigned_k for the SELECTED set drives the per-client arrow output.
    assigned_k, _    = assign_nearest(open_set, data)
    total_client_pop = sum(wpop[rows[1]] for (_, rows) in locations)
    mean_t           = isempty(assigned_k) ? 0.0 : sum(t_ij_col[k] * wpop[k] for (i, k) in assigned_k) / total_client_pop

    return (
        w=w, λ=λ, n_open=length(open_set), cost_c=travel_c, mean_t=mean_t,
        n_frac=n_fractional_x, sum_x=sum_x, travel_relax=travel_relax,
        travel_c_topp=travel_c_topp, travel_c_greedy=travel_c_greedy, travel_c_multi=travel_c_multi,
        uncov_topp=uncov_topp, uncov_greedy=uncov_greedy, uncov_multi=uncov_multi,
        rounding=ROUNDING, open_set=open_set, assigned_k=assigned_k,
    )
end
