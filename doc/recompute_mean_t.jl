# Recompute the mean_t of every rounded sweep/refine row from its per-w traveltime arrow,
# with the stranded clients (no open facility in their choice set) entering at the
# 120-min cutoff -- the baseline's convention (baseline_metrics) and, since 15 Sep 2026,
# lp_run.jl's. Rows logged before that date counted the stranded at 0 min, so their
# mean_t was not comparable with the baseline's wherever the rounding stranded anyone.
# cost_c and the S1/S2 selection are not affected (travel_of always priced them at BIG).
#
# Reads  logs/{sweep,refine}_<area>_<FUNC>.log and
#        <LocalData>/NewPharmacies/<area>/lambda_sweep/<FUNC>/{w=<w>,S1,S2}/traveltime.arrow
# writes doc/mean_t_stranded.csv (area, func, label, w, mean_t_logged, mean_t, stranded_pop,
#        total_pop), which build_deck_data.py applies to the rows and the S1/S2 summaries.
#
#   julia --startup-file=no doc/recompute_mean_t.jl            # every area with a sweep log
#   julia --startup-file=no doc/recompute_mean_t.jl SE2 SE3    # a subset: their entries are
#                                                              # replaced, the other areas' kept
using Arrow, Dates, Printf
include(joinpath(@__DIR__, "..", "settings.jl"))

const NEW_PATH = joinpath(LOCAL_DATA_PROJ_DIR, "NewPharmacies")
const LOGS     = joinpath(@__DIR__, "..", "logs")
const FUNCS    = ("LINEAR", "LOGISTIC")

# The client population and the client ids of the sweep's LP, as load_from builds them:
# candidates in an excluded NUTS region drop out with their OD rows, clients there weigh 0.
function client_pops(area)
    od  = Arrow.Table(joinpath(NEW_PATH, "$(area)_od.arrow"))
    loc = Arrow.Table(joinpath(NEW_PATH, "$(area)_i.arrow"))
    fac = Arrow.Table(joinpath(NEW_PATH, "$(area)_j.arrow"))
    excl, level, _ = excluded_nuts_regions(area)
    facilities_all = Int.(fac[:id])
    population     = Float64.(collect(client_weight_col(loc)))
    clients        = Int.(od[:client_rel])
    if !isempty(excl)
        fset    = Set(facilities_all[.!in_excluded_region(fac, excl, level)])
        clients = clients[[f in fset for f in Int.(od[:facility_rel])]]
        population[in_excluded_region(loc, excl, level)] .= 0
    end
    ids = unique(clients)
    return Dict(i => population[i+1] for i in ids)
end

# Rounded rows of a log's "Combined sweep" table, as build_deck_data.py reads them:
# (w as printed, mean_t as printed); LP-only rows print "-" and are skipped.
function log_rows(path)
    rows = Tuple{Float64,Float64}[]
    in_tbl = false; seen = false
    for ln in eachline(path)
        if startswith(ln, "Combined sweep")
            in_tbl = true; seen = false; continue
        end
        in_tbl || continue
        if startswith(ln, "w ")
            seen = true; continue
        end
        seen || continue
        (isempty(strip(ln)) || startswith(ln, "=")) && break
        f = split(ln)
        length(f) < 12 && continue
        w = tryparse(Float64, f[1]); m = tryparse(Float64, f[10])
        (w === nothing || m === nothing) && continue
        push!(rows, (w, m))
    end
    return rows
end

# The arrow directory of a row: the newest w=<w> folder within the row's rounding (the
# log prints 5 significant digits) written no later than the log itself.
function row_dir(base, w, log_mtime)
    best = nothing; best_t = -Inf
    for d in readdir(base)
        startswith(d, "w=") || continue
        wd = tryparse(Float64, d[3:end])
        (wd === nothing || abs(wd - w) > 6e-5 * w) && continue
        t = mtime(joinpath(base, d, "traveltime.arrow"))
        t <= log_mtime + 120 && t > best_t && (best = d; best_t = t)
    end
    return best
end

function mean_t_of(dir, pops)
    tt = Arrow.Table(joinpath(dir, "traveltime.arrow"))
    ids = Int.(tt[:id]); t = Float64.(tt[:t_ij])
    total = sum(values(pops))
    covered = 0.0; seen = Set{Int}()
    for (i, ti) in zip(ids, t)
        covered += ti * get(pops, i, 0.0); push!(seen, i)
    end
    stranded = sum((p for (i, p) in pops if !(i in seen)); init=0.0)
    return (covered + MAX_TRAVELTIME_MIN * stranded) / total, stranded, total
end

function main(areas)
csv = joinpath(@__DIR__, "mean_t_stranded.csv")
kept = isfile(csv) ? [l for l in readlines(csv)[2:end] if !(first(split(l, ',')) in areas)] : String[]
out = open(csv, "w")
println(out, "area,func,label,w,mean_t_logged,mean_t,stranded_pop,total_pop")
foreach(l -> println(out, l), kept)
n_rows = 0; n_changed = 0; n_missing = 0
for area in areas
    pops = client_pops(area)
    for fn in FUNCS
        base = joinpath(NEW_PATH, area, "lambda_sweep", fn)
        isdir(base) || continue
        done = Set{Float64}()
        for kind in ("sweep", "refine", "tail")
            lp = joinpath(LOGS, "$(kind)_$(area)_$(fn).log")
            isfile(lp) || continue
            lm = mtime(lp)
            for (w, m_logged) in log_rows(lp)
                w in done && continue
                d = row_dir(base, w, lm)
                if d === nothing
                    n_missing += 1
                    @warn "$area $fn w=$w: no traveltime arrow within the log's rounding"
                    continue
                end
                m, st, tot = mean_t_of(joinpath(base, d), pops)
                push!(done, w); n_rows += 1
                abs(m - m_logged) > 5e-4 && (n_changed += 1)
                @printf(out, "%s,%s,row,%.6g,%.4f,%.4f,%.1f,%.1f\n", area, fn, w, m_logged, m, st, tot)
            end
        end
        for lbl in ("S1", "S2")
            d = joinpath(base, lbl)
            isfile(joinpath(d, "traveltime.arrow")) || continue
            m, st, tot = mean_t_of(d, pops)
            @printf(out, "%s,%s,%s,,,%.4f,%.1f,%.1f\n", area, fn, lbl, m, st, tot)
        end
    end
    println(rpad(area, 12), " done")
end
close(out)
println("rows: $n_rows recomputed, $n_changed changed by > 0.0005 min, $n_missing without an arrow")
end

main(length(ARGS) > 0 ? ARGS :
     sort(unique(m.captures[1] for m in
         (match(r"^sweep_(.+)_(LINEAR|LOGISTIC)\.log$", f) for f in readdir(LOGS)) if m !== nothing)))
