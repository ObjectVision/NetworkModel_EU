using Arrow, Statistics



country = "Netherlands"

od = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_od.arrow")
loc = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_i.arrow")
fac = Arrow.Table("C:\\LocalData\\networkmodel_eu\\$(country)_j.arrow")

locations_col = od[:client_rel]
facilities_col = od[:facility_rel]
d_ij_col = od[:d_ij]
travelcost_ij_col = od[:travelcost_ij]
population = loc[:pop]
facilities = fac[:id]

N = length(locations_col) # od pairs
M = length(facilities)

locations = Dict{Int, Vector{Int}}()

for k in 1:N
    i = locations_col[k]
    if haskey(locations, i)
        push!(locations[i], k)
    else
        locations[i] = [k]
    end
end

K = length(locations)


regret = Vector{Tuple{Int, Float64}}(undef, K)
j = 1

for (i, rows) in locations
    min1 = Inf
    min2 = Inf

    for k in rows
        c = travelcost_ij_col[k]
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
facility_load = Dict(j => 0 for j in facilities)

total_dist = sum((0.2 * travelcost_ij_col[k]) * (population[locations_col[k]+1]*0.1) for k in 1:N)
total_pop = sum(population)*0.1
mean_dist = total_dist / total_pop
baseline_λ = mean_dist * (total_pop / M) # cost of a school equals average travel cost of students per school
facility_cost = baseline_λ

for i in clients
    best_delta = Inf
    best_j = nothing

    for k in locations[i]
        local j = facilities_col[k]
        cost = travelcost_ij_col[k]
        n_j = facility_load[j]

         # marginal facility cost
        delta_fac = n_j == 0 ? facility_cost : 0.0 # facility_cost/(n_j+1) - facility_cost/n_j

        # total marginal cost
        delta = delta_fac + cost

        if delta < best_delta
            best_delta = delta
            best_j = j
        end
    end

    # assign client i to best facility
    assigned_facility[i] = best_j
    facility_load[best_j] += 1
end


Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_greedy.arrow", (
    id = facilities,
    open = open_facilities
))
