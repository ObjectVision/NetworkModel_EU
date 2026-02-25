using Arrow, JuMP, HiGHS, Statistics, Random

country = "Finland"

od = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_od.arrow")
loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_i.arrow")
fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_j.arrow")

locations_col = Int.(od[:client_rel])
facilities_col = Int.(od[:facility_rel])
d_ij_col = od[:d_ij]
travelcost_ij_col = od[:travelcost_ij]
population = loc[:pop]
facilities = Int.(fac[:id])

N = length(locations_col) # od pairs
M = length(facilities)

println(typeof(facilities_col))
locations = Dict{Int, Vector{Int}}()

for k in 1:N
    i = locations_col[k]
    if haskey(locations, i)
        push!(locations[i], k)
    else
        locations[i] = [k]
    end
end

println("loc ", length(locations))


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


total_dist = sum((0.2 * travelcost_ij_col[k]) * (population[locations_col[k]+1]*0.1) for k in 1:N)
total_pop = sum(population)*0.1
mean_dist = total_dist / total_pop
baseline_λ = mean_dist * (total_pop / M) # cost of a school equals average travel cost of students per school

factors = [0.5]
open_scenarios = []

for factor in factors
    λ = factor * baseline_λ
    println("factor: ", factor)

    model = Model(HiGHS.Optimizer)
    # set_silent(model)
    # set_time_limit_sec(model, 60)
    set_optimizer_attribute(model, "mip_rel_gap", 0.01)
    set_optimizer_attribute(model, "presolve", "on")

    # variables
    @variable(model, y[shuffle(1:N)], Bin)    # per od pair
    @variable(model, x[j in shuffle(facilities)], Bin)   # per facility

    # objective
    @objective(model, Min, sum(y[k] * travelcost_ij_col[k] * population[locations_col[k]+1]*0.1 for k in 1:N) + sum(x[j]*λ for j in facilities))

    # constraints
    for (_, rows) in locations
        @constraint(model, sum(y[k] for k in rows) == 1)
    end

    # for k in 1:N
    #     @constraint(model, y[k] <= x[facilities_col[k]])
    # end

    @constraint(model,
        [j in facilities],
        sum(y[k] for k in facility_rows[j]) <= length(facility_rows[j]) * x[j]
    )

    optimize!(model)

    # for k in 1:N
    #     if value(y[k]) > 0.5
    #         println("client $(locations_col[k]) assigned to facility $(facilities_col[k])")
    #     end
    # end
                                                                                                   
    # println(sum(value(y[k]) * travelcost_ij_col[k] * population[locations_col[k]+1]*0.1 for k in 1:N))
    # println(sum(value(x[j])*λ for j in facilities))                                                  
    println(sum(value(x[j]) for j in facilities), " facilities open")                       

    # return clients (id, pop, facility_id) ?
    # return facilities (id, bool)

    open = falses(M)

    for j in facilities
        open[j+1] = value(x[j]) > 0.5
    end

    push!(open_scenarios, open)
end


columns = Dict{Symbol, AbstractVector}()
columns[:id] = facilities

for (i, factor) in enumerate(factors)
    columns[Symbol("lambda_$(factor)")] = open_scenarios[i]
end


# Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_mip.arrow", (
#     columns
# ))