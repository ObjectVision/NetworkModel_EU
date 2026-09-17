# Parse logs/sweep_<region>_<FUNC>.log into doc/deck_data.json for the slide generator.
# Captures, per region x {LINEAR,LOGISTIC}: baseline (cells,cost,mean_t),
# the Combined-sweep Pareto rows, and the S1/S2 scenario summary.
import os, re, glob, json, io, sys, math

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FUNCS = ["LINEAR", "LOGISTIC"]
# display order matches the existing deck
ORDER = ["Netherlands",
         "Luxembourg", "Estonia", "Latvia", "Slovenia", "Lithuania", "Ireland", "Norway", "Denmark", "Austria", "Portugal", "Czechia", "Belgium", "Poland_sweep", "Hungary", "Finland",
         "France", "Italy", "Sweden", "Poland",
         "FR1", "FRB", "FRC", "FRD", "FRE", "FRF", "FRG", "FRH",
         "FRI", "FRJ", "FRK", "FRL", "FRM", "ITC", "ITF", "ITG", "ITH", "ITI",
         "SE1", "SE2", "SE3",
         "PL2", "PL4", "PL5", "PL6", "PL7", "PL8", "PL9"]
NICE = {
    "Netherlands": ("NETHERLANDS", "Netherlands"),
    "Luxembourg": ("LUXEMBOURG", "Luxembourg"),
    "Estonia": ("ESTONIA", "Estonia"),
    "Latvia": ("LATVIA", "Latvia"),
    "Slovenia": ("SLOVENIA", "Slovenia"),
    "Lithuania": ("LITHUANIA", "Lithuania"),
    "Ireland": ("IRELAND", "Ireland"),
    "Norway": ("NORWAY", "Norway"),
    "Denmark": ("DENMARK", "Denmark"),
    "Austria": ("AUSTRIA", "Austria"),
    "Portugal": ("PORTUGAL", "Portugal"),
    "Czechia": ("CZECHIA", "Czechia"),
    "Belgium": ("BELGIUM", "Belgium"),
    "FR1": ("FRANCE · FR1", "Île-de-France"),
    "FRB": ("FRANCE · FRB", "Centre-Val de Loire"),
    "FRC": ("FRANCE · FRC", "Bourgogne-Franche-Comté"),
    "FRD": ("FRANCE · FRD", "Normandie"),
    "FRE": ("FRANCE · FRE", "Hauts-de-France"),
    "FRF": ("FRANCE · FRF", "Grand Est"),
    "FRG": ("FRANCE · FRG", "Pays de la Loire"),
    "FRH": ("FRANCE · FRH", "Bretagne"),
    "FRI": ("FRANCE · FRI", "Nouvelle-Aquitaine"),
    "FRJ": ("FRANCE · FRJ", "Occitanie"),
    "FRK": ("FRANCE · FRK", "Auvergne-Rhône-Alpes"),
    "FRL": ("FRANCE · FRL", "Provence-Alpes-Côte d'Azur"),
    "FRM": ("FRANCE · FRM", "Corse"),
    "ITC": ("ITALY · ITC", "Nord-Ovest"),
    "ITF": ("ITALY · ITF", "Sud"),
    "ITG": ("ITALY · ITG", "Isole"),
    "ITH": ("ITALY · ITH", "Nord-Est"),
    "ITI": ("ITALY · ITI", "Centro"),
    "SE1": ("SWEDEN · SE1", "Östra Sverige"),
    "SE2": ("SWEDEN · SE2", "Södra Sverige"),
    "SE3": ("SWEDEN · SE3", "Norra Sverige"),
    "Poland_sweep": ("POLAND · DIRECT COUNTRY SWEEP", "Poland (country-level sweep)"),
    "Poland": ("POLAND · 7 NUTS-1 AGGREGATED", "Poland"),
    "France": ("FRANCE · 13 NUTS-1 AGGREGATED", "France"),
    "Italy": ("ITALY · 5 NUTS-1 AGGREGATED", "Italy"),
    "Sweden": ("SWEDEN · 3 NUTS-1 AGGREGATED", "Sweden"),
    "Hungary": ("HUNGARY", "Hungary"),
    "Finland": ("FINLAND", "Finland"),
    "PL2": ("POLAND · PL2", "Południowy"),
    "PL4": ("POLAND · PL4", "Północno-Zachodni"),
    "PL5": ("POLAND · PL5", "Południowo-Zachodni"),
    "PL6": ("POLAND · PL6", "Północny"),
    "PL7": ("POLAND · PL7", "Centralny"),
    "PL8": ("POLAND · PL8", "Wschodni"),
    "PL9": ("POLAND · PL9", "Mazowiecki"),
}

