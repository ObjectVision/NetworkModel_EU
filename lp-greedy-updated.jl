using Arrow, JuMP, HiGHS

country       = "Romania"
travel        = "quadratic"   # "linear" or "quadratic"
facility_cost = 99699
grid          = false       # set to false for single run
w_single      = 1     # used when grid = false
min_students_single = 50  # used when grid = false

od  = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_od.arrow")
loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_i.arrow")
fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_j.arrow")

clients_col    = Int.(od[:client_rel])
facilities_col = Int.(od[:facility_rel])
t_ij_col       = od[:t_ij] ./ 60  # convert to minutes
population     = loc[:pop]
facilities     = Int.(fac[:id])

N = length(clients_col)
M = length(facilities)

wpop = [population[clients_col[k]+1] * 0.1 for k in 1:N]

locations = Dict{Int, Vector{Int}}()
for k in 1:N
    i = clients_col[k]
    if haskey(locations, i)
        push!(locations[i], k)
    else
        locations[i] = [k]
    end
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


function run_scenario(min_students, w)
    λ = w * facility_cost

    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "presolve", "on")
    set_optimizer_attribute(model, "user_objective_scale", -2)
    set_optimizer_attribute(model, "output_flag", false)

    @variable(model, 0 <= y[1:N] <= 1)
    @variable(model, 0 <= x[j in facilities] <= 1)
    @variable(model, deficit[j in facilities] >= 0)

    @expression(model, load[j in facilities],
        sum(y[k] * wpop[k] for k in facility_rows[j])
    )

    @objective(model, Min,
        sum(y[k] * c(t_ij_col[k]) * wpop[k] for k in 1:N) +
        sum(deficit[j] * λ for j in facilities)
    )

    for (i, rows) in locations
        @constraint(model, sum(y[k] for k in rows) == 1)
    end
    for k in 1:N
        @constraint(model, y[k] <= x[facilities_col[k]])
    end
    for j in facilities
        @constraint(model, deficit[j] >= min_students * x[j] - load[j])
    end

    optimize!(model)

    x_relaxed = value.(x)
    tol = 1e-6
    fixed_open_set = Set([j for j in facilities if x_relaxed[j] >= 1 - tol])
    fractional     = [j for j in facilities if tol < x_relaxed[j] < 1 - tol]
    fractional_set = Set(fractional)

    open_set = union(fixed_open_set, fractional_set)

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
            j = facilities_col[best_k]
            assigned[i] = j
            cur_cost[i] = best_cost
            cur_time[i] = t_ij_col[best_k]  # raw minutes for reporting
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

            penalty_saving = λ * max(0.0, min_students - fload[j])
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

    # fix and re-solve for optimal assignment
    for j in facilities
        fix(x[j], j in open_set ? 1.0 : 0.0; force=true)
    end
    optimize!(model)

    n_open_full     = sum(1 for j in open_set if fload[j] >= min_students; init=0)
    n_open_small    = sum(1 for j in open_set if fload[j] < min_students; init=0)
    mean_travel_min = sum(cur_time[i] for i in keys(cur_time)) / length(cur_time)
    travel_lp       = sum(value(y[k]) * c(t_ij_col[k]) * wpop[k] for k in 1:N)
    penalty_lp      = sum(value(deficit[j]) * λ for j in facilities)

    return open_set, assigned, fload, cur_cost, cur_time, n_open_full, n_open_small, mean_travel_min, travel_lp, penalty_lp
end


if grid
    min_students_values = [25, 50, 100, 150, 200]
    ws = [0.00001, 0.0001, 0.001, 0.01, 0.1, 1.0]

    println("\ngrid search (travel=$(travel))")
    println(rpad("min_students", 14),
            rpad("policy_weight", 14),
            rpad("open", 8),
            rpad(">=min", 8),
            rpad("<min", 8),
            rpad("travel", 14),
            rpad("penalty", 14),
            "mean_t (min)")

    for min_students in min_students_values
        for w in ws
            open_set, assigned, fload, cur_cost, cur_time, n_open_full, n_open_small, mean_travel_min, travel_lp, penalty_lp = run_scenario(min_students, w)
            println(rpad(min_students, 14),
                    rpad(w, 14),
                    rpad(n_open_full + n_open_small, 8),
                    rpad(n_open_full, 8),
                    rpad(n_open_small, 8),
                    rpad(round(travel_lp, digits=0), 14),
                    rpad(round(penalty_lp, digits=0), 14),
                    round(mean_travel_min, digits=2))
        end
    end
else
    open_set, assigned, fload, cur_cost, cur_time, n_open_full, n_open_small, mean_travel_min, travel_lp, penalty_lp = run_scenario(min_students_single, w_single)

    n_open = n_open_full + n_open_small
    println("\nresults (travel=$(travel), min_students=$(min_students_single), w=$(w_single)):")
    println("open (>= min_students): $n_open_full")
    println("open (< min_students): $n_open_small")
    println("closed: $(M - n_open)")
    println("total: $M")
    println("travel (LP reassign): ", round(travel_lp, digits=0))
    println("penalty (LP reassign): ", round(penalty_lp, digits=0))
    println("mean travel time (min): ", round(mean_travel_min, digits=2))
    println("unassigned clients: ", sum(1 for i in keys(locations) if !haskey(assigned, i); init=0))

    open_vec = zeros(Int, M)
    for (idx, j) in enumerate(facilities)
        if j in open_set
            open_vec[idx] = fload[j] >= min_students_single ? 1 : 2
        end
    end

    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_greedy.arrow", (
        id = facilities,
        open = open_vec
    ))
end