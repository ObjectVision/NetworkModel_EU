## What the k-median preprints mean for the λ-sweep: no algorithm to adopt, a benchmark for our certificates, and a frontier tail whose gap is mostly a fixable rounding failure

### The two papers

The linked preprint (*Single-exponential recovery and bounded-price strictness for metric k-median*, OpenAI, 24 Sep 2026) gives a randomized (2−σ)-approximation for some unspecified absolute σ>0. Its companion, published the same day (*The approximation threshold for metric k-median*), contains the headline result: a deterministic (1+2/e+ε)-approximation for every ε>0, in the model with a given candidate-facility set. That is exactly our p-median model: clients = populated cells, candidates = candidate cells, objective = Σ pop·c(t).

The lower bound 1+2/e ≈ 1.736 is old (Jain–Mahdian–Saberi 2002). It comes from Max-k-Coverage, where covered clients sit at distance 1 and uncovered ones at distance 3. If the companion holds up, that bound is now tight: unless P=NP, no polynomial algorithm can *guarantee* better than 73.6 % above the optimum on every instance. Both are preprints, not peer-reviewed.

Neither paper gives anything we could run. The constants are of the order 10+60000·2^3999, the local search exchanges 5 facilities at a time (O(N^10) per step), and the recovery step enumerates exponentially many cases. Their λ is our λ: the opening price in Jain–Vazirani's Lagrangian relaxation of the cardinality constraint. The difficulty they work around, that a price controls a weighted count but not an exact count, is the one our S1 rounding deals with.

### Our per-instance certificate is three orders of magnitude tighter

From `doc/issue48_sweep_results.csv` (49 areas): the gap between the multistart rounding and the lower bound at the same count, `gap_pct_vs_lower_bound` (see the second precision point below).

| point | LINEAR median / max | LOGISTIC median / max |
|---|---|---|
| S1 | 0.014 % / 0.13 % | 0.010 % / 0.08 % |
| S2 | 0.020 % / 0.65 % | 0.022 % / 0.63 % |
| cross-λ (two nearest sweep points) | max 0.07 % | max 0.07 % |

The worst-case hardness therefore does not bite where we draw conclusions. The deck can say so in one line: "in general no polynomial method can guarantee better than 1+2/e; per instance our LP bound certifies ≤ 0.65 % at S1, S2 and the cross-λ points".

Two precision points:

- **LOGISTIC is not a metric.** c(30)=0.62 > 2·c(15)=0.54, so the triangle inequality fails, and the metric guarantees (1+2/e included) apply to LINEAR only. For LOGISTIC our claim rests entirely on the LP certificate, which is fine, but we should not cite approximation theory for it.
- **The bound for an integer count — fixed.** `travel_relax` bounds the optimum at the fractional count `sum_y`, but the rounding opens p = `n_open` ≈ round(`sum_y`). Where p > `sum_y` it is not a valid bound: 306 of the 2,941 sweep rows had a slightly *negative* gap against it, down to −0.09 % (SE3 LINEAR S1: −0.065 %). Weak duality on the priced count gives `opt_p ≥ travel_relax + λ·(sum_y − p)` for every integer p. Against that bound there are no negative gaps left, and the extremes hardly move (table above). It is now computed from the λ, `sum_y` and `n_open` columns every log already has, so no re-solve is needed. `build_deck_data.py` carries it as `lb`; the deck's "multi vs relax" cells and p12's wording use it; the λ-axis chart draws it; `parse_compare.py` uses it; and `issue48_sweep_results.csv` gets two appended columns, `travelcost_lower_bound_at_n_open` and `gap_pct_vs_lower_bound` (the existing columns are unchanged). New sweeps also print it in the S1/S2 summary as `travel_lb`.

### The tail of the frontier is not certified

73 sweep rows have a gap above 5 %, up to 179 % (Belgium LINEAR w=0.5). They span 28 areas (plus the Italy sum), all at λ beyond S2, where the LP is highly fractional: more fractional facilities than open ones. By gap and fractionality (fractional / open):

| fractional / open | LINEAR median / max gap | LOGISTIC median / max gap |
|---|---|---|
| 0 (integral LP) | 0 / 0 | 0 / 0 |
| < 0.1 | 0.01 % / 0.7 % | 0.005 % / 0.2 % |
| 0.1 – 0.5 | 0.05 % / 19 % | 0.03 % / 3.3 % |
| 0.5 – 1 | 2.1 % / 45 % | 1.6 % / 13 % |
| 1 – 2 | 7.2 % / 83 % | 5.3 % / 41 % |
| ≥ 2 | 40 % / 179 % | 22 % / 34 % |

These rows are exported with `on_pareto_frontier=True`.

**What the gap is made of: stranding.** The OD search per client stops once it has reached 5 existing-pharmacy cells (`limit(OrgZone_max_mass, DstZone_mass)` with `max_nr_facilities_per_client := 5`, `cfg/main/Analyses.dms:288`). In Belgium the existing-side OD has exactly 5 rows per client, and on the candidate side 99.3 % of the clients' search radii equal their 5th-nearest-existing radius (median 9.5 min, p99 21.8 min; none reaches the 120-min cut). With 710 of 2,958 locations open (Belgium LINEAR w=0.5):