FLT = r"([-+]?[\d.]+(?:[eE][-+]?\d+)?)"

# Countries swept as NUTS-1 regions get a country entry that is the SUM of their regions
# at common λ (exact by separability, the rule of the deck's aggregate slide): on the
# w's every region solved, each region log-interpolated between its own grid points. The
# entry carries "aggregated_from" and appears in the per-country tables and the
# cross-lambda table; the region slides, the rankings and the 43-area aggregate keep the
# NUTS-1 regions. Poland's direct country sweep stays as "Poland_sweep" (its slide, and the
# #52 exception); "Poland" is its aggregate, like the three countries never swept whole.
AGGREGATES = {
    "France": ["FR1", "FRB", "FRC", "FRD", "FRE", "FRF", "FRG", "FRH", "FRI", "FRJ", "FRK", "FRL", "FRM"],
    "Italy": ["ITC", "ITF", "ITG", "ITH", "ITI"],
    "Sweden": ["SE1", "SE2", "SE3"],
    "Poland": ["PL2", "PL4", "PL5", "PL6", "PL7", "PL8", "PL9"],
}


def _interp_at(rows, w):
    """Log-w interpolate a region's row values at w (exact at its own grid points)."""
    lo = hi = None
    for r in rows:
        if r["w"] <= w and (lo is None or r["w"] > lo["w"]):
            lo = r
        if r["w"] >= w and (hi is None or r["w"] < hi["w"]):
            hi = r
    if lo is None or hi is None:
        return None
    if lo["w"] == hi["w"]:
        return lo
    f = (math.log(w) - math.log(lo["w"])) / (math.log(hi["w"]) - math.log(lo["w"]))
    return {k: lo[k] + f * (hi[k] - lo[k]) for k in ("sum_y", "relax", "multi", "n_open", "frac", "mean_t")}


def _cross(rows, key, target, descending):
    """The point on the row polyline where `key` equals `target`: linear in key for the
    values, log-linear in w -- the rule of the deck's S1/S2 tables. None when unbracketed."""
    rs = sorted(rows, key=lambda r: r["w"])
    for a, b in zip(rs, rs[1:]):
        xa, xb = a[key], b[key]
        if xa == xb or not (min(xa, xb) <= target <= max(xa, xb)):
            continue
        f = (target - xa) / (xb - xa)
        pt = {k: a[k] + f * (b[k] - a[k]) for k in ("sum_y", "relax", "multi", "n_open", "frac", "mean_t")}
        pt["w"] = math.exp(math.log(a["w"]) + f * (math.log(b["w"]) - math.log(a["w"])))
        pt["n_open"] = round(pt["n_open"]); pt["frac"] = round(pt["frac"])
        return pt
    return None


def aggregate_group(parts, fn):
    """The {baseline, rows, scen} of the sum of `parts` (region entries) for function fn."""
    regs = [e for e in parts if fn in e["func"] and e["func"][fn].get("rows")]
    if len(regs) != len(parts):
        return None
    pop = {e["region"]: e["func"]["LINEAR"]["baseline"]["cost"] / e["func"]["LINEAR"]["baseline"]["mean_t"] for e in regs}
    tot = sum(pop.values())
    per = {e["region"]: sorted([r for r in e["func"][fn]["rows"] if r["w"] > 0], key=lambda r: r["w"]) for e in regs}
    w_lo = max(rows[0]["w"] for rows in per.values())
    w_hi = min(rows[-1]["w"] for rows in per.values())
    union = sorted(set(round(r["w"], 12) for rows in per.values() for r in rows if w_lo <= r["w"] <= w_hi))
    rows = []
    for w in union:
        agg = dict(w=w, sum_y=0.0, relax=0.0, multi=0.0, n_open=0.0, frac=0.0, mean_t=0.0)
        vs = {reg: _interp_at(rr, w) for reg, rr in per.items()}
        if any(v is None for v in vs.values()):
            continue
        for reg, v in vs.items():
            for k in ("sum_y", "relax", "multi", "n_open", "frac"):
                agg[k] += v[k]
            agg["mean_t"] += v["mean_t"] * pop[reg] / tot
        agg["n_open"] = round(agg["n_open"]); agg["frac"] = round(agg["frac"])
        rows.append(agg)
    base = dict(cells=sum(e["func"][fn]["baseline"]["cells"] for e in regs),
                cost=sum(e["func"][fn]["baseline"]["cost"] for e in regs),
                mean_t=sum(e["func"][fn]["baseline"]["mean_t"] * pop[e["region"]] for e in regs) / tot)
    scen = {}
    for lbl, key, target in (("S1", "sum_y", base["cells"]), ("S2", "multi", base["cost"])):
        pt = _cross(rows, key, target, key == "sum_y")
        if pt:
            pt["interpolated"] = True
            pt["st"] = [0, 0, sum((e["func"][fn].get("scen", {}).get(lbl, {}).get("st") or [0, 0, 0])[2] for e in regs)]
            scen[lbl] = pt
    return {"baseline": base, "rows": rows, "scen": scen}


