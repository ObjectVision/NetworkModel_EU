# Modelling topics — status vs the team email thread

Source: the "How to assess the current distribution" thread (Lewis / Bernhard / Ana /
Chris / Maarten, 13 May – Jun 2026). Staging doc for later inclusion in the deck.

**Headline shift.** The agreed plan is a **four-option ladder (A→D) per scenario**, policy
"start at A, only step down". The **facility cost function is Option D — the fallback**;
the primary mechanisms are **max-catchment caps** and **min-catchment thresholds**, with
**urban pharmacies optionally held fixed**. The current code and the whole `lambda_sweep5`
deck are **Option D** (the λ-sweep over the linear cost) — i.e. today the deck presents the
fallback method as the headline.

---

## Implementing (now)

| Topic | Agreed direction | Current status | Action |
|---|---|---|---|
| **A/B scenario options** | A→D ladder per S1/S2/S3; build A/B first, D = fallback. S1: A) cap + multiple/cell → B) combine + cap + one/cell → C) fix urban, model rest → D) cost fn. S2: A) min-catchment + cap (global) → B) non-urban only → C) cost fn | Only the cost-fn sweep (D); S1/S2/S3 are λ-targets | Build **S1-A/B** and **S2-A/B** as the primary path; demote the sweep to D |
| **Max cap** | Max catchment-population per facility, from the observed distribution (95th pct or max). Core to S1-A and S2-A | none (only a 60-min travel cap + BIG stranding price) | Add a **max-catchment cap** constraint |
| **Min cap (threshold)** | Absolute minimum catchment for S2; test several values | soft `min_clients`/`deficit` penalty exists in `run_scenario`, **not used by the sweep**, tied to λ | Convert to an **absolute hard threshold**; wire into S2; sweep multiple values |
| **One vs multiple per cell** | A = allow multiple pharmacies per cell; B = combine within-cell first, then one per cell | candidates ≈ one per cell; baseline combines 1 992→1 617 | Support **both variants** (multiple-per-cell A, combine-then-one B) |
| *cap sources / scoping (notes)* | Pharmacist cap (Ana): #pharmacists as a natural ceiling, demand-to-pharmacist ratio. Cap/threshold **pooled across countries** by default, per-country reported alongside | n/a | Consider pharmacist-based cap; report S1-A **share of facilities at/near the cap** as the A→B trigger |

**Descriptive metrics** (Lewis, 22 May) — needed first; they set the caps/thresholds. Per country:

1. Number of pharmacies
2. Number of residents per pharmacy
3. Number of grid cells with more than one pharmacy
4. Average and maximum number of pharmacies in cells with more than one pharmacy
5. Distribution of catchment-area population size of existing pharmacies — min, max, p10, p25, p50, p75, p90, average
6. Same distribution, with all pharmacies in a single grid cell combined

*Catchment rule:* assign each user to the closest pharmacy; split evenly if equidistant; verify it
does not create very small city catchments. *Prerequisite fix — DONE:* `baseline_metrics` now
prices unreachable clients at the same BIG (120 min linear / 1.0 logistic) as the sweep
(coverage-consistent baseline, soft coverage, 10–12 Jul), so these metrics and any
distance-to-Pareto measure are well-defined.

---

## Later

| Topic | Agreed direction | Current status | Action |
|---|---|---|---|
| **Urban / non-urban scoping** | Options B/C: model only non-urban pharmacies, hold urban locations fixed (city markets have competition / space / variety factors we don't model) | no urban indicator at all | Add a **per-facility urban/non-urban flag**; minimise count over the non-urban subset only |
| **Counterfactuals** | −10 % facilities / population (easy); optimally replace a known X % (easy); let the model choose which X to close for minimal travel increase (hard) | not built | Implement after the baseline scenarios |
| **Update candidate set** | Restrict candidates to **settlement** cells (urban centres, towns, villages) **if** almost all existing pharmacies are in settlements | inhabited-cell candidates (NewPharmacies) | Verify existing ⊂ settlements, then restrict |

---

## To be fine-tuned

| Topic | Agreed direction | Current status | Action |
|---|---|---|---|
| **Split assignment** | nearest-open; even split when equidistant; central only as fallback | nearest-open only | Add even-split **only if** nearest produces pathological micro-catchments (de-prioritised) |
| **Travel cost functions** | linear · quadratic/exponential · flat-then-linear · logistic (preferred, kinks ~5 & ~45 min). Quadratic risks a pharmacy next to one island household | LINEAR + LOGISTIC (adapted logit, midpoint 25 / scale 10 — retuned to the ~5/~45-min kinks, all areas re-swept); quadratic & piecewise defined but unused | add **flat-then-linear**; test/sweep logit-parameter sensitivity |
| **Facility cost parameters** | calibrate real pharmacy `a,b` (schools: 99 699 + 3 277.5x); ?fixed cost depends on <6-y care; λ should scale **travel** cost & be communicable (person-minutes / value-per-user, Chris); keep facility cost concave + a *separate* convex congestion penalty (only under D) | a = 100 000, b = 3 333 placeholders; λ scales facility fixed cost | Calibrate `a,b`; re-express λ; separate concave-cost vs convex-congestion — all **Option D only** |
| **S3** | balance facilities-per-capita against mean travel **without** a cost function; go beyond the A–B segment (countries can sit close together) | only the cost-fn sweep | Build a **cost-function-free S3**; widen the sweep to allow **higher facility OR travel cost than baseline** |
