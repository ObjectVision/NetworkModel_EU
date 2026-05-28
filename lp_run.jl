include("settings.jl")

struct WarmStartState{TX, TY}
    model::Model
    x::TX
    y::TY
    data::CountryData
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

    # Travel-cost objective term (constant across w); x-term coefficients are
    # set per call to solve_at_w!. We initialise them to 0 here.
    @objective(model, Min, sum(y[k] * c(t_ij_col[k]) * wpop[k] for k in 1:N))

    for (_, rows) in locations
        @constraint(model, sum(y[k] for k in rows) == 1)
    end
    for k in 1:N
        @constraint(model, y[k] <= x[facilities_col[k]])
    end

    return WarmStartState(model, x, y, data)
end

function solve_at_w!(state::WarmStartState, w::Real)
    (; model, x, y, data) = state
    (; N, facilities, wpop, t_ij_col, facilities_col, locations) = data

    λ = w * FACILITY_MIN_COSTS

    # Update only the x[j] objective coefficients; simplex warm-starts from
    # the previous basis since constraints and y-coefficients are unchanged.
    for j in facilities
        set_objective_coefficient(model, x[j], λ)
    end

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
    travel_relax   = sum(y_relaxed[k] * c(t_ij_col[k]) * wpop[k] for k in 1:N)

    # Top-p facility set by x_relaxed
    p_open      = clamp(round(Int, sum_x), 1, length(facilities))
    sorted_by_x = sort(collect(facilities), by=j -> x_relaxed[j], rev=true)
    open_set    = Set(sorted_by_x[1:p_open])

    # LP2: fix x to top-p (1) / non-top-p (0), re-solve for y. Gives the
    # LP-optimal travel cost under the chosen integer open_set, with no
    # phantom-fractional smearing. Should match the deterministic phase-2.
    for j in facilities
        fix(x[j], j in open_set ? 1.0 : 0.0; force=true)
    end
    optimize!(model)
    ts2 = termination_status(model)
    travel_relax_topp = if ts2 ∈ (OPTIMAL, LOCALLY_SOLVED, ALMOST_OPTIMAL)
        sum(value(y[k]) * c(t_ij_col[k]) * wpop[k] for k in 1:N)
    else
        NaN
    end
    # Restore x to free [0,1] so next w's LP1 can warm-start
    for j in facilities
        unfix(x[j])
        set_lower_bound(x[j], 0.0)
        set_upper_bound(x[j], 1.0)
    end

    # Phase 2 deterministic nearest-open (kept as independent cross-check)
    assigned_k = Dict{Int, Int}()
    for (i, rows) in locations
        candidates = [k for k in rows if facilities_col[k] in open_set]
        if !isempty(candidates)
            assigned_k[i] = candidates[argmin(c(t_ij_col[k]) for k in candidates)]
        end
    end

    total_client_pop = sum(wpop[rows[1]] for (_, rows) in locations)
    travel_c         = isempty(assigned_k) ? 0.0 : sum(c(t_ij_col[k]) * wpop[k] for (i, k) in assigned_k)
    mean_t           = isempty(assigned_k) ? 0.0 : sum(t_ij_col[k] * wpop[k] for (i, k) in assigned_k) / total_client_pop

    return (
        w=w, λ=λ, n_open=length(open_set), cost_c=travel_c, mean_t=mean_t,
        n_frac=n_fractional_x, sum_x=sum_x,
        travel_relax=travel_relax, travel_relax_topp=travel_relax_topp,
    )
end
