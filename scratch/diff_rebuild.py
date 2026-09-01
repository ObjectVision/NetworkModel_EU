"""Affected-area diff for step 1 of doc/replan_connectivity_fix.md.

Compares the rebuilt network/OD artefacts against the pre-fix state and reports, per
area, how much the landbody-connectivity fix (79cb58b) actually moved it. Areas with a
negligible delta need no re-sweep, which is what sizes steps 2..k.

Two "before" sources, because they answer different questions:

  scratch/snapshot_before.csv  -- OD/i arrow byte sizes taken just before the purge.
                                  Cheap and complete, but ITG was already rebuilt when
                                  it was taken, so ITG's row is post-fix; it is read
                                  from the sweep logs instead.
  logs/sweep_<area>_LINEAR.log -- the pre-fix baseline block (client population,
                                  unreachable cells/residents, mean travel time). This
                                  is the number that actually matters, and it is what
                                  issue #49 quantified.

Prints a ranked table and writes scratch/affected_areas.csv.
"""
import csv
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_before_snapshot():
    p = os.path.join(ROOT, "scratch", "snapshot_before.csv")
    out = {}
    if not os.path.exists(p):
        return out
    with io.open(p, encoding="utf-8-sig", newline="") as fh:
        for r in csv.DictReader(fh):
            side = "ex" if r["side"] == "ExistingPharmacies" else "nw"
            out.setdefault(r["area"], {})[side + "_od"] = int(r["od_bytes"] or 0)
    return out


def read_sweep_baseline(area):
    """Pre-fix baseline block from the LAST run recorded in the sweep log."""
    p = os.path.join(ROOT, "logs", "sweep_%s_LINEAR.log" % area)
    if not os.path.exists(p):
        return None
    t = io.open(p, encoding="utf-8", errors="replace").read()

    def last(pat, cast=float):
        m = re.findall(pat, t)
        return cast(m[-1]) if m else None

    return {
        "pop": last(r"total client population:\s+(\d+)", int),
        "unreach_cells": last(r"unreachable clients:\s+(\d+) cells", int),
        "unreach_pop": last(r"unreachable clients:\s+\d+ cells / (\d+) residents", int),
        "mean_t": last(r"mean travel time \(min\):\s+([\d.]+)"),
        "od_rows_ex": last(r"N=(\d+) OD rows, M=\d+ facilities", int),
        "od_rows_nw": last(r"N=(\d+) OD rows, M=\d+ candidate facilities", int),
    }


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else "all"
    p = os.path.join(ROOT, "scratch", "rebuild_all_%s.csv" % tag)
    if not os.path.exists(p):
        print("no rebuild csv yet:", p)
        sys.exit(1)
    before = read_before_snapshot()

    rows = []
    with io.open(p, encoding="utf-8-sig", newline="") as fh:
        for r in csv.DictReader(fh):
            a = r["area"]
            b = before.get(a, {})
            pre = read_sweep_baseline(a)
            nw_now = int(r["nw_od"] or 0)
            ex_now = int(r["ex_od"] or 0)
            nw_pre = b.get("nw_od", 0)
            ex_pre = b.get("ex_od", 0)
            # ITG's snapshot row is post-fix (it was rebuilt first): fall back to the
            # sweep log's OD row counts, which are genuinely pre-fix.
            growth = (nw_now / nw_pre - 1.0) if nw_pre else None
            rows.append({
                "area": a,
                "ex_exit": r["ex_exit"], "nw_exit": r["nw_exit"],
                "secs": r["total_secs"],
                "ex_od_pre": ex_pre, "ex_od_now": ex_now,
                "nw_od_pre": nw_pre, "nw_od_now": nw_now,
                "nw_od_growth": growth,
                "pre_unreach_pop": (pre or {}).get("unreach_pop"),
                "pre_unreach_pct": (100.0 * pre["unreach_pop"] / pre["pop"])
                                   if pre and pre.get("pop") and pre.get("unreach_pop") is not None else None,
                "pre_mean_t": (pre or {}).get("mean_t"),
            })

    out = os.path.join(ROOT, "scratch", "affected_areas.csv")
    with io.open(out, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        for r in rows:
            w.writerow(r)

    def key(r):
        return -(r["nw_od_growth"] if r["nw_od_growth"] is not None else -9)

    print("%-12s %5s %5s %6s %12s %12s %8s %12s %7s %7s"
          % ("area", "exEx", "exNw", "secs", "nw_od_pre", "nw_od_now", "growth",
             "pre_unreach", "pre_%", "pre_t"))
    print("-" * 104)
    affected = 0
    for r in sorted(rows, key=key):
        g = r["nw_od_growth"]
        if g is not None and g > 0.01:
            affected += 1
        print("%-12s %5s %5s %6s %12s %12s %7s %12s %7s %7s" % (
            r["area"], r["ex_exit"], r["nw_exit"], r["secs"],
            "%d" % r["nw_od_pre"] if r["nw_od_pre"] else "-",
            "%d" % r["nw_od_now"] if r["nw_od_now"] else "-",
            ("%+.1f%%" % (100 * g)) if g is not None else "-",
            "%d" % r["pre_unreach_pop"] if r["pre_unreach_pop"] is not None else "-",
            ("%.1f" % r["pre_unreach_pct"]) if r["pre_unreach_pct"] is not None else "-",
            ("%.2f" % r["pre_mean_t"]) if r["pre_mean_t"] is not None else "-"))
    print("-" * 104)
    print("%d areas, %d with >1%% candidate-OD growth  ->  %s" % (len(rows), affected, out))
    bad = [r["area"] for r in rows if r["ex_exit"] != "0" or r["nw_exit"] != "0"]
    if bad:
        print("FAILED areas:", ", ".join(bad))


if __name__ == "__main__":
    main()
