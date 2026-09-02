using Arrow
base = "C:/LocalData/networkmodel_eu"
for area in ["Portugal","ITG"]
    i  = Arrow.Table("$base/ExistingPharmacies/$(area)_i.arrow")
    od = Arrow.Table("$base/ExistingPharmacies/$(area)_od.arrow")
    j  = Arrow.Table("$base/ExistingPharmacies/$(area)_j.arrow")
    println("=== ", area, " ===  cols_i=", propertynames(i), "  cols_od=", propertynames(od))
    n = length(i.x)
    reach = Set(od.client_rel)
    unre = [r for r in 0:(n-1) if !(r in reach)]
    println("  clients=", n, "  od=", length(od.client_rel), "  facilities=", length(j.x), "  unreachable=", length(unre))
    if !isempty(unre)
        idx = unre .+ 1
        ux = i.x[idx]; uy = i.y[idx]
        println("  unreachable x(km): ", round(minimum(ux)/1000), " .. ", round(maximum(ux)/1000),
                "   y(km): ", round(minimum(uy)/1000), " .. ", round(maximum(uy)/1000))
        println("  unreachable pop  : ", sum(i.total_pop[idx]))
    end
    println("  all clients x(km): ", round(minimum(i.x)/1000), " .. ", round(maximum(i.x)/1000),
            "   y(km): ", round(minimum(i.y)/1000), " .. ", round(maximum(i.y)/1000))
    println("  facilities  x(km): ", round(minimum(j.x)/1000), " .. ", round(maximum(j.x)/1000),
            "   y(km): ", round(minimum(j.y)/1000), " .. ", round(maximum(j.y)/1000))
end

