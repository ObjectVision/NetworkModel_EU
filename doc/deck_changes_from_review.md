# Deck changes proposed from the REGIO review of the methodology draft

Source: `doc/modelling_service_networks_REGIO_commentsBN.docx` — 26 comments by
**Ana Moreno Monroy** (CFE/EDS, July), **Martijn Brons** (REGIO, 6 Aug) and
**Bernhard Nöbauer** (CFE/EDS, 30 Aug, replying to both). Comment numbers below are the
docx comment ids. Deck page numbers refer to the current 71-slide `lambda_sweep5.pptx`.

Status legend: **DONE** = already in the deck · **PROPOSE** = a concrete edit · **DECIDE** = needs
the group · **ANSWER** = a question we can answer from the results.

---

## 1. Framing — drop the trilemma, lead with "by how much"

**Comments 1, 2, 3** (Ana, Brons, BN). All three reject the "two out of three, never all"
trilemma: efficiency and accessibility are *objectives* with a continuous trade-off, demand is
an *exogenous constraint* (it may change over time, but is not modelled endogenously —
nobody wants to model people moving away because there is no pharmacy).

**Comments 5, 6** (Brons, BN). The yes/no research questions are trivially "yes". The real
question is **by how much** — and BN's reading is right: the frontier answers that *without*
knowing λ. "Equal travel with 20 % fewer pharmacies" or "equal count with 25,000 travel-hours
saved" is a quantification in its own units. λ / β₀ is needed only to put **euros** on it.

