using Arrow, Statistics

country = "Finland"

od = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_od.arrow")
loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_i.arrow")
fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_j.arrow")

clients_col = od[:client_rel]
facilities_col = od[:facility_rel]
d_ij_col = od[:d_ij]
t_ij_col = od[:t_ij]
population = loc[:pop]
facilities = fac[:id]

N = length(clients_col) # od pairs
M = length(facilities)

locations = Dict{Int, Vector{Int}}()

for k in 1:N
    id = clients_col[k]
    if haskey(locations, id)
        push!(locations[id], k)
    else
        locations[id] = [k]
    end
end

K = length(locations)


regret = Vector{Tuple{Int, Float64}}(undef, K)
j = 1

for (i, rows) in locations
    min1 = Inf
    min2 = Inf

    for k in rows
        c = t_ij_col[k]
        if c < min1
            min2 = min1
            min1 = c
        elseif c < min2
            min2 = c
        end
    end

    regret[j] = (i, min2 - min1)
    global j += 1
end

sort!(regret, by = x -> x[2], rev = true)
clients = first.(regret)

assigned_facility = Dict{Int, Int}()
facility_load = Dict(j => 0.0 for j in facilities)

total_time = sum((0.2 * t_ij_col[k]) * (population[clients_col[k]+1]*0.1) for k in 1:N)
total_pop = sum(population)*0.1
avg_time = total_time / total_pop
estimated_cost = avg_time * (total_pop / M) # cost of a school equals average travel time (cost) of students per school
facility_cost = 2 * estimated_cost * 200 # per year

alpha = 1 # how important travel time is relative to facility cost
T = 2 * 1.5 * 200 # roughly corresponds to 15 minutes
gamma = facility_cost / T^2

for i in clients

    pop_i = population[clients_col[i+1]+1] * 0.1

    best_delta = Inf
    best_j = nothing

    for k in locations[i]
        local j = facilities_col[k]
        travel = t_ij_col[k]
        n_j = facility_load[j]

        # marginal facility cost
        delta_fac = ((facility_load[j] + pop_i) < 100) ? facility_cost : 0.0 # (n_j == 0) ? facility_cost : 0.0
       
        penalized_travel = travel > T ? travel + gamma * (travel - T)^2 : travel
        delta = delta_fac + alpha * penalized_travel * pop_i

        if delta < best_delta
            best_delta = delta
            best_j = j
        end

    end

    # assign client i to best facility
    if best_j === nothing
        error("no valid facility found for client $i")  # safety check
    end

    assigned_facility[i] = best_j
    facility_load[best_j] += pop_i
end

open_facilities = [facility_load[j] > 0 ? true : false for j in facilities]
println("total ", length(facilities))
println("open ", sum(open_facilities))

Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_greedy.arrow", (
    id = facilities,
    open = open_facilities
))
