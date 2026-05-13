using Arrow

countries      = ["Netherlands"]
travel         = "quadratic"
grid           = true
baseline       = true
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

function load_existing_facilities(country)
    od  = Arrow.Table("C:\\LocalData\\networkmodel_eu\\ExistingSchools\\$(country)_od.arrow")
    fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\ExistingSchools\\$(country)_j.arrow")
    loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\ExistingSchools\\$(country)_i.arrow")
    !grid && println("  [existing] clients: $(length(loc[:pop])), facilities: $(length(fac[:id]))")

    fac_id_set     = Set(Int.(fac[:id]))
    clients_col    = Int.(od[:client_rel])
    facilities_col = Int.(od[:facility_rel])
    t_ij_col       = od[:t_ij] ./ 60

    assigned = Dict{Int, Int}()
    cur_cost = Dict{Int, Float64}()
    cur_time = Dict{Int, Float64}()

    for k in 1:length(clients_col)
        i  = clients_col[k]
        j  = facilities_col[k]
        t  = t_ij_col[k]
        ck = c(t)
        if !haskey(cur_cost, i) || ck < cur_cost[i]
            assigned[i] = j
            cur_cost[i] = ck
            cur_time[i] = t
        end
    end

    return fac_id_set, assigned, cur_cost, cur_time
end

function load_potential_facilities(country)
    od  = Arrow.Table("C:\\LocalData\\networkmodel_eu\\NewSchools\\$(country)_od.arrow")
    loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\NewSchools\\$(country)_i.arrow")
    fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\NewSchools\\$(country)_j.arrow")
    !grid && println("  [potential] clients: $(length(loc[:pop])), facilities: $(length(fac[:id]))")

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
              client_pop, potential_time)
end

function facility_penalty(load, min_students, w, c0, use_power_law)
    if use_power_law
        load <= 0 ? 0.0 : w * 51712 * load^0.465
    else
        isinf(min_students) ? w * c0 : w * c0 * max(0.0, min_students - load)
    end
end

function merge_heuristic(open_set, initial_assigned, initial_cur_cost, initial_cur_time,
                         min_students, w, facility_cost, opening_cost, pot_data, use_power_law)
    (; potential_facs, locations, clients_col, facilities_col, t_ij_col,
       client_pop, potential_time) = pot_data

    open_set = copy(open_set)

    # Use pre-computed assignment from ExistingSchools OD
    assigned = copy(initial_assigned)
    cur_cost = copy(initial_cur_cost)
    cur_time = copy(initial_cur_time)
    fload    = Dict(j => 0.0 for j in union(open_set, Set(potential_facs)))

    for (i, j) in assigned
        if haskey(fload, j)
            fload[j] += client_pop[i]
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

    # Evaluate merges: for each potential p, find the best merge through p
    function best_merge_for(p)
        reachable_facs = Set(assigned[i] for i in potential_client_set[p] if haskey(assigned, i) && assigned[i] in open_set)
        length(reachable_facs) < 2 && return nothing
        reachable_vec = collect(reachable_facs)

        best_saving = 0.0
        best_move   = nothing
        for a in 1:length(reachable_vec)
            for b in a+1:length(reachable_vec)
                j_a = reachable_vec[a]
                j_b = reachable_vec[b]

                combined_clients = union(Set(facility_clients[j_a]), Set(facility_clients[j_b]))
                isempty(combined_clients) && continue
                combined_load    = sum(client_pop[i] for i in combined_clients)
                current_travel   = sum(cur_cost[i] * client_pop[i] for i in combined_clients)
                current_fac      = get(facility_cost_cache, j_a, 0.0) + get(facility_cost_cache, j_b, 0.0)
                current_total    = current_travel + current_fac

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

                saving = current_total - new_travel - facility_penalty(combined_load, min_students, w, facility_cost, use_power_law) - opening_cost
                if saving > best_saving
                    best_saving = saving
                    best_move   = (j_a, j_b, p, assignments, saving)
                end
            end
        end
        return best_move
    end

    n_pot = length(potential_facs)
    !grid && println("    [merge] $n_pot potential facilities, evaluating merges...")
    # initial full pass with progress
    savings = Dict{Int, Any}()
    for (idx, p) in enumerate(potential_facs)
        m = best_merge_for(p)
        if m !== nothing
            savings[p] = m
        end
        if !grid && (idx % 1000 == 0 || idx == n_pot)
            print("\r    [merge] initial scan: $idx / $n_pot")
        end
    end
    !grid && println()

    n_merges = 0
    while !isempty(savings)
        best_move = argmax(m -> m[5], collect(values(savings)))
        best_move[5] <= 0.0 && break

        j_a, j_b, p, new_assignments, _ = best_move

        # stale entry — facilities already closed, remove and skip
        if !(j_a in open_set) || !(j_b in open_set) || j_a == j_b
            delete!(savings, p)
            continue
        end

        !grid && print("\r    [merge] merges so far: $n_merges  ($(length(open_set)) open, $(length(savings)) potentials with savings)")

        if best_move !== nothing
            j_a, j_b, p, new_assignments = best_move

            delete!(open_set, j_a)
            delete!(open_set, j_b)
            fload[j_a] = 0.0
            fload[j_b] = 0.0
            delete!(facility_cost_cache, j_a)
            delete!(facility_cost_cache, j_b)

            push!(open_set, p)
            fload[p]            = 0.0
            facility_clients[p] = Int[]

            combined_clients = union(Set(facility_clients[j_a]), Set(facility_clients[j_b]))

            for i in combined_clients
                if haskey(new_assignments, i)
                    cp, bt      = new_assignments[i]
                    assigned[i] = p
                    cur_cost[i] = cp
                    cur_time[i] = bt
                    fload[p]   += client_pop[i]
                    push!(facility_clients[p], i)
                else
                    # client can't reach p — reassign to nearest remaining open facility
                    best_k    = nothing
                    best_cost = Inf
                    for k in locations[i]
                        j_cand = facilities_col[k]
                        if j_cand in open_set
                            ck = c(t_ij_col[k])
                            if ck < best_cost
                                best_cost = ck
                                best_k    = k
                            end
                        end
                    end
                    if best_k !== nothing
                        j_new       = facilities_col[best_k]
                        assigned[i] = j_new
                        cur_cost[i] = best_cost
                        cur_time[i] = t_ij_col[best_k]
                        fload[j_new] += client_pop[i]
                        push!(facility_clients[j_new], i)
                    end
                end
            end

            facility_clients[j_a] = Int[]
            facility_clients[j_b] = Int[]

            facility_cost_cache[p] = facility_penalty(fload[p], min_students, w, facility_cost, use_power_law)

            n_merges += 1
            !grid && print("\r    [merge] merges so far: $n_merges  ($(length(open_set)) open, $(length(savings)) potentials with savings)")

            # remove stale savings for closed facilities and rescan affected potentials
            delete!(savings, p)
            affected_potentials = Set{Int}()
            for i in union(Set(facility_clients[j_a]), Set(facility_clients[j_b]), Set(facility_clients[p]))
                for pot in keys(get(potential_time, i, Dict{Int,Float64}()))
                    if haskey(potential_client_set, pot)
                        push!(affected_potentials, pot)
                    end
                end
            end
            for pot in affected_potentials
                m = best_merge_for(pot)
                if m !== nothing
                    savings[pot] = m
                else
                    delete!(savings, pot)
                end
            end
        end
    end

    !grid && println("    [merge] done — $n_merges merges applied, $(length(open_set)) remaining open")

    travel_cost = sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
    penalty     = sum(facility_penalty(fload[j], min_students, w, facility_cost, use_power_law) for j in open_set)

    return open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty, n_merges
