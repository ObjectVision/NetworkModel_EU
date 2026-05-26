include("lp_run.jl")

grid              = false
apply_thresholds  = [true, false]       # add false to also run without max-travel filter
nearests          = [false]      # true: assign each client to nearest open school; false: re-solve LP for assignments

if grid
    # min_clients_values = [25.0, 50.0, 100.0, 150.0, 200.0]
    # ws = [0.00001, 0.0001, 0.001, 0.01, 0.1, 1.0]
    min_clients_values = [50.0, 100.0, 200.0]
    ws = [0.0001, 0.01, 1.0]

    for country in COUNTRIES
        max_facility_load = 0.0

        local data = try_load_country(country)
        data === nothing && continue

        for apply_threshold in apply_thresholds
            threshold_label = apply_threshold ? "max_travel=60 min" : "no max_travel"

            for nearest in nearests
                assignment_label = nearest ? "nearest" : "central"
                println("\n$country — grid search (travel_func=$(travel_func), $(threshold_label), assignment=$(assignment_label))")
                println(rpad("min_clients", 14),
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
                        rpad("t>60", 10),
                        rpad("frac_x", 10),
                        "sum_x")

                for min_clients in min_clients_values
                    for w in ws
                        local open_set, fload, assigned_k, n_open_full, n_open_small, mean_travel_min, travel_lp, penalty_lp, raw_penalty_lp, b1, b2, b3, b4, n_fractional_x, sum_x, travel_relax = run_scenario(data, min_clients, w, apply_threshold, nearest)
                        if !isempty(open_set)
                            max_facility_load = max(max_facility_load, maximum(fload[j] for j in open_set))
                        end
                        ms_label = isinf(min_clients) ? "Inf" : string(round(Int, min_clients))
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
                                rpad(round(Int, b4), 10),
                                rpad(n_fractional_x, 10),
                                round(sum_x, digits=2))
                    end
                end
            end
        end
        println("\n$country — max facility load across all configurations: ", round(Int, max_facility_load))
    end
else
    min_clients = 50.0
    w           = 0.01

    for country in COUNTRIES
        local data = try_load_country(country)
        data === nothing && continue

        for apply_threshold in apply_thresholds
            for nearest in nearests
                threshold_label  = apply_threshold ? "max_travel=60 min" : "no max_travel"
                assignment_label = nearest ? "nearest" : "central"

                open_set, fload, assigned_k, n_open_full, n_open_small, mean_travel_min, travel_lp, penalty_lp, raw_penalty_lp, b1, b2, b3, b4, n_fractional_x, sum_x, travel_relax = run_scenario(data, min_clients, w, apply_threshold, nearest)
                n_open = n_open_full + n_open_small

                println("\n$country — results (travel_func=$(travel_func), min_clients=$(round(Int, min_clients)), w=$(w), $(threshold_label), assignment=$(assignment_label)):")
                println("open (>= min_clients): $n_open_full")
                println("open (< min_clients): $n_open_small")
                println("closed: $(data.M - n_open)")
                println("total: $(data.M)")
                println("travel (LP): ", round(travel_lp, digits=0))
                println("penalty (LP): ", round(raw_penalty_lp, digits=0))
                println("mean travel time (min): ", round(mean_travel_min, digits=2))
                println("t < 15 min: ", round(Int, b1))
                println("15 <= t < 30 min: ", round(Int, b2))
                println("30 <= t < 60 min: ", round(Int, b3))
                println("t >= 60 min: ", round(Int, b4))
                println("fractional x[j]: ", n_fractional_x)
                println("sum(x[j]):       ", round(sum_x, digits=2))

                open_vec = zeros(Int, data.M)
                for (idx, j) in enumerate(data.facilities)
                    if j in open_set
                        open_vec[idx] = isinf(min_clients) || fload[j] >= min_clients ? 1 : 2
                    end
                end

                Arrow.write(output_path(country, "lp", assignment_label, "assignment"), (
                    id = data.facilities, open = open_vec
                ))

                sorted_ids = sort(collect(keys(assigned_k)))
                Arrow.write(output_path(country, "lp", assignment_label, "traveltime"), (
                    id   = sorted_ids,
                    t_ij = [data.t_ij_col[assigned_k[i]] for i in sorted_ids]
                ))
            end
        end
    end
end
