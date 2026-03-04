using Arrow, JuMP, HiGHS, Statistics, Random

country = "Finland"

od = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_od.arrow")
loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_i.arrow")
fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_j.arrow")

clients_col = Int.(od[:client_rel])
facilities_col = Int.(od[:facility_rel])
d_ij_col = od[:d_ij]
t_ij_col = od[:t_ij]
population = loc[:pop]
facilities = Int.(fac[:id])

N = length(clients_col) # od pairs
M = length(facilities)

println(typeof(facilities_col))
locations = Dict{Int, Vector{Int}}()

for k in 1:N
    i = clients_col[k]
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


total_time = sum((0.2 * t_ij_col[k]) * (population[clients_col[k]+1]*0.1) for k in 1:N)
total_pop = sum(population)*0.1
avg_time = total_time / total_pop
estimated_cost = avg_time * (total_pop / M) # cost of a school equals average travel time (cost) of students per school
facility_cost = 2 * estimated_cost * 200 # per year
U = sum(population) * 0.1
min_students = 50

factor = 1 # 0.001
open = falses(M)

λ = factor * facility_cost

model = Model(HiGHS.Optimizer)
# set_time_limit_sec(model, 60)
set_optimizer_attribute(model, "mip_rel_gap", 0.05)
set_optimizer_attribute(model, "presolve", "on")

# variables
@variable(model, y[1:N], Bin)    # per od pair
@variable(model, x[j in facilities], Bin)   # per facility
@variable(model, small[j in facilities], Bin)

@expression(model, load[j in facilities],
    sum(y[k] * population[clients_col[k]+1] * 0.1 for k in facility_rows[j])
)

# objective
@objective(model, Min, sum(y[k] * t_ij_col[k] * population[clients_col[k]+1]*0.1 for k in 1:N) + sum(small[j]*λ for j in facilities))

# constraints
for (_, rows) in locations
    @constraint(model, sum(y[k] for k in rows) == 1)
end

for k in 1:N
    @constraint(model, y[k] <= x[facilities_col[k]])
end

for j in facilities
    @constraint(model, load[j] >= min_students * (x[j] - small[j]))
end

for j in facilities
    @constraint(model, small[j] <= x[j])
end

optimize!(model)

# for k in 1:N
#     if value(y[k]) > 0.5
#         println("client $(locations_col[k]) assigned to facility $(facilities_col[k])")
#     end
# end
                                                                                                        
println(sum(value(x[j]) for j in facilities), " facilities open")                       
    
for j in facilities
    open[j+1] = value(x[j]) > 0.5
end


println("travel: ", sum(value(y[k]) * t_ij_col[k] * population[clients_col[k]+1] * 0.1 for k in 1:N))
println("penalty: ", sum(value(small[j]) * λ for j in facilities))


columns = Dict{Symbol, AbstractVector}()
columns[:id] = facilities
columns[:open] = open


Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_mip.arrow", (
    columns
))