def add_aggregates(out):
    by = {e["region"]: e for e in out}
    for name, parts in AGGREGATES.items():
        missing = [r for r in parts if r not in by]
        if missing:
            print(f"  {name}: not aggregated, missing {missing}")
            continue
        entry = {"region": name, "title": NICE[name][0], "name": NICE[name][1], "aggregated_from": parts, "func": {}}
        for fn in FUNCS:
            fd = aggregate_group([by[r] for r in parts], fn)
            if fd:
                entry["func"][fn] = fd
        if entry["func"]:
            out.append(entry)


def num(s):
    return float(s)


# doc/recompute_mean_t.jl: the mean_t of every rounded row and of S1/S2, recomputed from
# the per-w traveltime arrows with the stranded clients at the 120-min cutoff (rows logged
# before 15 Sep 2026 counted them at 0 min; the baseline never did). Keyed by
# (region, func, label) with label "S1"/"S2" or the row's w rounded as the log prints it.
MEAN_T = {}
mp = os.path.join(ROOT, "doc", "mean_t_stranded.csv")
if os.path.exists(mp):
    for ln in open(mp, encoding="utf-8").read().splitlines()[1:]:
        area, fn, label, w, _, m, _, _ = ln.split(",")
        MEAN_T[(area, fn, label if label != "row" else round(float(w), 9))] = float(m)


def apply_mean_t(reg, fn, rows, scen):
    for r in rows:
        k = (reg, fn, round(r["w"], 9))
        if k in MEAN_T:
            r["mean_t"] = MEAN_T[k]
    for lbl, d in scen.items():
        if (reg, fn, lbl) in MEAN_T:
            d["mean_t"] = MEAN_T[(reg, fn, lbl)]


def parse(path):
    t = open(path, encoding="utf-8", errors="replace").read().splitlines()
    base = {}
    for ln in t:
        m = re.search(r"facilities used \(cells\):\s+(\d+)", ln)
        if m and "cells" not in base:
            base["cells"] = int(m.group(1))
        m = re.search(r"total travel cost\(c\):\s+" + FLT, ln)
        if m and "cost" not in base:
            base["cost"] = num(m.group(1))
        m = re.search(r"mean travel time \(min\):\s+" + FLT, ln)
        if m and "mean_t" not in base:
            base["mean_t"] = num(m.group(1))

    # Combined sweep table
    rows, in_tbl, seen = [], False, False
    for ln in t:
        if ln.startswith("Combined sweep"):
            in_tbl, seen = True, False
            continue
        if in_tbl:
            if ln.startswith("w "):
                seen = True
                continue
            if not seen:
                continue
            if ln.strip() == "" or ln.startswith("="):
                break
            f = ln.split()
            if len(f) < 12:
                continue
            try:
                rows.append(dict(w=num(f[0]), sum_y=num(f[2]), relax=num(f[3]),
                                 topp=num(f[4]), greedy=num(f[5]), multi=num(f[6]),
                                 n_open=int(f[7]), mean_t=num(f[9]), frac=int(f[10])))
            except ValueError:
                continue

    # S1/S2 scenario summary
    scen, cur = {}, None
    for ln in t:
        if ln.startswith("S1 —"):
            cur = "S1"
            scen[cur] = {}
        elif ln.startswith("S2 —"):
            cur = "S2"
            scen[cur] = {}
        elif cur:
            d = scen[cur]
            m = re.search(r"sum_[xy]\s*:\s*" + FLT, ln)
            if m and "sum_y" not in d:
                d["sum_y"] = num(m.group(1))
            m = re.search(r"n_open\s*:\s*(\d+)\s+frac_[xy]:\s*(\d+)", ln)
            if m:
                d["n_open"] = int(m.group(1)); d["frac"] = int(m.group(2))
            m = re.search(r"stranded\s*:\s*topp (\d+)\s+greedy (\d+)\s+multi (\d+)", ln)
            if m:
                d["st"] = [int(m.group(1)), int(m.group(2)), int(m.group(3))]
            m = re.search(r"travel_c \(multistart\):\s*" + FLT, ln)
            if m and "multi" not in d:
                d["multi"] = num(m.group(1))
            m = re.search(r"mean t \(min\)\s*:\s*" + FLT, ln)
            if m and "mean_t" not in d:
                d["mean_t"] = num(m.group(1))
                cur = None  # mean t is the last line of each block

    # attach the w used by S1/S2 by matching sum_x to nearest sweep row, and pull
    # the relax/topp/greedy at that w from the combined table
    for k, d in scen.items():
        if "sum_y" not in d or not rows:
            continue
        r = min(rows, key=lambda r: abs(r["sum_y"] - d["sum_y"]))
        d["w"] = r["w"]
        for key in ("relax", "topp", "greedy"):
            d.setdefault(key, r[key])
        d.setdefault("multi", r["multi"])
    return base, rows, scen


