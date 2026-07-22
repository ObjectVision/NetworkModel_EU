# Charts from doc/frontier_metrics_interp1.json + doc/region_typology.csv:
#   pointcloud_<FN>.png   baselines (#F, TC) with projection to the diagonal-cross
#                         on the frontier, log-log, coloured by urban–rural class
#   rank_lambda_<FN>.png  regions ranked by λ_cross (balanced-improvement price)
#   rank_area_<FN>.png    regions ranked by raw rectangle area (potential box)
# Colour = DEGURBA-style class (PU / IN / PR).  RAW units throughout (user choice).
import os, json, csv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CH = os.path.join(ROOT, "doc", "charts")
os.makedirs(CH, exist_ok=True)
FUNCS = ["LINEAR", "LOGISTIC"]

# Policy typology (doc/Typology_Countries_to_share.pptx): colour = formalisation
# degree (the deck's legend chips); archetype Type 1–4 annotated on each label.
FORM_COLOR = {"HIGH": "#C0392B", "MEDIUM": "#E67E22", "LOW": "#27AE60", "VARIES": "#8E44AD"}
FORM_ORDER = ["HIGH", "MEDIUM", "LOW", "VARIES"]
FORM_NAME = {"HIGH": "HIGH formalisation", "MEDIUM": "MEDIUM", "LOW": "LOW", "VARIES": "VARIES"}

METRIC = os.environ.get("METRIC_SUFFIX", "interp1")
m = json.load(open(os.path.join(ROOT, "doc", f"frontier_metrics_{METRIC}.json"), encoding="utf-8"))
typ = {}
with open(os.path.join(ROOT, "doc", "policy_typology.csv"), encoding="utf-8") as fh:
    for row in csv.DictReader(fh):
        typ[row["region"]] = row
# Aggregate uses PL NUTS-1, not country Poland — drop it from these region views.
SKIP = {"Poland"}


def form_of(reg):
    return typ.get(reg, {}).get("formalisation", "LOW")


def label_of(reg):
    a = typ.get(reg, {}).get("archetype", "")
    return f"{reg}·T{a}" if a else reg


def rows_for(fn):
    out = []
    for reg, d in m.items():
        if reg in SKIP or fn not in d:
            continue
        out.append((reg, d[fn], form_of(reg)))
    return out


def legend_handles(forms):
    from matplotlib.patches import Patch
    return [Patch(facecolor=FORM_COLOR[f], label=FORM_NAME[f])
            for f in FORM_ORDER if f in forms]


def pointcloud(fn):
    rs = rows_for(fn)
    fig, ax = plt.subplots(figsize=(9, 6.2), dpi=200)
    forms = set()
    for reg, d, form in rs:
        forms.add(form)
        col = FORM_COLOR[form]
        Bx, By = d["B"]
        S1x, S1y = d["S1"]      # (baseline count, min travel there) — same-count scenario
        S2x, S2y = d["S2"]      # (min count, baseline travel)       — same-travel scenario
        proj = d["cross"] or d["corner"]
        Px, Py = proj
        # the improvement box: baseline (top-right) — S1 (drop straight down) —
        # S2 (straight left) — with the diagonal to the frontier crossing.
        ax.plot([Bx, S1x], [By, S1y], "-", color=col, lw=0.7, alpha=0.4, zorder=2)  # vertical -> S1
        ax.plot([Bx, S2x], [By, S2y], "-", color=col, lw=0.7, alpha=0.4, zorder=2)  # horizontal -> S2
        ax.plot([Bx, Px], [By, Py], "-", color=col, lw=0.9, alpha=0.6, zorder=2)     # diagonal -> crossing
        ax.scatter([Bx], [By], marker="*", s=95, color=col, edgecolor="white", lw=0.6, zorder=5)
        ax.scatter([S1x], [S1y], marker="D", s=20, color=col, edgecolor="white", lw=0.4, zorder=4)
        ax.scatter([S2x], [S2y], marker="s", s=20, color=col, edgecolor="white", lw=0.4, zorder=4)
        ax.scatter([Px], [Py], marker="o", s=22, color=col, edgecolor="white", lw=0.4, zorder=4)
        ax.annotate(label_of(reg), (Bx, By), fontsize=5.5, color="#444",
                    xytext=(2, 2), textcoords="offset points", zorder=6)
    ax.set_xscale("log"); ax.set_yscale("log")
    ax.set_xlabel("# facilities   (★ baseline · ◆ S1 same-count · ■ S2 same-travel · ● frontier crossing)", fontsize=8.5)
    ax.set_ylabel(f"total travel cost c(t)   [{fn}]", fontsize=9)
    ax.set_title(f"Baselines, S1/S2 and frontier projections — {fn}", fontsize=11)
    ax.grid(True, which="both", ls=":", lw=0.4, color="#CCC")
    ax.legend(handles=legend_handles(forms), fontsize=8, loc="lower left",
              title="policy typology · formalisation", title_fontsize=8)
    fig.tight_layout()
    p = os.path.join(CH, f"pointcloud_{fn}.png")
    fig.savefig(p); plt.close(fig)
    return p


def rank_bar(fn, key, label, logx, fname):
    rs = [(reg, d, form) for reg, d, form in rows_for(fn) if d.get(key) is not None]
    rs.sort(key=lambda t: t[1][key], reverse=True)
    regs = [label_of(t[0]) for t in rs]
    vals = [t[1][key] for t in rs]
    cols = [FORM_COLOR[t[2]] for t in rs]
    forms = {t[2] for t in rs}
    fig, ax = plt.subplots(figsize=(8.4, 9.2), dpi=200)
    y = range(len(regs))
    ax.barh(list(y), vals, color=cols, edgecolor="white", lw=0.4)
    ax.set_yticks(list(y)); ax.set_yticklabels(regs, fontsize=6.5)
    ax.invert_yaxis()
    if logx:
        ax.set_xscale("log")
    ax.set_xlabel(label, fontsize=9)
    ax.set_title(f"{label} — ranked, {fn}", fontsize=11)
    ax.grid(True, axis="x", ls=":", lw=0.4, color="#CCC")
    ax.legend(handles=legend_handles(forms), fontsize=8, loc="lower right",
              title="policy typology · formalisation", title_fontsize=8)
    fig.tight_layout()
    p = os.path.join(CH, fname)
    fig.savefig(p); plt.close(fig)
    return p


made = []
for fn in FUNCS:
    made.append(pointcloud(fn))
    made.append(rank_bar(fn, "lambda_cross", "λ at balanced-improvement crossing (€)",
                         False, f"rank_lambda_{fn}.png"))
    made.append(rank_bar(fn, "rect_area", "potential rectangle area (raw: #F × travel-cost)",
                         True, f"rank_area_{fn}.png"))
    # size-independent version: rectangle / (baseline facility-cost × travel-cost)
    made.append(rank_bar(fn, "rect_rel",
                         "potential rectangle relative to baseline facility × travel cost",
                         False, f"rank_area_rel_{fn}.png"))
for p in made:
    print("wrote", os.path.relpath(p, ROOT))
