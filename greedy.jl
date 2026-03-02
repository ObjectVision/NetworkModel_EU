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
    j += 1
end

sort!(regret, by = x -> x[2], rev = true)
clients = first.(regret)


facility_load = Dict(j => 0 for j in facilities)


for i in clients
    for k in locations[i]
        j = facilities_col[k]
        cost = travelcost_ij_col[k]
        n_j = facility_load[j]
    end
end

#     println(i)
# end
    

# while length(assigned_clients) < length(locations)
#     best_fac = nothing
#     best_net_saving = -Inf
    
#     for f in facilities
#         # skip if already open
#         if open_facilities[f]
#             continue
#         end
        
#         # TODO
#     end
    
#     if best_net_saving <= 0
#         break
#     end
    
#     # open best facility and update assigned clients
#     open_facilities[best_fac] = true
# end


# Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_greedy.arrow", (
#     id = facilities,
#     open = open_facilities
# ))
