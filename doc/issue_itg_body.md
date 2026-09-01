## Problem: ITG's baseline travel cost is an extreme outlier — and it is mostly an artefact

ITG (Sicilia + Sardegna) has by far the worst baseline of all 42 study areas:

| | ITG | next worst | typical |
|---|--:|--:|--:|
| baseline mean travel time | **22.30 min** | 9.46 min (SE3) | 2–5 min |
| baseline travel cost / facility | **€157,742** | €80,549 (Denmark) | €10–50k |
| `rect_rel` (relative improvement potential, LINEAR) | **0.384** | 0.320 (Portugal) | 0.005–0.15 |

Taken at face value this says Sicily and Sardinia have catastrophic pharmacy access and
the largest optimisation headroom in the study. **They do not.** The number is dominated
by clients that the model cannot route to *any* pharmacy, which soft coverage prices at
`BIG = c(120 min)`.

### Decomposition (from `logs/sweep_ITG_LINEAR.log`)

```
total client population:  6,253,866
unreachable clients:      1,859 cells / 983,169 residents (15.7%) priced at BIG=119.9638
total travel cost(c):     1.39443726e8
mean travel time (min):   22.2972
```

Splitting that total:

| component | value | share |
|---|--:|--:|
| BIG penalty on unreachable residents (983,169 × 119.96) | 117,944,689 | **84.6 %** |
| actual travel of the 5,270,697 served residents | 21,499,037 | 15.4 % |

⇒ **the served population of ITG travels 4.08 min on average** — entirely normal, right
next to ITI (4.18), Czechia (4.23) and Austria (4.82). Roughly **85 % of ITG's baseline
"travel cost" is not travel**; it is the penalty for residents the network cannot reach.

This is self-consistent with the optimisation: at **S1** (same facility count, optimally
relocated) the reported mean drops from 22.30 to **4.62 min**. The optimiser is not
achieving a 5× improvement in accessibility — it is mostly reshuffling facilities so that
fewer people fall into the unreachable bucket.

### ITG is the worst case, but not the only one

Same decomposition across all areas (LINEAR):

| area | population | unreachable | % | baseline mean_t | BIG share of cost | served mean_t |
|---|--:|--:|--:|--:|--:|--:|
| **ITG** | 6,253,866 | 983,169 | 15.7 % | 22.30 | **84.6 %** | 4.08 |
| Portugal | 10,300,382 | 459,683 | 4.5 % | 8.56 | **62.6 %** | 3.35 |
| PL8 | 4,674,751 | 153,669 | 3.3 % | 8.89 | **44.4 %** | 5.11 |
| SE2 | 4,398,063 | 32,226 | 0.7 % | 8.05 | 10.9 % | 7.23 |
| Norway | 5,110,060 | 3,696 | 0.1 % | 7.99 | 1.1 % | 7.91 |
| *(all other areas)* | | ≈0 | 0 % | 1.9–5.6 | ≈0 % | = mean_t |

Portugal's 459,683 unreachable residents match the combined population of the **Azores and
Madeira** almost exactly — separate landbodies, same mechanism. PL8's 153,669 needs a
separate look, since Poland has no comparable islands; it may be a genuinely disconnected
road component rather than an island.

**Consequence:** the ranked "improvement potential" lists (deck p64–p69) and the
`rect_rel` ordering are currently ranking *network-coverage artefacts* alongside real
policy headroom. ITG tops the LINEAR ranking for the wrong reason.

---

## Proposed solution: the landbody-connectivity fix Chris added in 79cb58b

Commit **`79cb58b`** ("Additional reporting elements") on branch `ServiceAccess` already
contains what looks like the right fix. In `cfg/main/Templates.dms` the network-selection
criterion changed:

```diff
- attribute<bool> Roads_isConnected (…) := …/Connectiveness/IsSterkVerbonden;
+ attribute<bool> Roads_isConnected (…) := …/Connectiveness_seldomain/
+                                          Strong_connectivity/IsConnected_seldomain;
```

with a new template `Check_Connectiveness_T_seldomain`, parameterised on
`seldomain = /SourceData/RegionalUnits/Country_Split`, which is

```
Country_Split := geos_split_union_polygon(Country/geometry, id(Country))
```

i.e. each country's multipolygon split into its **separate landbodies**.

**Before:** only the single largest strongly-connected component in the whole study-area
road extract survived; every island subnetwork was pruned. For ITG that is fatal — Sicilia
and Sardegna are two *separate* landbodies, so at most one of them could ever be kept, and
the smaller islands never.

**After:** the largest SCC is selected **per landbody** (`IsConnected_seldomain` via
`Networks_per_seldomain` / `Main_in_seldomain`), so each island keeps its own road network,
and the ferry links inside those components come back into play.

Worth stressing: **no source data changed.** The ferry and road links were already in the
TomTom `NW2021_SP_streets_subset` extract — they were being discarded together with the
components that got pruned. This is purely the selection rule, which is why the fix is
cheap and why no re-import is needed.

---

## What this invalidates

The network is the first link in the chain, so the change propagates all the way through:

```
road network → OD matrices (existing + candidate) → baseline metrics
             → λ-sweep → S1/S2 + frontier → metrics/crossings → deck + exports
```

Concretely: the descriptives (deck p5–8), every sweep, S1/S2, the frontier and its
projections (p62/63), the ranked improvement lists (p64–69), the aggregate, the S1/S2
open-location Arrow files delivered in #45, and the CSVs delivered in #48.

**Pre-fix and post-fix numbers will not be comparable** and should not be mixed in one
chart or table.

---

## Recalculation plan (steps of ≤ 24 h)

