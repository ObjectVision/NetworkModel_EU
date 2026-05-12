using Arrow

countries      = ["Netherlands"]
travel         = "quadratic"
grid           = true
policy         = true
use_power_laws = [true]

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

    locations = Dict{Int, Vector{Int}}()
    for k in 1:N
        i = clients_col[k]
        haskey(locations, i) ? push!(locations[i], k) : (locations[i] = [k])
    end

    client_pop = Dict(i => population[i+1] for i in keys(locations))

    nearest_facility = Dict{Int, Int}()
    for (i, rows) in locations
        best_k = rows[argmin(c(t_ij_col[k]) for k in rows)]
        nearest_facility[i] = facilities_col[best_k]
    end

    return (; N, M, facilities, clients_col, facilities_col, t_ij_col, locations, client_pop, nearest_facility)
end

function load_potential_facilities(country)
    od  = Arrow.Table("/Users/lola/Downloads/$(country)_od_new.arrow")
    loc = Arrow.Table("/Users/lola/Downloads/$(country)_i_new.arrow")
    fac = Arrow.Table("/Users/lola/Downloads/$(country)_j_new.arrow")

    clients_col    = Int.(od[:client_rel])
    facilities_col = Int.(od[:facility_rel])
    t_ij_col       = od[:t_ij] ./ 60
    population     = loc[:pop]
    potential_facs = Int.(fac[:id])

    N = length(clients_col)

    locations = Dict{Int, Vector{Int}}()
    for k in 1:N
        i = clients_col[k]
        haskey(locations, i) ? push!(locations[i], k) : (locations[i] = [k])
    end

    client_pop = Dict(i => population[i+1] for i in keys(locations))

    nearest_facility = Dict{Int, Int}()
    for (i, rows) in locations
        best_k = rows[argmin(c(t_ij_col[k]) for k in rows)]
        nearest_facility[i] = facilities_col[best_k]
    end

    potential_time = Dict{Int, Dict{Int, Float64}}()
    for k in 1:N
        i = clients_col[k]
        j = facilities_col[k]
        t = t_ij_col[k]
        if !haskey(potential_time, i)
            potential_time[i] = Dict{Int, Float64}()
        end
        if t < get(potential_time[i], j, Inf)
            potential_time[i][j] = t
        end
    end

    return (; potential_facs, locations, clients_col, facilities_col, t_ij_col,
              client_pop, nearest_facility, potential_time)
end

function facility_penalty(load, min_students, w, c0, use_power_law)
    if use_power_law
        load <= 0 ? 0.0 : w * 51712 * load^0.465
    else
        isinf(min_students) ? w * c0 : w * c0 * max(0.0, min_students - load)
    end
end

function drop_heuristic(open_set, min_students, w, facility_cost, data, use_power_law)
    (; facilities, facilities_col, t_ij_col, locations, client_pop) = data
    open_set = copy(open_set)

    assigned = Dict{Int, Int}()
    cur_cost = Dict{Int, Float64}()
    cur_time = Dict{Int, Float64}()
    fload    = Dict(j => 0.0 for j in open_set)

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

    facility_clients = Dict(j => Int[] for j in open_set)
    for (i, j) in assigned
        push!(facility_clients[j], i)
    end

    facility_cost_cache = Dict(j => facility_penalty(fload[j], min_students, w, facility_cost, use_power_law)
                               for j in open_set)

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

    second_best_clients = Dict(j => Set{Int}() for j in open_set)
    for (i, (j, _, _)) in second_best
        push!(second_best_clients[j], i)
    end

    n_dropped = 0
    improved = true
    while improved
        improved    = false
        best_saving = 0.0
        best_j      = nothing

        for j in open_set
            penalty_saving = facility_cost_cache[j]

            travel_increase = 0.0
            feasible = true
            other_facility_loads = Dict{Int, Float64}()
            for i in facility_clients[j]
                if !haskey(second_best, i)
                    feasible = false
                    break
                end
                travel_increase += (second_best[i][2] - cur_cost[i]) * client_pop[i]
                new_j = second_best[i][1]
                other_facility_loads[new_j] = get(other_facility_loads, new_j, 0.0) + client_pop[i]
            end

            if !feasible
                continue
            end

            other_facility_change = 0.0
            for (r, added) in other_facility_loads
                old_r = facility_cost_cache[r]
                new_r = facility_penalty(fload[r] + added, min_students, w, facility_cost, use_power_law)
                other_facility_change += new_r - old_r
            end

            saving = penalty_saving - travel_increase - other_facility_change
            if saving > best_saving
                best_saving = saving
                best_j      = j
            end
        end

        if best_j !== nothing
            n_dropped += 1
            open_set = setdiff(open_set, [best_j])
            affected = union(Set(facility_clients[best_j]), get(second_best_clients, best_j, Set{Int}()))

            loads_changed = Set{Int}([best_j])
            for i in facility_clients[best_j]
                old_second = second_best[i][1]
                new_j      = second_best[i][1]
                new_cost   = second_best[i][2]
                new_time   = second_best[i][3]

                fload[best_j] -= client_pop[i]
                fload[new_j]  += client_pop[i]
                push!(loads_changed, new_j)

                assigned[i]    = new_j
                cur_cost[i]    = new_cost
                cur_time[i]    = new_time

                push!(facility_clients[new_j], i)
                if haskey(second_best_clients, old_second)
                    delete!(second_best_clients[old_second], i)
                end
            end

            for f in loads_changed
                facility_cost_cache[f] = facility_penalty(fload[f], min_students, w, facility_cost, use_power_law)
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

    println("    [drop] done — dropped $n_dropped facilities, $(length(open_set)) remaining open")

    travel_cost = sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
    penalty     = sum(facility_penalty(fload[j], min_students, w, facility_cost, use_power_law) for j in open_set)

    return open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty
end

function merge_heuristic(open_set, min_students, w, facility_cost, pot_data, use_power_law)
    (; potential_facs, locations, clients_col, facilities_col, t_ij_col,
       client_pop, potential_time) = pot_data

    open_set = copy(open_set)

    # Build facility_client_set from potential OD
    println("    [merge] building facility-client sets from potential OD...")
    facility_client_set = Dict(j => Set{Int}() for j in open_set)
    for k in 1:length(clients_col)
        i = clients_col[k]
        j = facilities_col[k]
        if j in open_set
            push!(facility_client_set[j], i)
        end
    end

    # Assign each client to their nearest open facility in the potential OD
    assigned = Dict{Int, Int}()
    cur_cost = Dict{Int, Float64}()
    cur_time = Dict{Int, Float64}()
    fload    = Dict(j => 0.0 for j in union(open_set, Set(potential_facs)))

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

    facility_clients = Dict(j => Int[] for j in union(open_set, Set(potential_facs)))
    for (i, j) in assigned
        push!(facility_clients[j], i)
    end

    facility_cost_cache = Dict(j => facility_penalty(fload[j], min_students, w, facility_cost, use_power_law)
                               for j in open_set)

    # Precompute for each potential facility: which clients can reach it
    potential_client_set = Dict(p => Set{Int}() for p in potential_facs)
    for (i, d) in potential_time
        for p in keys(d)
            if haskey(potential_client_set, p)
                push!(potential_client_set[p], i)
            end
        end
    end

    # Precompute which potentials are reachable from each open facility's clients
    fac_to_potentials = Dict(j => Set{Int}() for j in open_set)
    for p in potential_facs
        for i in potential_client_set[p]
            if haskey(assigned, i)
                j = assigned[i]
                if haskey(fac_to_potentials, j)
                    push!(fac_to_potentials[j], p)
                end
            end
        end
    end

    # Step 1: candidate pairs — open facility pairs sharing at least one client in potential OD
    println("    [merge] $(length(potential_facs)) potential facilities, finding candidate pairs...")
    candidate_pairs = Tuple{Int,Int}[]
    open_vec = collect(open_set)
    for a in 1:length(open_vec)
        for b in a+1:length(open_vec)
            j_a = open_vec[a]
            j_b = open_vec[b]
            for i in facility_client_set[j_a]
                if i in facility_client_set[j_b]
                    push!(candidate_pairs, (j_a, j_b))
                    break
                end
            end
        end
    end
    println("    [merge] found $(length(candidate_pairs)) candidate pairs")

    # Step 2: evaluate each pair against candidate potentials and apply best merge
    println("    [merge] evaluating pairs against potential facilities...")
    n_merges = 0
    any_merged = true
    while any_merged
        any_merged  = false
        best_saving = 0.0
        best_move   = nothing

        for (j_a, j_b) in candidate_pairs
            (j_a in open_set && j_b in open_set) || continue

            candidate_potentials = intersect(
                get(fac_to_potentials, j_a, Set{Int}()),
                get(fac_to_potentials, j_b, Set{Int}())
            )
            isempty(candidate_potentials) && continue

            clients_a        = Set(facility_clients[j_a])
            clients_b        = Set(facility_clients[j_b])
            combined_clients = union(clients_a, clients_b)
            combined_load    = sum(client_pop[i] for i in combined_clients)

            current_travel = sum(cur_cost[i] * client_pop[i] for i in combined_clients)
            current_fac    = get(facility_cost_cache, j_a, 0.0) + get(facility_cost_cache, j_b, 0.0)
            current_total  = current_travel + current_fac

            for p in candidate_potentials
                new_travel  = 0.0
                assignments = Dict{Int, Tuple{Float64, Float64}}()

                for i in combined_clients
                    t_ip = get(get(potential_time, i, Dict{Int,Float64}()), p, Inf)
                    if isinf(t_ip)
                        new_travel += cur_cost[i] * client_pop[i]
                    else
                        cp = c(t_ip)
                        new_travel += cp * client_pop[i]
                        assignments[i] = (cp, t_ip)
                    end
                end

                new_fac   = facility_penalty(combined_load, min_students, w, facility_cost, use_power_law)
                new_total = new_travel + new_fac
                saving    = current_total - new_total

                if saving > best_saving
                    best_saving = saving
                    best_move   = (j_a, j_b, p, assignments)
                end
            end
        end

        if best_move !== nothing
            j_a, j_b, p, new_assignments = best_move

            delete!(open_set, j_a)
            delete!(open_set, j_b)
            fload[j_a] = 0.0
            fload[j_b] = 0.0
            delete!(facility_cost_cache, j_a)
            delete!(facility_cost_cache, j_b)

            push!(open_set, p)
            fload[p]             = 0.0
            facility_clients[p]  = Int[]
            fac_to_potentials[p] = Set{Int}()

            combined_clients = union(Set(facility_clients[j_a]), Set(facility_clients[j_b]))

            for i in combined_clients
                if haskey(new_assignments, i)
                    cp, bt      = new_assignments[i]
                    assigned[i] = p
                    cur_cost[i] = cp
                    cur_time[i] = bt
                    fload[p]   += client_pop[i]
                    push!(facility_clients[p], i)
                end
            end

            facility_clients[j_a] = Int[]
            facility_clients[j_b] = Int[]

            facility_cost_cache[p] = facility_penalty(fload[p], min_students, w, facility_cost, use_power_law)

            facility_client_set[p] = Set{Int}()
            for i in facility_clients[p]
                push!(facility_client_set[p], i)
                for pot in keys(get(potential_time, i, Dict{Int,Float64}()))
                    if haskey(potential_client_set, pot)
                        push!(fac_to_potentials[p], pot)
                    end
                end
            end

            n_merges  += 1
            any_merged = true
        end
    end

    n_existing  = sum(1 for j in open_set if !(j in Set(potential_facs)); init=0)
    n_potential = sum(1 for j in open_set if   j in Set(potential_facs);  init=0)
    println("    [merge] done — $n_merges merges applied, $n_existing existing + $n_potential potential open")

    travel_cost = sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
    penalty     = sum(facility_penalty(fload[j], min_students, w, facility_cost, use_power_law) for j in open_set)

    return open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty
end

function run_scenario(data, pot_data, min_students, w, use_power_law)
    (; facilities, facilities_col, t_ij_col, locations, client_pop, nearest_facility) = data
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

    println("    [drop] starting with $(length(initial_open)) facilities...")
    open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty =
        drop_heuristic(initial_open, min_students, w, facility_cost, data, use_power_law)

    println("    [merge] starting merge heuristic on potential OD...")
    merge_open, merge_assigned, merge_fload, merge_cur_cost, merge_cur_time, merge_travel_cost, merge_penalty =
        merge_heuristic(open_set, min_students, w, facility_cost, pot_data, use_power_law)

    n_open_full  = isinf(min_students) ? sum(1 for j in open_set if fload[j] >= 50;           init=0) :
                                         sum(1 for j in open_set if fload[j] >= min_students; init=0)
    n_open_small = isinf(min_students) ? sum(1 for j in open_set if fload[j] < 50;            init=0) :
                                         sum(1 for j in open_set if fload[j] < min_students;  init=0)

    travel_cost = isempty(assigned) ? 0.0 : sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
    penalty     = isempty(open_set) ? 0.0 : sum(facility_penalty(fload[j], min_students, w, facility_cost, use_power_law) for j in open_set)
    raw_penalty = isempty(open_set) ? 0.0 : (use_power_law ?
        sum(fload[j] > 0 ? 51712 * fload[j]^0.465 : 0.0 for j in open_set) :
        sum(isinf(min_students) ? facility_cost : facility_cost * max(0.0, min_students - fload[j]) for j in open_set))

    total_client_pop = sum(client_pop[i] for i in keys(cur_time))
    mean_travel_min  = sum(cur_time[i] * client_pop[i] for i in keys(cur_time)) / total_client_pop

    return open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty, raw_penalty,
           n_open_full, n_open_small, mean_travel_min,
           merge_open, merge_fload, merge_cur_time, pot_data.client_pop