- 2,783 cells / 789,817 residents (6.85 %) have no open candidate inside their radius and are charged BIG = 120 min;
- for those stranded cells, the nearest open pharmacy is a median of 5.1 km away in straight-line distance (p90 8.1 km);
- stranding accounts for 68 % of the rounded travel cost (9.48e7 of 1.388e8). The served part alone (4.41e7) is *below* the LP bound (4.98e7), so the whole gap is stranding.

A client a few minutes from an open pharmacy outside its 5-existing radius is charged 120. That breaks the triangle inequality and gives the instance a max-coverage flavour ("inside my radius" vs BIG), the structure behind the 1+2/e lower bound. The LP covers everyone by spreading y≈0.3 over thousands of candidates, so every client a rounding fails to cover costs 120.

### Experiment: rounding vs LP vs choice set

`tail_gap_experiment.jl` re-solves single λ points on exactly the sweep's problem (same loader, LP and multistart) and adds two things. First, an unrestricted 1-swap polish: best-improving swaps over *all* candidates, with the y≈1 locations allowed to close. The sweep's multistart swaps only within the LP's fractional support and keeps the y≈1 locations fixed. Second, the exact soft-coverage p-median MIP at the same count (HiGHS, 240–900 s, warm-started from the best heuristic). Logs: `logs/issue55_tailgap_<area>_<func>.log`. All gaps are relative to the Lagrangian bound at p.

| point | p | frac. y | multistart | unrestricted swap | MIP (proven bound) | stranded %: multi → swap / MIP |
|---|---|---|---|---|---|---|
| Luxembourg LINEAR S2 (w=0.25) | 61 | 6 | 0.05 % | 0.05 % | optimal 0.05 % | 0 → 0 / 0 |
| Luxembourg LINEAR w=1 | 22 | 24 | 1.19 % | 1.17 % | optimal 0.82 % | 0 → 0 / 0 |
| Luxembourg LINEAR w=2 | 18 | 25 | 2.69 % | 1.35 % | 1.35 % (≥ 0.88 %) | 0.24 → 0.16 / 0.16 |
| Luxembourg LINEAR w=5 | 16 | 51 | 6.94 % | 4.86 % | optimal 4.00 % | 0.57 → 0.37 / 0.32 |
| Luxembourg LOGISTIC S2 (w=0.0027) | 55 | 10 | 0.02 % | 0.02 % | optimal 0.02 % | 0 → 0 / 0 |
| Luxembourg LOGISTIC w=0.05 | 16 | 35 | 2.82 % | 2.66 % | 1.68 % (≥ 0.28 %) | 0.95 → 0.81 / 0.35 |
| Luxembourg LOGISTIC w=0.1 | 15 | 30 | 2.15 % | 1.24 % | optimal 1.24 % | 1.55 → 1.34 / 1.34 |
| Luxembourg LOGISTIC w=0.2 | 12 | 26 | 1.44 % | 0.61 % | optimal 0.25 % | 7.83 → 7.48 / 7.37 |
| **FR1 LINEAR w=1** | 341 | 692 | **132.3 %** | **2.29 %** | 2.29 % (≥ 0.27 %) | **4.37 → 0.02** / 0.02 |
| **FR1 LINEAR w=2** | 276 | 946 | **148.4 %** | **11.8 %** | 11.8 % (≥ 0.47 %) | **5.91 → 0.50** / 0.50 |

What this shows:

1. **At S2 the multistart set is the proven optimum** (both functions). The remaining 0.02–0.05 % is the LP's integrality gap. Together with the S1/S2/cross-λ table above, the decision points are certified.
2. **The large tail gaps are mainly a rounding failure, and a cheap one to fix.** On FR1 the unrestricted swap takes 132 % → 2.3 % (91 swaps) and 148 % → 11.8 % (72 swaps), and almost all the stranding disappears. Within 900 s the MIP finds nothing better than the swap solution, and its bound proves that solution is within 2.0 % (w=1) and 11.3 % (w=2) of the optimum. Mechanism: when the LP spreads y thinly over many candidates, the fractional-support neighbourhood with fixed y≈1 locations cannot move a facility to the clients the rounding left without one, and each of those costs BIG.
3. **The LP itself is fairly tight.** Where the MIP proved optimality, the optimum is at most 2.7 % above the LP at the same count (Luxembourg). On FR1 the MIP bounds sit within 0.5 % of the LP. Whether FR1 w=2's remaining ≤ 11.3 % is the swap's local optimum or a weak LP is still open.
4. **Far out, the choice-set cutoff shapes even the optimum.** At Luxembourg LOGISTIC w=0.2 (12 locations) the optimal set still leaves 7.4 % of residents outside their 5-existing radius at BIG. There the frontier reflects the OD cutoff more than travel.
5. **The rounding depends on the LP vertex.** FR1 LINEAR w=1 solved cold here gives a multistart 132 % above the bound. In the sweep, warm-started along the grid, the same λ gave 22 %. The LP is degenerate, and the multistart inherits whichever optimal vertex the solver returns. The unrestricted swap removes that sensitivity.

