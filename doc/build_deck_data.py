# Parse logs/sweep_<region>_<FUNC>.log into doc/deck_data.json for the slide generator.
# Captures, per region x {LINEAR,LOGISTIC}: baseline (cells,cost,mean_t),
# the Combined-sweep Pareto rows, and the S1/S2 scenario summary.
import os, re, glob, json, io, sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FUNCS = ["LINEAR", "LOGISTIC"]
# display order matches the existing deck
ORDER = ["Netherlands",
         "Luxembourg", "Estonia", "Latvia", "Slovenia", "Lithuania", "Norway", "Denmark", "Austria", "Portugal", "Czechia", "Belgium",
         "FR1", "FRB", "FRC", "FRD", "FRE", "FRF", "FRG", "FRH",
         "FRI", "FRJ", "FRK", "FRL", "FRM", "ITC", "ITF", "ITG", "ITH", "ITI",
         "SE1", "SE2", "SE3"]
NICE = {
    "Netherlands": ("NETHERLANDS", "Netherlands"),
    "Luxembourg": ("LUXEMBOURG", "Luxembourg"),
    "Estonia": ("ESTONIA", "Estonia"),
    "Latvia": ("LATVIA", "Latvia"),
    "Slovenia": ("SLOVENIA", "Slovenia"),
    "Lithuania": ("LITHUANIA", "Lithuania"),
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
}

FLT = r"([-+]?[\d.]+(?:[eE][-+]?\d+)?)"


def num(s):
    return float(s)


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
                rows.append(dict(w=num(f[0]), sum_x=num(f[2]), relax=num(f[3]),
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
            m = re.search(r"sum_x\s*:\s*" + FLT, ln)
            if m and "sum_x" not in d:
                d["sum_x"] = num(m.group(1))
            m = re.search(r"n_open\s*:\s*(\d+)\s+frac_x:\s*(\d+)", ln)
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
        if "sum_x" not in d or not rows:
            continue
        r = min(rows, key=lambda r: abs(r["sum_x"] - d["sum_x"]))
        d["w"] = r["w"]
        for key in ("relax", "topp", "greedy"):
            d.setdefault(key, r[key])
        d.setdefault("multi", r["multi"])
    return base, rows, scen


def main():
    out = []
    for reg in ORDER:
        entry = {"region": reg, "title": NICE.get(reg, (reg, reg))[0],
                 "name": NICE.get(reg, (reg, reg))[1], "func": {}}
        ok = False
        for fn in FUNCS:
            p = os.path.join(ROOT, "logs", f"sweep_{reg}_{fn}.log")
            if not os.path.exists(p):
                continue
            base, rows, scen = parse(p)
            entry["func"][fn] = {"baseline": base, "rows": rows, "scen": scen}
            ok = True
        if ok:
            out.append(entry)
    dest = os.path.join(ROOT, "doc", "deck_data.json")
    json.dump(out, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"wrote {dest}: {len(out)} regions")
    for e in out:
        fs = ",".join(e["func"].keys())
        rc = {f: len(e["func"][f]["rows"]) for f in e["func"]}
        sc = {f: list(e["func"][f]["scen"].keys()) for f in e["func"]}
        print(f"  {e['region']:>12} [{fs}] rows={rc} scen={sc}")


if __name__ == "__main__":
    main()
