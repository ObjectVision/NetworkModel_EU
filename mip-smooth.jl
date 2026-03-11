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
facility_cost = (2 * total_time * 200) / M

# total_time = sum((0.2 * t_ij_col[k]) * (population[clients_col[k]+1]*0.1) for k in 1:N)
# total_pop = sum(population)*0.1
# avg_time = total_time / total_pop
# estimated_cost = avg_time * (total_pop / M) # cost of a school equals average travel time (cost) of students per school
# facility_cost = 2 * estimated_cost * 200 # per year

min_students = 100
λ = facility_cost / (min_students / 2)

x_breaks = [0, 0.5*min_students, min_students-20, min_students-10, min_students, min_students+10, min_students+20, 1.5*min_students, 2*min_students]
f_breaks = [10*log(1 + exp((min_students-x)/10)) for x in x_breaks]


open = falses(M)

model = Model(HiGHS.Optimizer)

set_optimizer_attribute(model, "mip_rel_gap", 0.01)
set_optimizer_attribute(model, "presolve", "on")
set_optimizer_attribute(model, "user_objective_scale", -1)


@variable(model, 0 <= y[1:N] <= 1)
@variable(model, 0 <= x[j in facilities] <= 1)
# @variable(model, deficit[j in facilities] >= 0)
@variable(model, 0 <= deficit_pwl[j in facilities] <= 200)


for j in facilities
    @constraint(model, 
        deficit_pwl[j] == @expression(model, 
            [x_breaks; f_breaks], load[j]
        )
    )
end


@expression(model, load[j in facilities],
    sum(y[k] * population[clients_col[k]+1] * 0.1
        for k in facility_rows[j])
)


@objective(model, Min, sum(y[k] * t_ij_col[k] * population[clients_col[k]+1] * 0.1 for k in 1:N) + sum(deficit[j] * λ for j in facilities))


# each client assigned
for (_, rows) in locations
    @constraint(model, sum(y[k] for k in rows) == 1)
end

# only assign to open facility
for k in 1:N
    @constraint(model, y[k] <= x[facilities_col[k]])
end

# deficit constraint
# for j in facilities
#     @constraint(model, deficit[j] >= min_students * x[j] - load[j])
# end

println("solving LP relaxation...")
optimize!(model)

# store relaxed solution
x_relaxed = value.(x)
y_relaxed = value.(y)


println("converting to MIP...")
set_binary.(x)


# fix integer values
tol = 1e-6
for j in facilities
    if abs(x_relaxed[j]) <= tol
        fix(x[j], 0.0; force=true)
    elseif abs(x_relaxed[j] - 1.0) <= tol
        fix(x[j], 1.0; force=true)
    end
end


for j in facilities
    set_start_value(x[j], x_relaxed[j])
end

for k in 1:N
    set_start_value(y[k], y_relaxed[k])
end


# optional rounding 
for j in facilities
    if x_relaxed[j] > 0.5
        set_start_value(x[j], 1.0)
    else
        set_start_value(x[j], 0.0)
    end
end


println("solving MIP with warm start...")
optimize!(model)

println("objective value: ", objective_value(model))

                                                                                                       
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