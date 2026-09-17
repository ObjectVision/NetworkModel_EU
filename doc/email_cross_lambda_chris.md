**To:** Chris Jacobs
**Subject:** Cross-lambda per study area — shapefiles and map (follow-up to the csv)

Chris,

As a follow-up to the cross-lambda table of yesterday, here are the same figures as geodata, plus a map.

**Attached**

1. `cross_lambda_shapefiles_20260917.zip` — three shapefiles (EPSG:3035, NUTS 2021 boundaries at 1 : 1 M), same attribute table in each:
   - `cross_lambda_countries` — the 16 country study areas (Portugal = mainland, PT1; the Azores and Madeira are outside the model);
   - `cross_lambda_nuts1` — the 28 NUTS-1 regions of France, Italy, Sweden and Poland;
   - `cross_lambda_regions` — all 44 rows of the csv in one file (countries + NUTS-1), handy for a single map.
2. `cross_lambda_map_LINEAR.png` — the thematic map of the LINEAR cross-lambda over all 44 areas, green (low λ) → yellow → red (high λ), rendered with GeoDMS from `cross_lambda_regions`.
3. `cross_lambda_table.csv` — the table again, for reference.

**The attribute table** (shapefile field names are limited to 10 characters; the csv has the long names):

| field | csv column | meaning |
|---|---|---|
| area, name, level, country | area, name, level, country | study area code, its name, `country` / `NUTS-1`, and the country |
| NUTS_ID | — | NUTS 2021 code of the polygon |
| ARCHETYPE, ARCH_NAME | oecd_archetype, archetype_name | OECD policy archetype: 1 rule-of-law-anchored, 2 consensual-pluralist, 3 public-interest majoritarian |
| residents, LOC_TODAY, RES_PERLOC, MEAN_T_MIN | residents, pharmacy_locations_today, residents_per_location, mean_travel_min_today | today's network in the model's scope: residents, 1-km² cells with ≥ 1 pharmacy, residents per such location, population-weighted road travel time (min) to the nearest pharmacy |
| XLAM_LIN, W_LIN | cross_lambda_eur_linear, w_cross_linear | cross-lambda under the LINEAR cost, in EUR via the placeholder 100 000 per location, and as the model's own w (λ = w · 100 000) |
| XLOC_LIN, XLOCP_LIN, XTRAV_LIN | crossing_locations_linear, crossing_locations_change_pct_linear, crossing_travel_change_pct_linear | the crossing point: locations, and locations and travel relative to today (%) |
| S1TRAV_LIN, S2LOC_LIN | s1_travel_change_pct_linear, s2_locations_change_pct_linear | the rectangle's ends: travel saved at today's count (S1), locations saved at today's travel (S2) |
| XLAM_LOG … S2LOC_LOG | the `_logistic` columns | the same under the LOGISTIC cost (XCOST_LOG = the dimensionless logistic cost change); these live on their own λ scale (≈ 60–630 EUR) and compare only among themselves |

**How to read cross-lambda.** B is today's network (locations, travel); S1 is the frontier point with today's number of locations, S2 the one with today's travel; the crossing is where the diagonal from B to the far corner (S2's locations, S1's travel) meets the frontier — the balanced improvement — and cross-lambda is the sweep's λ there. In EUR only through the placeholder of 100 000 per location; the ranking of areas does not depend on it.

**What the map shows.** The Nordic areas sit at 32 000–45 000 € (Denmark, Norway, the three Swedish NUTS-1), the Netherlands, Finland, Austria and Slovenia at 20 000–30 000, most of France, Poland and the Baltics at 10 000–15 000, and the Italian regions and Belgium below 10 000. Cross-lambda moves with residents per location as much as with policy (a sparse network makes each location buy a lot of travel), so read it next to RES_PERLOC — and with the caveat that Belgium's low value is the inheritance of its 1973 establishment moratorium rather than a revealed preference.

Best,
Maarten

---
*Generated from `cfg/cross_lambda_map.dms` (GeoDMS 20.19.1) on `doc/cross_lambda_table.csv`; map composed by `doc/cross_lambda_map_figure.py`.*
