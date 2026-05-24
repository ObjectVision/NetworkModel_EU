include("settings.jl")

grid               = false
policy             = true          # true: vary min_students [25..200]; false: Inf (no minimum)
use_power_laws     = [false]       # false: fixed cost + deficit penalty; true: power-law facility cost
nearests           = [true, false] # true: keep nearest-open assignments from drop heuristic; false: re-solve LP for optimal assignments

# if use_power_law: total cost = 51712 * load^0.465 (derived from cost-per-pupil = 51712 * load^-0.535)
# else if min_students is Inf: fixed cost w * c0 per open facility
# else: w * c0 * max(0, min_students - load)
function facility_penalty(load, min_students, w, c0, use_power_law)
    if use_power_law
        load <= 0 ? 0.0 : w * 51712 * load^0.465
    else
        isinf(min_students) ? w * c0 : w * c0 * max(0.0, min_students - load)
    end
end

function drop_heuristic(open_set, min_students, w, c0, data, use_power_law)
    (; facilities, facilities_col, t_ij_col, locations, client_pop) = data
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

    c0_cache = Dict(j => facility_penalty(fload[j], min_students, w, c0, use_power_law) for j in keys(fload))

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
            penalty_saving = c0_cache[j]

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
                old_r = c0_cache[r]
                new_r = facility_penalty(fload[r] + added, min_students, w, c0, use_power_law)
                other_facility_change += new_r - old_r
            end

            saving = penalty_saving - travel_increase - other_facility_change
            if saving > best_saving
                best_saving = saving
                best_j      = j
            end
        end

        if best_j !== nothing
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
                c0_cache[f] = facility_penalty(fload[f], min_students, w, c0, use_power_law)
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

    travel_cost = sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
    penalty     = sum(facility_penalty(fload[j], min_students, w, c0, use_power_law) for j in open_set)

    return open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty
end


function lp_assignment(open_set, min_students, w, c0, data)
    (; N, facilities, clients_col, facilities_col, t_ij_col, locations, client_pop) = data

    facility_rows = Dict(j => Int[] for j in open_set)
    for k in 1:N
        j = facilities_col[k]
        if j in open_set
            push!(facility_rows[j], k)
        end
    end

    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "presolve", "on")
    set_optimizer_attribute(model, "output_flag", false)

    @variable(model, 0 <= y[1:N] <= 1)

    for k in 1:N
        if facilities_col[k] ∉ open_set
            fix(y[k], 0.0; force=true)
        end
    end

    if !isinf(min_students)
        @variable(model, deficit[j in open_set] >= 0)
        @expression(model, load[j in open_set],
            sum(y[k] * client_pop[clients_col[k]] for k in facility_rows[j])
        )
        @objective(model, Min,
            sum(y[k] * c(t_ij_col[k]) * client_pop[clients_col[k]] for k in 1:N) +
            sum(deficit[j] * w * c0 for j in open_set)
        )
        for j in open_set
            @constraint(model, deficit[j] >= min_students - load[j])
        end
    else
        @objective(model, Min,
            sum(y[k] * c(t_ij_col[k]) * client_pop[clients_col[k]] for k in 1:N)
        )
    end

    for (_, rows) in locations
        @constraint(model, sum(y[k] for k in rows) == 1)
    end

    optimize!(model)

    assigned = Dict{Int, Int}()
    cur_cost = Dict{Int, Float64}()
    cur_time = Dict{Int, Float64}()

    for (i, rows) in locations
        best_k, best_val = rows[1], value(y[rows[1]])
        for k in rows[2:end]
            v = value(y[k])
            if v > best_val
                best_val = v; best_k = k
            end
        end
        assigned[i] = facilities_col[best_k]
        cur_cost[i] = c(t_ij_col[best_k])
        cur_time[i] = t_ij_col[best_k]
    end

    fload = Dict(j => 0.0 for j in facilities)
    for (i, j) in assigned
        fload[j] += client_pop[i]
    end

    return assigned, fload, cur_cost, cur_time
end


