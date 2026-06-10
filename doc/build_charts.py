# Render per-region Pareto charts to doc/charts/<region>_<FUNC>.png for the deck.
# Per spec: vs sum_x (x), show travel_relax + travel_multi (left, cost) and frac_x
# (second left axis), plus log10(w) on the right axis; mark the baseline (current
# network), S1 and S2. LOGISTIC left axis is stretched to the data (non-zero origin).
import os, json, math
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "doc", "charts")
os.makedirs(OUT, exist_ok=True)

# palette (matches the deck)
RELAX = "#9AA7B4"   # LP relaxation bound
MULTI = "#0B6E99"   # multistart (hero)
FRAC = "#2E8B57"    # frac_x (integrality)
WCOL = "#E8A33D"    # log10(w)
BASE = "#34495E"    # baseline / current network
S1C = "#0B6E99"
S2C = "#8E44AD"
INK = "#12233A"

plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 8.5,
    "axes.edgecolor": "#7A8794", "axes.linewidth": 0.8,
})


def window(fd):
    sc = fd.get("scen", {})
    anchors = [sc[k]["sum_x"] for k in ("S1", "S2") if sc.get(k) and sc[k].get("sum_x")]
    anchors.append(fd["baseline"].get("cells"))
    anchors = [a for a in anchors if a]
    ref = anchors if anchors else [r["sum_x"] for r in fd["rows"]]
    lo, hi = 0.6 * min(ref), 1.7 * max(ref)
    rows = sorted([r for r in fd["rows"] if lo <= r["sum_x"] <= hi], key=lambda r: r["sum_x"])
    if len(rows) < 2:
        rows = sorted(fd["rows"], key=lambda r: r["sum_x"])
    return rows


def fmt_cost(ax):
    ax.ticklabel_format(axis="y", style="sci", scilimits=(6, 6))
    ax.yaxis.get_offset_text().set_fontsize(7)


def render(region, fn, fd):
    rows = window(fd)
    sx = [r["sum_x"] for r in rows]
    relax = [r["relax"] for r in rows]
    multi = [r["multi"] for r in rows]
    frac = [r["frac"] for r in rows]
    logw = [math.log10(r["w"]) for r in rows if r["w"] > 0]
    sxw = [r["sum_x"] for r in rows if r["w"] > 0]
    base = fd["baseline"]
    sc = fd.get("scen", {})

    fig, ax = plt.subplots(figsize=(5.95, 3.5), dpi=200)
    fig.subplots_adjust(left=0.205, right=0.865, bottom=0.155, top=0.9)

    # second LEFT axis for frac_x (offset further left)
    ax_f = ax.twinx()
    ax_f.spines["left"].set_position(("axes", -0.16))
    ax_f.yaxis.set_label_position("left"); ax_f.yaxis.set_ticks_position("left")
    ax_f.spines["left"].set_visible(True)
    # RIGHT axis for log10(w)
    ax_w = ax.twinx()

    # frac (draw first, behind)
    ax_f.fill_between(sx, frac, color=FRAC, alpha=0.10, zorder=1)
    ax_f.plot(sx, frac, color=FRAC, lw=1.1, marker=".", ms=4, zorder=2)
    ax_f.set_ylabel("frac_x  (fractional vars)", color=FRAC, fontsize=8)
    ax_f.tick_params(axis="y", colors=FRAC, labelsize=7.5)
    ax_f.set_ylim(0, max(frac) * 1.15 + 1)

    # log10(w)
    ax_w.plot(sxw, logw, color=WCOL, lw=1.1, marker=".", ms=4, ls=(0, (4, 2)), zorder=3)
    ax_w.set_ylabel("log₁₀(w)", color=WCOL, fontsize=8)
    ax_w.tick_params(axis="y", colors=WCOL, labelsize=7.5)

    # travel curves (left, on top)
    ax.plot(sx, relax, color=RELAX, lw=1.6, ls="--", marker="o", ms=3.2, zorder=5, label="LP relax (bound)")
    ax.plot(sx, multi, color=MULTI, lw=2.4, marker="o", ms=4.2, zorder=6, label="multistart")

    # baseline (current network): point at (cells, cost) + reference lines
    ax.axhline(base["cost"], color=BASE, ls=":", lw=1.0, alpha=0.55, zorder=4)
    ax.scatter([base["cells"]], [base["cost"]], marker="*", s=170, color=BASE,
               edgecolor="white", linewidth=0.6, zorder=8, label="baseline (current)")

    # S1 / S2 markers on the multistart curve
    for key, col, mk in (("S1", S1C, "D"), ("S2", S2C, "s")):
        d = sc.get(key)
        if not d or not d.get("sum_x"):
            continue
        ax.scatter([d["sum_x"]], [d["multi"]], marker=mk, s=70, color=col,
                   edgecolor="white", linewidth=0.8, zorder=9)
        ax.annotate(key, (d["sum_x"], d["multi"]), textcoords="offset points",
                    xytext=(4, 7), fontsize=9, fontweight="bold", color=col)

    ax.set_xlabel("sum_x  (LP-relaxed facility count)", fontsize=8)
    ax.set_ylabel("total travel cost  (person·c(t))", color=INK, fontsize=8)
    ax.tick_params(axis="both", labelsize=7.5)
    fmt_cost(ax)

    # y-limits: LINEAR from 0; LOGISTIC stretched to the data (non-zero origin)
    yvals = relax + multi + [base["cost"]]
    ylo, yhi = min(yvals), max(yvals)
    if fn == "LOGISTIC":
        pad = (yhi - ylo) * 0.08 or yhi * 0.05
        ax.set_ylim(ylo - pad, yhi + pad)
    else:
        ax.set_ylim(0, yhi * 1.06)

    ax.set_title(f"{fn}  c(t)", fontsize=11, color=INK, fontweight="bold", pad=6)
    ax.set_zorder(ax_f.get_zorder() + 2); ax.patch.set_visible(False)

    # unified legend (compact, top-left inside)
    handles = [
        Line2D([0], [0], color=RELAX, ls="--", marker="o", ms=3, label="LP relax (bound)"),
        Line2D([0], [0], color=MULTI, lw=2.2, marker="o", ms=4, label="multistart"),
        Line2D([0], [0], color=FRAC, marker=".", label="frac_x"),
        Line2D([0], [0], color=WCOL, ls=(0, (4, 2)), marker=".", label="log₁₀(w)"),
        Line2D([0], [0], color=BASE, marker="*", ls="none", ms=8, label="baseline"),
    ]
    ax.legend(handles=handles, loc="upper right", fontsize=6.8, framealpha=0.85,
              borderpad=0.4, handlelength=1.6, labelspacing=0.3)

    p = os.path.join(OUT, f"{region}_{fn}.png")
    fig.savefig(p, dpi=200)
    plt.close(fig)
    return p


def main():
    data = json.load(open(os.path.join(ROOT, "doc", "deck_data.json"), encoding="utf-8"))
    n = 0
    for e in data:
        for fn, fd in e["func"].items():
            render(e["region"], fn, fd)
            n += 1
    print(f"rendered {n} charts into {OUT}")


if __name__ == "__main__":
    main()
