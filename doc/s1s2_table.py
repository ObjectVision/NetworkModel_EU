# The per-area S1/S2 table of the deck (build_deck.mjs lambdaTableSlide), as text: the
# same interpolation between adjacent w-sorted sweep rows, LINEAR and LOGISTIC, so the
# README's per-country table and an issue comment can be filled from one source.
#   PYTHONIOENCODING=utf-8 python s1s2_table.py [REGION ...]     (default: every area)
import json, math, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FMIN = 100000  # FACILITY_MIN_COSTS: λ = w · FMIN, a placeholder


def interp(rows, key, target, out):
    rs = sorted((r for r in rows if r["w"] > 0), key=lambda r: r["w"])
    if len(rs) < 2 or target is None:
        return None
    for a, b in zip(rs, rs[1:]):
        xa, xb = a.get(key), b.get(key)
        if xa is None or xb is None or xa == xb:
            continue
        if min(xa, xb) <= target <= max(xa, xb):
            f = (target - xa) / (xb - xa)
            if out == "w":
                return math.exp(math.log(a["w"]) + f * (math.log(b["w"]) - math.log(a["w"]))) * FMIN
            if a.get(out) is None or b.get(out) is None:
                return None
            return a[out] + f * (b[out] - a[out])
    return None


def sgn(d):
    return "−" if d < 0 else "+"


def fmt_min(d):
    return f"{abs(d) / 1e6:.1f} M" if abs(d) >= 1e6 else f"{abs(d) / 1e3:.0f} k"


def pct(v, base):
    return "—" if v is None or not base else f"{sgn(v - base)}{abs(v / base - 1) * 100:.1f} %"


def fl(v):
    return "—" if v is None else f"{round(v):,}".replace(",", " ")


def main():
    data = json.load(open(os.path.join(ROOT, "doc", "deck_data.json"), encoding="utf-8"))
    want = set(sys.argv[1:])
    print("| area | today | S1 · Δ travel (lin) | S2 · Δ locations (lin) | S1 · Δ cost · Δ mean t (log) | S2 · Δ locations (log) | λ S1 lin | λ S2 lin | λ S1 log | λ S2 log |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for e in data:
        if want and e["region"] not in want:
            continue
        L = e["func"].get("LINEAR"); G = e["func"].get("LOGISTIC")
        if not L or not L.get("baseline"):
            continue
        cells, cost = L["baseline"]["cells"], L["baseline"]["cost"]
        t = interp(L["rows"], "n_open", cells, "multi")
        s1lin = "—" if t is None else f"{sgn(t - cost)}{fmt_min(t - cost)} min · {pct(t, cost)}"
        n = interp(L["rows"], "multi", cost, "n_open")
        s2lin = "—" if n is None else f"{sgn(n - cells)}{fl(abs(n - cells))} · {pct(n, cells)}"
        if G and G.get("baseline"):
            gc, gcost = G["baseline"]["cells"], G["baseline"]["cost"]
            tg = interp(G["rows"], "n_open", gc, "multi"); mg = interp(G["rows"], "n_open", gc, "mean_t")
            s1log = "—" if tg is None else pct(tg, gcost) + ("" if mg is None or G["baseline"].get("mean_t") is None
                                                            else f" · {sgn(mg - G['baseline']['mean_t'])}{abs(mg - G['baseline']['mean_t']):.1f} min")
            ng = interp(G["rows"], "multi", gcost, "n_open")
            s2log = "—" if ng is None else f"{sgn(ng - gc)}{fl(abs(ng - gc))} · {pct(ng, gc)}"
            l1g = fl(interp(G["rows"], "sum_y", gc, "w")); l2g = fl(interp(G["rows"], "multi", gcost, "w"))
        else:
            s1log = s2log = l1g = l2g = "—"
        print(f"| {e['name']} ({e['region']}) | {fl(cells)} | {s1lin} | {s2lin} | {s1log} | {s2log} | "
              f"{fl(interp(L['rows'], 'sum_y', cells, 'w'))} | {fl(interp(L['rows'], 'multi', cost, 'w'))} | {l1g} | {l2g} |")


if __name__ == "__main__":
    main()
