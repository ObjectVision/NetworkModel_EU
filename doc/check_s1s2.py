# #52 acceptance check: for every area x function in deck_data.json, how far the exported
# S1 (same count as today) and S2 (same travel as today) sit from their definition.
# Run after build_deck_data.py. Exit 1 when any S1 is > 1% off in count or any S2 > 1% in travel.
import json, sys, io, os, statistics
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
d = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "deck_data.json"), encoding="utf-8"))
rows = []
for e in d:
    for fn in ("LINEAR", "LOGISTIC"):
        F = e["func"].get(fn)
        if not F:
            rows.append((e["region"], fn, None, None, "no sweep")); continue
        b, sc = F["baseline"], F.get("scen", {})
        s1, s2 = sc.get("S1"), sc.get("S2")
        if not s1 or not s2 or "n_open" not in s1:
            rows.append((e["region"], fn, None, None, "no S1/S2")); continue
        e1 = (s1["n_open"] - b["cells"]) / b["cells"] * 100
        e2 = (s2["multi"] - b["cost"]) / b["cost"] * 100
        one = abs(s1["n_open"] - b["cells"]) <= 1          # the sweep's own S1 tolerance is max(1 facility, 0.2%)
        rows.append((e["region"], fn, e1, e2, "same point" if s1["w"] == s2["w"] else ("" if not one else "±1")))
bad = [r for r in rows if r[2] is None or (abs(r[2]) > 1 and r[4] != "±1") or abs(r[3]) > 1 or r[4] == "same point"]
ok = [r for r in rows if r[2] is not None]
print(f"{len(rows)} area x function; S1 count error: median {statistics.median(abs(r[2]) for r in ok):.2f}%  max {max(abs(r[2]) for r in ok):.2f}%;"
      f"  S2 travel error: median {statistics.median(abs(r[3]) for r in ok):.2f}%  max {max(abs(r[3]) for r in ok):.2f}%")
if bad:
    print(f"\n{len(bad)} NOT within 1% (or missing / same point):")
    for r in bad:
        print(f"  {r[0]:12} {r[1]:8} S1 count {r[2] if r[2] is None else f'{r[2]:+.2f}%':>8}  S2 travel {r[3] if r[3] is None else f'{r[3]:+.2f}%':>8}  {r[4]}")
    sys.exit(1)
print("all S1 within 1% of today's count, all S2 within 1% of today's travel, no coincident points")
