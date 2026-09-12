## Superseded again — S1/S2 pinned by bisection (#52), OECD Italian list (#53), Hungary and Finland added

Attached `s1s2_open_locations_20260912.zip`: **176 files, 44 areas, 202,064 open locations**, same naming (`<area>_<s1|s2>_<linear|logistic>_open.arrow`, lower case), same columns (`x, y` in EPSG:3035).

Every file in the previous zip is stale in one of three ways:

1. **All 42 previous areas:** S1 and S2 were read off the nearest swept grid point; the S1 file was more than 10 % off today's count in 22 of 74 sweeps (SE2's S1 had 309 facilities, not 452) and S2's travel up to 17 % off in the French and Polish regions. Both are now pinned by bisection to within max(1, 0.2 %) of today's count and 0.2 % of today's travel (#52). One exception: country-level `Poland` LINEAR keeps its grid point (S1 1.6 % over today's count) — the largest LP; its seven `PL*` files are pinned.
2. **ITC, ITF, ITG, ITH, ITI:** the pharmacy set changed (OECD-geolocated Ministry of Health list, 20,635 instead of ESPON's 12,991; #53), so the baseline, the candidate set and both scenarios are new.
3. **New:** `Hungary` (#53) and `Finland` (#44), four files each.

`services_allocated` in `Locations.dms` lists 21 areas; the other 23 are in the zip under the same naming.