Full version committed as `doc/replan_connectivity_fix.md`. Sizing is anchored on
**measured** runtimes from the previous full recalculation (`logs/recalc_q*.log`):

| stage | measured, all 42 areas |
|---|--:|
| network + OD rebuild (both sides) | **~1,400 s ≈ 0.4 h** |
| λ-sweeps (LINEAR + LOGISTIC) | **~81.5 h** sequential |

Rebuilding networks is nearly free; the sweeps are the entire bill. So the plan spends one
cheap step rebuilding **all** networks and **diffing** them, to decide which areas actually
moved, before spending any sweep time.

| step | content | budget |
|---|---|--:|
| **0** | Config decisions (see below) + snapshot current network/OD stats + end-to-end smoke test on **ITG** (island case) and a single-landbody control (expect *no* change) | ≤ 4 h |
| **1** | Purge `FinalSet_*`, rebuild networks + ODs for all 42 areas, diff vs. snapshot → **the affected-area table** (Δlinks, Δnodes, ΔOD rows, Δunreachable). Areas with zero delta are excluded from re-sweeping. **This is the decision point that sizes everything below.** | ≤ 12 h |
| **2…k** | Re-sweep affected areas via `run_resweep_batch.ps1`, 7 parallel workers, bin-packed on measured cost × 1.5 (reconnected islands add OD rows, so expect +20–50 %) | 24 h × ~2–4 |
| **P** | Poland country-level: 32.3 h measured, does **not** fit one step. **Recommend dropping** — it is already excluded from the aggregate (the 7 PL NUTS-1 are used, for disjointness) and only feeds its own deck page | optional |
| **F1** | Baseline + descriptives (p5–8). Expect the unreachable-resident figures to collapse — that is the visible payoff and should be called out explicitly | ≤ 6 h |
| **F2** | `build_deck_data.py` → `build_charts.py` → `frontier_metrics.py` → `build_deck.mjs` → `merge_deck.ps1`, then `doc/export_issue48.py`; re-export the S1/S2 Arrow files | ≤ 4 h |
| **F3** | Re-communicate: supersede #45 and #48, and note on deck p60 that the frontier now runs on landbody-complete networks | ≤ 2 h |

⚠️ In step 1, verify that `run_recalc_batch.ps1`'s purge pattern (`*set_O-1km*`) really
catches the `FinalSet_*.mmd` **directories** on both sides. `doc/todo.md` §A1 records that
GeoDMS silently skips rewriting a stale `.mmd`, which would make the whole step a no-op.

---

## Decisions needed before any batch run

1. **Blocking — baseline and LP must run over the SAME client set.** `79cb58b` switched
   `AllocateClientsToExistingPharmacies` (the baseline) to `Client_pharmacy_coverage`
   (`Analyses.dms:115`), while `AllocateClientsToNewPharmacies` (the LP) still uses
   `Client` (`:123`). That re-opens the comparability defect fixed in `doc/todo.md` §B3.

   It is also more than a comparability issue. The same commit correctly generalised the
   template's `attribute<Client> client_rel` → `attribute<Org> client_rel`, so `client_rel`
   now follows whichever `Org` was passed. But the descriptives still hard-code `Client`:

   ```
   Analyses.dms:42  attribute<…/Allocation> best_od                     (Client) :=
                        min_index(…/Allocation/impedance, …/Allocation/client_rel);
   Analyses.dms:43  attribute<cells>        nearest_cell_by_road_client (Client) := …
   Analyses.dms:44  attribute<Client>       grid_client_rel             (grid)   := …
   ```

   These aggregate over the **existing** allocation, whose `client_rel` is now in
   `Client_pharmacy_coverage`, but they are declared over `Client`. Note this is **not**
   automatically a no-op for single-country areas: a client cell whose `Country_rel` is
   null (coastal/border cells that fall outside the country polygon) drops out of
   `Client_pharmacy_coverage`, so the two units can differ in count even for ITG — and
   where the counts happen to match, they are still distinct units.

   **Proposed fix — one client unit, used everywhere.** Introduce a single alias and route
   both allocations and the descriptives through it, so the two can never drift apart again:

   ```
   unit<uint32> ModelClient := Client_pharmacy_coverage;   // single source of truth
   ```

   then `Analyses.dms:115` and `:123` both take `ModelClient`, and `:42–44` are retyped
   from `Client` to `ModelClient`. The s1/s2 reporting containers (`:146`, `:153`) should
   follow too if their travel times are to be compared with the baseline.

   The alternative — reverting `:115` to `Client` — restores the pre-commit behaviour with
   zero risk, but drops the intent of excluding countries that have no pharmacy data.
   **Recommendation: `ModelClient = Client_pharmacy_coverage` on both sides.**
   @cjacobscrisioni — agreed, or was the coverage filter meant for multi-country areas only?

2. **Circular dependency.** The new `services_allocated` container reads the S1/S2 Arrow
   files (`service_access_202608/<c>_s1_logistic_open.arrow`) that this re-sweep will
   invalidate. It also lists **21** areas with a lowercase naming scheme, whereas the
   delivered set is **41** areas named `<region>_<S1|S2>_<LINEAR|LOGISTIC>_open.arrow` — as
   written it will silently read nothing. Naming and coverage need reconciling in step F2.

3. **Minor.** `ModelParameters.dms` `StudyArea_default` is now `'ITG'`. Harmless for
   batches (the pipelines export `STUDY_AREA`), but it changes what an interactive GUI open
   loads — revert, or keep deliberately?

4. **Reporting.** Once stranding is largely gone, should the ranked improvement lists still
   report the BIG-penalty share per area, so a coverage artefact can never again masquerade
   as policy headroom?

cc @cjacobscrisioni
