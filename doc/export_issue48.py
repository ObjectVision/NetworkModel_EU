# Issue #48 export -- frontier-projection data for Chris Jacobs.
#
# Produces two deliverables from doc/deck_data.json (no new solves), reusing the
# EXACT functions that produced deck pages 62/63 and the aggregate slide:
#
#  1. issue48_crossings.csv     -- per area x cost function (+ AGGREGATE): the
#     rectangle B/S1/S2/corner, its area (raw + relative), the point where the
#     Pareto frontier crosses the B->corner diagonal, and lambda at that crossing.
#     This is the data behind deck p62/p63.
#
#  2. issue48_sweep_results.csv -- per area x cost function x lambda: the found
#     travel cost and facility cost at every swept lambda (LINEAR and LOGISTIC),
#     including the aggregate curve.
#
# Facility cost is reported explicitly as lambda * n_open, with lambda = w *
# FACILITY_MIN_COSTS (EUR), so travel and facility costs are directly comparable
# and sum to the swept objective.
import os, sys, json, csv

# stdout is re-wrapped as utf-8 by frontier_metrics on import; do not wrap twice
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from frontier_metrics import metrics_for, pareto_frontier, FACILITY_MIN_COSTS, FUNCS
from build_charts import _interp_at

OUT = os.path.join(ROOT, "doc")


def build_aggregate(data):
    """The aggregate frontier, identical rule to build_charts.render_aggregate:
    Poland-country excluded when its NUTS-1 areas are present (disjointness);
    per COMMON w the regional optima are summed (exact by separability)."""
    part = [e for e in data if not (e["region"] == "Poland"
                                    and any(x["region"].startswith("PL") for x in data))]
    agg = {}
    for fn in FUNCS:
        regs = [e for e in part if fn in e["func"] and e["func"][fn].get("rows")]
        if len(regs) < 2:
            continue
        per = {e["region"]: sorted([r for r in e["func"][fn]["rows"] if r["w"] > 0],
                                   key=lambda r: r["w"]) for e in regs}
        w_lo = max(rows[0]["w"] for rows in per.values())
        w_hi = min(rows[-1]["w"] for rows in per.values())
        union = sorted(set(round(r["w"], 12) for rows in per.values()
                           for r in rows if w_lo <= r["w"] <= w_hi))
        rows = []
        for w in union:
            a = dict(w=w, sum_y=0.0, relax=0.0, multi=0.0, n_open=0.0, frac=0.0, mean_t=0.0)
            ok = True
            for rr in per.values():
                v = _interp_at(rr, w)
                if v is None:
                    ok = False
                    break
                for k in ("sum_y", "relax", "multi", "n_open", "frac"):
                    a[k] += v[k]
            if ok:
                a["n_open"] = round(a["n_open"])
                a["frac"] = round(a["frac"])
                rows.append(a)
        base = dict(cells=sum(e["func"][fn]["baseline"]["cells"] for e in regs),
                    cost=sum(e["func"][fn]["baseline"]["cost"] for e in regs), mean_t=0.0)
        agg[fn] = {"baseline": base, "rows": rows, "n_regions": len(regs)}
    return agg