| | page | change |
|---|---|---|
| PROPOSE | p2 agenda | Reword any trilemma phrasing: *trade-off between operational cost and accessibility, under exogenous demand*. Continuous, not a dichotomy. |
| PROPOSE | p58 summary | Lead with the two quantified deltas per area **in native units** (Δ#facilities at equal travel, Δperson-minutes at equal count), and say explicitly that these need no λ. Keep € as a secondary, labelled-placeholder column. |
| DONE | p57–58, p64–71 | The crossings table and rectangle charts already quantify S1/S2 and the balanced crossing per area. |

## 2. Observed distribution first

**Comment 4** (BN). "Should we add a description of the observed service locations across EU
countries as a first item?"

| | page | change |
|---|---|---|
| PROPOSE | p6–9 → before p3 | The descriptives (residents per pharmacy, catchments, multi-pharmacy cells) currently follow the model slides. Move them **ahead** of the model: *what exists* → *what we optimise*. One-line change in `merge_deck.ps1` (a `Move-ByMarker` per descriptives slide). Cheap, and it answers BN's question structurally. |

## 3. Demand weighting by age

**Comments 9, 10** (Brons, BN). Weight residents by age for pharmacy demand (e.g. young 0.5,
old 1.5, or bracket weights 1/2/3). BN is agnostic; suggests a box for one country.

| | page | change |
|---|---|---|
| PROPOSE | p60 Remaining | Add: *age-weighted demand — box for one country, compare S1/S2 shift*. Feasible: `client_weight_col` already reads a configurable column; an age-weighted `total_pop` variant is a GeoDMS export away. |

## 4. Fractional assignment and multi-pharmacy cells

**Comments 11–14** (Brons, BN). Brons: doesn't nearest-only imply y ∈ {0,1}? and aren't
same-cell facilities a free merge? BN's answers are the right deck text:

- fractional y comes from the LP relaxation; a fractional facility can serve only a fraction, so
  fractions are never "free";
- a *location* is a grid cell with ≥ 1 pharmacy; *closing* means fewer such cells; within-cell
  multiplicity is left to forces outside the model (competition, variety, congestion). Observed
  catchments reach ~30,000 people, so one cell can in principle carry the demand.

| | page | change |
|---|---|---|
| PROPOSE | p3 ingredients | Add a fourth ingredient: **"A location is a cell with ≥ 1 pharmacy."** Three sentences from BN's comment 14, verbatim in spirit. |
| DONE | p3 | Fractional y and the relaxation are already explained. |

## 5. Facility-cost values — show the form, not the numbers

**Comments 20, 21, 22** (Ana, Brons, BN). Ana: keep the description generic, don't include
values. Brons: the values drive the outcome. BN: with fixed + linear variable cost, λ weights the
*fixed* cost; the frontier and its comparisons are valid **without** the true β₀ — β₀ only
matters for euros; changing the functional form would upend the exercise.

| | page | change |
|---|---|---|
| PROPOSE | p3 | `λ = w · €100,000` → label the €100,000 explicitly as a **placeholder**, and add BN's point: *rankings and frontier shape are invariant to β₀; only the € labels move with it*. |
| PROPOSE | p57–58, p64–65 | Add the same one-line caveat under the λ_cross columns. |
| DONE | p60 Remaining | "Calibrate real pharmacy a,b" is already listed. |

## 6. The logistic function — name it, parametrise it, consider rescaling

**Comments 26, 27, 28** (BN, Brons, BN). BN asks Maarten/Chris directly: logistic or
**log-logistic**? what parameters? should it start at f(0) = 0? how non-linear?
**Comments 35, 36** (Brons, BN). Degeneracy in the logistic variant: does the S-curve have a
location parameter? is the λ range the same for both variants? BN proposes **rescaling the whole
function so its values at 0 and 60 min align with the linear one** (his 23 July email), which
would also reduce degeneracy.

| | page | change |
|---|---|---|
| **DONE** | p63 (logistic) | State explicitly: **logistic, not log-logistic**; midpoint 25 / scale 10; **f(0) = 1/(1+e^{2.5}) ≈ 0.076, not 0**; the λ grid is the same 1-2-5/decade for both, but the logistic's *useful* range is much narrower (union grid tops at 0.02 vs 0.5) — that narrowness *is* the degeneracy Brons asks about. |
| DECIDE (tabled on p63) | p63 + p60 | BN's rescaling (align f(0) and f(60) with linear) — put it on the slide as the open proposal it is, with the trade-off: it changes the equity weighting the group chose the logistic for. |

## 7. Candidate cells — neighbours too?

**Comments 32, 33** (Brons, BN). Extend candidates to the ≥ 50-cells *and their neighbours*;
try one country.

| | page | change |
|---|---|---|
| PROPOSE | p60 Remaining | Add as a one-country experiment. Note it pulls in the **same direction as the choice-set widening on p5** — both enlarge what the optimiser may choose from. |

## 8. Bounds — total cost only, not per component

**Comments 37, 38** (Brons, BN). Brons: the method yields a cost *range* per λ (LB from the
relaxation, UB from the heuristic). Does that hold **per component** — travel vs facility? and for
logistic "travel times"? BN defers to Maarten/Chris.

| | page | change |
|---|---|---|
| **DONE** | p7 (multistart) | Add one line: **the bounds hold for TOTAL cost only.** The discrete solution can sit with *higher* travel and *lower* facility cost than the relaxation, or the reverse — the components are not individually bounded. For the logistic variant the bound is on the *transformed* cost c(t), not on minutes; mean_t is reported separately and carries no bound. BN's remark that the two bounds are now nearly a line for most areas is correct and worth stating. |

## 9. A diagram of how the curve is traced

**Comments 41, 42** (Brons, BN). Precede the Pareto figure with a diagram for **one or two λ
values** showing the trade-off and its optimum, so the reader sees how the frontier is traced.

| | page | change |
|---|---|---|
| PROPOSE | new slide before p6 | "How one λ picks one point": the objective as a straight line of slope −λ in the (#facilities, travel) plane, tangent to the feasible set; then two λ values → two tangent points → the curve is the envelope. Cheap to draw from any region's `deck_data.json` rows. |

---

## Not in the review, found while preparing it

**S1/S2 snap to the nearest swept grid point.** In **5 of 42 areas** (FRC, FRH, FRJ, FRK, SE2)
both scenarios resolve to the *same* λ point — SE2's S1 bracket (0.2, 0.5) and S2 bracket
(0.5, 1.0) both snap to w = 0.5, so its delivered **S1 has 309 open facilities, not the baseline
452**. The interpolated λ tables (p57–58) are unaffected because they interpolate; the exported
S1/S2 **location files** (#45) and the planned exact-MIP step are where a refinement step is
needed instead of a snap. Flagged on p5; deserves its own issue.

---

## Suggested order of work

1. ~~**Answers** first (§6, §8)~~ — DONE (commit below); BN's rescaling is tabled on p63 as the open decision it is.
2. **Reorder** descriptives ahead of the model (§2) — one script edit.
3. **Framing** rewrites (§1, §5) — text on p2, p3, p57–58, p58.
4. **New diagram** (§9).
5. **Roadmap additions** (§3, §7) on p60.
6. **Decision** items (§6 rescaling) to the group.