end

function run_scenario(country, pot_data, min_students, w, use_power_law)
    (; potential_facs, locations, client_pop) = pot_data
    facility_cost = 99699
    opening_cost  = 5000

    initial_open, initial_assigned, initial_cur_cost, initial_cur_time =
        load_existing_facilities(country)

    if baseline
        open_set = initial_open
        assigned = initial_assigned
        cur_cost = initial_cur_cost
        cur_time = initial_cur_time
        fload    = Dict(j => 0.0 for j in open_set)
        for (i, j) in assigned
            if haskey(fload, j)
                fload[j] += client_pop[i]
            end
        end
        travel_cost = sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
        penalty     = 0.0
        n_merges    = 0
    else
        !grid && println("    [merge] starting with $(length(initial_open)) existing facilities...")
        open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty, n_merges =
            merge_heuristic(initial_open, initial_assigned, initial_cur_cost, initial_cur_time,
                            min_students, w, facility_cost, opening_cost, pot_data, use_power_law)
    end

    thr          = isinf(min_students) ? 50 : min_students
    n_open_full  = sum(1 for j in open_set if fload[j] >= thr; init=0)
    n_open_small = sum(1 for j in open_set if fload[j] <  thr; init=0)

    raw_penalty = isempty(open_set) ? 0.0 : (use_power_law ?
        sum(fload[j] > 0 ? 51712 * fload[j]^0.465 : 0.0 for j in open_set) :
        sum(isinf(min_students) ? facility_cost : facility_cost * max(0.0, min_students - fload[j]) for j in open_set))

    total_client_pop = sum(client_pop[i] for i in keys(cur_time))
    mean_travel_min  = sum(cur_time[i] * client_pop[i] for i in keys(cur_time)) / total_client_pop

    return open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty, raw_penalty,
           n_open_full, n_open_small, mean_travel_min, n_merges
end