Belgium (179 %) has the same signature (served part below the LP bound, 6.85 % stranded) but was not re-solved here: its LP alone takes about 5,000 s at that λ.

### Next steps

1. ~~Fix the integer-count bound~~: done (above).
2. **Unrestricted swap polish: added**, behind an env switch, off by default. `FULL_SWAP=1` polishes the multistart set in `solve_at_w!`. It runs only where the multistart is at least `FULL_SWAP_MIN_GAP` % above the bound at its count and λ ≥ `FULL_SWAP_MIN_LAMBDA` € (both default 0). Caps: `FULL_SWAP_ROUNDS` (2000 swaps) and `FULL_SWAP_TIME_LIMIT` (1800 s). The polished set replaces the multistart only when it is better, so `travel_multi` in the log holds the polished value; each attempt is logged as `full-swap polish at w=…`. Checked on Luxembourg: with the switch off the results are identical to before; with `FULL_SWAP_MIN_GAP=1` S2 is untouched and w=1/2/5 match the experiment's swap values; with `FULL_SWAP_MIN_LAMBDA=150000` only w≥2 are polished. Cost on FR1 LINEAR w=2: 72 swaps in 8.8 s, against about 150 s for that point's LP (`logs/issue55_fullswap_timing_FR1_LINEAR.log`). New sweeps can switch it on directly (e.g. `FULL_SWAP=1 FULL_SWAP_MIN_GAP=1`); the existing sweep results are polished afterwards by step 3.
3. **Stored tail rows polished without re-solving: done** (`polish_tail.jl`, step 1b in `doc/README_deck.md`). The pass reads the rows the deck uses (`doc/polish_rows.tsv`, written by `build_deck_data.py`). For every row with gap ≥ 1 % it reloads the set the sweep stored in its `w=…` folder, and uses it only if count and travel still match the log row on today's OD. It then applies the unrestricted swap polish. Results are in `doc/full_swap_polish_{LINEAR,LOGISTIC}.csv`; polished arrows go to a separate `lambda_sweep/<FUNC>/polished/w=…/` folder, so the sweep's own folders are untouched. `build_deck_data.py` applies the polished rows (keeping the multistart value as `multi_ms`), and `issue48_sweep_results.csv` flags them in a new last column, `multistart_polished`.

   | | LINEAR | LOGISTIC |
   |---|---|---|
   | eligible rows (gap ≥ 1 %) | 54 | 70 |
   | polished / unchanged / stale | 43 / 1 / 10 | 57 / 2 / 11 |
   | gap of polished rows, before (max / median) | 179 % / 11.8 % | 41 % / 7.7 % |
   | gap of polished rows, after (max / median) | 7.5 % / 1.2 % | 3.5 % / 0.7 % |
   | compute time (max per row) | 61 min (305 s) | 110 min (421 s) |

   Examples: Belgium LINEAR w=0.5 179 % → 5.0 % (stranded cells 2,783 → 157); ITF LINEAR w=2 122 % → 5.6 %; ITC LINEAR w=0.5 83 % → 1.1 %; Netherlands LINEAR w=1.5 69 % → 1.1 %; ITF LOGISTIC w=0.02 41 % → 1.7 %. Across all area rows, gaps above 5 % fall from 73 to 16 and above 1 % from 131 to 76.

   No per-area or per-country S1/S2 changes (their gaps are < 1 %, and no polished row reaches the baseline travel). The AGGREGATE does change, because at a common λ part of its areas sit deep in their tail. LINEAR: S2 35,816 → 35,478 locations, cross-λ €14,034 → €14,122. LOGISTIC: S2 33,421 → 32,816, cross-λ €154.9 → €156.8.

   Of the 16 rows still above 5 %, 10 are **stale**: their stored set no longer reproduces the logged travel. In LINEAR this is FR1, FRB, PL7 and PL9, whose July sweep logs priced stranding at BIG = 42–50 (the region's own t_max) instead of 120. Their frontier rows therefore mix two stranding prices with their September S1/S2. In LOGISTIC it is FR1, FRB, PL7, PL9 and Czechia, also July logs, cause not yet established. Plus one overwritten Luxembourg folder. These areas need a re-sweep (separate task). The other 6 (Estonia, FRL and ITF at the far end) stay at 5.6–7.5 % after polishing, where the choice-set cutoff strands even good solutions.
4. Wider choice set (5 → 20 existing): not yet run. It needs a temporary change to `max_nr_facilities_per_client` (or making it env-overridable, as `STUDY_AREA` is). Point 4 above says it matters at the far end of the frontier, but not for S1/S2/cross-λ.
