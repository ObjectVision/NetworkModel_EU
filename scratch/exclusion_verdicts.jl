include(joinpath(dirname(@__DIR__), "lp_run.jl"))
areas = String[]
open(joinpath(dirname(@__DIR__),"scratch","rebuild_all_all.csv")) do fh
    readline(fh)
    for l in eachline(fh)
        p = split(strip(l), ',')
        push!(areas, strip(p[1], '"'))
    end
end
skip = Set(["Norway","SE2","SE3"])
println(rpad("area",13), rpad("lvl",5), "excluded regions")
println("-"^80)
nany = Ref(0)
open(joinpath(dirname(@__DIR__),"scratch","exclusion_verdicts.csv"),"w") do out
    println(out, "area,nuts_level,nuts_code,share_not_in_od,population,cells")
    for a in areas
        a in skip && continue
        try
            excl, lvl, rep = excluded_nuts_regions(a)
            if isempty(rep)
                println(rpad(a,13), rpad(lvl,5), "-")
            else
                nany[] += 1
                println(rpad(a,13), rpad("NUTS$lvl",5), join(["$(g) ($(round(100*s,digits=1))%, $(round(Int,p)) inw, $c cellen)" for (g,s,p,c) in rep], "; "))
                for (g,s,p,c) in rep
                    println(out, "$a,$lvl,$g,$(round(s,digits=4)),$(round(Int,p)),$c")
                end
            end
        catch e
            println(rpad(a,13), rpad("ERR",5), sprint(showerror, e)[1:min(60,end)])
        end
    end
end
println("-"^80)
println("$(nany[]) area(s) with at least one excluded region")
