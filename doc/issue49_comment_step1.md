## Step 1 done: 42/42 rebuilt — the fix works, and only 3 areas actually move. But it breaks Norway, SE2 and SE3.

Purged the cached `FinalSet_*`/`Linkset_*` artefacts on both sides and rebuilt network +
OD for every area under the landbody-connectivity fix, on the installed GeoDms 20.19.1.m.
Runner and results are committed (`run_rebuild_all.ps1`, `scratch/rebuild_all_all.csv`,
`scratch/affected_areas.csv`).

### The fix delivers exactly what was predicted — ITG measured

| ITG | before | after | change |
|---|--:|--:|--:|
| unreachable residents | 983,169 (15.7 %) | **591 (0.009 %)** | **−99.94 %** |
| baseline mean travel time | 22.30 min | **4.878 min** | **−78 %** |
| baseline travel cost | 1.394e8 | 3.063e7 | −78 % |
| Existing OD rows | 57,375 | 90,299 | +57 % |
| candidate OD rows | 505,944 | 809,249 | +60 % |

The decomposition in the issue body predicted the *served* population travels ≈4.08 min.
The new overall mean is 4.878 min — slightly higher, which is exactly right: the
newly-connected island residents travel further than the mainland average. ITG is no
longer an outlier.

### Only 3 areas move at all

Candidate-OD growth after the rebuild, all 42 areas:

| area | growth | pre-fix unreachable | pre-fix % | pre-fix mean_t |
|---|--:|--:|--:|--:|
| **PL8** | **+27.9 %** | 153,669 | 3.3 % | 8.89 |
| **Portugal** | **+10.7 %** | 459,683 | 4.5 % | 8.56 |
| **ITG** | **+60 %** (OD rows) | 983,169 | 15.7 % | 22.30 |
| ITF | +0.1 % | 0 | 0.0 % | 6.67 |
| *(35 further areas)* | +0.0 % … −0.1 % | 0 | 0.0 % | 1.03–6.52 |
| FRH | −0.5 % | 0 | 0.0 % | 4.34 |
| SE1 | −2.9 % | 6 | 0.0 % | 5.41 |

ITG's byte-size row reads +0.0 % only because its snapshot was taken *after* it was
rebuilt first as the smoke test; its real growth comes from the sweep-log OD row counts.

This lines up precisely with the BIG-share table in the issue body: the areas that move
are exactly the ones whose baseline cost was dominated by the unreachable-client penalty
(ITG 84.6 %, Portugal 62.6 %, PL8 44.4 %). Every area with zero unreachable residents is
untouched. SE1's −2.9 % is the new candidate coverage filter, not connectivity.

**So steps 2…k shrink from 2–4 × 24 h to a single short step: 3 areas, ~2.5 h of
sequential sweep at the previously measured cost.**

Also worth noting for the mechanism: the Netherlands, with its Wadden islands and
ferries, shows **0.0 %** growth. A ferry link joins the island to the mainland component,
so those islands were never pruned. The pruning only bit where a populated landbody was
connected to the main component by *no modelled link at all* — which is why ITG (whose
study area is only Sicilia + Sardegna, two separate landbodies) was the extreme case.

---

### Defect: Norway, SE2 and SE3 now fail

All three fail at `alloc`, identically:

```
[[/NetworkSetup/NewPharmacy_Analysis/NetwerkSpec/CreateMoreEfficientNetwork/
   FinalSet_stored/FinalLinkSet/F2]] Link_Node2_rel: out of range or undefined
```

`network1` and `network2` succeed, so the `.mmd` is written; it breaks when the link set
is read back. These three swept fine before, so this is new.

**Attribution established by experiment, not assumed.** I reverted *only* the
connectivity criterion in `Templates.dms` — back to `Connectiveness/IsSterkVerbonden` and
`Connectiveness/NodesSterkVerbonden` — leaving the MMD read-holder split and every other
change in place, purged Norway and re-ran:

| Norway, new side | result |
|---|---|
| per-landbody criterion (`Strong_connectivity/IsConnected_seldomain`) | **fails** |
| old single-largest-SCC criterion | **exit 0, 51 s** |

So the cause is the connectivity change itself, not the read-holder split. The criterion
has been restored to the new one; the three areas stay failing pending your call.

**Hypothesis, not verified** — @cjacobscrisioni this is your algorithm, so I have not
touched it. In `CreateInitialWorkingNetwork`:

```
Roads_isConnected := …/Strong_connectivity/IsConnected_seldomain    // link: both endpoints kept
Nodes_isConnected := …/Strong_connectivity/NodesConnected_seldomain // node: kept
unit<uint32> Roads := select(Roads_isConnected) {
    unit<uint32> UqGeomPointSet := select(Nodes_isConnected) { attribute<uint64> values := JnctIds; }
    attribute<UqGeomPointSet> F1 := rlookup(F_JnctId, UqGeomPointSet/values);
    attribute<UqGeomPointSet> F2 := rlookup(T_JnctId, UqGeomPointSet/values);
}
```

The per-landbody rule retains nodes from *several* disconnected components at once, where
the old rule retained one. `F1`/`F2` resolve through `rlookup` on `JnctIds`, which needs
those ids to be unique across the retained set — if two retained landbodies carry a
duplicate junction id, `rlookup` yields undefined and `F2` goes out of range. Norway, SE2
and SE3 being the most island-rich areas fits that, but I have not confirmed it.

One more thing worth a look while you are in there: `Strong_connectivity/Networks` mixes
`pcount(part_rel)` with `PartNr == Main` and `rlookup(PartNr, …)`. If
`strongly_connected_components` exposes `part_rel` rather than `PartNr`, those are not the
same attribute.

### Where this leaves the plan

- Re-sweeping **PL8, Portugal and ITG** can start now — they rebuilt clean and are the
  only areas that moved.
- Norway, SE2 and SE3 are blocked on the defect above. They showed near-zero unreachable
  residents before (3,696 / 32,226 / 475), so they are **not** expected to move much; the
  blocker is correctness, not results.
- The other 36 areas need no re-sweep at all.
