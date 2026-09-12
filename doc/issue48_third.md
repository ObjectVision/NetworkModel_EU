## Superseded again — attached `issue48_frontier_data_20260912.zip` (216ac77)

Same two files, same columns. What changed since the previous zip: the OECD-checked Italian list (#53) rebuilds ITC/ITF/ITG/ITH/ITI from the network up; Hungary (#53) and Finland (#44) are added; S1/S2 are pinned by bisection (#52) — the crossings themselves never used the snapped points, so those move only where the data did.

| | previous | now |
|---|--:|--:|
| areas (+ AGGREGATE) | 42 | **44** |
| disjoint areas in the aggregate | 41 | **43** |
| aggregate baseline, pharmacy cells | 43,320 | **51,350** |
| aggregate baseline travel (LINEAR) | 1,030,069,422 | **964,560,939** |
| sweep rows | 1,530 | 2,964 |

The ranked improvement lists change at the top. ESPON had under-counted the south of Italy (ITF 1,951 → 4,955 pharmacies): on the OECD list ITG and ITF fall from 0.384 / 0.268 to 0.073 / 0.071 (relative rectangle, LINEAR, 6th and 7th), and SE1, Norway, Lithuania, SE2 and Estonia lead (0.12–0.07). Under LOGISTIC the Italian areas are in the bottom ten.

**Pre- and post-12-Sep numbers must not be mixed in one chart or table.** Regenerate with `python doc/export_issue48.py`.
