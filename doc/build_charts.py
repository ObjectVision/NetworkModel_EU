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
    fig.subplots_adjust(left=0.125, right=0.865, bottom=0.155, top=0.9)

    # RIGHT axis for log10(w). (frac_x dropped from the charts per Maarten 6-Jul —
    # it overcomplicated the plot; integrality is still reported in the S1/S2 table.)
    ax_w = ax.twinx()

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
    ax.set_zorder(ax_w.get_zorder() + 2); ax.patch.set_visible(False)

    # unified legend (compact, top-left inside)
    handles = [
        Line2D([0], [0], color=RELAX, ls="--", marker="o", ms=3, label="LP relax (bound)"),
        Line2D([0], [0], color=MULTI, lw=2.2, marker="o", ms=4, label="multistart"),
        Line2D([0], [0], color=WCOL, ls=(0, (4, 2)), marker=".", label="log₁₀(w)"),
        Line2D([0], [0], color=BASE, marker="*", ls="none", ms=8, label="baseline"),
    ]
    ax.legend(handles=handles, loc="upper right", fontsize=6.8, framealpha=0.85,
              borderpad=0.4, handlelength=1.6, labelspacing=0.3)

    p = os.path.join(OUT, f"{region}_{fn}.png")
    fig.savefig(p, dpi=200)
    plt.close(fig)
    return p


def render_logistic():
    """Compare the current logistic travel cost (midpoint 30, scale 15) with a
    Lewis-tuned alternative (midpoint 25, scale 10) over 0-60 min."""
    import numpy as np
    t = np.linspace(0, 60, 241)
    L = lambda t, m, s: 1.0 / (1.0 + np.exp(-(t - m) / s))
    fig, ax = plt.subplots(figsize=(7.5, 4.05), dpi=200)
    ax.axhline(0.5, color="#B4B2A9", ls=":", lw=1, zorder=1)
    for x in (5, 45):
        ax.axvline(x, color="#C9A24B", ls=":", lw=1, zorder=1)
    ax.text(5, 1.005, "~5", color="#9A7B1C", fontsize=7.5, ha="center")
    ax.text(45, 1.005, "~45 (Lewis)", color="#9A7B1C", fontsize=7.5, ha="center")
    ax.plot(t, L(t, 30, 15), color="#185FA5", lw=2.6, label="previous  ·  midpoint 30, scale 15", zorder=4)
    ax.plot(t, L(t, 25, 10), color="#1D9E75", lw=2.6, label="adopted  ·  midpoint 25, scale 10", zorder=5)
    ax.scatter([30], [0.5], color="#185FA5", s=55, edgecolor="white", lw=1, zorder=6)
    ax.scatter([25], [0.5], color="#1D9E75", s=55, edgecolor="white", lw=1, zorder=6)
    ax.set_xlim(0, 60); ax.set_ylim(0, 1.02)
    ax.set_xticks(range(0, 61, 10)); ax.set_yticks([0, .25, .5, .75, 1])
    ax.set_xlabel("travel time  t  (minutes)", fontsize=9)
    ax.set_ylabel("c(t)   cost weight", fontsize=9)
    ax.tick_params(labelsize=8)
    ax.legend(loc="lower right", fontsize=9, framealpha=0.9)
    ax.set_title("Logistic travel cost   c(t) = 1 / (1 + e^[ −(t − m) / s ])",
                 fontsize=11, color="#12233A", fontweight="bold", pad=8)
    fig.tight_layout()
    p = os.path.join(OUT, "logistic_compare.png")
    fig.savefig(p, dpi=200); plt.close(fig)
    return p


# --- Aggregate frontier over all (disjoint) areas -----------------------------
# The objective separates by area, so for a COMMON lambda the sum of the regional
# optima IS the optimum of the combined problem: summing (sum_x, travel) per w gives
# the exact aggregate lower-bound curve (and summing the multistart points a valid
# aggregate upper bound). Only w values present in EVERY area are aggregated (the
# coarse grid; region-specific fine-sweep w's drop out of the intersection).
# Poland-country is EXCLUDED whenever its NUTS-1 regions are present (disjointness).
def _interp_at(rows, w):
    """Log-w interpolate sum_x/relax/multi/frac at w from a region's sorted rows.
    Exact at the region's own grid points; assumes w within [rows0.w, rows-1.w]."""
    lo, hi = None, None
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
    mix = lambda k: lo[k] + f * (hi[k] - lo[k])
    return dict(w=w, sum_x=mix("sum_x"), relax=mix("relax"), multi=mix("multi"),
                n_open=mix("n_open"), frac=mix("frac"))


