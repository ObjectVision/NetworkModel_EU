# The sweep read along λ instead of along the frontier: x = λ, the price of a location,
# on a log axis; LEFT axis the two bounds on travel cost at each λ (LP relaxation below,
# multistart integer solution above); RIGHT axis the facility count of each (the LP's
# fractional Σy and the rounded integer count of the multistart set). One panel per
# travel-cost function.
#
# What it adds to the frontier charts: the frontier hides λ (it only labels it on a
# second axis), so it cannot show WHERE along the sweep the bounds open up or how fast
# the count collapses per decade of λ. Here that is the picture. The horizontal
# guides are the baseline — travel on the left axis, count on the right — so S2 is
# where the travel curve crosses its guide and S1 where the count curve crosses its
# guide; the vertical guides mark the λ the deck's tables report for each.
#
# On the right axis, honestly: Σy* (dashed) is the LP-relaxed count and n_open (solid)
# is the integer count of the rounded set, with n_open = round(Σy*) by construction
# (lp_run.jl multistart_round). Neither is a rigorous bound on the integer optimum's
# count — the certified bound is on TOTAL cost only (deck p12) — so the two count
# curves nearly coincide and the informative gap is the one on the left axis.
#
#   PYTHONIOENCODING=utf-8 python doc/lambda_axis_chart.py [REGION ...]
#   -> doc/charts/lambda_axis_<REGION>.png      (default: AGGREGATE Netherlands)
#
# Reads doc/deck_data.json (build_deck_data.py); the aggregate comes from
# build_charts.aggregate_fd, the same 41-area separable sum the deck's p59 uses.
import os, sys, json, math
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from build_charts import aggregate_fd, RELAX, MULTI, BASE, INK, OUT   # palette + charts dir

FMIN = 100000            # FACILITY_MIN_COSTS (settings.jl); λ = w · FMIN, a placeholder €
CNT_LO = "#F0B27A"       # LP-relaxed count Σy* (dashed)
CNT_HI = "#C0392B"       # integer count n_open of the multistart set (solid)

plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 8.5,
    "axes.edgecolor": "#7A8794", "axes.linewidth": 0.8,
})


def scen_lambda(fd, key):
    """λ (€) of the deck's S1/S2 row for this area, or None when not bracketed."""
    s = fd.get("scen", {}).get(key)
    return s["w"] * FMIN if s and s.get("w") else None