function run_scenario(data, min_students, w, use_power_law, nearest)
    (; facilities, facilities_col, t_ij_col, locations, client_pop, nearest_facility) = data

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

    open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty = drop_heuristic(initial_open, min_students, w, FACILITY_MIN_COSTS, data, use_power_law)

    if !nearest
        assigned, fload, cur_cost, cur_time = lp_assignment(open_set, min_students, w, FACILITY_MIN_COSTS, data)
    end

    n_open_full  = isinf(min_students) ? sum(1 for j in open_set if fload[j] >= 50; init=0) : sum(1 for j in open_set if fload[j] >= min_students; init=0)
    n_open_small = isinf(min_students) ? sum(1 for j in open_set if fload[j] < 50;  init=0) : sum(1 for j in open_set if fload[j] < min_students;  init=0)

    travel_cost = isempty(assigned) ? 0.0 : sum(cur_cost[i] * client_pop[i] for i in keys(assigned))
    penalty     = isempty(open_set) ? 0.0 : sum(facility_penalty(fload[j], min_students, w, FACILITY_MIN_COSTS, use_power_law) for j in open_set)
    raw_penalty = isempty(open_set) ? 0.0 : (use_power_law ?
        sum(fload[j] > 0 ? 51712 * fload[j]^0.465 : 0.0 for j in open_set) :
        sum(isinf(min_students) ? FACILITY_MIN_COSTS : FACILITY_MIN_COSTS * max(0.0, min_students - fload[j]) for j in open_set))

    total_client_pop = sum(client_pop[i] for i in keys(cur_time))
    mean_travel_min  = sum(cur_time[i] * client_pop[i] for i in keys(cur_time)) / total_client_pop

    return open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty, raw_penalty, n_open_full, n_open_small, mean_travel_min
end


function grid_search()
    # ws = [0.00001, 0.0001, 0.001, 0.01, 0.1, 1]
    ws = [0.0001, 0.01, 1]

    for country in COUNTRIES
        local data = try_load_country(country)
        data === nothing && continue
        (; client_pop) = data

        for use_power_law in use_power_laws
            cost_label          = use_power_law ? "power-law" : "fixed"
            min_students_values = use_power_law ? [Inf] : (policy ? [50.0, 100.0, 200.0] : [Inf])

            for nearest in nearests
                if !nearest && use_power_law
                    continue
                end

                assignment_label = nearest ? "nearest" : "central"
                println("\n$country — grid search (travel_func=$(travel_func), facility=$(cost_label), assignment=$(assignment_label))")
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
                        local open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty, raw_penalty, n_open_full, n_open_small, mean_travel_min = run_scenario(data, min_students, w, use_power_law, nearest)

                    b1 = sum(client_pop[i] for (i, t) in cur_time if t < 15;       init=0.0)
                    b2 = sum(client_pop[i] for (i, t) in cur_time if 15 <= t < 30; init=0.0)
                    b3 = sum(client_pop[i] for (i, t) in cur_time if 30 <= t < 60; init=0.0)
                    b4 = sum(client_pop[i] for (i, t) in cur_time if t >= 60;      init=0.0)

                    ms_label = isinf(min_students) ? "None" : string(round(Int, min_students))

                    println(rpad(ms_label, 14),
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
                    end
                end
            end
        end
    end
end


function single_run(country, min_students, w, use_power_law, nearest=true; data=nothing)
    data = data === nothing ? load_country(country) : data
    (; M, facilities, client_pop, locations) = data

    open_set, assigned, fload, cur_cost, cur_time, travel_cost, penalty, raw_penalty, n_open_full, n_open_small, mean_travel_min = run_scenario(data, min_students, w, use_power_law, nearest)

    b1 = sum(client_pop[i] for (i, t) in cur_time if t < 15;       init=0.0)
    b2 = sum(client_pop[i] for (i, t) in cur_time if 15 <= t < 30; init=0.0)
    b3 = sum(client_pop[i] for (i, t) in cur_time if 30 <= t < 60; init=0.0)
    b4 = sum(client_pop[i] for (i, t) in cur_time if t >= 60;      init=0.0)

    n_open     = n_open_full + n_open_small
    ms_label   = isinf(min_students) ? "None" : string(round(Int, min_students))
    cost_label = use_power_law ? "power-law" : "fixed"
    println("\nresults ($country, travel_func=$(travel_func), facility=$(cost_label), min_students=$(ms_label), w=$(w)):")
    println("open: $n_open")
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

    open_vec = zeros(Int, M)
    for (idx, j) in enumerate(facilities)
        if j in open_set
            open_vec[idx] = isinf(min_students) || fload[j] >= min_students ? 1 : 2
        end
    end

    assignment_label = nearest ? "nearest" : "central"
    Arrow.write(output_path(country, "greedy", assignment_label, "assignment"), (
        id   = facilities,
        open = open_vec
    ))

    sorted_ids = sort(collect(keys(cur_time)))
    Arrow.write(output_path(country, "greedy", assignment_label, "traveltime"), (
        id   = sorted_ids,
        t_ij = [cur_time[i] for i in sorted_ids]
    ))
end


if grid
    @time grid_search()
else
    min_students = 50.0
    w            = 0.01

    for country in COUNTRIES
        local data = try_load_country(country)
        data === nothing && continue

        for use_power_law in use_power_laws
            for nearest in nearests
                if !nearest && use_power_law
                    continue
                end

                @time single_run(country, min_students, w, use_power_law, nearest; data=data)
            end
        end
    end
end
