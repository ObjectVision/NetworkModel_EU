import os, re, glob

FUNC = os.environ.get("FUNC", "LINEAR")
logs = sorted(glob.glob(f"logs/sweep_*_{FUNC}.log"))

def parse(path):
    txt = open(path, encoding="utf-8", errors="replace").read().splitlines()
    base = {}
    for ln in txt:
        m = re.search(r"facilities used \(cells\):\s+(\d+)", ln); base.setdefault("cells", m.group(1)) if m else None
        m = re.search(r"total travel cost\(c\):\s+([\d.eE+]+)", ln); base.setdefault("cost", float(m.group(1))) if m else None
    rows, in_tbl, seen = [], False, False
    for ln in txt:
        if ln.startswith("Combined sweep"): in_tbl, seen = True, False; continue
        if in_tbl:
            if ln.startswith("w "): seen = True; continue
            if not seen: continue
            if ln.strip() == "" or ln.startswith("=") or "scenario" in ln: break
            f = ln.split()
            if len(f) < 12: continue
            try:
                rows.append(dict(w=float(f[0]), sum_x=float(f[2]), relax=float(f[3]),
                                 topp=float(f[4]), greedy=float(f[5]), multi=float(f[6]),
                                 n_open=int(f[7]), frac=int(f[10])))
            except ValueError: continue
    # S1/S2 w + stranded
    scen, cur = {}, None
    for ln in txt:
        if ln.startswith("S1 —"): cur = "S1"
        elif ln.startswith("S2 —"): cur = "S2"
        elif cur:
            m = re.search(r"w\s*=\s*([\d.]+)", ln)
            if m and cur not in scen: scen[cur] = {"w": float(m.group(1))}
            m = re.search(r"stranded\s*:\s*topp (\d+)\s+greedy (\d+)\s+multi (\d+)", ln)
            if m and cur in scen:
                scen[cur].update(st=(int(m.group(1)), int(m.group(2)), int(m.group(3)))); cur = None
    return base, rows, scen

def pct(a, b): return 100*(a-b)/b if b else 0.0

print(f"\n{'='*120}\n{FUNC} — multistart vs top-p vs greedy vs LP-relaxed  (travel; stranded clients priced at c(t_max))\n{'='*120}")
hdr = f"{'region':>12} {'pt':>3} {'w':>5} {'n_open':>6} {'frac':>5} | {'relax':>10} {'topp':>10} {'greedy':>10} {'multi':>10} | {'m/topp':>7} {'m/grdy':>7} {'m/relax':>8} | {'strand t/g/m':>14}"
print(hdr)
for p in logs:
    reg = re.search(r"sweep_(.+)_"+FUNC, p).group(1)
    base, rows, scen = parse(p)
    by_w = {r["w"]: r for r in rows}
    for pt in ("S1", "S2"):
        if pt not in scen: continue
        w = scen[pt]["w"]; r = by_w.get(w)
        if not r: continue
        st = scen[pt].get("st", (0,0,0))
        print(f"{reg:>12} {pt:>3} {w:>5g} {r['n_open']:>6} {r['frac']:>5} | "
              f"{r['relax']:>10.3g} {r['topp']:>10.3g} {r['greedy']:>10.3g} {r['multi']:>10.3g} | "
              f"{pct(r['multi'],r['topp']):>+6.1f}% {pct(r['multi'],r['greedy']):>+6.1f}% {pct(r['multi'],r['relax']):>+7.1f}% | "
              f"{st[0]:>4}/{st[1]:>4}/{st[2]:>4}")
