# Issue #55: where does the gap between the multistart rounding and the LP bound come
# from in the tail of the frontier (λ well beyond S2, LP highly fractional)?
#
# For one area and travel function, at each w in WS, on exactly the sweep's problem
# (same loader, same soft-coverage LP, same multistart rounding):
#   lagr_lb  — the Lagrangian bound at the rounded count p: relax + λ·(sum_y − p)
#   lp_p     — the LP relaxation with the count fixed, Σy = p (≥ lagr_lb)
#   multi    — the sweep's multistart rounding (p = n_open)
#   swap     — multistart polished further by best-improving 1-swaps over ALL candidates
#              (not only the LP's fractional support; must-opens may close too) — the
#              lp_run.jl full_swap that FULL_SWAP=1 applies inside the sweep
#   mip      — the exact soft-coverage p-median at the same p (HiGHS, warm-started
#              from the better of multi/swap), with its proven bound
# and, for each solution, the residents left without an open candidate in their OD
# choice set (stranded, charged BIG).
#
# multi/mip − 1 is the rounding's own loss; mip/lp_p − 1 the integrality gap of the LP.
#
# Usage (one travel function per process, like the sweep):
#   AREA=Luxembourg TRAVEL_FUNC=LINEAR WS="0.25149,1,2,5" julia --startup-file=no tail_gap_experiment.jl
# Env OD_DIR points the candidate side at another NewPharmacies-like folder (e.g. an OD
# exported with a wider choice set); MIP_TIME_LIMIT caps each MIP (default 900 s); SKIP_MIP=1
# leaves the MIP out.
ENV["COUNTRIES"] = ""                       # include the sweep's code without running it
ENV["FULL_SWAP"] = "0"                      # multi must be the plain multistart: the polish is compared here
include("lambda_sweep_simplex.jl")

const AREA     = get(ENV, "AREA", "Luxembourg")
const WS       = parse.(Float64, split(get(ENV, "WS", "1,2,5"), ','))
const OD_DIR   = get(ENV, "OD_DIR", NEW_PATH)
const MIP_TIME = parse(Float64, get(ENV, "MIP_TIME_LIMIT", "900"))
const SKIP_MIP = get(ENV, "SKIP_MIP", "0") == "1"    # bounds + multistart + swap only (timing runs)

function stranded_pop(open_set, data)
    _, _, phi1 = client_nearest(open_set, data, big_cost())
    sum((data.client_pop[i] for i in keys(data.locations) if phi1[i] == -1); init=0.0)
end

# full_swap (the unrestricted 1-swap polish) lives in lp_run.jl, where FULL_SWAP=1 uses it.

# Soft-coverage p-median with exactly p open: the sweep's LP with Σy = p in place of the
# price λ. integer=false gives the LP bound at that count.
function solve_pmedian(data, p; integer::Bool, start=nothing, time_limit=MIP_TIME)
    (; N, facilities, wpop, t_ij_col, facilities_col, locations) = data
    BIG = big_cost()
    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "output_flag", false)
    set_optimizer_attribute(model, "time_limit", time_limit)
    @variable(model, 0 <= x[1:N] <= 1)
    if integer
        @variable(model, y[j in facilities], Bin)
    else
        @variable(model, 0 <= y[j in facilities] <= 1)
    end
    @objective(model, Min, sum(x[k] * (c(t_ij_col[k]) - BIG) * wpop[k] for k in 1:N))
    for (_, rows) in locations
        @constraint(model, sum(x[k] for k in rows) <= 1)
    end
    for k in 1:N
        @constraint(model, x[k] <= y[facilities_col[k]])
    end
    @constraint(model, sum(y[j] for j in facilities) == p)
    if start !== nothing
        for j in facilities
            set_start_value(y[j], j in start ? 1.0 : 0.0)
        end
        xs = zeros(N)
        for (_, rows) in locations
            best = 0; bc = Inf
            for k in rows
                if facilities_col[k] in start && c(t_ij_col[k]) < bc
                    bc = c(t_ij_col[k]); best = k
                end
            end
            best > 0 && (xs[best] = 1.0)
        end
        set_start_value.(x, xs)
    end
    t = @elapsed optimize!(model)
    const_part = BIG * sum(values(data.client_pop))
    ts = termination_status(model)
    has_values(model) || return (status=ts, travel=NaN, bound=NaN, open_set=Set{Int}(), secs=t)
    open_set = integer ? Set(j for j in facilities if value(y[j]) > 0.5) : Set{Int}()
    bound = integer ? objective_bound(model) + const_part : objective_value(model) + const_part
    return (status=ts, travel=objective_value(model) + const_part, bound=bound,
            open_set=open_set, secs=t)
