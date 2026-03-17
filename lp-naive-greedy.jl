using Arrow, JuMP, HiGHS

country = "France"
flag = 1
force = false

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

assign_cons = Dict(i => @constraint(model, sum(y[k] for k in rows) == 1)
                   for (i, rows) in locations)

link_cons = [@constraint(model, y[k] <= x[facilities_col[k]]) for k in 1:N]

for j in facilities
    @constraint(model, deficit[j] >= min_students * x[j] - load[j])
end

println("solving LP relaxation...")
optimize!(model)
x_relaxed = value.(x)
y_relaxed = value.(y)

tol = 1e-6
fractional   = [j for j in facilities if tol < x_relaxed[j] < 1-tol]
fixed_open   = [j for j in facilities if x_relaxed[j] >= 1-tol]
fixed_closed = [j for j in facilities if x_relaxed[j] <= tol]

println("LP: $(length(fixed_open)) open, $(length(fixed_closed)) closed, $(length(fractional)) fractional")
println("travel: ", sum(value(y[k]) * t_ij_col[k] * wpop[k] for k in 1:N))
println("penalty: ", sum(value(deficit[j]) * λ for j in facilities))

# round fractional variables
for j in facilities
    if force
        fix(x[j], 1.0; force=true)
    elseif x_relaxed[j] >= 0.5
        fix(x[j], 1.0; force=true)
    else
        fix(x[j], 0.0; force=true)
    end
end

# more informed rounding - leads to same penalty, more schools closed, slightly higher travel cost
# for j in facilities
#     if force
#         fix(x[j], 1.0; force=true)
#     elseif j in fixed_open
#         fix(x[j], 1.0; force=true)
#     elseif j in fixed_closed
#         fix(x[j], 0.0; force=true)
#     else
#         expected_load = sum(y_relaxed[k] * wpop[k] for k in facility_rows[j])
#         if expected_load >= min_students * x_relaxed[j]
#             fix(x[j], 1.0; force=true)
#         else
#             fix(x[j], 0.0; force=true)
#         end
#     end
# end

println("solving assignment LP with rounded x...")
optimize!(model)

println("results...")
open_vec = falses(M)
for j in facilities
    open_vec[j+1] = value(x[j]) > 0.5
end

n_open   = sum(open_vec)
n_closed = M - n_open
println("$n_open open, $n_closed closed")
println("travel: ", sum(value(y[k]) * t_ij_col[k] * wpop[k] for k in 1:N))
println("penalty: ", sum(value(deficit[j]) * λ for j in facilities))

columns = Dict{Symbol, AbstractVector}()
columns[:id] = facilities
columns[:open] = open_vec

Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_mip.arrow", columns)