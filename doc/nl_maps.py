# The Netherlands maps figure of the deck: travel time to the nearest open pharmacy per
# 1-km client cell, baseline | S1 | S2, in the classes of Classifications.dms
# (ClientTravelTimeK: 0-2, 2-4, 4-6, 6-8, 8-10, 10-20, 20-30, 30-60, > 60 min), with the
# cell count per class beside each map. Input: doc/charts/maps_<AREA>_<FUNC>.csv from
# nl_maps.jl; output: doc/charts/maps_<AREA>_<FUNC>.png (build_deck.mjs places it on the
# maps slide after the area's results slide).
#   PYTHONIOENCODING=utf-8 python nl_maps.py [AREA=Netherlands] [FUNC=LINEAR]
import csv, json, os, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap, BoundaryNorm
from matplotlib.patches import Patch

HERE = os.path.dirname(os.path.abspath(__file__))
area = sys.argv[1] if len(sys.argv) > 1 else "Netherlands"
func = sys.argv[2] if len(sys.argv) > 2 else "LINEAR"

BREAKS = [0, 2, 4, 6, 8, 10, 20, 30, 60]                     # Classifications.dms ClientTravelTimeK
LABELS = [f"{a}–{b} min" for a, b in zip(BREAKS, BREAKS[1:])] + ["> 60 min"]
# one hue, light -> dark (the deck's sequential blue ramp, steps 100..700); stranded = ink
RAMP = ["#cde2fb", "#b7d3f6", "#9ec5f4", "#6da7ec", "#5598e7", "#2a78d6", "#1c5cab", "#104281", "#0d366b"]
INK, MUTED, NAVY = "#12233A", "#5B6B7B", "#1C3D5A"

rows = list(csv.DictReader(open(os.path.join(HERE, "charts", f"maps_{area}_{func}.csv"), encoding="utf-8")))
x = np.array([float(r["x"]) for r in rows]); y = np.array([float(r["y"]) for r in rows])
pop = np.array([float(r["pop"]) for r in rows])
CELL = 1000.0
ix = np.round((x - x.min()) / CELL).astype(int); iy = np.round((y.max() - y) / CELL).astype(int)
H, W = iy.max() + 1, ix.max() + 1

# the pinned scenarios' w and open counts, for the panel titles
scen = {}
try:
    dd = json.load(open(os.path.join(HERE, "deck_data.json"), encoding="utf-8"))
    e = next(e for e in dd if e["region"] == area)["func"][func]
    scen = {k: (v["w"], v["n_open"]) for k, v in e["scen"].items()}
    base_cells = e["baseline"]["cells"]
except (StopIteration, KeyError, FileNotFoundError):
    base_cells = None

panels = [("t_base", "Baseline — today's pharmacies", f"{base_cells:,} cells" if base_cells else ""),
          ("t_S1", "S1 — same count, travel minimised", f"{scen['S1'][1]:,} open · w = {scen['S1'][0]:.3g}" if "S1" in scen else ""),
          ("t_S2", "S2 — same travel, fewer locations", f"{scen['S2'][1]:,} open · w = {scen['S2'][0]:.3g}" if "S2" in scen else "")]

cmap = ListedColormap(RAMP); norm = BoundaryNorm(BREAKS + [1e9], cmap.N)
fig, axes = plt.subplots(1, 3, figsize=(12.4, 5.0), dpi=200)
fig.patch.set_facecolor("white")
for ax, (col, title, sub) in zip(axes, panels):
    grid = np.full((H, W), np.nan)
    t = np.array([float(r[col]) if r[col] != "" else np.nan for r in rows])
    stranded = np.isnan(t)
    grid[iy[~stranded], ix[~stranded]] = t[~stranded]
    ax.imshow(grid, cmap=cmap, norm=norm, interpolation="nearest", aspect="equal")
    if stranded.any():
        ax.scatter(ix[stranded], iy[stranded], s=28, marker="s", facecolors="none", edgecolors=INK, linewidths=1.2, zorder=5)
    ax.set_axis_off()
    ax.text(0.0, 1.075, title, transform=ax.transAxes, fontsize=11, color=INK, va="bottom", ha="left", fontweight="bold")
    ax.text(0.0, 1.03, sub, transform=ax.transAxes, fontsize=8.5, color=MUTED, va="bottom", ha="left")
    # class counts (cells) and the population-weighted mean, stranded cells at the 120-min
    # cutoff as everywhere else, over the North Sea in the top-left corner
    counts = np.histogram(t[~stranded], bins=BREAKS + [1e9])[0]
    mean_t = (np.nansum(t[~stranded] * pop[~stranded]) + 120.0 * pop[stranded].sum()) / pop.sum()
    lines = [f"mean {mean_t:.2f} min"]
    lines += [f"{LABELS[i]:>10}  {counts[i]:>6,}" for i in range(len(LABELS))]
    if stranded.any():
        lines.append(f"{'stranded':>10}  {int(stranded.sum()):>6,}")
    ax.text(0.02, 0.975, "\n".join(lines), transform=ax.transAxes, fontsize=6.0, family="monospace", color=INK,
            va="top", ha="left", bbox=dict(boxstyle="round,pad=0.4", fc="white", ec="#D9E0E7", lw=0.6))

handles = [Patch(facecolor=c, edgecolor="none", label=l) for c, l in zip(RAMP, LABELS)]
handles.append(Patch(facecolor="white", edgecolor=INK, label="stranded: no open pharmacy in the choice set"))
fig.legend(handles=handles, loc="lower center", ncol=10, fontsize=7.5, frameon=False, bbox_to_anchor=(0.5, -0.005),
           handlelength=1.4, columnspacing=1.2)
fig.subplots_adjust(left=0.01, right=0.99, top=0.88, bottom=0.07, wspace=0.04)
out = os.path.join(HERE, "charts", f"maps_{area}_{func}.png")
fig.savefig(out, facecolor="white")
print("wrote", out, f"({H}x{W} cells)")
