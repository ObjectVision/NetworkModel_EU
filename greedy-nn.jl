using Arrow

country = "Romania"
travel = "linear"  # "linear", "quadratic", or "piecewise"
grid = false       # set to false to run a single scenario
underenrollment = false

od = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_od.arrow")
loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_i.arrow")
fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_j.arrow")

clients_col = Int.(od[:client_rel])
facilities_col = Int.(od[:facility_rel])
t_ij_col = od[:t_ij] ./ 60  # convert to minutes
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

function c(t)
    if travel == "quadratic"
        return 0.05 * t^2 + 0.5 * t
    elseif travel == "piecewise"
        if t <= 15
            return 1.0 * t
        elseif t <= 30
            return 2.0 * t
        else
            return 4.0 * t
        end
    elseif travel == "linear"
        return t
    end
end

nearest_facility = Dict{Int, Int}()
for (i, rows) in locations
    best_k = rows[argmin(c(t_ij_col[k]) for k in rows)]
    nearest_facility[i] = facilities_col[best_k]
end


function drop_heuristic(open_set, min_students, w, facility_cost)
    open_set = copy(open_set)

    assigned = Dict{Int, Int}()
    cur_cost = Dict{Int, Float64}()
    cur_time = Dict{Int, Float64}()
    fload = Dict(j => 0.0 for j in facilities)

    for (i, rows) in locations
        best_k = nothing
        best_cost = Inf
        for k in rows
            j = facilities_col[k]
            if j in open_set
                ck = c(t_ij_col[k])
                if ck < best_cost
                    best_cost = ck
                    best_k = k
                end
            end
        end
        if best_k !== nothing
            j = facilities_col[best_k]
            assigned[i] = j
            cur_cost[i] = best_cost
            cur_time[i] = t_ij_col[best_k]  # already in minutes
            fload[j] += client_pop[i]
        end
    end

    facility_clients = Dict(j => Int[] for j in facilities)
    for (i, j) in assigned
        push!(facility_clients[j], i)
    end

    # second_best: (facility, cost, time in minutes)
    second_best = Dict{Int, Tuple{Int, Float64, Float64}}()
    for (i, rows) in locations
        if !haskey(assigned, i)
            continue
        end
        j_cur = assigned[i]
        best_alt = Inf
        best_alt_j = -1
        best_alt_k = nothing
        for k in rows
            j_cand = facilities_col[k]
            if j_cand != j_cur && j_cand in open_set
                ck = c(t_ij_col[k])
                if ck < best_alt
                    best_alt = ck
                    best_alt_j = j_cand
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
        improved = false
        best_saving = 0.0
        best_j = nothing

        for j in open_set
            penalty_saving = underenrollment ? w * facility_cost * max(0.0, min_students - fload[j]) : w * facility_cost
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
                new_time = second_best[i][3]

                fload[best_j] -= client_pop[i]
                fload[new_j] += client_pop[i]
                assigned[i] = new_j
                cur_cost[i] = new_cost
                cur_time[i] = new_time

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

                j_cur = assigned[i]
                best_alt = Inf
                best_alt_j = -1
                best_alt_k = nothing
                for k in locations[i]
                    j_cand = facilities_col[k]
                    if j_cand != j_cur && j_cand in open_set
                        ck = c(t_ij_col[k])
                        if ck < best_alt
                            best_alt = ck
                            best_alt_j = j_cand
                            best_alt_k = k
                        end
                    end
                end
                if best_alt_j != -1
                    second_best[i] = (best_alt_j, best_alt, t_ij_col[best_alt_k])  # already in minutes
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
    penalty = underenrollment ? sum(w * facility_cost * max(0.0, min_students - fload[j]) for j in open_set) : sum(w * facility_cost for j in open_set)

    return open_set, assigned, fload, cur_cost, cur_time, travel, penalty
end


