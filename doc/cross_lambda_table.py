# One table of the cross-lambda for every study area -- 19 countries (France, Italy, Sweden and
# Poland as the sums of their NUTS-1 regions, build_deck_data.py AGGREGATES) and the 28 NUTS-1
# regions -- both travel-cost functions side by side, for mailing. The direct country-level
# Poland sweep is left out (its aggregate replaces it).
#   PYTHONIOENCODING=utf-8 python cross_lambda_table.py   -> doc/cross_lambda_table.csv
#
# Cross-lambda (frontier_metrics.py, Lewis's "cross-lambda", his p21): B = today's network
# (locations, travel); S1 = the frontier point with today's count, S2 = the one with today's
# travel; C = (S2 locations, S1 travel) is the far corner of the improvement rectangle; the
# crossing is where the diagonal B -> C meets the frontier (the balanced improvement), and
# cross-lambda is the lambda of the sweep there. In EUR only through the placeholder
# EUR 100,000 per location (lambda = w * 100,000); w itself is the model's number.
#
# Inputs: doc/issue48_crossings.csv (export_issue48.py: crossings per area and function),
# doc/deck_data.json (baseline population = LINEAR cost / mean_t, as cross_lambda_scatter.py),
# doc/policy_typology.csv (OECD archetype per country), build_deck_data.NICE (names).
import csv, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from build_deck_data import NICE, ORDER

COUNTRY_OF = {"FR": "France", "IT": "Italy", "SE": "Sweden", "PL": "Poland"}
COUNTRIES = {"Netherlands", "Luxembourg", "Estonia", "Latvia", "Slovenia", "Lithuania", "Ireland", "Norway",
             "Denmark", "Austria", "Portugal", "Czechia", "Belgium", "Poland", "Hungary", "Finland",
             "France", "Italy", "Sweden"}


def country_of(reg):
    return reg if reg in COUNTRIES else COUNTRY_OF[reg[:2]]


cross = {}
for r in csv.DictReader(open(os.path.join(HERE, "issue48_crossings.csv"), encoding="utf-8")):
    cross[(r["region"], r["func"])] = r
typ = {r["region"]: r for r in csv.DictReader(open(os.path.join(HERE, "policy_typology.csv"), encoding="utf-8"))}
deck = {e["region"]: e for e in json.load(open(os.path.join(HERE, "deck_data.json"), encoding="utf-8"))}


def num(x, nd=0):
    if x in ("", None):
        return ""
    v = float(x)
    return f"{v:.{nd}f}" if nd else f"{round(v):d}"


rows = []
for reg in ORDER:
    L, G = cross.get((reg, "LINEAR")), cross.get((reg, "LOGISTIC"))
    if not L or not G or reg == "Poland_sweep":
        continue
    agg = deck[reg].get("aggregated_from")
    b = deck[reg]["func"]["LINEAR"]["baseline"]
    pop = b["cost"] / b["mean_t"] if b.get("mean_t") else None
    ctry = country_of(reg)
    t = typ.get(reg) or typ.get(ctry) or {}
    cells = int(L["B_facilities"])
    rows.append({
        "area": reg,
        "name": NICE.get(reg, (reg, reg))[1],
        "level": ("country (NUTS-1 aggregate)" if agg else "country") if reg in COUNTRIES else "NUTS-1",
        "country": ctry,
        "oecd_archetype": t.get("archetype", ""),
        "archetype_name": t.get("archetype_name", ""),
        "residents": num(pop),
        "pharmacy_locations_today": cells,
        "residents_per_location": num(pop / cells) if pop else "",
        "mean_travel_min_today": num(b.get("mean_t"), 2),
        # LINEAR
        "cross_lambda_eur_linear": num(L["lambda_cross_eur"]),
        "w_cross_linear": num(L["w_cross"], 5),
        "crossing_locations_linear": num(L["cross_facilities"]),
        "crossing_travel_change_pct_linear": num((float(L["cross_travelcost"]) / float(L["B_travelcost"]) - 1) * 100, 1),
        "crossing_locations_change_pct_linear": num((float(L["cross_facilities"]) / cells - 1) * 100, 1),
        "s1_travel_change_pct_linear": num((float(L["S1_travelcost"]) / float(L["B_travelcost"]) - 1) * 100, 1),
        "s2_locations_change_pct_linear": num((float(L["S2_facilities"]) / cells - 1) * 100, 1),
        # LOGISTIC
        "cross_lambda_eur_logistic": num(G["lambda_cross_eur"]),
        "w_cross_logistic": num(G["w_cross"], 6),
        "crossing_locations_logistic": num(G["cross_facilities"]),
        "crossing_cost_change_pct_logistic": num((float(G["cross_travelcost"]) / float(G["B_travelcost"]) - 1) * 100, 1),
        "crossing_locations_change_pct_logistic": num((float(G["cross_facilities"]) / cells - 1) * 100, 1),
        "s1_cost_change_pct_logistic": num((float(G["S1_travelcost"]) / float(G["B_travelcost"]) - 1) * 100, 1),
        "s2_locations_change_pct_logistic": num((float(G["S2_facilities"]) / cells - 1) * 100, 1),
    })

out = os.path.join(HERE, "cross_lambda_table.csv")
with open(out, "w", encoding="utf-8-sig", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)
print(f"wrote {out}: {len(rows)} rows ({sum(r['level'].startswith('country') for r in rows)} countries, of which "
      f"{sum('aggregate' in r['level'] for r in rows)} summed from their NUTS-1 regions; {sum(r['level'] == 'NUTS-1' for r in rows)} NUTS-1 regions)")