end

function grid_search()
    ws = [0.00001, 0.0001, 0.001, 0.01, 0.1, 1]

    for country in countries
        local data     = load_country(country)
        local pot_data = load_potential_facilities(country)
        (; client_pop) = data

        for use_power_law in use_power_laws
            cost_label          = use_power_law ? "power-law" : "fixed"
            min_students_values = use_power_law ? [Inf] : (policy ? [25.0, 50.0, 100.0] : [Inf])

            println("\n$country — grid search (travel=$(travel), facility=$(cost_label))")
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
                    rpad("30<t<=60", 10),
                    "t>60")

            for min_students in min_students_values
                for w in ws
                    ms_str = isinf(min_students) ? "Inf" : string(round(Int, min_students))
                    println("\n  w=$w, min_students=$ms_str")

                    local open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty,
                          raw_penalty, n_open_full, n_open_small, mean_travel_min,
                          merge_open, merge_fload, merge_cur_time, merge_client_pop =
                        run_scenario(data, pot_data, min_students, w, use_power_law)

                    b1 = sum(client_pop[i] for (i, t) in cur_time if t < 15;       init=0.0)
                    b2 = sum(client_pop[i] for (i, t) in cur_time if 15 <= t < 30; init=0.0)
                    b3 = sum(client_pop[i] for (i, t) in cur_time if 30 <= t < 60; init=0.0)
                    b4 = sum(client_pop[i] for (i, t) in cur_time if t >= 60;      init=0.0)

                    ms_label = isinf(min_students) ? "None" : string(round(Int, min_students))

                    println(rpad(ms_label * "(drop)", 14),
                            rpad(w, 14),
                            rpad(n_open_full + n_open_small, 8),
                            rpad(n_open_full, 16),
                            rpad(n_open_small, 16),
                            rpad(round(travel_cost, digits=0), 14),
                            rpad(round(raw_penalty, digits=0), 16),
                            rpad(round(mean_travel_min, digits=2), 14),
                            rpad(round(Int, b1), 10),
                            rpad(round(Int, b2), 10),
                            rpad(round(Int, b3), 10),
                            round(Int, b4))

                    # merge result row
                    thr = isinf(min_students) ? 50 : min_students
                    mn_full  = sum(1 for j in merge_open if merge_fload[j] >= thr; init=0)
                    mn_small = sum(1 for j in merge_open if merge_fload[j] <  thr; init=0)
                    mn_travel = isempty(merge_cur_time) ? 0.0 :
                        sum(c(t) * merge_client_pop[i] for (i, t) in merge_cur_time)
                    mn_penalty = isempty(merge_open) ? 0.0 : (use_power_law ?
                        sum(merge_fload[j] > 0 ? 51712 * merge_fload[j]^0.465 : 0.0 for j in merge_open) :
                        sum(isinf(min_students) ? 99699 : 99699 * max(0.0, min_students - merge_fload[j]) for j in merge_open))
                    mn_total_pop = sum(merge_client_pop[i] for i in keys(merge_cur_time); init=0.0)
                    mn_mean_t    = mn_total_pop > 0 ?
                        sum(t * merge_client_pop[i] for (i, t) in merge_cur_time) / mn_total_pop : 0.0
                    mb1 = sum(merge_client_pop[i] for (i, t) in merge_cur_time if t < 15;       init=0.0)
                    mb2 = sum(merge_client_pop[i] for (i, t) in merge_cur_time if 15 <= t < 30; init=0.0)
                    mb3 = sum(merge_client_pop[i] for (i, t) in merge_cur_time if 30 <= t < 60; init=0.0)
                    mb4 = sum(merge_client_pop[i] for (i, t) in merge_cur_time if t >= 60;      init=0.0)

                    println(rpad(ms_label * "(merge)", 14),
                            rpad(w, 14),
                            rpad(mn_full + mn_small, 8),
                            rpad(mn_full, 16),
                            rpad(mn_small, 16),
                            rpad(round(mn_travel, digits=0), 14),
                            rpad(round(mn_penalty, digits=0), 16),
                            rpad(round(mn_mean_t, digits=2), 14),
                            rpad(round(Int, mb1), 10),
                            rpad(round(Int, mb2), 10),
                            rpad(round(Int, mb3), 10),
                            round(Int, mb4))
                end
            end
        end
    end
