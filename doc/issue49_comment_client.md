## `Client` vs `ModelClient` — intended difference and purpose

Following up on decision 1. Agreed: **baseline and LP must run over the same client set.**
Here is what each unit is *for*, so the distinction stays deliberate rather than accidental.

### The two units answer different questions

| | `Client` | `ModelClient` (= `Client_pharmacy_coverage`) |
|---|---|---|
| **Question** | *Where do people live?* | *Where do people live **and** do we have the supply data to model them?* |
| **Definition** | cells with `ModelParameters/Client > 0` (i.e. `population > 0` for pharmacy runs) | the same, **and** `covered_country[Country_rel]` — the cell's country contains ≥1 pharmacy in the study area |
| **Depends on** | population grid only | population grid **+ pharmacy source coverage** |
| **Role** | the *demand universe* — a property of the geography | the *modelled demand* — a property of this run's data availability |

`ModelClient ⊆ Client` by construction.

### Why the distinction is worth keeping

The filter is **not** a modelling assumption about accessibility; it is an honest statement
about **data coverage**. In a multi-country study area (e.g. `EU`) some countries have no
pharmacy records at all. Those residents are not "badly served" — we simply *do not know*
how they are served. Including them would make every one of them unreachable and price
them at `BIG`, which would:

- inflate the baseline travel cost with pure data-absence,
- create the exact artefact this issue is about (see the ITG decomposition above — 84.6 %
  of ITG's baseline cost is a `BIG` penalty), and
- let a data gap masquerade as a policy finding in the ranked improvement lists.

So the separation is right. What was wrong is only that the two sides used *different*
units.

### Why they must be the SAME unit on both sides

`ModelClient` is the correct choice for both, because the λ-sweep compares a baseline and
an optimum **on the same demand**:

- The **baseline** (`AllocateClientsToExistingPharmacies`) measures what the current
  network delivers.
- The **LP** (`AllocateClientsToNewPharmacies`) measures what an optimal network could
  deliver.

S1 ("same facility count") and S2 ("same travel cost") are both defined *relative to the
baseline point*. If the two sides carry different populations, S1/S2, the frontier, the
rectangle and its diagonal crossing are all comparing incomparable quantities — the defect
`doc/todo.md` §B3 fixed once already.

### It is also a live correctness bug, not only a comparability concern

`79cb58b` correctly generalised the template's `attribute<Client> client_rel` →
`attribute<Org> client_rel`, so `client_rel` now follows whichever `Org` was passed. But
the descriptives still hard-code `Client` while reading the **existing** allocation, whose
`client_rel` is now in `Client_pharmacy_coverage`:

```
Analyses.dms:42  attribute<…/Allocation> best_od                     (Client) :=
                     min_index(…/Allocation/impedance, …/Allocation/client_rel);
Analyses.dms:43  attribute<cells>        nearest_cell_by_road_client (Client) := …
Analyses.dms:44  attribute<Client>       grid_client_rel             (grid)   := …
```

And this is **not** automatically a no-op for single-country areas: a client cell whose
`Country_rel` is null — coastal or border cells that fall just outside the country polygon —
drops out of `Client_pharmacy_coverage`. So the two units can differ in row count even for
ITG, and where the counts happen to coincide they are still *distinct units*.

### Proposed shape

One alias as the single source of truth, so the two can never drift apart again:

```
// Client      : the demand universe — every inhabited cell in the study area.
// ModelClient : the demand we can legitimately MODEL — inhabited cells in countries
//               for which pharmacy supply data exists. Baseline and LP must both use
//               THIS unit, or S1/S2 and the frontier compare different populations.
unit<uint32> ModelClient := Client_pharmacy_coverage;
```

- `Analyses.dms:115` (baseline) and `:123` (LP) → both `ModelClient`
- `Analyses.dms:42–44` (descriptives over the existing allocation) → retype to `ModelClient`
- `:146` / `:153` (the s1/s2 reporting containers) → follow, if their travel times are to be
  compared with the baseline

`Client` stays, and stays meaningful: it is the denominator for "share of residents we can
model", which is worth reporting per area precisely so a data gap can never again be read
as a policy result.

**Open question for @cjacobscrisioni:** should the *candidate* set (`NewPharmacyLocations`)
be restricted to covered countries as well? With λ > 0 the LP will not open a facility that
serves nobody, so it is harmless for the optimum — but leaving it unrestricted means the
reported candidate count `M` includes cells that can never be selected, which is confusing
in the logs.

---

### Unrelated, but worth recording here

The pipelines defaulted `GEODMS_EXE` to `C:\dev\GeoDMS_2026\bin\Release\x64\GeoDmsRun.exe`
— the **live build tree** of the GeoDMS engine project. That couples two unrelated
workstreams in both directions: a batch run can pick up binaries that are mid-relink, and
the running `GeoDmsRun` holds a handle on `Dm*.dll` that makes the next engine link
silently *skip*. Repointed to the installed **GeoDms 20.19.1.m** in `c368a01`
(`GEODMS_EXE` still overrides). Verified: `cfg/main.dms` loads and `/Analyses/Client`
computes under 20.19.1.m.
