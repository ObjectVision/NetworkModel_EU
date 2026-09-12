## Results (216ac77): the south of Italy was three pharmacies in five short — the Italian "improvement potential" was missing data

Italy's five NUTS-1 areas and Hungary were rebuilt from the network up (the cached network carries the pharmacy connector links) and fully swept on both cost functions; Finland came in alongside (#44). Deck `doc/lambda_sweep5.pptx` (76 slides), README and the #45/#48 exports are regenerated.

### What the OECD list changed

| area | ESPON | OECD | residents / pharmacy |
|---|--:|--:|--:|
| Italy | 12,991 | **20,621** in the study area | 4,520 → **2,848** |
| ITC Nord-Ovest | 4,463 | 5,624 | 3,548 → 2,815 |
| ITF Sud | 1,951 | **4,955** | 6,831 → 2,690 |
| ITG Isole | 1,449 | 2,332 | 4,352 → 2,704 |
| ITH Nord-Est | 2,786 | 3,805 | 4,138 → 3,030 |
| ITI Centro | 2,342 | 3,919 | 4,996 → 2,986 |
| Hungary | — | 3,094 | 3,119 |

ITG's baseline mean travel goes from 4.9 min (after the landbody fix) to **2.0 min**; ITF from 6.7 to 2.0 min.

### Consequence for the rankings

Relative improvement potential (rectangle / baseline count × travel), LINEAR:

| rank | ESPON list | OECD list |
|---|---|---|
| 1 | ITG 0.384 | SE1 0.117 |
| 2 | ITF 0.268 | Norway 0.112 |
| 3 | ITI 0.129 | Lithuania 0.086 |
| 4 | ITC 0.128 | SE2 0.085 |
| 6–7 | | ITG 0.073, ITF 0.071 |

Under LOGISTIC the five Italian areas are in the bottom ten of 43. The sparse Nordic and Baltic areas lead now, which is also where the 5-nearest choice set binds hardest (Norway: 18.6 % of residents one closure from stranding at S2; ITF on the new list 1.8 %, was "a third of the population"). The earlier decks' headline — southern Italy far above the field — was the ESPON list, not the geography. The scope slide (p8) and the roadmap (p65) say so.

Aggregate over the 43 disjoint areas (Hungary and Finland included): 51,350 pharmacy cells today; S1 −23 % travel at today's count, S2 −30 % locations at today's travel (LINEAR; were −26 % / −34 % over 41 areas) — Italy on its full list sits closer to its frontier.

### Hungary

3,094 pharmacies in 1,865 cells, 9.65 M residents, baseline mean travel 3.6 min, no unreachable cell; S1 −19.5 % travel, S2 −25.8 % locations; ranks 20th of 43 (LINEAR). Typology Type 1 / HIGH from slide 13 of the typology deck.

Provenance: the OECD document and zip are under `SourceData/NetworkModel_EU/Locations/Pharmacies/` next to the installed parquets; the June unchecked Italy file is kept as `ita_pharmacies_20260622_unchecked.parquet`.