def main():
    out = []
    # Optional partial-deck filter: DECK_ONLY="Netherlands,ITG,..." restricts to a subset
    # (used for preview decks while a re-run is still finishing the other regions).
    only = os.environ.get("DECK_ONLY", "").strip()
    only_set = set(s.strip() for s in only.split(",") if s.strip()) if only else None
    for reg in ORDER:
        if only_set is not None and reg not in only_set:
            continue
        if reg in AGGREGATES:
            continue                       # built from its parts below
        entry = {"region": reg, "title": NICE.get(reg, (reg, reg))[0],
                 "name": NICE.get(reg, (reg, reg))[1], "func": {}}
        ok = False
        logreg = "Poland" if reg == "Poland_sweep" else reg     # the direct sweep's logs
        for fn in FUNCS:
            p = os.path.join(ROOT, "logs", f"sweep_{logreg}_{fn}.log")
            if not os.path.exists(p):
                continue
            base, rows, scen = parse(p)
            # A refine-only rerun (#52: SWEEP_STOP_AFTER_REFINE=1, written to
            # logs/refine_<reg>_<FN>.log) pins S1/S2 by bisection without re-sweeping the
            # frontier. When it is newer than the sweep it supplies the S1/S2 summary, and
            # its rows (the bracket walk + bisection points) join the frontier at w's the
            # sweep did not solve.
            rp = os.path.join(ROOT, "logs", f"refine_{logreg}_{fn}.log")
            if os.path.exists(rp) and os.path.getmtime(rp) > os.path.getmtime(p):
                rbase, rrows, rscen = parse(rp)
                if rscen.get("S1") and rscen.get("S2"):
                    have = {round(r["w"], 9) for r in rows}
                    rows = sorted(rows + [r for r in rrows if round(r["w"], 9) not in have],
                                  key=lambda r: r["w"])
                    scen = rscen
                    base = rbase or base
            # A tail-only run (SWEEP_TAIL_ONLY=1, logs/tail_<reg>_<FN>.log) continues the
            # sweep's grid beyond its tail stop with a longer time limit; its rows extend the
            # frontier at the w's the sweep did not reach. S1/S2 stay the sweep's (or refine's).
            tp = os.path.join(ROOT, "logs", f"tail_{logreg}_{fn}.log")
            if os.path.exists(tp) and os.path.getmtime(tp) > os.path.getmtime(p):
                _, trows, _ = parse(tp)
                have = {round(r["w"], 9) for r in rows}
                rows = sorted(rows + [r for r in trows if round(r["w"], 9) not in have],
                              key=lambda r: r["w"])
            apply_mean_t(logreg, fn, rows, scen)
            entry["func"][fn] = {"baseline": base, "rows": rows, "scen": scen}
            ok = True
        if ok:
            out.append(entry)
    if only_set is None:
        add_aggregates(out)
    dest = os.path.join(ROOT, "doc", "deck_data.json")
    json.dump(out, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"wrote {dest}: {len(out)} regions" +
          (f"; mean_t from mean_t_stranded.csv ({len(MEAN_T)} entries)" if MEAN_T else
           "; mean_t as logged (no doc/mean_t_stranded.csv)"))
    for e in out:
        fs = ",".join(e["func"].keys())
        rc = {f: len(e["func"][f]["rows"]) for f in e["func"]}
        sc = {f: list(e["func"][f]["scen"].keys()) for f in e["func"]}
        agg = f" = sum of {len(e['aggregated_from'])} NUTS-1" if e.get("aggregated_from") else ""
        print(f"  {e['region']:>12} [{fs}] rows={rc} scen={sc}{agg}")


if __name__ == "__main__":
    main()
