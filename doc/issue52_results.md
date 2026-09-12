## Done — S1/S2 pinned in 87 of 88 sweeps (216ac77)

Every area was either fully re-swept (the six whose pharmacy set changed under #53, plus Finland) or refined in place (the 37 unchanged ones, `-RefineOnly`). Acceptance check `doc/check_s1s2.py` over `deck_data.json`:

| | before | after |
|---|---|---|
| S1 file: count vs today, median | 5.9 % | **0.13 %** |
| S1 off by > 10 % | 22 of 74 | 0 |
| S1 off by > 1 % (or > 1 facility) | — | **1 of 88** |
| S2 file: travel vs today, median | 0.31 % | **0.10 %** |
| S2 off by > 1 % | 14 of 74 | 0 (max 0.74 %) |
| S1 = S2 same point | 5 areas | 0 |

SE2 LINEAR, the headline case: S1 now **451 of 452** cells (was 309), S2 at 278 open within 0.05 % of today's travel.

### The one exception

Country-level **Poland LINEAR** keeps its grid point (S1 +1.6 %, S2 −0.15 %). It is the largest LP in the study (274 MB OD), and near S1 its warm-started dual simplex needs 3–15 h *per solve* — the old full sweep spent 4.7 h on w = 0.1 and 15.5 h on w = 0.2 — so even the climb with a 4 h limit did not get there (w = 0.065: 79 min, 0.0845: 2.9 h, 0.11: time-out). Its seven NUTS-1 areas are all pinned and are what the aggregate and the ranked lists use; country-level Poland only appears as a region slide, a table row and a #45 file. Pinning it is a job for the IPM solver path or the exact MIP, not for another night of simplex.

### What the refine-only walk turned out to need (all in the commits since 29fcf7f)

1. **LP-only walk** up to the bracket — the three roundings cost 50–100 s per grid point against a 7 s LP at low λ (e25416b).
2. **Climb to S2** from the pinned S1 point in ×1.3 steps instead of taking the next grid step: that step's upper endpoint was the most expensive solve of the walk (Denmark: 1,883 s for w = 1.0 to bracket an S2 at 0.557; on SE2 it timed out) (6aaab27).
3. **Climb to S1** likewise once the LP count is within ×2 of today's (92ab4e4); no basis restore after the last scenario (82d84b4); a timed-out climb step ends the walk instead of being retried (86e242e).

Two runs that had started before the climb landed went wrong and were redone: Austria LOGISTIC (time-out cascade after S1) and Denmark LOGISTIC (a fallback bisection across a failed point reported S2 "pinned" 9.5 % off — the summary line looked complete). That is why the acceptance check exists.

Wall time: full sweeps of the Italian areas 1.5–3 h each instead of 9–14 h (the tail stop); refine-only 5 min (Luxembourg) to 4 h (Austria) per area and function under 6-way contention.

### Delivered on it

- #45: `s1s2_open_locations_20260912.zip` — 176 files, 44 areas, all on the pinned points.
- #48: `issue48_frontier_data_20260912.zip`.
- Deck p9 records the fix; the roadmap's exact-MIP item is now about the integrality gap, not the snap.
