include("lp_run.jl")

# Validate topp vs greedy vs multistart + coverage, on NL (set TRAVEL_FUNC in env).
data = load_country("Netherlands")
println("Loaded Netherlands: N=$(data.N) OD rows, M=$(data.M), clients=$(length(data.locations)), func=$travel_func_name"); flush(stdout)

state = build_lp_warmstart(data)
println("LP built. MS_RESTARTS=$MS_RESTARTS MS_ROUNDS=$MS_ROUNDS"); flush(stdout)

println(rpad("w",6), rpad("n_frac",7), rpad("topp",13), rpad("greedy",13), rpad("multi",13),
        rpad("m/topp",9), rpad("m/grdy",9), rpad("uncov(t/g/m)",16), "s")
for w in (0.1, 0.2)
    t = @elapsed r = solve_at_w!(state, w)
    dmt = 100*(r.travel_c_multi - r.travel_c_topp)/r.travel_c_topp
    dmg = 100*(r.travel_c_multi - r.travel_c_greedy)/r.travel_c_greedy
    println(rpad(w,6), rpad(r.n_frac,7),
            rpad(round(r.travel_c_topp,digits=0),13), rpad(round(r.travel_c_greedy,digits=0),13),
            rpad(round(r.travel_c_multi,digits=0),13),
            rpad("$(round(dmt,digits=2))%",9), rpad("$(round(dmg,digits=2))%",9),
            rpad("$(r.uncov_topp)/$(r.uncov_greedy)/$(r.uncov_multi)",16), round(t,digits=1))
    flush(stdout)
end
