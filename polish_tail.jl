# Issue #55, route 2: polish the stored multistart sets of the sweep rows beyond S2 by
# unrestricted swaps (lp_run.jl full_swap, the FULL_SWAP polish), WITHOUT re-solving the LP.
#
# Input: doc/polish_rows.tsv, written by doc/build_deck_data.py: exactly the region rows
# the deck uses, with λ, sum_y, the LP bound at the row's count (lb) and the multistart
# travel (multi_ms). A row is polished when its gap vs lb is ≥ FULL_SWAP_MIN_GAP % and
# λ ≥ FULL_SWAP_MIN_LAMBDA € (same switches as FULL_SWAP inside the sweep).
#
# Per row: the per-w folder NewPharmacies/<area>/lambda_sweep/<FUNC>/w=<w>/ holds the open
# set that run wrote. A later run may have overwritten it, or the OD may have been rebuilt
# since, so the set is only used when its count equals n_open and its travel, recomputed on
# today's OD, equals the row's multistart travel. Otherwise the row is recorded as
# "stale" and left alone.
#
# Output (one per travel function):
#   doc/full_swap_polish_<FUNC>.csv — one line per eligible row: status
#       polished | unchanged | stale | no_arrow, travel before/after, swaps, seconds,
#       stranded cells/residents before/after, mean travel time of the polished set
#       (stranded at the 120-min cutoff, as the sweep reports it).
#       build_deck_data.py applies the "polished" lines.
#   NewPharmacies/<area>/lambda_sweep/<FUNC>/polished/w=<w>/{assignment,traveltime}.arrow
#       for polished rows (a separate folder: the sweep's own w=… folders are not touched;
#       POLISH_WRITE_ARROWS=0 skips them).
#
# Usage (one travel function per process, like the sweep):
#   python doc/build_deck_data.py
#   FULL_SWAP_MIN_GAP=1 TRAVEL_FUNC=LINEAR   julia --startup-file=no polish_tail.jl
#   FULL_SWAP_MIN_GAP=1 TRAVEL_FUNC=LOGISTIC julia --startup-file=no polish_tail.jl
#   python doc/build_deck_data.py && python doc/export_issue48.py
# POLISH_ONLY="FR1 Belgium" restricts the run to those areas (as named in the logs) and
# keeps the other areas' lines of an existing csv.
ENV["COUNTRIES"] = ""                       # include the sweep's code without running it
include("lambda_sweep_simplex.jl")

const ROWS_TSV     = joinpath(@__DIR__, "doc", "polish_rows.tsv")
const OUT_CSV      = joinpath(@__DIR__, "doc", "full_swap_polish_$(travel_func_name).csv")
const ONLY         = Set(split(get(ENV, "POLISH_ONLY", "")))
const WRITE_ARROWS = get(ENV, "POLISH_WRITE_ARROWS", "1") == "1"

const HEADER = "area,func,w,lambda,n_open,sum_y,relax,lb,multi_logged,multi_recomputed,folder," *
               "status,swaps,secs,multi_polished,gap_before_pct,gap_after_pct," *
               "stranded_cells_before,stranded_cells_after,stranded_pop_before,stranded_pop_after," *
               "mean_t_polished"

function read_rows()
    rows = NamedTuple[]
    for (n, ln) in enumerate(eachline(ROWS_TSV))
        n == 1 && continue
        f = split(ln, '\t')
        f[3] == travel_func_name || continue
        area = String(f[2])
        isempty(ONLY) || area in ONLY || continue
        r = (area=area, w_str=String(f[4]), w=parse(Float64, f[4]), lam=parse(Float64, f[5]),
             sum_y=parse(Float64, f[6]), relax=parse(Float64, f[7]), lb=parse(Float64, f[8]),
             multi=parse(Float64, f[9]), n_open=parse(Int, f[10]))
        gap = r.lb > 0 ? 100 * (r.multi - r.lb) / r.lb : -Inf
        gap >= FULL_SWAP_MIN_GAP && r.lam >= FULL_SWAP_MIN_LAMBDA && push!(rows, r)
    end
    return rows
end

# The sweep's per-w folders whose w matches the row's (the log prints w to 5 significant
# digits; folder names carry the full Float64, e.g. w=0.05000000000000001), nearest first.
function matching_folders(base, w)
    isdir(base) || return String[]
    c = [(abs(parse(Float64, d[3:end]) - w) / w, d) for d in readdir(base)
         if startswith(d, "w=") && tryparse(Float64, d[3:end]) !== nothing]
    c = sort([x for x in c if x[1] <= 1e-4]; by=first)
    return [d for (_, d) in c]
end

function stranded(open_set, data)
    _, _, phi1 = client_nearest(open_set, data, big_cost())
    cells = 0; pop = 0.0
    for i in keys(data.locations)
        if phi1[i] == -1
            cells += 1; pop += data.client_pop[i]
        end
    end
    return cells, pop