end

pct(a, b) = round(100 * (a - b) / b, digits=3)

function run_area()
    pln("=" ^ 100)
    pln("Issue #55 tail-gap experiment — $AREA, $travel_func_name, OD from $OD_DIR")
    pln("=" ^ 100)
    data = load_from(OD_DIR, AREA)
    totpop = sum(values(data.client_pop))
    pln("  N=$(data.N) OD rows, M=$(data.M) candidates, $(length(data.locations)) client cells, ",
        "$(round(Int, totpop)) residents; BIG=$(big_cost())")
    state = build_lp_warmstart(data)
    set_optimizer_attribute(state.model, "output_flag", false)   # keep this log readable
    for w in sort(WS)
        pln("\n--- w = $w ---")
        r = solve_at_w!(state, w)
        p = r.n_open
        t_swap = @elapsed (sw, nsw) = full_swap(r.open_set, data)
        t_sw, _ = travel_of(sw, data, big_cost())
        best_heur = t_sw <= r.cost_c ? sw : r.open_set
        lp_p = solve_pmedian(data, p; integer=false)
        mip  = SKIP_MIP ? (status=:SKIPPED, travel=NaN, bound=NaN, open_set=Set{Int}(), secs=0.0) :
                          solve_pmedian(data, p; integer=true, start=best_heur)
        sp(s) = round(100 * stranded_pop(s, data) / totpop, digits=2)
        pln("  λ=$(round(r.λ, digits=2))  sum_y=$(round(r.sum_y, digits=2))  p=n_open=$p  frac_y=$(r.n_frac)")
        pln("  bounds    : lagr_lb=$(round(r.travel_lb, digits=1))  lp_p=$(round(lp_p.travel, digits=1))  (LP at Σy=p, $(lp_p.status))")
        pln("  multi     : $(round(r.cost_c, digits=1))   stranded $(sp(r.open_set))% of residents")
        pln("  full swap : $(round(t_sw, digits=1))   stranded $(sp(sw))%   ($nsw swaps beyond multistart, $(round(t_swap, digits=1)) s)")
        pln("  MIP       : $(round(mip.travel, digits=1))   bound $(round(mip.bound, digits=1))   ",
            "$(mip.status) in $(round(mip.secs, digits=1)) s   stranded $(isempty(mip.open_set) ? "?" : sp(mip.open_set))%")
        pln("  gaps (%)  : multi vs lagr_lb $(pct(r.cost_c, r.travel_lb))   multi vs lp_p $(pct(r.cost_c, lp_p.travel))")
        pln("              rounding loss multi vs MIP $(pct(r.cost_c, mip.travel))   swap vs MIP $(pct(t_sw, mip.travel))")
        pln("              integrality gap MIP vs lp_p $(pct(mip.travel, lp_p.travel))   (MIP bound vs lp_p $(pct(mip.bound, lp_p.travel)))")
        pln("  SUMMARY\t$AREA\t$travel_func_name\t$w\t$p\t$(round(r.sum_y, digits=2))\t$(r.n_frac)\t",
            "$(r.travel_lb)\t$(lp_p.travel)\t$(r.cost_c)\t$t_sw\t$(mip.travel)\t$(mip.bound)\t$(mip.status)\t",
            "$(sp(r.open_set))\t$(sp(sw))\t$(isempty(mip.open_set) ? NaN : sp(mip.open_set))")
    end
end

run_area()