function run_scenario(min_students, w)
    facility_cost = 99699

    expected_load = Dict(j => 0.0 for j in facilities)
    for (i, j) in nearest_facility
        expected_load[j] += client_pop[i]
    end

    min_viable_load = min_students * 0
    initial_open = Set(j for j in facilities if expected_load[j] >= min_viable_load)

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
            k = locations[i][argmin(c(t_ij_col[k]) for k in locations[i])]
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

    open_set, assigned, fload, cur_cost, cur_time, travel, penalty = drop_heuristic(initial_open, min_students, w, facility_cost)

    n_open_full = sum(1 for j in open_set if fload[j] >= min_students; init=0)
    n_open_small = sum(1 for j in open_set if fload[j] < min_students; init=0)

    travel = isempty(assigned) ? 0.0 :
        sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
    penalty = isempty(open_set) ? 0.0 :
        (underenrollment ? sum(w * facility_cost * max(0.0, min_students - fload[j]) for j in open_set) : sum(w * facility_cost for j in open_set))

    # b1 = sum(1 for (i, t) in cur_time if t <= 15; init=0)
    # b2 = sum(1 for (i, t) in cur_time if 15 < t <= 30; init=0)
    # b3 = sum(1 for (i, t) in cur_time if t > 30; init=0)
    # println("  assigned clients by travel band:")
    # println("    t <= 15 min:      $b1 (", round(100*b1/length(assigned), digits=1), "%)")
    # println("    15 < t <= 30 min: $b2 (", round(100*b2/length(assigned), digits=1), "%)")
    # println("    t > 30 min:       $b3 (", round(100*b3/length(assigned), digits=1), "%)")

    mean_travel_min = sum(cur_time[i] for i in keys(cur_time)) / length(cur_time)

    return open_set, assigned, fload, cur_cost, cur_time, travel, penalty, n_open_full, n_open_small, mean_travel_min
end


function grid_search()
    min_students_values = underenrollment ? [25, 50, 100, 150, 200] : [50]
    ws = [0.00001, 0.0001, 0.001, 0.01, 0.1, 1.0]

    println("\ngrid search (travel cost function=$(travel))")
    println(rpad("min_students", 14),
            rpad("policy_weight", 14),
            rpad("open", 8),
            rpad(">=min", 8),
            rpad("<min", 8),
            rpad("travel_cost", 14),
            rpad("facility_cost", 14),
            "mean_t (min)")

    for min_students in min_students_values
        for w in ws
            open_set, assigned, fload, cur_cost, cur_time, travel, penalty, n_open_full, n_open_small, mean_travel_min = run_scenario(min_students, w)
            println(rpad(min_students, 14),
                    rpad(w, 14),
                    rpad(n_open_small + n_open_full, 8),
                    rpad(n_open_full, 8),
                    rpad(n_open_small, 8),
                    rpad(round(travel, digits=0), 14),
                    rpad(round(penalty, digits=0), 14),
                    round(mean_travel_min, digits=2))
        end
    end
end


function single_run(min_students, w)
    open_set, assigned, fload, cur_cost, cur_time, travel, penalty, n_open_full, n_open_small, mean_travel_min = run_scenario(min_students, w)

    n_open = n_open_full + n_open_small
    println("\nresults (travel cost=$(travel), min_students=$(min_students), w=$(w)):")
    println("open: $n_open")
    println("open (>= min_students): $n_open_full")
    println("open (< min_students): $n_open_small")
    println("closed: $(M - n_open)")
    println("total: $M")
    println("travel: ", round(travel, digits=0))
    println("penalty: ", round(penalty, digits=0))
    println("mean travel time (min): ", round(mean_travel_min, digits=2))
    println("unassigned clients: ", sum(1 for i in keys(locations) if !haskey(assigned, i); init=0))

    open_vec = zeros(Int, M)
    for (idx, j) in enumerate(facilities)
        if j in open_set
            open_vec[idx] = fload[j] >= min_students ? 1 : 2
        end
    end

    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_greedy.arrow", (
        id = facilities,
        open = open_vec
    ))
end


if grid
    grid_search()
else
    single_run(50, 1)
end