def panel(ax, fd, fn, title):
    rows = sorted([r for r in fd["rows"] if r["w"] > 0], key=lambda r: r["w"])
    lam = [r["w"] * FMIN for r in rows]
    base = fd["baseline"]
    # both panels in millions: keeps matplotlib's "1e7" offset text off the title line
    scale = 1e6
    ulabel = "M person-minutes" if fn == "LINEAR" else "M person·c(t)"

    # LEFT: the two travel-cost bounds
    ax.plot(lam, [r["relax"] / scale for r in rows], color=RELAX, lw=1.6, ls=(0, (5, 2)),
            marker=".", ms=3.5, zorder=3)
    ax.plot(lam, [r["multi"] / scale for r in rows], color=MULTI, lw=1.8, marker=".", ms=3.5, zorder=4)
    ax.axhline(base["cost"] / scale, color=MULTI, lw=0.9, ls=":", alpha=0.8, zorder=2)
    ax.set_xscale("log")
    ax.set_xlabel("λ — price per location  (€, placeholder €100 000 · w)", color=INK)
    ax.set_ylabel(f"total travel cost  ({ulabel})", color=MULTI)
    ax.tick_params(axis="y", colors=MULTI, labelsize=7.5)
    ax.tick_params(axis="x", labelsize=7.5)
    ax.grid(True, which="major", axis="x", color="#DDE3E9", lw=0.6)
    ax.set_title(f"{title}   {fn}  c(t)", color=INK, fontsize=10, fontweight="bold", loc="left")

    # RIGHT: the two facility counts. n_open = round(Σy*), so the two curves coincide to
    # within half a facility; the dashed Σy* is drawn ON TOP so it shows through the
    # solid n_open and the reader sees that they coincide rather than that one is missing.
    axr = ax.twinx()
    axr.plot(lam, [r["n_open"] for r in rows], color=CNT_HI, lw=1.8, marker=".", ms=3.5, zorder=3)
    axr.plot(lam, [r["sum_y"] for r in rows], color=CNT_LO, lw=1.2, ls=(0, (4, 3)), zorder=4)
    axr.axhline(base["cells"], color=CNT_HI, lw=0.9, ls=":", alpha=0.8, zorder=2)
    axr.set_ylabel("number of facilities", color=CNT_HI)
    axr.tick_params(axis="y", colors=CNT_HI, labelsize=7.5)

    # vertical guides at the λ the deck reports for S1 and S2; S1's label sits to the
    # left of its line and S2's to the right, so the two never overlap however close
    # the λ's are (the aggregate has them within a factor 1.7)
    ytop = ax.get_ylim()[1]
    for key, col, dx, ha in (("S1", MULTI, -3, "right"), ("S2", "#8E44AD", 3, "left")):
        lv = scen_lambda(fd, key)
        if lv:
            ax.axvline(lv, color=col, lw=0.9, ls="--", alpha=0.7, zorder=1)
            ax.annotate(f"{key}  λ ≈ €{lv:,.0f}", xy=(lv, ytop), xytext=(dx, -6),
                        textcoords="offset points", fontsize=7.5, color=col,
                        ha=ha, va="top", rotation=90)

    return axr


def render(region, entries):
    fig, axes = plt.subplots(1, 2, figsize=(11.9, 4.2), dpi=200)
    fig.subplots_adjust(left=0.06, right=0.925, bottom=0.2, top=0.9, wspace=0.45)
    title = "All 41 areas combined" if region == "AGGREGATE" else region
    drawn = 0
    for ax, fn in zip(axes, ("LINEAR", "LOGISTIC")):
        fd = entries.get(fn)
        if not fd or not fd.get("rows"):
            ax.set_axis_off()
            ax.text(0.5, 0.5, f"no {fn} sweep", ha="center", va="center", color="#7A8794")
            continue
        panel(ax, fd, fn, title)
        drawn += 1
    handles = [
        Line2D([], [], color=RELAX, lw=1.6, ls=(0, (5, 2)), label="travel cost lower bound — LP relaxation"),
        Line2D([], [], color=MULTI, lw=1.8, label="travel cost upper bound — multistart integer solution"),
        Line2D([], [], color=CNT_LO, lw=1.2, ls=(0, (4, 3)), label="facilities — LP-relaxed Σy* (coincides with n_open)"),
        Line2D([], [], color=CNT_HI, lw=1.8, label="facilities — integer n_open = round(Σy*) of the multistart set"),
        Line2D([], [], color=BASE, lw=0.9, ls=":", label="baseline (★): travel on the left axis, count on the right"),
    ]
    fig.legend(handles=handles, loc="lower center", ncol=3, fontsize=7.5, frameon=False,
               bbox_to_anchor=(0.5, 0.0))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"lambda_axis_{region}.png")
    fig.savefig(path)
    plt.close(fig)
    print(f"  {path}  ({drawn} panels)")


def main(regions):
    data = json.load(open(os.path.join(HERE, "deck_data.json"), encoding="utf-8"))
    for region in regions:
        if region == "AGGREGATE":
            entries = {fn: aggregate_fd(data, fn) for fn in ("LINEAR", "LOGISTIC")}
        else:
            e = next((x for x in data if x["region"] == region), None)
            if e is None:
                print(f"  unknown region: {region}")
                continue
            entries = e["func"]
        render(region, entries)


if __name__ == "__main__":
    main(sys.argv[1:] or ["AGGREGATE", "Netherlands"])
