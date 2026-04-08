using Arrow, JuMP, HiGHS

country = "Romania"
travel  = "quadratic"  # "linear" or "quadratic"
grid    = true

od  = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_od.arrow")
loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_i.arrow")
fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_j.arrow")

clients_col    = Int.(od[:client_rel])
facilities_col = Int.(od[:facility_rel])
t_ij_col       = od[:t_ij] ./ 60
population     = loc[:pop]
facilities     = Int.(fac[:id])

N = length(clients_col)
M = length(facilities)

wpop = [population[clients_col[k]+1] * 0.1 for k in 1:N]

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

client_pop = Dict(i => wpop[rows[1]] for (i, rows) in locations)

function c(t)
    if travel == "quadratic"
        return 0.05 * t^2 + 0.5 * t
    else
        return t
    end
end

function facility_penalty(load, min_students, w, c0)
    isinf(min_students) ? w * c0 : w * c0 * max(0.0, min_students - load)
end

function run_scenario(min_students, w)
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

    for (i, rows) in locations
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
    fractional_set = Set(fractional)
    open_set       = union(fixed_open_set, fractional_set)

    # nearest facility assignment
    assigned = Dict{Int, Int}()
    cur_cost = Dict{Int, Float64}()
    cur_time = Dict{Int, Float64}()
    fload    = Dict(j => 0.0 for j in facilities)

    for (i, rows) in locations
        best_k    = nothing
        best_cost = Inf
        for k in rows
            j = facilities_col[k]
            if j in open_set
                ck = c(t_ij_col[k])
                if ck < best_cost
                    best_cost = ck
                    best_k    = k
                end
            end
        end
        if best_k !== nothing
            j           = facilities_col[best_k]
            assigned[i] = j
            cur_cost[i] = best_cost
            cur_time[i] = t_ij_col[best_k]
            fload[j]   += client_pop[i]
        end
    end

    facility_clients = Dict(j => Int[] for j in facilities)
    for (i, j) in assigned
        push!(facility_clients[j], i)
    end

    second_best = Dict{Int, Tuple{Int, Float64, Float64}}()
    for (i, rows) in locations
        if !haskey(assigned, i)
            continue
        end
        j_cur      = assigned[i]
        best_alt   = Inf
        best_alt_j = -1
        best_alt_k = nothing
        for k in rows
            jj = facilities_col[k]
            if jj != j_cur && jj in open_set
                ck = c(t_ij_col[k])
                if ck < best_alt
                    best_alt   = ck
                    best_alt_j = jj
                    best_alt_k = k
                end
            end
        end
        if best_alt_j != -1
            second_best[i] = (best_alt_j, best_alt, t_ij_col[best_alt_k])
        end
    end

    second_best_clients = Dict(j => Set{Int}() for j in facilities)
    for (i, (j, _, _)) in second_best
        push!(second_best_clients[j], i)
    end

    improved = true
    while improved
        improved    = false
        best_saving = 0.0
        best_j      = nothing

        for j in fractional
            if !(j in open_set)
                continue
            end

            penalty_saving = facility_penalty(fload[j], min_students, w, facility_cost)
            if penalty_saving == 0.0
                continue
            end

            travel_increase = 0.0
            feasible = true
            for i in facility_clients[j]
                if !haskey(second_best, i)
                    feasible = false
                    break
                end
                travel_increase += (second_best[i][2] - cur_cost[i]) * client_pop[i]
            end

            if !feasible
                continue
            end

            saving = penalty_saving - travel_increase
            if saving > best_saving
                best_saving = saving
                best_j      = j
            end
        end

        if best_j !== nothing
            open_set = setdiff(open_set, [best_j])
            affected = union(Set(facility_clients[best_j]), get(second_best_clients, best_j, Set{Int}()))

            for i in facility_clients[best_j]
                old_second = second_best[i][1]
                new_j      = second_best[i][1]
                new_cost   = second_best[i][2]
                new_time   = second_best[i][3]

                fload[best_j] -= client_pop[i]
                fload[new_j]  += client_pop[i]
                assigned[i]    = new_j
                cur_cost[i]    = new_cost
                cur_time[i]    = new_time

                push!(facility_clients[new_j], i)
                if haskey(second_best_clients, old_second)
                    delete!(second_best_clients[old_second], i)
                end
            end
            facility_clients[best_j] = Int[]
            delete!(second_best_clients, best_j)

            for i in affected
                if haskey(second_best, i) && haskey(second_best_clients, second_best[i][1])
                    delete!(second_best_clients[second_best[i][1]], i)
                end

                j_cur      = assigned[i]
                best_alt   = Inf
                best_alt_j = -1
                best_alt_k = nothing
                for k in locations[i]
                    jj = facilities_col[k]
                    if jj != j_cur && jj in open_set
                        ck = c(t_ij_col[k])
                        if ck < best_alt
                            best_alt   = ck
                            best_alt_j = jj
                            best_alt_k = k
                        end
                    end
                end
                if best_alt_j != -1
                    second_best[i] = (best_alt_j, best_alt, t_ij_col[best_alt_k])
                    if haskey(second_best_clients, best_alt_j)
                        push!(second_best_clients[best_alt_j], i)
                    end
                else
                    delete!(second_best, i)
                end
            end

            improved = true
        end
    end

    # no re-solve — all metrics from nearest assignment
    travel_nearest  = sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
    penalty_nearest = sum(facility_penalty(fload[j], min_students, w, facility_cost) for j in open_set)
    mean_travel_min = sum(cur_time[i] for i in keys(cur_time)) / length(cur_time)

    b1 = sum(client_pop[i] for (i, t) in cur_time if t < 15;       init=0.0)
    b2 = sum(client_pop[i] for (i, t) in cur_time if 15 <= t < 30; init=0.0)
    b3 = sum(client_pop[i] for (i, t) in cur_time if t >= 30;      init=0.0)

    n_open_full  = isinf(min_students) ? length(open_set) : sum(1 for j in open_set if fload[j] >= min_students; init=0)
    n_open_small = isinf(min_students) ? 0                : sum(1 for j in open_set if fload[j] < min_students;  init=0)

    return open_set, assigned, fload, cur_cost, cur_time, n_open_full, n_open_small, mean_travel_min, travel_nearest, penalty_nearest, b1, b2, b3