end

# Mean travel time as solve_at_w! reports it: nearest open facility, stranded at the cutoff.
function mean_t_of(open_set, data)
    assigned_k, _ = assign_nearest(open_set, data)
    total = sum(data.wpop[rows[1]] for (_, rows) in data.locations)
    sp = sum((data.client_pop[i] for i in keys(data.locations) if !haskey(assigned_k, i)); init=0.0)
    mt = (sum((data.t_ij_col[k] * data.wpop[k] for (_, k) in assigned_k); init=0.0) +
          MAX_TRAVELTIME_MIN * sp) / total
    return mt, assigned_k
end

fmt(x) = x isa AbstractFloat ? (isfinite(x) ? string(round(x, sigdigits=10)) : "") : string(x)

function main()
    rows = read_rows()
    pln("polish_tail.jl ($travel_func_name): $(length(rows)) rows with gap ≥ $(FULL_SWAP_MIN_GAP) % and " *
        "λ ≥ $(FULL_SWAP_MIN_LAMBDA) €; caps $(FULL_SWAP_ROUNDS) swaps / $(FULL_SWAP_TIME) s per row" *
        (isempty(ONLY) ? "" : "; areas $(join(sort(collect(ONLY)), ' '))"))
    # keep the other areas' lines when restricted to a subset
    keep = String[]
    if !isempty(ONLY) && isfile(OUT_CSV)
        keep = [ln for ln in Iterators.drop(eachline(OUT_CSV), 1) if !(split(ln, ',')[1] in ONLY)]
    end
    io = open(OUT_CSV, "w")
    println(io, HEADER)
    foreach(ln -> println(io, ln), keep)
    flush(io)
    BIG = big_cost()
    areas = unique(r.area for r in rows)
    for area in areas
        ar = [r for r in rows if r.area == area]
        pln("\n== $area: $(length(ar)) rows")
        data = load_from(NEW_PATH, area)
        base = joinpath(NEW_PATH, area, "lambda_sweep", travel_func_name)
        for r in ar
            status = "no_arrow"; folder = ""; recomputed = NaN
            open_set = Set{Int}()
            for d in matching_folders(base, r.w)
                tbl = Arrow.Table(joinpath(base, d, "assignment.arrow"))
                s = Set(Int(id) for (id, o) in zip(tbl.id, tbl.open) if o == 1)
                t, _ = travel_of(s, data, BIG)
                folder = d; recomputed = t
                if length(s) == r.n_open && abs(t - r.multi) <= max(1.0, 1e-6 * r.multi)
                    status = "match"; open_set = s
                    break
                end
                status = "stale"
            end
            line = [r.area, travel_func_name, r.w_str, fmt(r.lam), r.n_open, fmt(r.sum_y), fmt(r.relax),
                    fmt(r.lb), fmt(r.multi), fmt(recomputed), folder]
            gap0 = 100 * (r.multi - r.lb) / r.lb
            if status != "match"
                pln("  w=$(r.w_str): $status ($(isempty(folder) ? "no folder" : "$folder: n/travel do not match the log, recomputed $(round(recomputed, digits=0)) vs $(round(r.multi, digits=0))"))")
                append!(line, [status, "", "", "", fmt(gap0), "", "", "", "", "", ""])
            else
                c0, p0 = stranded(open_set, data)
                t_pol = @elapsed (pol, nsw) = full_swap(open_set, data)
                tp, _ = travel_of(pol, data, BIG)
                better = tp < r.multi - 1e-6 * r.multi
                status = better ? "polished" : "unchanged"
                fin = better ? pol : open_set
                tfin = better ? tp : r.multi
                c1, p1 = stranded(fin, data)
                mt, assigned_k = mean_t_of(fin, data)
                gap1 = 100 * (tfin - r.lb) / r.lb
                if better && WRITE_ARROWS
                    dir = joinpath(base, "polished", folder); mkpath(dir)
                    write_assignment_arrow(dir, data.facilities, fin)
                    write_traveltime_arrow(dir, data.t_ij_col, assigned_k)
                end
                pln("  w=$(r.w_str) n=$(r.n_open): $status, $nsw swaps in $(round(t_pol, digits=1)) s, gap ",
                    "$(round(gap0, digits=2)) % -> $(round(gap1, digits=2)) %, stranded cells $c0 -> $c1")
                append!(line, [status, nsw, fmt(t_pol), fmt(tfin), fmt(gap0), fmt(gap1), c0, c1,
                               fmt(p0), fmt(p1), fmt(mt)])
            end
            println(io, join(string.(line), ','))
            flush(io)
        end
    end
    close(io)
    pln("\nwrote $OUT_CSV")
end

main()
