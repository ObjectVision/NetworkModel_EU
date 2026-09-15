## Fixed — FRI re-swept on the full candidate set; the bound is one problem again

FRI was fully re-swept on the current arrows with the full candidate set (17,133), both cost functions, one worker: LINEAR 2.2 h, LOGISTIC 1.9 h. Both scenarios pinned inside the sweep:

| | S1 — today's 1,583 cells | S2 — today's travel |
|---|---|---|
| LINEAR | w = 0.088289, Σy = 1,582.1 | w = 0.12419, travel +0.15 % |
| LOGISTIC | w = 0.00093708, Σy = 1,581.1 | w = 0.0014768, travel −0.12 % |

The LINEAR lower bound has no point above the chord of its neighbours any more (22 rows; λ and Σy monotone). `build_deck_data.py` takes FRI's frontier and its S1/S2 from this sweep alone — the July subsampled rows and the September refine points are out of the curve.

**What moved.** FRI's S2 (same travel, fewer locations) read −232 locations (−14.7 %) off the mixed curve and reads **−364 (−23.0 %)** off the clean one: the July subsample, missing two thirds of the candidates, had a frontier too far from the axis, and the interpolated S2 sat on it. S1 is unchanged (−3.8 M min, −14.2 %, λ 8,824); λ at S2 goes 10,268 → 12,369. LOGISTIC is unchanged (−428 locations, −27.0 %). In the S2 column FRI leaves the bottom of the French regions (−14.7 %, beside Île-de-France's −15.1 %) for the pack (the other eleven sit at −19 to −24 %, Corse −30 %). Deck p46 and the tables on p62–63, README and the #45/#48 files follow in one commit once the tail run below lands (216ac77's zips will be superseded by `s1s2_open_locations_20260915.zip` and `issue48_frontier_data_20260915.zip`).

### Two things the check turned up

**The subsample is history, not just for FRI.** The README said "the largest areas are candidate-subsampled". Checked against the candidate arrows: every one of the 88 current sweeps runs on the full candidate set (M = the arrow's count in all of them). The July PL8 subsampled sweep was superseded on 2 Sep, FRI's now. README and the roadmap slide say so; the knob stays as a scale test.

**A tail stop can cap the aggregate.** FRI LOGISTIC's sweep stopped at w = 0.002: the next grid point, 0.005, did not solve within the hour from the post-bisection basis (925k iterations, still converging). The aggregate frontier is the sum over areas on the w-range every area covers, so FRI capped it at 0.002 — just below the aggregate's own S2 (w ≈ 0.00212), which then did not bracket. A tail-only mode now continues a finished sweep's grid with a longer limit and without touching its S1/S2 (`run_resweep_batch.ps1 -TailFrom 0.001 -TailTo 0.005 -TailLimit 14400`; rows in `logs/tail_<area>_<FUNC>.log`, merged by `build_deck_data.py`). Running now for FRI LOGISTIC (w = 0.001 from cold, then 0.002 and 0.005 at 4 h each); the result goes into this comment.

### Not in the chart: the rows' mean travel time

While rebuilding the deck data: a sweep row's `mean_t` counted a stranded client (no open facility in its choice set) at 0 min, the baseline's at the 120-min cutoff — `cost_c`, which selects S1/S2, always priced both at BIG, so the pinning is untouched, but the "Δ mean t" beside the LOGISTIC S1 column compared two conventions. Fixed in `lp_run.jl`; for the existing logs `doc/recompute_mean_t.jl` recomputes every rounded row and S1/S2 from its per-λ traveltime arrow (2,289 rows; 162 whose arrow a later run overwrote keep the logged value). The effect is bounded by the stranded population: at most +0.17 min on an S1/S2 (SE3 LOGISTIC S2), 16 of 176 scenario values move by more than 0.01 min; the LOGISTIC S1 "Δ mean t" for SE2 goes −1.6 → −1.5 min, nothing else in the tables changes at one decimal.

### The other 16 areas

Unchanged from the previous comment: Estonia, FRC–FRM (except FRI), PL2/4/5/6 and SE1 have July sweeps on arrows that differ slightly from the 2 Sep rebuild (kinks ≤ 1.5 %, S1/S2 pinned on the current data). A clean re-sweep is 32 runs, ~20 h on four workers. Not started.
