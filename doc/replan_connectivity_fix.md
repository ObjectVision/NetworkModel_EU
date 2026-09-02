# Recalculation plan — Chris's landbody-connectivity fix (commit `79cb58b`)

Scope: what must be redone after `79cb58b` ("Additional reporting elements" / *"the model
selects the largest connected network on every separate landbody"*), and in steps of
**max 24 h wall-clock each**.

---

## 1. What actually changed, and why it propagates

`cfg/main/Templates.dms` swapped the network-selection criterion:

```
- Roads_isConnected := Connectiveness/IsSterkVerbonden                      // ONE global largest SCC
+ Roads_isConnected := Connectiveness_seldomain/Strong_connectivity/
                       IsConnected_seldomain                                // largest SCC PER landbody
```

`seldomain` = `/SourceData/RegionalUnits/Country_Split`, which is
`geos_split_union_polygon(Country/geometry, id(Country))` — every country's multipolygon
split into its **separate landbodies** (mainland, Sicilia, Sardegna, Corse, Gotland,
Bornholm, the Wadden islands, …).

**Before**, only the single largest strongly-connected component in the whole study-area
road extract survived; every island subnetwork was pruned, so island cells had *no*
network at all. **After**, each landbody keeps its own largest SCC, and the ferry/road
links inside those subnetworks come back into play. Hence ITG (Sicilia + Sardegna) is
"better connected" — the ferries were already in the TomTom data, they were being thrown
away with the pruned components. No source data changed; this is purely the config rule.

This invalidates the whole chain, because the network is the first link in it:

```
road network  ->  OD matrices (existing + candidate)  ->  baseline metrics
              ->  lambda sweep  ->  S1/S2 + frontier  ->  metrics/crossings  ->  deck + exports
```

Corroborating evidence that this is material, from `doc/todo.md` §B3: clients unable to
reach any pharmacy within t_max were **DK ~11 %, ITG ~15 %, SE2 ~5 %** of residents. That
stranding was largely an *artefact* of the pruning, and it was being priced at BIG on both
sides. Those three numbers should collapse after this fix.

### 1a. Two side-changes in the same commit that need a decision before any batch run

| # | Change | Risk |
|---|---|---|
| **A** | `AllocateClientsToExistingPharmacies` now takes `Client_pharmacy_coverage` (clients restricted to countries that actually have pharmacy data) while `AllocateClientsToNewPharmacies` still takes `Client` | The **baseline** and the **LP** would run over *different client sets*, which is exactly the comparability defect `todo.md` §B3 fixed. Harmless for single-country areas (`covered_country` is all-true), but must be confirmed per area — **blocking** |
| **B** | `ModelParameters.dms`: `StudyArea_default` `'Netherlands'` → `'ITG'` | Harmless for batches (the pipelines export `STUDY_AREA`, and `StudyArea_ext` overrides), but it silently changes what an interactive GUI open loads — worth reverting or agreeing to keep |

### 1b. A circular dependency to break

Chris's new `SourceData/Locations.dms` `services_allocated` container **reads the S1/S2
open-location Arrow files** (`D:/sourcedata/.../service_access_202608/<c>_s1_logistic_open.arrow`)
— i.e. the very outputs of the sweep we are about to invalidate. Two consequences:

- Those files (delivered as issue #45 batches 1–3) become **stale** the moment we re-sweep;
  his new reporting must be re-pointed at the regenerated set.
- His list covers **21 areas**, and names files `<c>_s1_logistic_open.arrow` (lowercase),
  whereas the delivered set is 41 areas named `<region>_<S1|S2>_<LINEAR|LOGISTIC>_open.arrow`.
  **Naming/coverage must be reconciled** — cheap to fix, but it will silently read nothing
  if left as is.

---

## 2. Cost model (measured, not guessed)

From the previous full recalculation (`logs/recalc_q*.log`, 42 areas):

| Stage | Measured total | Notes |
|---|---|---|
| Network + OD rebuild (both sides) | **~1 400 s ≈ 0.4 h** for *all* 42 areas | max ~310 s (ITG), ~200 s (Portugal) |
| Lambda sweeps (LINEAR + LOGISTIC) | **~81.5 h** sequential | Poland **32.3 h**, ITF 7.5 h, ITH 6.7 h, Ireland 4.0 h, ITC 3.6 h, Austria 3.6 h, FRI 3.4 h, Denmark 2.8 h |

Two things follow:

1. **Rebuilding networks + ODs is nearly free; sweeping is the entire bill.** So the plan
   must *scope which areas actually changed* before spending sweep time.
2. **Poland (32.3 h) alone exceeds a 24 h step** and must be handled separately.

Expect the sweeps to get *more* expensive, not less: reconnected islands add reachable OD
pairs, so N grows. Budget **+20–50 %** on the affected areas. The previous run used
**7 parallel workers** (`recalc_q1..q7`), which is how 81.5 h sequential fits in wall-clock.

---

## 3. The plan (each step ≤ 24 h)

### Step 0 — De-risk the config change · **≤ 4 h** · *blocking*
1. Decide on side-changes **A** and **B** (§1a). For **A**, either revert the existing side
   to `Client` or apply `Client_pharmacy_coverage` to *both* sides — they must match.
2. Snapshot the *current* per-area network/OD statistics (link count, node count, OD rows,
   OD file size) so Step 1 has something to diff against. Cheap: read the existing
   `*_od.arrow` + `FinalSet_*.mmd` metadata.
3. End-to-end smoke test on **two** areas: **ITG** (island case, expect a big change) and
   **Luxembourg** or **FRL** (single-landbody control, expect *no* change). Confirms the
   config builds and that unaffected areas are genuinely untouched.

**Exit criterion:** ITG's network grows, the control area's network is byte-identical.

### Step 1 — Rebuild networks + ODs for all 42 areas, and diff · **≤ 12 h**
Purge `FinalSet_*` on both sides, rerun `STEPS="network1 network2 alloc"` for all areas,
then diff against the Step 0 snapshot.

> Note: `run_recalc_batch.ps1` purges only `*set_O-1km*`. Verify that pattern actually
> catches the `FinalSet_O-…mmd` **directories** for both sides — `todo.md` §A1 records that
> GeoDMS silently skips rewriting a stale `.mmd`, which would make this whole step a no-op.

**Deliverable: the affected-area table** — for each of the 42 areas, Δlinks, Δnodes, ΔOD
rows, and Δunreachable-clients. Areas with zero delta are **excluded from all re-sweeping**.
This is the decision point that sizes everything below.

### Steps 2…k — Re-sweep the affected areas · **24 h per step**
Use `run_resweep_batch.ps1` (sweep-only; networks/ODs already rebuilt in Step 1), 7 parallel
workers, areas bin-packed by *measured* cost × 1.5 so each worker's queue fits inside 24 h.

Rough sizing on the plausible affected set (islands / coastal): ITG, ITF, ITC, ITH, ITI,
Denmark, SE1, SE2, SE3, Norway, Estonia, Netherlands, Ireland, Portugal, FRM, FRD, FRG,
FRH + the PL Baltic areas ⇒ **≈ 35–45 h sequential × 1.5 ≈ 55–65 h**, which is
**~2 steps** at 7 workers. If the diff shows *every* area moved (possible — mainland areas
can also gain small peninsulas/islets), it is **~4 steps**.

### Step P — Poland, country-level · **own step, 24–36 h**
32.3 h measured, so it does **not** fit one step. Options, in order of preference:
1. **Drop it** — Poland-country is already *excluded* from the aggregate (the 7 PL NUTS-1
   are used instead, for disjointness). It only feeds its own deck page. Cheapest.
2. Raise `-Threads` / `MAX_PARALLEL` for this single run and accept ~1 step.
3. Split LINEAR and LOGISTIC into two steps (measured 28.9 h + 3.3 h — LINEAR still overruns).

**Recommend option 1** unless the group wants the country-level page refreshed.

### Step F1 — Baseline + descriptives · **≤ 6 h**
Re-run `collect_descriptives.jl` (deck pages 5–8) and the coverage-consistent baseline.
The 6 descriptive indicators and the catchment distributions are all road-network-derived,
so they move with the network. **Expect the headline "unreachable residents" figures
(DK 11 %, ITG 15 %, SE2 5 %) to drop sharply** — that is the visible payoff of the fix and
should be called out explicitly in the deck.

### Step F2 — Metrics, deck, exports · **≤ 4 h**
`build_deck_data.py` → `build_charts.py` → `frontier_metrics.py` → `build_deck.mjs` →
`merge_deck.ps1`, then `doc/export_issue48.py`. Also re-export the S1/S2 open-location
Arrow files, **using the naming/coverage Chris's `services_allocated` expects** (§1b).

### Step F3 — Re-communicate · **≤ 2 h**
- Comment on **#45** that the S1/S2 location tables are superseded, with the new zip.
- Comment on **#48** that `issue48_crossings.csv` / `issue48_sweep_results.csv` are
  superseded (the posted comment stays as the record of the pre-fix state).
- Note in the deck roadmap (p60) that the frontier is now computed on landbody-complete
  networks, and that pre-fix and post-fix numbers are **not comparable**.

---

## 4. Sequencing summary

| Step | Content | Budget |
|---|---|---|
| 0 | Config decisions (A/B) + snapshot + 2-area smoke test | ≤ 4 h |
| 1 | Rebuild networks + ODs (42 areas) + **affected-area diff** | ≤ 12 h |
| 2…k | Re-sweep affected areas, 7 workers, bin-packed | 24 h × ~2–4 |
| P | Poland country-level — *recommend dropping* | 24–36 h (optional) |
| F1 | Baseline + descriptives | ≤ 6 h |
| F2 | Metrics + deck + exports (incl. S1/S2 arrows) | ≤ 4 h |
| F3 | Re-communicate (#45, #48, deck p60) | ≤ 2 h |

**Total ~4–7 working steps**, dominated by Step 2…k, whose size is decided by Step 1.

## 5. What can be skipped

- **Areas with zero network delta** (Step 1 output) — no re-sweep, no re-export.
- **Poland country-level** — excluded from the aggregate by construction.
- **The road source data** — unchanged; no TomTom re-import needed.
- **The candidate-set rule** (≥50 inhabitants ∪ pharmacy cells) and the client definition —
  unchanged by this commit (modulo decision **A**).

---

## 6. Actual outcome (2026-09-02) — steps 0-2 executed

| step | status |
|---|---|
| 0 | **done** — GEODMS_EXE repointed to the installed 20.19.1.m (`c368a01`); ModelClient landed (`f0acbc9`); MMD read-holders adapted (`d80622d`) |
| 1 | **done** — 42/42 rebuilt (`32aca59`). 39 clean, 3 fail |
| 2 | **done for the movers** — ITG, PL8, Portugal re-swept |
| P | Poland: unchanged (+0.0%), so **no re-sweep needed** — the drop-or-run question is moot |
| F1/F2/F3 | **blocked** on Norway/SE2/SE3 |

### Which areas moved

Only **3 of 42**, exactly the ones whose baseline was dominated by the BIG penalty:

| area | candidate-OD growth | unreachable before -> after | mean_t before -> after |
|---|--:|--:|--:|
| ITG | +60% (OD rows) | 983,169 -> **591** | 22.30 -> **4.878** |
| PL8 | +27.9% | 153,669 -> **0** | 8.89 -> **4.534** |
| Portugal | +10.7% | 459,683 -> 467,704 | 8.56 -> 8.644 |

The other 39 sit between +0.1% and -0.5% and had zero unreachable residents to begin
with. SE1's -2.9% is the new candidate coverage filter, not connectivity.

**Mechanism, confirmed by the Netherlands:** Wadden islands, ferries, and 0.0% growth. A
ferry link *joins* the island to the mainland component, so those islands were never
pruned. The pruning only bit where a populated landbody reached the main component by no
modelled link at all -- hence ITG, whose study area is only two separate landbodies.

### Two open blockers

1. **Norway, SE2, SE3 fail at `alloc`** -- `FinalLinkSet/F2: Link_Node2_rel out of range
   or undefined`. Attributed by experiment to the connectivity criterion itself (reverting
   only that criterion makes Norway succeed, exit 0/51s); not the MMD split. Chris's
   algorithm, reported on #49 with a hypothesis about `rlookup` on `JnctIds` across
   multiple retained components. **The aggregate cannot be rebuilt while these fail** --
   it sums over 41 disjoint areas.
2. **Portugal is a pharmacy DATA GAP, not connectivity.** All 1,893 Portuguese pharmacies
   lie at x >= 2640 km (EPSG:3035, mainland); every unreachable client lies at x <= 1884 km
   (Azores/Madeira). The sets do not overlap, so no network fix can help. Proposed on #49:
   evaluate coverage per `Country_Split` (per landbody) instead of per country. **Not
   applied** -- it is a modelling-semantics decision that removes 467k residents from
   Portugal's denominator.

### Measurement caveat

Client populations rose in all three (ITG +25,895; PL8 +382,273; Portugal +8,021).
`total client population` counts clients present in the OD, and a larger retained network
admits more cells as OD clients, so before/after unreachable counts are not exactly
like-for-like. The direction is unambiguous; the precise deltas are not.