end

function single_run(country, min_students, w, use_power_law)
    data     = load_country(country)
    pot_data = load_potential_facilities(country)
    (; M, facilities, client_pop, locations) = data
    (; potential_facs) = pot_data

    open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty, raw_penalty,
    n_open_full, n_open_small, mean_travel_min,
    merge_open, merge_fload, merge_cur_time, merge_client_pop =
        run_scenario(data, pot_data, min_students, w, use_power_law)

    b1 = sum(client_pop[i] for (i, t) in cur_time if t < 15;       init=0.0)
    b2 = sum(client_pop[i] for (i, t) in cur_time if 15 <= t < 30; init=0.0)
    b3 = sum(client_pop[i] for (i, t) in cur_time if 30 <= t < 60; init=0.0)
    b4 = sum(client_pop[i] for (i, t) in cur_time if t >= 60;      init=0.0)

    n_open     = n_open_full + n_open_small
    ms_label   = isinf(min_students) ? "None" : string(round(Int, min_students))
    cost_label = use_power_law ? "power-law" : "fixed"
    println("\nresults ($country, travel=$(travel), facility=$(cost_label), min_students=$(ms_label), w=$(w)):")
    println("open (drop): $n_open")
    println("open (>= min_students): $n_open_full")
    println("open (< min_students): $n_open_small")
    println("closed: $(M - n_open)")
    println("total: $M")
    println("travel: ", round(travel_cost, digits=0))
    println("penalty: ", round(raw_penalty, digits=0))
    println("mean travel time (min): ", round(mean_travel_min, digits=2))
    println("unassigned clients: ", sum(1 for i in keys(locations) if !haskey(assigned, i); init=0))
    println("t < 15 min: ", round(Int, b1))
    println("15 <= t < 30 min: ", round(Int, b2))
    println("30 <= t < 60 min: ", round(Int, b3))
    println("t >= 60 min: ", round(Int, b4))

    # Existing facilities — from drop heuristic
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

    # Potential facilities — from merge heuristic
    pot_open_ids  = Int[]
    pot_open_flag = Int[]
    for j in potential_facs
        if j in merge_open
            push!(pot_open_ids,  j)
            push!(pot_open_flag, isinf(min_students) || merge_fload[j] >= min_students ? 1 : 2)
        end
    end
    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_greedy_new.arrow", (
        id   = pot_open_ids,
        open = pot_open_flag
    ))

    # Client travel times — from drop heuristic
    sorted_ids = sort(collect(keys(cur_time)))
    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_i_travel.arrow", (
        id   = sorted_ids,
        t_ij = [cur_time[i] for i in sorted_ids]
    ))

    # Client travel times — from merge heuristic
    merge_sorted_ids = sort(collect(keys(merge_cur_time)))
    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_i_travel_new.arrow", (
        id   = merge_sorted_ids,
        t_ij = [merge_cur_time[i] for i in merge_sorted_ids]
    ))
end

if grid
    @time grid_search()
else
    @time single_run(countries[1], 50.0, 0.0001, use_power_laws[1])
end