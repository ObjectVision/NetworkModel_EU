# Urban–rural typology per region from the 1 km² population grid (<region>_i.arrow,
# total_pop = residents per cell = density/km² since cells are 1 km²).
#
# Eurostat DEGURBA density bands (1 km grid):
#   rural cell        total_pop <  300 /km²
#   town/suburb cell  300 … 1500 /km²
#   urban-centre cell total_pop >= 1500 /km²
# (density criterion only — the full DEGURBA contiguity/cluster step is skipped;
#  at 1 km this share-based proxy is the standard quick classification.)
#
# Region class by rural population share (Eurostat NUTS-3 rule):
#   Predominantly Urban  PU : rural share <  20%
#   Intermediate         IN : 20% … 50%
#   Predominantly Rural  PR : rural share >= 50%
# Also emits urban_share (>=1500 band) as a continuous colour key.
#
# Writes doc/region_typology.csv.
using Arrow, Printf

DIR = "C:/LocalData/networkmodel_eu/ExistingPharmacies"
ORDER = ["Netherlands","Luxembourg","Estonia","Latvia","Slovenia","Lithuania","Ireland",
         "Norway","Denmark","Austria","Portugal","Czechia","Belgium","Poland",
         "FR1","FRB","FRC","FRD","FRE","FRF","FRG","FRH","FRI","FRJ","FRK","FRL","FRM",
         "ITC","ITF","ITG","ITH","ITI","SE1","SE2","SE3",
         "PL2","PL4","PL5","PL6","PL7","PL8","PL9"]

function classify(region)
    path = joinpath(DIR, "$(region)_i.arrow")
    isfile(path) || return nothing
    t = Arrow.Table(path)
    d = Float64.(collect(t.total_pop))          # residents/km²
    tot = sum(d)
    tot <= 0 && return nothing
    rural  = sum(d[d .< 300])       / tot
    town   = sum(d[(d .>= 300) .& (d .< 1500)]) / tot
    urban  = sum(d[d .>= 1500])     / tot
    cls = rural < 0.20 ? "PU" : rural < 0.50 ? "IN" : "PR"
    return (; region, pop=round(Int,tot), rural, town, urban, cls)
end

open(joinpath(@__DIR__, "region_typology.csv"), "w") do io
    println(io, "region,pop,rural_share,town_share,urban_share,class")
    @printf("%12s %11s %7s %7s %7s  %s\n", "region","pop","rural","town","urban","class")
    println("-"^54)
    for r in ORDER
        c = classify(r)
        c === nothing && continue
        println(io, join((c.region, c.pop, round(c.rural,digits=4),
                          round(c.town,digits=4), round(c.urban,digits=4), c.cls), ","))
        @printf("%12s %11d %6.1f%% %6.1f%% %6.1f%%  %s\n",
                c.region, c.pop, 100c.rural, 100c.town, 100c.urban, c.cls)
    end
end
println("\nwrote doc/region_typology.csv")
