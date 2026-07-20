# Round-1 frontier metrics from doc/deck_data.json (no new solves).
#
# Per region x {LINEAR, LOGISTIC}, using the realized multistart frontier
# (x = n_open facilities, y = multistart travel cost) and the baseline point
# B = (cells, cost):
#   S1   = (B_x, S1_y)   S1_y = min travel at the baseline facility count      (vertical drop)
#   S2   = (S2_x, B_y)   S2_x = min count at the baseline travel               (horizontal drop)
#   corner C = (S2_x, S1_y)                                                    (opposite rect corner)
#   rect_area = (B_x - S2_x) * (B_y - S1_y)        RAW units (facilities x travel-cost)
#   diag = segment B -> C; cross = diag ∩ frontier  (the balanced-improvement point)
#   lambda_cross = w(at cross) * FACILITY_MIN_COSTS  (real EUR)
#
# All values are interpolated linearly between the two bracketing frontier
# points (chord interpolation). Convexity ⇒ chords slightly OVER-estimate the
# true frontier, so S1_y/rect_area are mild upper bounds — stated, not hidden.
# `bracketed` flags say whether the swept range actually spans the target;
# unbracketed S1/S2 are exactly what Round 2 / the Belgium-FRI high-λ runs fix.
#
# Writes doc/frontier_metrics_interp1.json (+ .csv) and prints a table.
import os, json, csv, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FACILITY_MIN_COSTS = 100000
FUNCS = ["LINEAR", "LOGISTIC"]


def pareto_frontier(rows):
    """Lower-left Pareto envelope of (n_open, multi) points: keep a point only
    if no other has both >= count and <= travel. Returns list sorted by count
    ascending, travel descending — a monotone decreasing staircase."""
    pts = [(r["n_open"], r["multi"], r["w"]) for r in rows
           if r.get("n_open") and r.get("multi")]
    # dedup by count, keep the cheapest travel per count
    best = {}
    for x, y, w in pts:
        if x not in best or y < best[x][0]:
            best[x] = (y, w)
    pts = sorted(((x, y, w) for x, (y, w) in best.items()))
    # enforce monotone-decreasing travel as count rises (drop dominated)
    env = []
    for x, y, w in pts:
        while env and y >= env[-1][1]:   # this count is cheaper-or-equal ⇒ prior dominated
            env.pop()
        env.append((x, y, w))
    return env  # sorted by count ascending, travel strictly decreasing


def interp_y_at_x(env, x0):
    """Travel at count x0 by linear interpolation; (val, bracketed)."""
    xs = [p[0] for p in env]
    if x0 <= xs[0]:
        return env[0][1], (x0 == xs[0])
    if x0 >= xs[-1]:
        return env[-1][1], (x0 == xs[-1])
    for a, b in zip(env, env[1:]):
        if a[0] <= x0 <= b[0]:
            t = (x0 - a[0]) / (b[0] - a[0])
            return a[1] + t * (b[1] - a[1]), True
    return None, False


def interp_x_at_y(env, y0):
    """Count at travel y0 (travel decreases as count rises); (val, bracketed)."""
    # env travel is decreasing in count; walk segments
    for a, b in zip(env, env[1:]):
        ylo, yhi = min(a[1], b[1]), max(a[1], b[1])
        if ylo <= y0 <= yhi:
            t = (y0 - a[1]) / (b[1] - a[1])
            return a[0] + t * (b[0] - a[0]), True
    # not bracketed: clamp to the end whose travel is closest
    if y0 > env[0][1]:      # want more travel than the lowest-count point offers
        return env[0][0], False
    return env[-1][0], False


def interp_w_at_x(env, x0):
    xs = [p[0] for p in env]
    if x0 <= xs[0]:
        return env[0][2]
    if x0 >= xs[-1]:
        return env[-1][2]
    for a, b in zip(env, env[1:]):
        if a[0] <= x0 <= b[0]:
            t = (x0 - a[0]) / (b[0] - a[0])
            return a[2] + t * (b[2] - a[2])
    return env[-1][2]


def seg_intersect(p1, p2, p3, p4):
    """Intersection of segment p1p2 with p3p4, or None. Points are (x,y)."""
    x1, y1 = p1; x2, y2 = p2; x3, y3 = p3; x4, y4 = p4
    den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    if abs(den) < 1e-12:
        return None
    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
    u = ((x1 - x3) * (y1 - y2) - (y1 - y3) * (x1 - x2)) / den
    if 0 <= t <= 1 and 0 <= u <= 1:
        return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))
    return None


def diagonal_cross(env, B, C):
    """First intersection of the B->C diagonal with the frontier polyline."""
    for a, b in zip(env, env[1:]):
        pa = (a[0], a[1]); pb = (b[0], b[1])
        hit = seg_intersect(B, C, pa, pb)
        if hit is not None:
            return hit
    return None


