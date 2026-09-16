# Cross-lambda against residents per location, by OECD archetype (16 Sep 2026).
#   doc/charts/xlambda_scatter_<FN>.png   one per travel-cost function, log-log, with the
#                                         least-squares fit over all areas and its R^2
#   doc/cross_lambda_residuals_<FN>.csv    per area: density, cross-lambda, fitted, residual
#
# Why: Lewis's benchmarking deck (p21, p24) reads cross-lambda as a country's revealed
# preference for efficiency over proximity and groups it by OECD archetype. For one and the
# same geography cross-lambda falls as today's facility count rises, so across areas it
# moves with residents per location as well as with policy. The fit is the part today's
# density predicts; the distance to the line is what is left for geography and policy.
#
# Inputs: doc/frontier_metrics_<METRIC>.json (lambda_cross, in EUR via the placeholder
# 100,000 per location), doc/deck_data.json (baseline cells and, from LINEAR cost / mean_t,
# the sweep's own client population), doc/policy_typology.csv (archetype). Country-level
# Poland is skipped in favour of its seven NUTS-1 areas, as in frontier_charts.py.
import os, json, csv, math
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "doc")
CH = os.path.join(DOC, "charts")
os.makedirs(CH, exist_ok=True)
FUNCS = ["LINEAR", "LOGISTIC"]
METRIC = os.environ.get("METRIC_SUFFIX", "interp3")
SKIP = {"Poland"}

# archetype colours as on the OECD-archetype map of Lewis's deck (p23)
ARCH_COLOR = {"1": "#6DB33F", "2": "#3B2A4E", "3": "#3FA9E0", "4": "#F0812E"}
ARCH_NAME = {"1": "1 rule-of-law-anchored", "2": "2 consensual-pluralist",
             "3": "3 public-interest majoritarian", "4": "4 segmented-federal"}

m = json.load(open(os.path.join(DOC, f"frontier_metrics_{METRIC}.json"), encoding="utf-8"))
deck = {e["region"]: e for e in json.load(open(os.path.join(DOC, "deck_data.json"), encoding="utf-8"))}
typ = {}
with open(os.path.join(DOC, "policy_typology.csv"), encoding="utf-8") as fh:
    for row in csv.DictReader(fh):
        typ[row["region"]] = row


def residents_per_location(reg):
    """Sweep baseline: LINEAR cost = sum pop * minutes (stranded at 120), mean_t = cost / pop,
    so pop = cost / mean_t; cells = today's 1 km2 pharmacy locations in the model's scope."""
    b = deck[reg]["func"]["LINEAR"]["baseline"]
    if not b.get("mean_t"):
        return None
    pop = b["cost"] / b["mean_t"]
    return pop / b["cells"]


def ols_loglog(xs, ys):
    lx = [math.log10(x) for x in xs]; ly = [math.log10(y) for y in ys]
    n = len(lx); mx = sum(lx) / n; my = sum(ly) / n
    sxx = sum((a - mx) ** 2 for a in lx); sxy = sum((a - mx) * (b - my) for a, b in zip(lx, ly))
    slope = sxy / sxx; icpt = my - slope * mx
    ss_res = sum((b - (icpt + slope * a)) ** 2 for a, b in zip(lx, ly))
    ss_tot = sum((b - my) ** 2 for b in ly)
    return slope, icpt, 1 - ss_res / ss_tot


for fn in FUNCS:
    rows = []
    for reg, d in m.items():
        if reg in SKIP or fn not in d or d[fn].get("lambda_cross") is None or reg not in deck:
            continue
        rpl = residents_per_location(reg)
        if rpl is None:
            continue
        rows.append((reg, rpl, d[fn]["lambda_cross"], typ.get(reg, {}).get("archetype", "")))
    xs = [r[1] for r in rows]; ys = [r[2] for r in rows]
    slope, icpt, r2 = ols_loglog(xs, ys)
    fit = lambda x: 10 ** (icpt + slope * math.log10(x))

    fig, ax = plt.subplots(figsize=(9, 6.2), dpi=200)
    seen = set()
    for reg, x, y, a in rows:
        col = ARCH_COLOR.get(a, "#888888")
        ax.scatter([x], [y], s=34, color=col, edgecolor="white", lw=0.5, zorder=4,
                   label=ARCH_NAME.get(a, "no archetype") if a not in seen else None)
        seen.add(a)
        ax.annotate(reg, (x, y), fontsize=5.8, color="#444", xytext=(3, 2), textcoords="offset points", zorder=6)
    xr = [min(xs) * 0.9, max(xs) * 1.1]
    ax.plot(xr, [fit(v) for v in xr], ":", color="#555", lw=1.1, zorder=3,
            label=f"log-log fit over all areas: slope {slope:.2f}, R² {r2:.2f}")
    ax.set_xscale("log"); ax.set_yscale("log")
    ax.set_xlabel("residents per 1 km² pharmacy location today (sweep baseline)", fontsize=9)
    ax.set_ylabel(f"cross-lambda: λ at the balanced-improvement crossing (€)   [{fn}]", fontsize=9)
    ax.set_title(f"Cross-lambda against today's density, by OECD archetype — {fn}", fontsize=11)
    ax.grid(True, which="both", ls=":", lw=0.4, color="#CCC")
    ax.legend(fontsize=7.5, loc="upper left", title="OECD archetype (Lewis, p22)", title_fontsize=7.5)
    fig.tight_layout()
    p = os.path.join(CH, f"xlambda_scatter_{fn}.png")
    fig.savefig(p); plt.close(fig)
    print("wrote", os.path.relpath(p, ROOT), f"| n={len(rows)} slope={slope:.3f} R2={r2:.3f}")

    # residual table: what density does not explain, ranked
    out = os.path.join(DOC, f"cross_lambda_residuals_{fn}.csv")
    res = []
    for reg, x, y, a in rows:
        f = fit(x); res.append((reg, a, x, y, f, math.log10(y / f), y / f))
    res.sort(key=lambda t: t[5], reverse=True)
    with open(out, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["region", "archetype", "residents_per_location", "lambda_cross_eur", "fitted_eur",
                    "residual_log10", "ratio_actual_over_fitted"])
        for t in res:
            w.writerow([t[0], t[1], f"{t[2]:.0f}", f"{t[3]:.0f}", f"{t[4]:.0f}", f"{t[5]:.3f}", f"{t[6]:.2f}"])
    print("wrote", os.path.relpath(out, ROOT))
    # archetype summary: mean residual as a factor
    for a in sorted({t[1] for t in res}):
        rs = [t[5] for t in res if t[1] == a]
        print(f"  archetype {a}: n={len(rs)} mean ratio actual/fitted = {10 ** (sum(rs) / len(rs)):.2f}")
