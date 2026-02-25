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


open_facilities = falses[M]

assigned_clients = Set{Int}()

while length(assigned_clients) < length(locations)
    best_fac = nothing
    best_net_saving = -Inf
    
    for f in facilities
        # skip if already open
        if open_facilities[f]
            continue
        end
        
        # TODO
    end
    
    if best_net_saving <= 0
        break
    end
    
    # open best facility and update assigned clients
    open_facilities[best_fac] = true
end


Arrow.write("C:\\LocalData\\networkmodel_eu\\$(country)_j_greedy.arrow", (
    id = facilities
    open = open_facilities
))
