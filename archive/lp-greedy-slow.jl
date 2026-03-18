using Arrow, JuMP, HiGHS

country = "France"
flag = 1

od  = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_od.arrow")
loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_i.arrow")
fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_j.arrow")

clients_col    = Int.(od[:client_rel])
facilities_col = Int.(od[:facility_rel])
t_ij_col       = od[:t_ij]
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
    j = facilities_col[k]   # facility of od row k
    if !haskey(facility_rows, j)
        facility_rows[j] = Int[]
    end
    push!(facility_rows[j], k)
end

for j in facilities
    if !haskey(facility_rows, j)
        facility_rows[j] = Int[]   # empty vector if no od rows
    end
end

min_students  = 100
total_time    = sum(0.2 * t_ij_col[k] * wpop[k] for k in 1:N)
facility_cost = (2 * total_time * 200) / M
λ             = facility_cost / (min_students / 2)

# LP relaxation
model = Model(HiGHS.Optimizer)
set_optimizer_attribute(model, "presolve", "on")
set_optimizer_attribute(model, "user_objective_scale", -2)

@variable(model, 0 <= y[1:N] <= 1)
@variable(model, 0 <= x[j in facilities] <= 1)
@variable(model, deficit[j in facilities] >= 0)

@expression(model, load[j in facilities],
    sum(y[k] * wpop[k] for k in facility_rows[j])
)

@objective(model, Min,
    sum(y[k] * t_ij_col[k] * wpop[k] for k in 1:N) +
    flag * sum(deficit[j] * λ for j in facilities)
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

println("solving LP relaxation...")
optimize!(model)

x_relaxed = value.(x)

tol = 1e-6
fixed_open   = [j for j in facilities if x_relaxed[j] >= 1 - tol]
fixed_closed = [j for j in facilities if x_relaxed[j] <= tol]
fractional   = [j for j in facilities if tol < x_relaxed[j] < 1 - tol]

println("LP: $(length(fixed_open)) open, $(length(fixed_closed)) closed, $(length(fractional)) fractional")

fixed_open_set   = Set(fixed_open)
fixed_closed_set = Set(fixed_closed)
fractional_set   = Set(fractional)

function drop_heuristic()
    open_set = union(fixed_open_set, fractional_set)

    # initial assignment: each client to nearest open facility
    assigned = Dict{Int, Int}()  # client -> facility
    fload    = Dict(j => 0.0 for j in facilities)

    for (i, rows) in locations
        best_k    = nothing
        best_cost = Inf
        for k in rows
            j = facilities_col[k]
            if j in open_set && t_ij_col[k] < best_cost
                best_cost = t_ij_col[k]
                best_k    = k
            end
        end
        if best_k !== nothing
            j = facilities_col[best_k]
            assigned[i] = j
            fload[j]   += wpop[best_k]
        end
    end

    # current cost
    travel_cost  = sum(t_ij_col[k] * wpop[k]
                       for k in 1:N
                       if haskey(assigned, clients_col[k]) &&
                          assigned[clients_col[k]] == facilities_col[k])
    penalty_cost = flag * sum(λ * max(0.0, min_students - fload[j]) for j in open_set)
    current_cost = travel_cost + penalty_cost

    println("initial cost: ", round(current_cost, digits=0),
            " (travel=", round(travel_cost, digits=0),
            " penalty=", round(penalty_cost, digits=0), ")")

    improved = true
    while improved
        improved    = false
        best_saving = 0.0
        best_j      = nothing

        for j in fractional
            if !(j in open_set)
                continue
            end

            # penalty saving from closing j
            penalty_saving = flag * λ * max(0.0, min_students - fload[j])

            # travel cost increase: clients assigned to j must reroute
            travel_increase = 0.0
            for (i, rows) in locations
                if !haskey(assigned, i) || assigned[i] != j
                    continue
                end
                # find next best open facility excluding j
                best_alt_cost = Inf
                for k in rows
                    jj = facilities_col[k]
                    if jj != j && jj in open_set
                        if t_ij_col[k] < best_alt_cost
                            best_alt_cost = t_ij_col[k]
                        end
                    end
                end
                # current travel cost for this client
                cur_cost = minimum(t_ij_col[k] for k in rows if facilities_col[k] == j)
                if best_alt_cost < Inf
                    travel_increase += (best_alt_cost - cur_cost) * wpop[first(k for k in rows if facilities_col[k] == j)]
                else
                    travel_increase = Inf  # no alternative, can't close
                    break
                end
            end

            saving = penalty_saving - travel_increase
            if saving > best_saving
                best_saving = saving
                best_j      = j
            end
        end

        if best_j !== nothing
            # close best_j and reassign its clients
            open_set = setdiff(open_set, [best_j])

            for (i, rows) in locations
                if !haskey(assigned, i) || assigned[i] != best_j
                    continue
                end
                # reassign to next best
                best_k    = nothing
                best_cost = Inf
                for k in rows
                    jj = facilities_col[k]
                    if jj in open_set && t_ij_col[k] < best_cost
                        best_cost = t_ij_col[k]
                        best_k    = k
                    end
                end
                if best_k !== nothing
                    old_j = best_j
                    new_j = facilities_col[best_k]
                    fload[old_j] -= wpop[best_k]
                    fload[new_j] += wpop[best_k]
                    assigned[i]   = new_j
                end
            end

            # recompute cost
            travel_cost  = sum(t_ij_col[k] * wpop[k]
                               for k in 1:N
                               if haskey(assigned, clients_col[k]) &&
                                  assigned[clients_col[k]] == facilities_col[k])
            penalty_cost = flag * sum(λ * max(0.0, min_students - fload[j]) for j in open_set)
            current_cost = travel_cost + penalty_cost

            println("closed $(best_j), saving=$(round(best_saving,digits=0)), cost=$(round(current_cost,digits=0))")
            improved = true
        end
    end

    return open_set, assigned, fload, current_cost
end

open_set, assigned, fload, total_cost = drop_heuristic()

# fix x based on open_set and re-solve for optimal assignment
for j in facilities
    if j in open_set
        fix(x[j], 1.0; force=true)
    else
        fix(x[j], 0.0; force=true)
    end
end

println("solving assignment LP...")
optimize!(model)

println("\nresults after LP assignment:")
println("open: $(sum(j in open_set for j in facilities))")
println("closed: $(sum(!(j in open_set) for j in facilities))")
println("travel: ", sum(value(y[k]) * t_ij_col[k] * wpop[k] for k in 1:N))
println("penalty: ", sum(value(deficit[j]) * λ for j in facilities))


open_vec = [j in open_set for j in facilities]

Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_lp_greedy.arrow", (
    id   = facilities,
    open = open_vec
))