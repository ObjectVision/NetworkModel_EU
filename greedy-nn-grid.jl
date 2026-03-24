using Arrow


country = "Netherlands"
flag = 1

od = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_od.arrow")
loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_i.arrow")
fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_j.arrow")

clients_col = Int.(od[:client_rel])
facilities_col = Int.(od[:facility_rel])
t_ij_col = od[:t_ij]
population = loc[:pop]
facilities = Int.(fac[:id])

N = length(clients_col)
M = length(facilities)


locations = Dict{Int, Vector{Int}}()
for k in 1:N
    i = clients_col[k]
    haskey(locations, i) ? push!(locations[i], k) : (locations[i] = [k])
end

client_pop = Dict(i => population[i+1] * 0.1 for i in keys(locations))

# nearest facility
nearest_facility = Dict{Int, Int}()
for (i, rows) in locations
    best_k = rows[argmin(t_ij_col[k] for k in rows)]
    nearest_facility[i] = facilities_col[best_k]
end


function drop_heuristic(open_set, min_students, λ)
    open_set = copy(open_set)

    assigned = Dict{Int, Int}()
    cur_cost = Dict{Int, Float64}()
    fload = Dict(j => 0.0 for j in facilities)

    for (i, rows) in locations
        best_k = nothing
        best_cost = Inf
        for k in rows
            j = facilities_col[k]
            if j in open_set && t_ij_col[k] < best_cost
                best_cost = t_ij_col[k]
                best_k = k
            end
        end
        if best_k !== nothing
            j = facilities_col[best_k]
            assigned[i] = j
            cur_cost[i] = best_cost
            fload[j] += client_pop[i]
        end
    end

    facility_clients = Dict(j => Int[] for j in facilities)
    for (i, j) in assigned
        push!(facility_clients[j], i)
    end

    second_best = Dict{Int, Tuple{Int, Float64}}()
    for (i, rows) in locations
        if !haskey(assigned, i)
            continue
        end
        j_cur = assigned[i]
        best_alt = Inf
        best_alt_j = -1
        for k in rows
            j_cand = facilities_col[k]
            if j_cand != j_cur && j_cand in open_set && t_ij_col[k] < best_alt
                best_alt = t_ij_col[k]
                best_alt_j = j_cand
            end
        end
        if best_alt_j != -1
            second_best[i] = (best_alt_j, best_alt)
        end
    end

    second_best_clients = Dict(j => Set{Int}() for j in facilities)
    for (i, (j, _)) in second_best
        push!(second_best_clients[j], i)
    end

    improved = true
    while improved
        improved = false
        best_saving = 0.0
        best_j = nothing

        for j in open_set
            penalty_saving = flag * λ * max(0.0, min_students - fload[j])
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
                best_j = j
            end
        end

        if best_j !== nothing
            open_set = setdiff(open_set, [best_j])
            affected = union(Set(facility_clients[best_j]), get(second_best_clients, best_j, Set{Int}()))

            for i in facility_clients[best_j]
                old_second = second_best[i][1]
                new_j = second_best[i][1]
                new_cost = second_best[i][2]

                fload[best_j] -= client_pop[i]
                fload[new_j] += client_pop[i]
                assigned[i] = new_j
                cur_cost[i] = new_cost

                push!(facility_clients[new_j], i)
                if haskey(second_best_clients, old_second)
                    delete!(second_best_clients[old_second], i)
                end
            end
            facility_clients[best_j] = Int[]
            delete!(second_best_clients, best_j)

            for i in affected
                # if !haskey(assigned, i)
                #     continue
                # end
                if haskey(second_best, i) && haskey(second_best_clients, second_best[i][1])
                    delete!(second_best_clients[second_best[i][1]], i)
                end

                j_cur = assigned[i]
                best_alt = Inf
                best_alt_j = -1
                for k in locations[i]
                    j_cand = facilities_col[k]
                    if j_cand != j_cur && j_cand in open_set && t_ij_col[k] < best_alt
                        best_alt = t_ij_col[k]
                        best_alt_j = j_cand
                    end
                end
                if best_alt_j != -1
                    second_best[i] = (best_alt_j, best_alt)
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

    travel = sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
    penalty = flag * sum(λ * max(0.0, min_students - fload[j]) for j in open_set)

    return open_set, assigned, fload, cur_cost, travel, penalty
end


function run_scenario(min_students, λ_factor)

    total_time = sum(0.2 * t_ij_col[k] * client_pop[clients_col[k]] for k in 1:N)
    facility_cost = (2 * total_time * 200) / M
    λ = λ_factor * (facility_cost / (min_students / 2))

    # expected load
    expected_load = Dict(j => 0.0 for j in facilities)
    for (i, j) in nearest_facility
        expected_load[j] += client_pop[i]
    end

    min_viable_load = min_students * 0
    initial_open = Set(j for j in facilities if expected_load[j] >= min_viable_load)

    # ensure no student remains unassigned
    unassigned = Set(i for (i, rows) in locations if !any(facilities_col[k] in initial_open for k in rows))

    while !isempty(unassigned)
        coverage = Dict{Int, Int}()

        for i in unassigned
            for k in locations[i]
                j = facilities_col[k]
                if !(j in initial_open)
                    coverage[j] = get(coverage, j, 0) + 1
                end
            end
        end

        if isempty(coverage)
            i = first(unassigned)
            k = locations[i][argmin(t_ij_col[k] for k in locations[i])]
            push!(initial_open, facilities_col[k])
        else
            best_j = argmax(coverage)
            push!(initial_open, best_j)
        end

        for i in collect(unassigned)
            if any(facilities_col[k] in initial_open for k in locations[i])
                delete!(unassigned, i)
            end
        end
    end

    open_set, assigned, fload, cur_cost, travel, penalty = drop_heuristic(initial_open, min_students, λ)

    n_open_full = sum(1 for j in open_set if fload[j] >= min_students; init=0)
    n_open_small = sum(1 for j in open_set if fload[j] < min_students; init=0)

    travel = isempty(assigned) ? 0.0 :
        sum(cur_cost[i] * client_pop[i] for i in keys(assigned))

    penalty = isempty(open_set) ? 0.0 :
        flag * sum(λ * max(0.0, min_students - fload[j]) for j in open_set)

    return travel, penalty, n_open_full, n_open_small
end


function grid_search()

    min_students_values = [25, 50, 100, 150, 200]
    λ_factors = [0.00001, 0.0001, 0.001, 0.01, 0.1, 1.0]

    println("\ngrid search")
    println(rpad("min_students", 14),
            rpad("λ_factor", 10),
            rpad("open", 12),
            rpad("open>=min", 12),
            rpad("open<min", 12),
            rpad("travel", 14),
            "penalty")

    for min_students in min_students_values
        for λ_factor in λ_factors
            travel, penalty, n_open_full, n_open_small = run_scenario(min_students, λ_factor)
            println(rpad(min_students, 14), 
                    rpad(λ_factor, 10),
                    rpad(n_open_small+n_open_full, 12),
                    rpad(n_open_full, 12),
                    rpad(n_open_small, 12),
                    rpad(round(travel, digits=0), 14),
                    round(penalty, digits=0))
        end
    end
end

grid_search()