def render_aggregate(data):
    part = [e for e in data if not (e["region"] == "Poland" and any(x["region"].startswith("PL") for x in data))]
    agg_out = {}
    for fn in ("LINEAR", "LOGISTIC"):
        regs = [e for e in part if fn in e["func"] and e["func"][fn].get("rows")]
        missing = [e["region"] for e in part if e not in regs]
        if missing:
            print(f"  [aggregate {fn}] WARNING: skipping areas without {fn} data: {missing}")
        if len(regs) < 2:
            continue
        # union of w values, restricted to the range covered by EVERY area; each area
        # contributes log-interpolated values between its own adjacent sweep points
        # (exact at its own grid points) — the same rule as the interpolated-λ tables.
        per = {e["region"]: sorted([r for r in e["func"][fn]["rows"] if r["w"] > 0], key=lambda r: r["w"]) for e in regs}
        w_lo = max(rows[0]["w"] for rows in per.values())
        w_hi = min(rows[-1]["w"] for rows in per.values())
        union = sorted(set(round(r["w"], 12) for rows in per.values() for r in rows if w_lo <= r["w"] <= w_hi))
        rows = []
        for w in union:
            agg = dict(w=w, sum_x=0.0, relax=0.0, multi=0.0, n_open=0.0, frac=0.0, mean_t=0.0)
            ok = True
            for reg, rr in per.items():
                v = _interp_at(rr, w)
                if v is None:
                    ok = False
                    break
                agg["sum_x"] += v["sum_x"]; agg["relax"] += v["relax"]; agg["multi"] += v["multi"]
                agg["n_open"] += v["n_open"]; agg["frac"] += v["frac"]
            if ok:
                agg["n_open"] = round(agg["n_open"]); agg["frac"] = round(agg["frac"])
                rows.append(agg)
        base = dict(cells=sum(e["func"][fn]["baseline"]["cells"] for e in regs),
                    cost=sum(e["func"][fn]["baseline"]["cost"] for e in regs),
                    mean_t=0.0)
        # S1/S2 only when genuinely bracketed by the aggregate curve
        sxs = [r["sum_x"] for r in rows]; mts = [r["multi"] for r in rows]
        s1 = min(rows, key=lambda r: abs(r["sum_x"] - base["cells"])) if min(sxs) <= base["cells"] <= max(sxs) else None
        s2 = min(rows, key=lambda r: abs(r["multi"] - base["cost"])) if min(mts) <= base["cost"] <= max(mts) else None
        scen = {k: dict(v) for k, v in (("S1", s1), ("S2", s2)) if v}
        fd = {"rows": rows, "baseline": base, "scen": scen}
        render("AGGREGATE", fn, fd)
        by_sx = sorted(rows, key=lambda r: r["sum_x"])
        agg_out[fn] = {"n_regions": len(regs), "n_w": len(rows), "baseline": base,
                       "S1": s1, "S2": s2, "few": by_sx[0], "many": by_sx[-1]}
        print(f"  [aggregate {fn}] {len(regs)} areas, {len(rows)} union w-points in "
              f"[{w_lo:g}, {w_hi:g}]; baseline {base['cells']} cells / {base['cost']:.3e}; "
              f"S1 bracketed: {s1 is not None}, S2 bracketed: {s2 is not None}")
    json.dump(agg_out, open(os.path.join(ROOT, "doc", "agg_data.json"), "w", encoding="utf-8"), indent=1)


def main():
    data = json.load(open(os.path.join(ROOT, "doc", "deck_data.json"), encoding="utf-8"))
    n = 0
    for e in data:
        for fn, fd in e["func"].items():
            render(e["region"], fn, fd)
            n += 1
    render_aggregate(data)
    render_logistic()
    print(f"rendered {n} region charts + aggregate + logistic comparison into {OUT}")


if __name__ == "__main__":
    main()
