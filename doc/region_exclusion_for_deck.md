# Region exclusion — text for the deck (issue #49)

Draft wording + the numbers, for a slide to be added when the deck is regenerated (step
F2 of `replan_connectivity_fix.md`). Put it next to the method pages (p3) and reference it
from the per-region pages of any affected area.

---

## Slide text (draft)

**Excluding regions the model cannot serve**

Some regions hold population but no pharmacy anywhere in the source data. Under soft
coverage every resident there is "unreachable" and priced at the maximum travel cost
(`BIG` = 120 min), which inflates that country's baseline with what is really a **data
gap**, not a policy finding — and lets that gap outrank genuine improvement potential in
the ranked lists.

**Rule.** If more than **50 %** of a NUTS region's inhabitant locations are absent from the
OD matrix — i.e. with or without a road network they reach no pharmacy within the maximum
travel time — the **whole region** is excluded: its population *and* its candidate
locations, from the baseline and from the λ-sweep alike.

**Level.** NUTS3 where populated, otherwise NUTS2, otherwise NUTS1.

**Judged on the existing network,** so the verdict cannot depend on which candidate set a
run uses, and is identical for the baseline and the sweep.

---

## What it excludes today

| country | level | region | name | cells | residents | share absent from OD |
|---|--:|---|---|--:|--:|--:|
| Portugal | NUTS3 | PT200 | Região Autónoma dos Açores | 919 | 212,855 | 100 % |
| Portugal | NUTS3 | PT300 | Região Autónoma da Madeira | 419 | 244,867 | 100 % |

Both are unambiguous: **100 %** absent at every NUTS level, while all 27 other Portuguese
NUTS3 regions are far below the 50 % threshold. No borderline case arises.

### Effect on Portugal's baseline

| | before | after |
|---|--:|--:|
| client population | 10,308,403 | **9,850,681** (−457,722) |
| candidate locations | 19,382 | **18,487** (−895) |
| baseline travel cost | 8.91e7 | **3.42e7** (−62 %) |
| baseline mean travel time | 8.64 min | **3.47 min** (−60 %) |
| unreachable residents | 467,704 | **9,982** (0.1 %) |

The −62 % matches the ~63 % BIG-share that issue #49 measured, i.e. the inflation was
almost entirely this data gap. The residual 9,982 residents are genuinely remote mainland
cells and stay in, correctly priced.

**State this on the page:** Portugal's figures cover the mainland only; the Azores and
Madeira are outside the modelled population. Pre- and post-exclusion numbers are not
comparable.

---

## Implementation

- `cfg/main/Analyses.dms` — `ClientExport` / `FacilityExport` export the NUTS3 code
  (column **`NUTS`**; `NUTS_CODE` encodes all three levels as 5/4/3-character prefixes).
- `settings.jl` — `excluded_nuts_regions(country)` applies the rule and writes
  `scratch/excluded_regions_<country>.csv`; `in_excluded_region(tbl, …)` masks rows.
- `lambda_sweep_simplex.jl` — `load_from()` drops excluded candidates and zeroes the
  weight of excluded clients. Baseline (`:231`) and sweep (`:235`) share this loader.
- `NUTS_EXCLUSION=0` disables the rule; `NUTS_EXCLUDE_SHARE` overrides the 50 % threshold.

## Open points

- **Both sides must be re-exported.** The rule reads the NUTS column from the *existing*
  client table, so `run_pharmacy_pipeline.bat` **and** `run_new_pharmacy_pipeline.bat` must
  rerun their `alloc` step per area. Done for Portugal only so far.
- **Cosmetic:** the baseline still reports the unreachable **cell** count including the
  now zero-weight excluded cells (Portugal: 1,360 cells / 9,982 residents). The population
  figure is right; the cell count over-reads. Worth fixing before the deck goes out.
- **Only Portugal triggers the rule so far.** Whether any other area does can only be
  settled after its exports are regenerated — in particular Norway, SE2 and SE3, which
  currently cannot be rebuilt at all (issue #50).
