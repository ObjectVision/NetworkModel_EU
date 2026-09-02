include(joinpath(dirname(@__DIR__), "lp_run.jl"))
for a in ["Norway","SE2","SE3"]
    excl, lvl, rep = excluded_nuts_regions(a)
    if isempty(rep)
        println(rpad(a,8), "NUTS$lvl  -> geen uitsluitingen")
    else
        println(rpad(a,8), "NUTS$lvl  -> ", join(["$(g) ($(round(100*s,digits=1))%, $(round(Int,p)) inw, $c cellen)" for (g,s,p,c) in rep], "; "))
    end
end
