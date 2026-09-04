# How one lambda picks one point on the frontier (REGIO review, comments 41/42):
# the objective travel + lambda*#facilities is a straight line of slope -lambda in the
# (#facilities, travel) plane; its minimum over the feasible set is where that line
# is tangent to the Pareto frontier. Two lambdas -> two tangent points; the frontier
# is the envelope of all of them. Drawn from one region's real sweep rows.
import json, os, io, sys
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
REGION, FUNC, FMC = "Netherlands", "LINEAR", 100000
W1, W2 = 0.1, 0.5                                     # two lambdas to illustrate
M = 1e6                                               # plot in million person-minutes

data = json.load(open(os.path.join(HERE, "deck_data.json"), encoding="utf-8"))
e = next(x for x in data if x["region"] == REGION)
rows = sorted([r for r in e["func"][FUNC]["rows"] if r.get("n_open") and r.get("multi")],
              key=lambda r: r["n_open"])
base = e["func"][FUNC]["baseline"]
# lower-left Pareto envelope: ascending n_open, keep only strictly falling travel;
# cut the near-flat "open everything" tail so the linear axes show the bend
env = []
for r in rows:
    if r["n_open"] > 8300 or (env and r["multi"] >= env[-1]["multi"]):
        continue
    env.append(r)
xs = [r["n_open"] for r in env]; ys = [r["multi"] / M for r in env]

def optimum(w):
    lam = w * FMC
    return min(env, key=lambda r: r["multi"] + lam * r["n_open"]), lam

fig, ax = plt.subplots(figsize=(9.2, 5.6), dpi=200)
ax.plot(xs, ys, "-", color="#1C3D5A", lw=2.2, label="Pareto frontier (multistart)", zorder=3)
ax.scatter(xs, ys, s=14, color="#1C3D5A", zorder=4)
ax.scatter([base["cells"]], [base["cost"] / M], marker="*", s=260, color="#B9791C", zorder=6,
           label="baseline ★ (current network)")
x0, x1 = min(xs) * 0.85, max(xs) * 1.05
for w, col, tag in ((W1, "#0B6E99", "λ₁"), (W2, "#1E7A52", "λ₂")):
    opt, lam = optimum(w)
    C = opt["multi"] + lam * opt["n_open"]               # iso-cost through the optimum
    ax.plot([x0, x1], [(C - lam * x0) / M, (C - lam * x1) / M], "--", color=col, lw=1.6, zorder=2,
            label=f"iso-cost line, slope −{tag} (w = {w})")
    ax.scatter([opt["n_open"]], [opt["multi"] / M], s=120, facecolors="white", edgecolors=col, lw=2.2, zorder=7)
    ax.annotate(f"optimum for {tag}\n{opt['n_open']:,} open, {opt['multi'] / M:.1f} M",
                (opt["n_open"], opt["multi"] / M), textcoords="offset points", xytext=(14, 18),
                fontsize=9, color=col, arrowprops=dict(arrowstyle="-", color=col, lw=0.8))
ax.set_xlim(x0, x1)
ax.set_ylim(0, max(ys) * 1.08)
ax.set_xlabel("number of open pharmacy locations  →  higher facility cost")
ax.set_ylabel("total travel  (million person-minutes, c(t) = t)")
ax.set_title(f"{REGION} · {FUNC}: minimising  travel + λ·#open  =  sliding a line of slope −λ down until it touches the frontier",
             fontsize=10.5)
ax.grid(alpha=0.25); ax.legend(fontsize=8.5, loc="upper right")
out = os.path.join(HERE, "charts", "lambda_tangent.png")
fig.tight_layout(); fig.savefig(out); print("wrote", out)
for w in (W1, W2):
    o, lam = optimum(w); print(f"  w={w}: λ=€{lam:,.0f}  optimum n_open={o['n_open']}  travel={o['multi'] / M:.1f} M person-min")