function grid_search()
    ws = [0.00001, 0.0001, 0.001, 0.01, 0.1, 1]

    for country in countries
        local pot_data = load_potential_facilities(country)
        (; client_pop) = pot_data

        for use_power_law in use_power_laws
            cost_label          = use_power_law ? "power-law" : "fixed"
            min_students_values = use_power_law ? [Inf] : (policy ? [25.0, 50.0, 100.0] : [Inf])

            println("\n$country — grid search (travel=$(travel), facility=$(cost_label))")
            println(rpad("min_students", 14),
                    rpad("policy_weight", 14),
                    rpad("open", 8),
                    rpad(">=min_students", 16),
                    rpad("<min_students", 16),
                    rpad("merges", 10),
                    rpad("travel_cost", 14),
                    rpad("facility_cost", 16),
                    rpad("mean_t (min)", 14),
                    rpad("t<=15", 10),
                    rpad("15<t<=30", 10),
                    rpad("30<t<=60", 10),
                    "t>60")

            iter_min_students = baseline ? [first(min_students_values)] : min_students_values
            iter_ws           = baseline ? [first(ws)]                  : ws

            for min_students in iter_min_students
                for w in iter_ws
                    local open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty,
                          raw_penalty, n_open_full, n_open_small, mean_travel_min, n_merges =
                        run_scenario(country, pot_data, min_students, w, use_power_law)

                    b1 = sum(client_pop[i] for (i, t) in cur_time if t < 15;       init=0.0)
                    b2 = sum(client_pop[i] for (i, t) in cur_time if 15 <= t < 30; init=0.0)
                    b3 = sum(client_pop[i] for (i, t) in cur_time if 30 <= t < 60; init=0.0)
                    b4 = sum(client_pop[i] for (i, t) in cur_time if t >= 60;      init=0.0)

                    ms_label = isinf(min_students) ? "None" : string(round(Int, min_students))
                    w_label  = baseline ? "—" : string(w)

                    println(rpad(ms_label, 14),
                            rpad(w_label, 14),
                            rpad(n_open_full + n_open_small, 8),
                            rpad(n_open_full, 16),
                            rpad(n_open_small, 16),
                            rpad(n_merges, 10),
                            rpad(round(travel_cost, digits=0), 14),
                            rpad(round(raw_penalty, digits=0), 16),
                            rpad(round(mean_travel_min, digits=2), 14),
                            rpad(round(Int, b1), 10),
                            rpad(round(Int, b2), 10),
                            rpad(round(Int, b3), 10),
                            round(Int, b4))
                end
            end
        end
    end
end

function single_run(country, min_students, w, use_power_law)
    pot_data = load_potential_facilities(country)
    (; potential_facs, client_pop, locations) = pot_data

    open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty, raw_penalty,
    n_open_full, n_open_small, mean_travel_min, n_merges =
        run_scenario(country, pot_data, min_students, w, use_power_law)

    b1 = sum(client_pop[i] for (i, t) in cur_time if t < 15;       init=0.0)
    b2 = sum(client_pop[i] for (i, t) in cur_time if 15 <= t < 30; init=0.0)
    b3 = sum(client_pop[i] for (i, t) in cur_time if 30 <= t < 60; init=0.0)
    b4 = sum(client_pop[i] for (i, t) in cur_time if t >= 60;      init=0.0)

    n_open     = n_open_full + n_open_small
    ms_label   = isinf(min_students) ? "None" : string(round(Int, min_students))
    cost_label = use_power_law ? "power-law" : "fixed"
    println("\nresults ($country, travel=$(travel), facility=$(cost_label), min_students=$(ms_label), w=$(w)):")
    println("open: $n_open")
    println("open (>= min_students): $n_open_full")
    println("open (< min_students): $n_open_small")
    println("merges: $n_merges")
    println("total potential: $(length(potential_facs))")
    println("travel: ", round(travel_cost, digits=0))
    println("penalty: ", round(raw_penalty, digits=0))
    println("mean travel time (min): ", round(mean_travel_min, digits=2))
    println("unassigned clients: ", sum(1 for i in keys(locations) if !haskey(assigned, i); init=0))
    println("t < 15 min: ", round(Int, b1))
    println("15 <= t < 30 min: ", round(Int, b2))
    println("30 <= t < 60 min: ", round(Int, b3))
    println("t >= 60 min: ", round(Int, b4))

    thr = isinf(min_students) ? 50 : min_students
    pot_open_ids  = Int[]
    pot_open_flag = Int[]
    for j in potential_facs
        if j in open_set
            push!(pot_open_ids,  j)
            push!(pot_open_flag, fload[j] >= thr ? 1 : 2)
        end
    end
    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_merge.arrow", (
        id   = pot_open_ids,
        open = pot_open_flag
    ))

    sorted_ids = sort(collect(keys(cur_time)))
    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_i_travel_merge.arrow", (
        id   = sorted_ids,
        t_ij = [cur_time[i] for i in sorted_ids]
    ))
end

if grid
    @time grid_search()
else
    @time single_run(countries[1], 50.0, 0.01, use_power_laws[1])
end
