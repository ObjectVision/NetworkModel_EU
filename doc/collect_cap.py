#!/usr/bin/env python3
# Collect the cap-scenario result rows from logs/cap_<country>_S{1,2}_<rung>.log
# (written by run_cap_scenarios.bat) into one CSV for the deck's capSlide().
#   python collect_cap.py [Netherlands] [../logs] [cap_results_Netherlands.csv]
import sys, os, re

country = sys.argv[1] if len(sys.argv) > 1 else "Netherlands"
here    = os.path.dirname(os.path.abspath(__file__))
logdir  = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "..", "logs")
out     = sys.argv[3] if len(sys.argv) > 3 else os.path.join(here, f"cap_results_{country}.csv")

cols = ["scen", "rung", "min_cap", "max_cap", "n_pharm", "n_cells", "base", "sum_y",
        "travel", "base_trav", "dtravel_pct", "mean_t", "strand_pct", "urban_fx",
        "below_min", "load_p50", "load_p90", "load_max"]
order = ["S1_A", "S1_B", "S1_C", "S2_A", "S2_B"]

rows = []
for tag in order:
    f = os.path.join(logdir, f"cap_{country}_{tag}.log")
    if not os.path.exists(f):
        continue
    for line in open(f, encoding="utf-8", errors="replace"):
        if re.match(r"^S[12]\s", line):
            parts = line.split()
            if len(parts) >= 18:
                rows.append(parts[:18])

with open(out, "w", encoding="utf-8") as fo:
    fo.write(",".join(cols) + "\n")
    for r in rows:
        fo.write(",".join(r) + "\n")
print(f"wrote {out}: {len(rows)} rows")