end


if grid
    min_students_values = [25.0, 50.0, 100.0, 150.0, 200.0, Inf]
    ws = [0.00001, 0.0001, 0.001, 0.01, 0.1, 1.0]

    println("\ngrid search (travel=$(travel))")
    println(rpad("min_students", 14),
            rpad("policy_weight", 14),
            rpad("open", 8),
            rpad(">=min", 8),
            rpad("<min", 8),
            rpad("travel", 14),
            rpad("penalty", 14),
            rpad("mean_t (min)", 14),
            rpad("t<=15", 10),
            rpad("15<t<=30", 10),
            "t>30")

    for min_students in min_students_values
        for w in ws
            open_set, assigned, fload, cur_cost, cur_time, n_open_full, n_open_small, mean_travel_min, travel_nearest, penalty_nearest, b1, b2, b3 = run_scenario(min_students, w)
            ms_label = isinf(min_students) ? "Inf" : string(round(Int, min_students))
            println(rpad(ms_label, 14),
                    rpad(w, 14),
                    rpad(n_open_full + n_open_small, 8),
                    rpad(n_open_full, 8),
                    rpad(n_open_small, 8),
                    rpad(round(travel_nearest, digits=0), 14),
                    rpad(round(penalty_nearest, digits=0), 14),
                    rpad(round(mean_travel_min, digits=2), 14),
                    rpad(round(Int, b1), 10),
                    rpad(round(Int, b2), 10),
                    round(Int, b3))
        end
    end
else
    open_set, assigned, fload, cur_cost, cur_time, n_open_full, n_open_small, mean_travel_min, travel_nearest, penalty_nearest, b1, b2, b3 = run_scenario(50.0, 1.0)

    n_open = n_open_full + n_open_small
    println("\nresults (travel=$(travel), min_students=50, w=1.0):")
    println("open (>= min_students): $n_open_full")
    println("open (< min_students): $n_open_small")
    println("closed: $(M - n_open)")
    println("total: $M")
    println("travel (nearest): ", round(travel_nearest, digits=0))
    println("penalty (nearest): ", round(penalty_nearest, digits=0))
    println("mean travel time (min): ", round(mean_travel_min, digits=2))
    println("t < 15 min: ", round(Int, b1))
    println("15 <= t < 30 min: ", round(Int, b2))
    println("t >= 30 min: ", round(Int, b3))
    println("unassigned clients: ", sum(1 for i in keys(locations) if !haskey(assigned, i); init=0))

    open_vec = zeros(Int, M)
    for (idx, j) in enumerate(facilities)
        if j in open_set
            open_vec[idx] = isinf(50.0) || fload[j] >= 50.0 ? 1 : 2
        end
    end

    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_lp.arrow", (
        id   = facilities,
        open = open_vec
    ))
end