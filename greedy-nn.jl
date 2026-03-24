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

min_students = 100
total_time = sum(0.2 * t_ij_col[k] * client_pop[clients_col[k]] for k in 1:N)
facility_cost = (2 * total_time * 200) / M
λ = facility_cost / (min_students / 2) * 0.00001

nearest_facility = Dict{Int, Int}()
nearest_cost = Dict{Int, Float64}()

for (i, rows) in locations
    best_k = nothing
    best_cost = Inf
    for k in rows
        if t_ij_col[k] < best_cost
            best_cost = t_ij_col[k]
            best_k = k
        end
    end
    nearest_facility[i] = facilities_col[best_k]
    nearest_cost[i] = best_cost
end

expected_load = Dict(j => 0.0 for j in facilities)
for (i, j) in nearest_facility
    expected_load[j] += client_pop[i]
end

println("facilities with expected load >= min_students: ",
    sum(1 for j in facilities if expected_load[j] >= min_students))
println("facilities with expected load < min_students: ",
    sum(1 for j in facilities if expected_load[j] < min_students))

min_viable_load = min_students * 0.5
initial_open = Set(j for j in facilities if expected_load[j] >= min_viable_load)

println("initially open: ", length(initial_open))
println("initially closed: ", M - length(initial_open))


unassigned = Set(i for (i, rows) in locations if !any(facilities_col[k] in initial_open for k in rows))
force_open = 0
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
    best_j = argmax(coverage)
    push!(initial_open, best_j)
    global force_open += 1
    for i in collect(unassigned)
        if any(facilities_col[k] == best_j for k in locations[i])
            delete!(unassigned, i)
        end
    end
end

println("force open ", force_open)


function drop_heuristic(open_set)
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

    travel_cost = sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
    penalty_cost = flag * sum(λ * max(0.0, min_students - fload[j]) for j in open_set)
    current_cost = travel_cost + penalty_cost

    println("initial cost: ", round(current_cost, digits=0),
            " (travel=", round(travel_cost, digits=0),
            " penalty=", round(penalty_cost, digits=0), ")")

    n_closed_count = 0
    improved = true
    while improved
        improved = false
        best_saving = 0.0
        best_j = nothing

        # find facility to close
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

        # if we find a facility to close
        if best_j !== nothing
            open_set = setdiff(open_set, [best_j])

            # collect affected clients
            affected = union(Set(facility_clients[best_j]), get(second_best_clients, best_j, Set{Int}()))

            # reassign clients
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

            # update second_best for affected clients
            for i in affected
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
                    # if client no longer has an alternative
                    delete!(second_best, i)
                end
            end

            travel_cost = sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
            penalty_cost = flag * sum(λ * max(0.0, min_students - fload[j]) for j in open_set)
            current_cost = travel_cost + penalty_cost

            n_closed_count += 1
            print("\rclosed $n_closed_count facilities, cost=$(round(current_cost, digits=0)), penalty=$(round(penalty_cost, digits=0))    ")
            improved = true
        end
    end
    println()

    return open_set, assigned, fload, cur_cost, current_cost
end

open_set, assigned, fload, cur_cost, total_cost = drop_heuristic(initial_open)

open_vec = zeros(Int, M)
for (idx, j) in enumerate(facilities)
    if j in open_set
        open_vec[idx] = fload[j] >= min_students ? 1 : 2
    end
end

n_open_full = sum(open_vec .== 1)
n_open_small = sum(open_vec .== 2)
n_open = n_open_full + n_open_small
n_closed = sum(open_vec .== 0)

println("\nresults:")
println("open: $n_open")
println("open (>= min_students): $n_open_full")
println("open (< min_students): $n_open_small")
println("closed: $n_closed")
println("total: $M")
println("travel: ", sum(cur_cost[i] * client_pop[i] for i in keys(assigned)))
println("penalty: ", flag * sum(λ * max(0.0, min_students - fload[j]) for j in open_set))

unassigned_list = [i for i in keys(locations) if !haskey(assigned, i)]
println("unassigned clients: ", length(unassigned_list))

Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_greedy.arrow", (
    id = facilities,
    open = open_vec
))