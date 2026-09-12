## Measured, and a wider defect than the five areas — fixed in 29fcf7f, rerun in progress

### How far off the exported S1/S2 files were

Over the 74 area×function sweeps (42 areas, LINEAR + LOGISTIC; `deck_data.json` `scen` rows, which are exactly what the sweep exported to the `S1`/`S2` folders):

| | S1 file: facility count vs today | S2 file: travel vs today |
|---|---|---|
| median error | 5.9 % | 0.31 % |
| off by > 5 % | 41 of 74 | 14 of 74 (all LINEAR) |
| off by > 10 % | 22 of 74 | 10 of 74 |
| worst | Norway LOGISTIC −27.5 %, SE2 LINEAR −31.6 %, SE3 LINEAR +26.4 % | FRF LINEAR +16.9 %, FRK −15.3 %, FRH −14.5 %, FRD +13.9 %, FRJ −13.5 %, FRC −12.0 % |
| S1 = S2, same point | FRC, FRH, FRJ, FRK, SE2 (LINEAR) — as reported | |

So the issue's framing was too narrow in two ways. **S1 is off by more than 10 % in 22 sweeps**, not only in the five where it coincides with S2: the 1-2-5 grid is a factor 2–2.5 in λ per step and the count moves ~30 % per step, so "nearest grid point" is a coarse read anywhere. And **"S2 is fine in all five" was wrong**: S2 is 5–15 % off in those five and in nine more LINEAR areas (FRD, FRF, FRG, PL4, PL6, PL7, PL8, PL9, Portugal).

### Why the existing S2 bisection did not help

The sweep already had a bisection for S2. It ran **after** the coarse sweep had climbed to w_max, and there it timed out at its first point in 14 of 42 LINEAR areas. The logs make the mechanism unambiguous:

- FRC LINEAR: w = 0.1 solved in **75 s** as a grid step (warm-started from w = 0.05). The fine sweep then re-solved *the same LP* at w = 0.1 after the sweep had been through 1.0, 2.0 and 5.0 — each of which had timed out at 1 h — and that re-solve **timed out at 1 h**. Same LP, different starting basis.
- ITC LINEAR: the bisection's first point took 2,695 s from that far basis; the next five, each a near step, took 120 / 61 / 46 / 40 / 37 s.

Warm-started dual simplex is cheap for a near step and hopeless from the basis HiGHS is left with after a 1 h abort. The interior-point comment in `lp_run.jl` from July describes the same cliff.

### The fix (29fcf7f)

- **Both S1 and S2 are bisected the moment their bracket closes**, inside the coarse loop, right after the grid point that closes it — every bisection solve is a near step. S1 bisects on `sum_y` (the LP count, monotone in λ) to within max(1, 0.2 %) of today's count; S2 on the multistart travel to within 0.2 % of today's travel. Up to 8 solves each.
- After the detour the bracket's upper endpoint is re-solved for its basis only (`resolve_for_basis!`), so the grid continues as if uninterrupted.
- Once both are pinned, the **first tail time-out ends the sweep**: the later points would start from the aborted basis and time out too (FRC lost 3 h per function that way).
- The fine sweep no longer re-solves grid points it already has (its default multipliers *are* the coarse grid; those re-solves were the far-basis failures in the LOGISTIC logs at 0.01/0.02/0.05).
- `run_resweep_batch.ps1 -RefineOnly` (`SWEEP_STOP_AFTER_REFINE=1`): walk the grid from 1e-4, pin both scenarios, stop — no high-λ tail. Writes `logs/refine_<area>_<FUNC>.log`; `build_deck_data.py` takes the S1/S2 summary from it when newer than the sweep log, so the frontier rows stay those of the full sweep.

Luxembourg LINEAR, refine-only, 35 s: **S1 now 87 of 86 cells (was 69, −20 %)**, S2 within +0.3 % of today's travel (was read off a grid point 61 facilities wide).

### Running now

Three refine-only workers over the 37 areas whose data did not change, in parallel with the #53 rebuild; the six areas whose pharmacy set changed (ITC, ITF, ITG, ITH, ITI, Hungary) get full sweeps afterwards. Results and the regenerated S1/S2 location files (#45) follow in a second comment.

### What this does and does not change in the deck

The interpolated tables (p60–61) and the #48 crossings never used the snapped points, so they do not move. What moves: the S1/S2 markers on the region slides (p16–58), the LINEAR-vs-LOGISTIC table (p62), the exported S1/S2 location files (#45) and the stranding counts read from the S1 assignment (p9).
