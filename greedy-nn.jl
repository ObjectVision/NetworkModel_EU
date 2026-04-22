using Arrow

country = "Netherlands"
travel  = "quadratic"   # "linear", "quadratic", or "piecewise"
grid    = true
policy  = false       # true: vary min_students [25..200]; false: Inf (no minimum)

od = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_od.arrow")
loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_i.arrow")
fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_j.arrow")

clients_col    = Int.(od[:client_rel])
facilities_col = Int.(od[:facility_rel])
t_ij_col       = od[:t_ij] ./ 60
population     = loc[:pop]
facilities     = Int.(fac[:id])

N = length(clients_col)
M = length(facilities)
println(M)

locations = Dict{Int, Vector{Int}}()
for k in 1:N
    i = clients_col[k]
    haskey(locations, i) ? push!(locations[i], k) : (locations[i] = [k])
end

client_pop = Dict(i => population[i+1] for i in keys(locations))

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

# if min_students is Inf: fixed cost w * c0 per open facility
# else: w * c0 * max(0, min_students - load)
function facility_penalty(load, min_students, w, c0)
    isinf(min_students) ? w * c0 : w * c0 * max(0.0, min_students - load)
end

function drop_heuristic(open_set, min_students, w, facility_cost)
    open_set = copy(open_set)

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
            j_cand = facilities_col[k]
            if j_cand != j_cur && j_cand in open_set
                ck = c(t_ij_col[k])
                if ck < best_alt
                    best_alt   = ck
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
        improved    = false
        best_saving = 0.0
        best_j      = nothing

        for j in open_set
            # saving from closing j: penalty we avoid by closing it
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
                    j_cand = facilities_col[k]
                    if j_cand != j_cur && j_cand in open_set
                        ck = c(t_ij_col[k])
                        if ck < best_alt
                            best_alt   = ck
                            best_alt_j = j_cand
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

    travel  = sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
    penalty = sum(facility_penalty(fload[j], min_students, w, facility_cost) for j in open_set)

    return open_set, assigned, fload, cur_cost, cur_time, travel, penalty
end


function run_scenario(min_students, w)
    facility_cost = 99699

    expected_load = Dict(j => 0.0 for j in facilities)
    for (i, j) in nearest_facility
        expected_load[j] += client_pop[i]
    end

    initial_open = Set(j for j in facilities if expected_load[j] >= 0)

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

    # n_open_full  = isinf(min_students) ? length(open_set) : sum(1 for j in open_set if fload[j] >= min_students; init=0)
    # n_open_small = isinf(min_students) ? 0                : sum(1 for j in open_set if fload[j] < min_students;  init=0)
    n_open_full  = isinf(min_students) ? sum(1 for j in open_set if fload[j] >= 50; init=0) : sum(1 for j in open_set if fload[j] >= min_students; init=0)
    n_open_small = isinf(min_students) ? sum(1 for j in open_set if fload[j] < 50;  init=0) : sum(1 for j in open_set if fload[j] < min_students;  init=0)

    travel      = isempty(assigned) ? 0.0 : sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
    penalty     = isempty(open_set) ? 0.0 : sum(facility_penalty(fload[j], min_students, w, facility_cost) for j in open_set)
    raw_penalty = isempty(open_set) ? 0.0 : sum(isinf(min_students) ? facility_cost : facility_cost * max(0.0, min_students - fload[j]) for j in open_set)

    total_client_pop = sum(client_pop[i] for i in keys(cur_time))
    mean_travel_min = sum(cur_time[i] * client_pop[i] for i in keys(cur_time)) / total_client_pop

    return open_set, assigned, fload, cur_cost, cur_time, travel, penalty, raw_penalty, n_open_full, n_open_small, mean_travel_min
end


function grid_search()
    min_students_values = policy ? [25.0, 50.0, 100.0] : [Inf]
    ws = [0.00001, 0.0001, 0.001, 0.01, 0.1, 1]

    println("\ngrid search (travel cost function=$(travel))")
    println(rpad("min_students", 14),
            rpad("policy_weight", 14),
            rpad("open", 8),
            rpad(">=min_students", 16),
            rpad("<min_students", 16),
            rpad("travel_cost", 14),
            rpad("facility_cost", 16),
            rpad("mean_t (min)", 14),
            rpad("t<=15", 10),
            rpad("15<t<=30", 10),
            "t>30")

    for min_students in min_students_values
        for w in ws
            open_set, assigned, fload, cur_cost, cur_time, travel, penalty, raw_penalty, n_open_full, n_open_small, mean_travel_min = run_scenario(min_students, w)

            b1 = sum(client_pop[i] for (i, t) in cur_time if t < 15; init=0.0)
            b2 = sum(client_pop[i] for (i, t) in cur_time if 15 <= t < 30; init=0.0)
            b3 = sum(client_pop[i] for (i, t) in cur_time if t >= 30; init=0.0)

            ms_label = isinf(min_students) ? "None" : string(round(Int, min_students))

            println(rpad(ms_label, 14),
                    rpad(w, 14),
                    rpad(n_open_full + n_open_small, 8),
                    rpad(n_open_full, 16),
                    rpad(n_open_small, 16),
                    rpad(round(travel, digits=0), 14),
                    rpad(round(raw_penalty, digits=0), 16),
                    rpad(round(mean_travel_min, digits=2), 14),
                    rpad(round(Int, b1), 10),
                    rpad(round(Int, b2), 10),
                    round(Int, b3))
        end
    end
end


function single_run(min_students, w)
    open_set, assigned, fload, cur_cost, cur_time, travel, penalty, raw_penalty, n_open_full, n_open_small, mean_travel_min = run_scenario(min_students, w)

    b1 = sum(client_pop[i] for (i, t) in cur_time if t < 15; init=0.0)
    b2 = sum(client_pop[i] for (i, t) in cur_time if 15 <= t < 30; init=0.0)
    b3 = sum(client_pop[i] for (i, t) in cur_time if t >= 30; init=0.0)

    n_open = n_open_full + n_open_small
    ms_label = isinf(min_students) ? "None" : string(round(Int, min_students))
    println("\nresults (travel=$(travel), min_students=$(ms_label), w=$(w)):")
    println("open: $n_open")
    println("open (>= min_students): $n_open_full")
    println("open (< min_students): $n_open_small")
    println("closed: $(M - n_open)")
    println("total: $M")
    println("travel: ", round(travel, digits=0))
    println("penalty: ", round(raw_penalty, digits=0))
    println("mean travel time (min): ", round(mean_travel_min, digits=2))
    println("unassigned clients: ", sum(1 for i in keys(locations) if !haskey(assigned, i); init=0))
    println("t < 15 min: ", round(Int, b1))
    println("15 <= t < 30 min: ", round(Int, b2))
    println("t >= 30 min: ", round(Int, b3))

    open_vec = zeros(Int, M)
    for (idx, j) in enumerate(facilities)
        if j in open_set
            open_vec[idx] = isinf(min_students) || fload[j] >= min_students ? 1 : 2
        end
    end

    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_greedy.arrow", (
        id   = facilities,
        open = open_vec
    ))

    sorted_ids = sort(collect(keys(cur_time)))
    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_i_travel.arrow", (
        id     = sorted_ids,
        t_ij   = [cur_time[i] for i in sorted_ids] #,
        # t_band = [cur_time[i] < 15 ? 1 : cur_time[i] < 30 ? 2 : cur_time[i] < 45 ? 3 : cur_time[i] < 60 ? 4 : 5 for i in sorted_ids]
    ))
end


if grid
    grid_search()
else
    single_run(50.0, 0.0001)
end