def main():
    data = json.load(open(os.path.join(ROOT, "doc", "deck_data.json"), encoding="utf-8"))
    agg = build_aggregate(data)

    entries = [(e["region"], e["func"]) for e in data]
    entries.append(("AGGREGATE", agg))

    # ---- 1. crossings (per area + aggregate) --------------------------------
    cx_path = os.path.join(OUT, "issue48_crossings.csv")
    n_cx = 0
    with open(cx_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["region", "func",
                    "B_facilities", "B_travelcost",
                    "S1_travelcost", "S2_facilities",
                    "corner_facilities", "corner_travelcost",
                    "rect_area_raw", "rect_rel",
                    "cross_facilities", "cross_travelcost",
                    "lambda_cross_eur", "w_cross",
                    "cross_facilitycost_eur", "cross_totalcost_eur",
                    "s1_bracketed", "s2_bracketed", "n_frontier_pts"])
        for reg, fd in entries:
            for fn in FUNCS:
                f = fd.get(fn)
                if not f:
                    continue
                m = metrics_for(f["baseline"], f["rows"])
                if m is None:
                    continue
                lam = m["lambda_cross"]
                cx, cy = (m["cross"] if m["cross"] else (None, None))
                fac = lam * cx if (lam is not None and cx is not None) else None
                w.writerow([reg, fn,
                            m["B"][0], "%.0f" % m["B"][1],
                            "%.0f" % m["S1"][1], "%.2f" % m["S2"][0],
                            "%.2f" % m["corner"][0], "%.0f" % m["corner"][1],
                            "%.6e" % m["rect_area"],
                            "%.6f" % m["rect_rel"] if m["rect_rel"] is not None else "",
                            "%.2f" % cx if cx is not None else "",
                            "%.0f" % cy if cy is not None else "",
                            "%.2f" % lam if lam is not None else "",
                            "%.6f" % (lam / FACILITY_MIN_COSTS) if lam is not None else "",
                            "%.0f" % fac if fac is not None else "",
                            "%.0f" % (fac + cy) if (fac is not None and cy is not None) else "",
                            m["s1_bracketed"], m["s2_bracketed"], m["n_frontier_pts"]])
                n_cx += 1

    # ---- 2. per-lambda sweep results (per area + aggregate) ------------------
    sw_path = os.path.join(OUT, "issue48_sweep_results.csv")
    n_sw = 0
    with open(sw_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["region", "func", "w", "lambda_eur",
                    "n_open", "sum_y_lp",
                    "travelcost_multistart", "travelcost_lp_relaxation",
                    "facilitycost_eur", "totalcost_eur",
                    "mean_traveltime_min", "frac_open",
                    "baseline_facilities", "baseline_travelcost", "on_pareto_frontier"])
        for reg, fd in entries:
            for fn in FUNCS:
                f = fd.get(fn)
                if not f or not f.get("rows"):
                    continue
                base = f["baseline"]
                env = pareto_frontier(f["rows"])
                on_env = set((round(p[0]), round(p[1], 6)) for p in env)
                for r in sorted(f["rows"], key=lambda r: r["w"]):
                    lam = r["w"] * FACILITY_MIN_COSTS
                    n_open = r.get("n_open")
                    multi = r.get("multi")
                    fac = lam * n_open if n_open is not None else None
                    is_env = (n_open is not None and multi is not None
                              and (round(n_open), round(multi, 6)) in on_env)
                    w.writerow([reg, fn, "%.6g" % r["w"], "%.2f" % lam,
                                n_open,
                                "%.3f" % r["sum_y"] if r.get("sum_y") is not None else "",
                                "%.0f" % multi if multi is not None else "",
                                "%.0f" % r["relax"] if r.get("relax") is not None else "",
                                "%.0f" % fac if fac is not None else "",
                                "%.0f" % (fac + multi) if (fac is not None and multi is not None) else "",
                                # the aggregate has no meaningful mean travel time
                                # (build_charts stores a 0.0 placeholder): blank it rather
                                # than emit a misleading zero
                                "" if reg == "AGGREGATE" else r.get("mean_t", ""),
                                r.get("frac", ""),
                                base.get("cells", ""),
                                "%.0f" % base["cost"] if base.get("cost") else "",
                                is_env])
                    n_sw += 1

    print("wrote %s   (%d rows: areas x cost function, incl. AGGREGATE)" % (cx_path, n_cx))
    print("wrote %s   (%d rows)" % (sw_path, n_sw))
    for fn in FUNCS:
        if fn in agg:
            print("  aggregate %s: %d disjoint areas, %d common-w points"
                  % (fn, agg[fn]["n_regions"], len(agg[fn]["rows"])))


if __name__ == "__main__":
    main()
