## Two problems mixed into one curve; FRI is being re-swept on the current data

You are right that the LP bound must be convex — the sweep traces the lower convex envelope of a parametric LP, and any point above the chord of its neighbours is not the same LP. That is exactly what happened: **the FRI LINEAR curve on p46 is the union of two different problems.**

### What the chart is made of

`build_deck_data.py` takes an area's frontier rows from its last full sweep log and, since #52, adds the rows of the refine-only run (the S1/S2 bisection points) at λ values the sweep did not solve. For FRI those two runs are not the same LP:

| | full sweep (`logs/sweep_FRI_LINEAR.log`) | refine (`logs/refine_FRI_LINEAR.log`, 11 Sep) |
|---|---|---|
| run | **22 July**, `scratch/run_fri_protect.ps1` | 11 Sep, `run_resweep_batch.ps1 -RefineOnly` |
| candidate set | **6,765 of 17,141** (`LOCATION_SELECTION_FACTOR=3`, baseline-protected stride) | **17,133** (full) |
| solver, w_max | IPM, 0.5 | dual simplex, grid |
| existing-side OD | 327,370 rows, 6,052,430 residents | 327,285 rows, 6,048,670 residents |
| baseline | 1,584 cells, 27,489,201 | 1,583 cells, 26,839,141 |

So the grey "LB" alternates between the July subsampled frontier (higher travel at a given count, because two thirds of the candidates are missing) and the September full-set frontier — the bumps at sum_y ≈ 1,070–1,650 are the September points sitting *below* the July chord, and λ is not even monotone along the curve (0.109 → 0.115 → 0.119 → 0.123). Chart-level symptom, data-level cause.

### Why FRI in particular

FRI was the one area whose July sweep used the candidate subsample (it was the slow one then, hence IPM + factor 3 + w_max 0.5 in `run_fri_protect.ps1`). Every other area's full sweep ran on the full candidate set, so their refine points join a frontier of the same problem. And FRI's July log predates the 2 Sep landbody rebuild: the rebuilt FRI OD differs slightly (85 existing-side rows, 8 candidates), which is why the baselines differ too.

### Fix

FRI is being **fully re-swept on the current arrows with the full candidate set**, both cost functions, with the current sweep (S1/S2 pinned inside the sweep, tail stop): task `NM_fri54`, ~4–6 h. `build_deck_data.py` will then take its frontier and its S1/S2 from that sweep alone (the refine log is older), and the deck, the README numbers and the #45/#48 files follow.

### What this exposed for the other areas — your call

Checking every area the same way: **16 more areas** have a July full sweep whose OD differs slightly from the 2 Sep rebuild (Estonia, FRC, FRD, FRE, FRF, FRG, FRH, FRJ, FRK, FRL, FRM, PL2, PL4, PL5, PL6, SE1 — a few dozen to, for SE1, 3,500 OD rows out of 1.6 M). The 2 Sep diff had called them unchanged. Their refine points therefore also come from a marginally different LP; the resulting kinks are ≤ 1.5 % (FRH), invisible in the charts, and their S1/S2 are pinned on the current data. Re-sweeping them fully for a clean frontier is 32 runs, roughly 20 h on four workers with the current sweep. I have not started that; say so and I will.