def metrics_for(base, rows):
    if not rows or "cells" not in base or "cost" not in base:
        return None
    env = pareto_frontier(rows)
    if len(env) < 2:
        return None
    Bx, By = base["cells"], base["cost"]
    S1y, s1_br = interp_y_at_x(env, Bx)
    S2x, s2_br = interp_x_at_y(env, By)
    C = (S2x, S1y)
    rect_area = (Bx - S2x) * (By - S1y)
    # Rectangle RELATIVE to the region's own baseline facility-cost × travel-cost.
    # denominator = (Bx·FACILITY_MIN_COSTS)·By, numerator = ((Bx−S2x)·FACILITY_MIN_COSTS)·(By−S1y)
    # ⇒ the €/facility constant cancels, leaving fractional-facility-saving ×
    # fractional-travel-saving, dimensionless in [0,1] and size-independent (the raw
    # area mostly ranks by region size; this ranks by improvement potential).
    rect_rel = ((Bx - S2x) / Bx) * ((By - S1y) / By) if Bx and By else None
    cross = diagonal_cross(env, (Bx, By), C)
    lam = None
    if cross is not None:
        lam = interp_w_at_x(env, cross[0]) * FACILITY_MIN_COSTS
    return {
        "B": [Bx, By], "S1": [Bx, S1y], "S2": [S2x, By], "corner": list(C),
        "rect_area": rect_area, "rect_rel": rect_rel,
        "cross": list(cross) if cross else None,
        "lambda_cross": lam, "s1_bracketed": s1_br, "s2_bracketed": s2_br,
        "frontier_count_range": [env[0][0], env[-1][0]],
        "n_frontier_pts": len(env),
    }


def main():
    # optional suffix: `python frontier_metrics.py interp2` → frontier_metrics_interp2.*
    suffix = sys.argv[1] if len(sys.argv) > 1 else "interp1"
    data = json.load(open(os.path.join(ROOT, "doc", "deck_data.json"), encoding="utf-8"))
    out = {}
    table = []
    for e in data:
        reg = e["region"]
        out[reg] = {}
        for fn in FUNCS:
            f = e["func"].get(fn)
            if not f:
                continue
            m = metrics_for(f["baseline"], f["rows"])
            if m is None:
                continue
            out[reg][fn] = m
            table.append((reg, fn, m))
    dest = os.path.join(ROOT, "doc", f"frontier_metrics_{suffix}.json")
    json.dump(out, open(dest, "w", encoding="utf-8"), indent=1)

    # CSV
    csv_path = os.path.join(ROOT, "doc", f"frontier_metrics_{suffix}.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as fh:
        wtr = csv.writer(fh)
        wtr.writerow(["region", "func", "B_x", "B_y", "S1_y", "S2_x",
                      "rect_area", "rect_rel", "cross_x", "cross_y", "lambda_cross",
                      "s1_bracketed", "s2_bracketed"])
        for reg, fn, m in table:
            wtr.writerow([reg, fn, m["B"][0], f'{m["B"][1]:.0f}', f'{m["S1"][1]:.0f}',
                          f'{m["S2"][0]:.1f}', f'{m["rect_area"]:.3e}',
                          f'{m["rect_rel"]:.5f}' if m["rect_rel"] is not None else "",
                          f'{m["cross"][0]:.1f}' if m["cross"] else "",
                          f'{m["cross"][1]:.0f}' if m["cross"] else "",
                          f'{m["lambda_cross"]:.1f}' if m["lambda_cross"] else "",
                          m["s1_bracketed"], m["s2_bracketed"]])

    print(f"wrote {dest}\nwrote {csv_path}\n")
    hdr = f'{"region":>12} {"fn":>4} {"B_x":>7} {"B_y":>13} {"S1_y":>13} ' \
          f'{"S2_x":>8} {"rect_area":>11} {"λ_cross":>10} {"S1?":>4} {"S2?":>4}'
    print(hdr); print("-" * len(hdr))
    for reg, fn, m in table:
        lam = f'{m["lambda_cross"]:.0f}' if m["lambda_cross"] else "—"
        print(f'{reg:>12} {fn:>4} {m["B"][0]:>7} {m["B"][1]:>13,.0f} '
              f'{m["S1"][1]:>13,.0f} {m["S2"][0]:>8.1f} {m["rect_area"]:>11.2e} '
              f'{lam:>10} {"Y" if m["s1_bracketed"] else "n":>4} '
              f'{"Y" if m["s2_bracketed"] else "n":>4}')


if __name__ == "__main__":
    main()
