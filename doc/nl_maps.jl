# Per-client travel time to the nearest open pharmacy for the deck's Netherlands maps
# slide: baseline (existing pharmacies) and the pinned S1/S2 of one cost function, read
# from the arrows the sweep wrote (lambda_sweep/<FUNC>/{baseline,S1,S2}/traveltime.arrow)
# and joined to the 1-km client cells. A cell absent from a scenario's arrow has no open
# pharmacy in its choice set (stranded) and gets t = missing.
#   julia --startup-file=no doc/nl_maps.jl [AREA=Netherlands] [FUNC=LINEAR]
#   -> doc/charts/maps_<AREA>_<FUNC>.csv  (id, x, y, pop, t_base, t_S1, t_S2)
using Arrow, Printf
include(joinpath(@__DIR__, "..", "settings.jl"))

area = length(ARGS) >= 1 ? ARGS[1] : "Netherlands"
func = length(ARGS) >= 2 ? ARGS[2] : "LINEAR"
base = joinpath(LOCAL_DATA_PROJ_DIR, "ExistingPharmacies", area, "lambda_sweep", func, "baseline")
newd = joinpath(LOCAL_DATA_PROJ_DIR, "NewPharmacies", area, "lambda_sweep", func)

loc = Arrow.Table(joinpath(LOCAL_DATA_PROJ_DIR, "NewPharmacies", "$(area)_i.arrow"))
ids = Int.(loc[:id]); xs = Float64.(loc[:x]); ys = Float64.(loc[:y]); pop = Float64.(collect(client_weight_col(loc)))

function tmap(dir)
    t = Arrow.Table(joinpath(dir, "traveltime.arrow"))
    Dict{Int,Float64}(zip(Int.(t[:id]), Float64.(t[:t_ij])))
end
tb, t1, t2 = tmap(base), tmap(joinpath(newd, "S1")), tmap(joinpath(newd, "S2"))

out = joinpath(@__DIR__, "charts", "maps_$(area)_$(func).csv")
mkpath(dirname(out))
open(out, "w") do io
    println(io, "id,x,y,pop,t_base,t_S1,t_S2")
    for k in eachindex(ids)
        pop[k] > 0 || continue           # a cell without demand is out of scope (#49), not a client
        f(d) = haskey(d, ids[k]) ? @sprintf("%.3f", d[ids[k]]) : ""
        @printf(io, "%d,%.0f,%.0f,%.0f,%s,%s,%s\n", ids[k], xs[k], ys[k], pop[k], f(tb), f(t1), f(t2))
    end
end
n(d) = count(k -> pop[k] > 0 && haskey(d, ids[k]), eachindex(ids))
println("wrote $out: $(count(>(0), pop)) client cells; covered baseline $(n(tb)), S1 $(n(t1)), S2 $(n(t2))")
