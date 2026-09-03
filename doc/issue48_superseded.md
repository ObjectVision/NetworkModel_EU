## Superseded — the frontier-projection data has been regenerated

The CSVs delivered in [the comment above](#issuecomment-5479662425) were computed before
two method changes landed (#49, #50). **Both files are stale.** The replacement is the
attached `issue48_frontier_data_postfix.zip`, same two files and same columns.

### What changed

1. **Landbody-complete networks** — the largest strongly-connected road network is now kept
   per *separate landbody*, so island networks (and their ferry links) are no longer pruned.
2. **Region exclusion** — a NUTS region where >50 % of inhabitant locations cannot reach any
   pharmacy is dropped entirely, population *and* candidates. Removes the Azores and Madeira
   from Portugal, which hold population but no pharmacy in the source data.

Five areas moved; the other 37 are unchanged.

| area | baseline travel cost | baseline mean_t |
|---|--:|--:|
| ITG | 139,443,726 → **30,632,858** | 22.30 → **4.88** |
| Portugal | 88,146,125 → **34,176,605** | 8.56 → **3.47** |
| PL8 | 41,552,629 → **22,928,948** | 8.89 → **4.53** |
| SE2 | 35,418,726 → **32,421,787** | 8.05 → **7.36** |
| SE3 | 16,449,419 → 16,444,582 | 9.46 → 9.48 |
| **AGGREGATE** | 1,214,475,267 → **1,030,069,422** | −15 % |

Aggregate diagonal crossing: travel 969,433,105 → **882,495,639**, λ_cross €20,022 → **€17,150**
(LINEAR); λ_cross €222 → **€194** (LOGISTIC).

### What this means for the ranked lists

The improvement-potential ranking was partly ranking *coverage artefacts*. It no longer is:

| # | LINEAR before | LINEAR now |
|---|---|---|
| 1 | ITG 0.3837 | **ITF 0.2679** |
| 2 | Portugal 0.3204 | ITG 0.2610 |
| 3 | ITF 0.2679 | ITI 0.1294 |
| 4 | PL8 0.1470 | ITC 0.1282 |

Portugal and PL8 leave the top 8 entirely and ITG drops to #2, while **ITF takes #1 with an
unchanged 0.2679** — it was never inflated, merely outranked by artefacts. Same pattern for
LOGISTIC.

### Unchanged

Columns, units and method are identical, so anything built on the previous files keeps
working. All **86 crossings are still genuinely bracketed** (no clamped values).
`issue48_sweep_results.csv` now has 1,530 rows rather than 1,626 — the swept λ-grids differ
slightly per area after the re-sweep.

**Pre- and post-fix numbers must not be mixed in one chart or table.**

Regenerate with `python doc/export_issue48.py`.
