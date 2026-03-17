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
min_students = 100

open = falses(M)

λ = facility_cost / (min_students/2)

lower_bound = [0, 20, 40, 60, 80]       # lower bound of deficit per bin
upper_bound = [19, 39, 59, 79, 99]     # upper bound of deficit per bin
bin_multipliers = [0.2, 0.4, 0.6, 0.8, 1.0]   # big to small
λ_bin = bin_multipliers .* λ

model = Model(HiGHS.Optimizer)
# set_time_limit_sec(model, 60)
set_optimizer_attribute(model, "mip_rel_gap", 0.01)
set_optimizer_attribute(model, "presolve", "on")
set_optimizer_attribute(model, "user_objective_scale", -1)

# variables
@variable(model, y[1:N], Bin)   # per od pair
@variable(model, x[j in facilities], Bin)   # per facility
@variable(model, small[j in facilities], Bin)
@variable(model, bin[j=facilities, b=1:5], Bin)

@expression(model, load[j in facilities],
    sum(y[k] * population[clients_col[k]+1] * 0.1 for k in facility_rows[j])
)

# objective
@objective(model, Min, sum(y[k] * t_ij_col[k] * population[clients_col[k]+1]*0.1 for k in 1:N) + sum(bin[j,b]*λ_bin[b] for j in facilities, b=1:5))

# constraints
for (_, rows) in locations
    @constraint(model, sum(y[k] for k in rows) == 1)
end

for k in 1:N
    @constraint(model, y[k] <= x[facilities_col[k]])
end

for j in facilities
    @constraint(model, small[j] <= x[j])
end

for j in facilities
    @constraint(model, load[j] >= (min_students * (x[j] - small[j])))
end

for j in facilities
    @constraint(model, sum(bin[j,b] for b in 1:5) == small[j])
end

for j in facilities, b in 1:5
    @constraint(model, load[j] >= lower_bound[b] * bin[j,b]) # lb
    @constraint(model, load[j] <= upper_bound[b] * bin[j,b] + 5000*(1-small[j])) # ub
end

optimize!(model)
                                                                                                        
println(sum(value(x[j]) for j in facilities), " facilities open")                       
    
for j in facilities
    open[j+1] = value(x[j]) > 0.5
end


println("travel: ", sum(value(y[k]) * t_ij_col[k] * population[clients_col[k]+1] * 0.1 for k in 1:N))
# println("penalty: ", sum(value(small[j]) * λ for j in facilities))


columns = Dict{Symbol, AbstractVector}()
columns[:id] = facilities
columns[:open] = open


Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_mip.arrow", (
    columns
))