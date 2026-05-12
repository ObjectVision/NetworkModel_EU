using Arrow, JuMP, HiGHS

countries         = ["Netherlands"]  # add more countries here
travel            = "quadratic"  # "linear" or "quadratic"
grid              = true
apply_thresholds  = [true]       # add false to also run without max-travel filter
nearest           = true               # true: assign each client to nearest open school; false: re-solve LP for assignments

function c(t)
    travel == "quadratic" ? 0.05 * t^2 + 0.5 * t : t
end

function load_country(country)
    od  = Arrow.Table("C:\\LocalData\\networkmodel_eu\\ExistingSchools\\$(country)_od.arrow")
    loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\ExistingSchools\\$(country)_i.arrow")
    fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\ExistingSchools\\$(country)_j.arrow")

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
        if !haskey(facility_rows, j)
            facility_rows[j] = Int[]
        end
        push!(facility_rows[j], k)
    end
    for j in facilities
        if !haskey(facility_rows, j)
            facility_rows[j] = Int[]
        end
    end

    return (; N, M, facilities, wpop, t_ij_col, facilities_col, locations, facility_rows)
end

function run_scenario(data, min_students, w, apply_threshold)
    (; N, facilities, wpop, t_ij_col, facilities_col, locations, facility_rows) = data

    facility_cost = 99699
    λ = w * facility_cost

    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "presolve", "on")
    set_optimizer_attribute(model, "output_flag", false)

    @variable(model, 0 <= y[1:N] <= 1)
    @variable(model, 0 <= x[j in facilities] <= 1)

    if !isinf(min_students)
        @variable(model, deficit[j in facilities] >= 0)
        @expression(model, load[j in facilities],
            sum(y[k] * wpop[k] for k in facility_rows[j])
        )
        @objective(model, Min,
            sum(y[k] * c(t_ij_col[k]) * wpop[k] for k in 1:N) +
            sum(deficit[j] * λ for j in facilities)
        )
        for j in facilities
            @constraint(model, deficit[j] >= min_students * x[j] - load[j])
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

    x_relaxed      = value.(x)
    tol            = 1e-6
    fixed_open_set = Set([j for j in facilities if x_relaxed[j] >= 1 - tol])
    fractional     = [j for j in facilities if tol < x_relaxed[j] < 1 - tol]
    open_set       = union(fixed_open_set, Set(fractional))

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
    penalty_lp     = isinf(min_students) ?
                         length(open_set) * facility_cost * w :
                         sum(max(0.0, min_students - fload[j]) * λ for j in open_set; init=0.0)
    raw_penalty_lp = isinf(min_students) ?
                         length(open_set) * facility_cost :
                         sum(max(0.0, min_students - fload[j]) * facility_cost for j in open_set; init=0.0)

    n_open_full  = isinf(min_students) ? length(open_set) : sum(1 for j in open_set if fload[j] >= min_students; init=0)
    n_open_small = isinf(min_students) ? 0                : sum(1 for j in open_set if fload[j] < min_students;  init=0)

    return open_set, fload, assigned_k, n_open_full, n_open_small, mean_travel_min, travel_lp, penalty_lp, raw_penalty_lp, b1, b2, b3, b4
end


if grid
    # min_students_values = [25.0, 50.0, 100.0, 150.0, 200.0]
    # ws = [0.00001, 0.0001, 0.001, 0.01, 0.1, 1.0]
    min_students_values = [50.0, 100.0, 200.0]
    ws = [0.0001, 0.01, 1.0]

    for country in countries
        max_facility_load = 0.0

        local data = load_country(country)

        for apply_threshold in apply_thresholds
            threshold_label = apply_threshold ? "max_travel=60 min" : "no max_travel"

            assignment_label = nearest ? "nearest" : "central"
            println("\n$country — grid search (travel=$(travel), $(threshold_label), assignment=$(assignment_label))")
            println(rpad("min_students", 14),
                    rpad("policy_weight", 14),
                    rpad("open", 8),
                    rpad(">=min", 8),
                    rpad("<min", 8),
                    rpad("travel", 14),
                    rpad("penalty", 16),
                    rpad("mean_t (min)", 14),
                    rpad("t<=15", 10),
                    rpad("15<t<=30", 10),
                    rpad("30<t<=60", 10),
                    "t>60")

            for min_students in min_students_values
                for w in ws
                    local open_set, fload, assigned_k, n_open_full, n_open_small, mean_travel_min, travel_lp, penalty_lp, raw_penalty_lp, b1, b2, b3, b4 = run_scenario(data, min_students, w, apply_threshold)
                    if !isempty(open_set)
                        max_facility_load = max(max_facility_load, maximum(fload[j] for j in open_set))
                    end
                    ms_label = isinf(min_students) ? "Inf" : string(round(Int, min_students))
                    println(rpad(ms_label, 14),
                            rpad(w, 14),
                            rpad(n_open_full + n_open_small, 8),
                            rpad(n_open_full, 8),
                            rpad(n_open_small, 8),
                            rpad(round(travel_lp, digits=0), 14),
                            rpad(round(raw_penalty_lp, digits=0), 16),
                            rpad(round(mean_travel_min, digits=2), 14),
                            rpad(round(Int, b1), 10),
                            rpad(round(Int, b2), 10),
                            rpad(round(Int, b3), 10),
                            round(Int, b4))
                end
            end
        end
        println("\n$country — max facility load across all configurations: ", round(Int, max_facility_load))
    end
else
    country         = countries[1]
    apply_threshold = apply_thresholds[1]
    data            = load_country(country)
    open_set, fload, assigned_k, n_open_full, n_open_small, mean_travel_min, travel_lp, penalty_lp, raw_penalty_lp, b1, b2, b3, b4 = run_scenario(data, 50.0, 1.0, apply_threshold)
    n_open = n_open_full + n_open_small
    println("\nresults (travel=$(travel), min_students=50, w=1.0, max_travel=60 min):")
    println("open (>= min_students): $n_open_full")
    println("open (< min_students): $n_open_small")
    println("closed: $(data.M - n_open)")
    println("total: $(data.M)")
    println("travel (LP): ", round(travel_lp, digits=0))
    println("penalty (LP): ", round(raw_penalty_lp, digits=0))
    println("mean travel time (min): ", round(mean_travel_min, digits=2))
    println("t < 15 min: ", round(Int, b1))
    println("15 <= t < 30 min: ", round(Int, b2))
    println("30 <= t < 60 min: ", round(Int, b3))
    println("t >= 60 min: ", round(Int, b4))

    open_vec = zeros(Int, data.M)
    for (idx, j) in enumerate(data.facilities)
        if j in open_set
            open_vec[idx] = isinf(50.0) || fload[j] >= 50.0 ? 1 : 2
        end
    end

    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_lp.arrow", (
        id = data.facilities, open = open_vec
    ))

    sorted_ids = sort(collect(keys(assigned_k)))
    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_i_travel.arrow", (
        id   = sorted_ids,
        t_ij = [data.t_ij_col[assigned_k[i]] for i in sorted_ids]
    ))
end
