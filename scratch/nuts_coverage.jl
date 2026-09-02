using Arrow
base = "C:/LocalData/networkmodel_eu"
area = length(ARGS) > 0 ? ARGS[1] : "Portugal"
i  = Arrow.Table("$base/NewPharmacies/$(area)_i.arrow")
od = Arrow.Table("$base/ExistingPharmacies/$(area)_od.arrow")
println("cols_i = ", propertynames(i))
n = length(i.x)
inod = falses(n)
for r in od.client_rel; inod[r+1] = true; end
nuts = i.NUTS
lvl(c, k) = length(c) >= k ? c[1:k] : ""
for k in (5, 4, 3)
    groups = Dict{String, Vector{Int}}()
    for r in 1:n
        g = lvl(nuts[r], k)
        push!(get!(groups, g, Int[]), r)
    end
    bad = [(g, count(!, inod[rs]) / length(rs), sum(i.total_pop[rs]), length(rs)) for (g, rs) in groups]
    filter!(t -> t[2] > 0.5, bad)
    sort!(bad, by = t -> -t[3])
    println("--- NUTS level $(k==5 ? 3 : k==4 ? 2 : 1) ($(length(groups)) groups): $(length(bad)) exceed 50% not-in-OD ---")
    for (g, frac, pop, ncell) in bad
        println("    $(rpad(g,6)) not_in_OD=$(round(100*frac,digits=1))%  cells=$ncell  pop=$(round(Int,pop))")
    end
end
