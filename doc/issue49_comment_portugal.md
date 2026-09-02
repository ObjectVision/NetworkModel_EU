## Correction: Portugal is NOT fixed by the connectivity change — and the cause is not the road network

Re-swept the three areas that moved. Post-fix baselines (LINEAR):

| area | unreachable before → after | mean_t before → after |
|---|--:|--:|
| **ITG** | 983,169 (15.7 %) → **591** | 22.30 → **4.878** |
| **PL8** | 153,669 (3.3 %) → **0** | 8.89 → **4.534** |
| **Portugal** | 459,683 (4.5 %) → **467,704** | 8.56 → **8.644** |

ITG and PL8 are resolved, PL8 completely. **Portugal is not**, and my earlier framing —
that its stranding was "separate landbodies, same mechanism" — implied it would be. That
was wrong, so here is the actual cause.

### The Azores and Madeira have no pharmacies in the source data

Probing the rebuilt Portugal artefacts directly (coordinates in EPSG:3035, km):

```
all clients          x:  944 .. 2976    y: 1506 .. 2788
unreachable clients  x:  944 .. 1884    y: 1506 .. 2788     (1,360 cells, 467,704 residents)
facilities (_j)      x: 2640 .. 2966    y: 1736 .. 2296     (1,893 pharmacies)
```

Every one of the 1,893 pharmacies sits at **x ≥ 2640 km** — mainland Portugal. Every
unreachable client sits at **x ≤ 1884 km** — the Azores and Madeira. The two sets do not
overlap at all.

So this was never a connectivity problem. **No road-network fix can help**: even a
perfectly retained island network has no pharmacy to route to. The islands are in the
population grid and in the study area, but absent from the pharmacy source data.

For contrast, ITG's residual 591 unreachable residents (12 cells) fall at x 4276–4530,
inside the range its 906 pharmacies span (4168–4818) — genuinely remote cells, not a data
gap. That is the expected residual.

### Consequence: Portugal's baseline is inflated by pure data absence

467,704 residents × BIG(120 min) ≈ 5.6e7 of Portugal's 8.9e7 baseline travel cost — about
**63 %** — is the penalty for demand we have no supply data for. Exactly the failure mode
this issue was opened about, one level down: `covered_country` filters at **country**
granularity, and Portugal-the-country does have pharmacies, so its islands pass the filter
and are then priced as if catastrophically underserved.

### Proposed fix: move the coverage filter from country to landbody

`ModelClient` currently uses

```
covered_country (Country/subset) := pcount(Pharmacies/within_StudyArea/Country_rel) > 0
```

The natural refinement is to evaluate coverage per **`Country_Split`** — the same
per-landbody unit Chris's connectivity fix already introduced — instead of per country:
a landbody with no pharmacy in the data is excluded from `ModelClient` and from
`NewPharmacyLocations`, exactly as an uncovered country is today.

That keeps the existing principle ("model demand only where we have supply data") and
just applies it at the granularity the data gap actually has. It would drop the Azores and
Madeira from Portugal's baseline and remove the ~63 % inflation.

**This is a modelling-semantics decision, so I have not applied it.** Two things to weigh:

1. It changes what "Portugal" means in the deck — 467k residents leave the denominator.
   That must be stated on the page, not silently applied.
2. The alternative reading is that the islands *are* genuinely underserved and should stay
   in. But we cannot tell that from this data: absence of pharmacy records is not evidence
   of absence of pharmacies. Pricing an unknown at BIG asserts the strong version.

@cjacobscrisioni — is the pharmacy source known to exclude the Azores and Madeira, or is
this an unexpected gap worth chasing upstream first?

### Status of the plan

- **ITG, PL8** — re-swept, resolved.
- **Portugal** — pipeline fine, result blocked on the decision above.
- **Norway, SE2, SE3** — still blocked on the `FinalLinkSet/F2` defect reported above.
- **The other 36 areas** — unchanged, no re-sweep needed.

F1 (descriptives) and F2 (deck + exports) should wait for Norway/SE2/SE3: the aggregate
sums over 41 disjoint areas, so it cannot be rebuilt while three of them are failing.

### One measurement caveat

Client populations rose in all three areas (ITG +25,895; PL8 +382,273; Portugal +8,021).
That is expected rather than alarming — `total client population` counts clients present
in the OD, and a larger retained network admits more cells as OD clients. It does mean the
before/after unreachable counts are not exactly like-for-like; the direction is
unambiguous, the precise deltas are not. It also explains the ITG population rise I had
flagged earlier as needing verification: it is the network, not the Italian data update.
