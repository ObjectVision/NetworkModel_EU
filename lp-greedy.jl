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

wpop = [population[clients_col[k]+1] for k in 1:N]

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
    open_set       = union(fixed_open_set, Set(fractional))

    # fix and re-solve
    for j in facilities
        fix(x[j], j in open_set ? 1.0 : 0.0; force=true)
    end
    optimize!(model)

    # compute fload from LP assignment for reporting
    fload = Dict(j => 0.0 for j in facilities)
    for k in 1:N
        fload[facilities_col[k]] += value(y[k]) * wpop[k]
    end

    # mean travel time: LP-weighted average
    total_weight  = sum(wpop[k] for k in 1:N)
    mean_travel_min = sum(value(y[k]) * t_ij_col[k] * wpop[k] for k in 1:N) / total_weight

    # travel bands: LP-weighted
    b1 = sum(value(y[k]) * wpop[k] for k in 1:N if t_ij_col[k] < 15)
    b2 = sum(value(y[k]) * wpop[k] for k in 1:N if 15 <= t_ij_col[k] < 30)
    b3 = sum(value(y[k]) * wpop[k] for k in 1:N if t_ij_col[k] >= 30)

    travel_lp  = sum(value(y[k]) * c(t_ij_col[k]) * wpop[k] for k in 1:N)
    penalty_lp = isinf(min_students) ?
                    sum(value(x[j]) * facility_cost * w for j in facilities) :
                    sum(value(deficit[j]) * λ for j in facilities)

    n_open_full  = isinf(min_students) ? length(open_set) : sum(1 for j in open_set if fload[j] >= min_students; init=0)
    n_open_small = isinf(min_students) ? 0                : sum(1 for j in open_set if fload[j] < min_students;  init=0)

    return open_set, fload, n_open_full, n_open_small, mean_travel_min, travel_lp, penalty_lp, b1, b2, b3
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
            open_set, fload, n_open_full, n_open_small, mean_travel_min, travel_lp, penalty_lp, b1, b2, b3 = run_scenario(min_students, w)
            ms_label = isinf(min_students) ? "Inf" : string(round(Int, min_students))
            println(rpad(ms_label, 14),
                    rpad(w, 14),
                    rpad(n_open_full + n_open_small, 8),
                    rpad(n_open_full, 8),
                    rpad(n_open_small, 8),
                    rpad(round(travel_lp, digits=0), 14),
                    rpad(round(penalty_lp, digits=0), 14),
                    rpad(round(mean_travel_min, digits=2), 14),
                    rpad(round(Int, b1), 10),
                    rpad(round(Int, b2), 10),
                    round(Int, b3))
        end
    end
else
    open_set, fload, n_open_full, n_open_small, mean_travel_min, travel_lp, penalty_lp, b1, b2, b3 = run_scenario(50.0, 1.0)
    n_open = n_open_full + n_open_small
    println("\nresults (travel=$(travel), min_students=50, w=1.0):")
    println("open (>= min_students): $n_open_full")
    println("open (< min_students): $n_open_small")
    println("closed: $(M - n_open)")
    println("total: $M")
    println("travel (LP): ", round(travel_lp, digits=0))
    println("penalty (LP): ", round(penalty_lp, digits=0))
    println("mean travel time (min): ", round(mean_travel_min, digits=2))
    println("t < 15 min: ", round(Int, b1))
    println("15 <= t < 30 min: ", round(Int, b2))
    println("t >= 30 min: ", round(Int, b3))

    open_vec = zeros(Int, M)
    for (idx, j) in enumerate(facilities)
        if j in open_set
            open_vec[idx] = isinf(50.0) || fload[j] >= 50.0 ? 1 : 2
        end
    end
    Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_lp.arrow", (
        id = facilities, open = open_vec
    ))
end