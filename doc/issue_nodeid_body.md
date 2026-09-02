## Norway, SE2 and SE3 fail after the landbody-connectivity fix: node ids collide / overflow

Spun off from #49, where the landbody-connectivity fix (`79cb58b`) is being rolled out.
39 of 42 areas rebuild cleanly; these three fail at `alloc`, all identically:

```
[[/NetworkSetup/NewPharmacy_Analysis/NetwerkSpec/CreateMoreEfficientNetwork/
   FinalSet_stored/FinalLinkSet/F2]] Link_Node2_rel: out of range or undefined
```

`network1` and `network2` succeed — the `.mmd` is written — and it breaks when the link
set is read back. All three swept fine before the fix.

### Attribution (by experiment, not assumption)

Reverting *only* the connectivity criterion in `Templates.dms` — back to
`Connectiveness/IsSterkVerbonden` + `Connectiveness/NodesSterkVerbonden`, leaving the MMD
read-holder split and every other change in place — and re-running Norway's new side:

| Norway, new side | result |
|---|---|
| per-landbody criterion (`Strong_connectivity/IsConnected_seldomain`) | **fails** |
| old single-largest-SCC criterion | **exit 0, 51 s** |

So the trigger is the connectivity change. The criterion has been restored to the new one.

### Two plausible causes, both ruled out

I proposed both on #49; both are wrong, recorded here so nobody re-treads them:

1. **Duplicate `JnctIds` among retained nodes** — no. `NodeSet_src := unique(PointSet/JnctIds)`
   (`Templates.dms:79`) makes junction ids unique *by construction*, and
   `Roads/UqGeomPointSet` is a `select()` subset of it, so they stay unique.
2. **`PartNr` vs `part_rel` mismatch** in `Check_Connectiveness_T_seldomain` — no. The
   engine's `ConnectedParts.cpp` creates **both**: `part_rel` (`s_PartRel`) and the
   deprecated `PartNr` (`s_PartNr`, slated for removal in v21, GeoDMS #1177). They are the
   same data under two names, so mixing them is a style issue, not this bug.

### What the actual mechanism looks like

`CreateInitialWorkingNetwork/LinkSet_Calc` packs **three disjoint id ranges into one node
number space by hand** (`Templates.dms:~140-158`):

```
road nodes         0                       .. #Roads/UqGeomPointSet - 1
OD locations       F1 := ul_id             +  #Roads/UqGeomPointSet
new cutpoints      suggested_node_id := makedefined(ecn_rel[uint32],
                                          #Roads/UqGeomPointSet + #UniqueLocations + id(.))
```

The per-landbody criterion **retains far more nodes** than the single-largest-SCC rule did
— that is the whole point of the fix — so `#Roads/UqGeomPointSet` grows, and every offset
derived from it shifts. Downstream, `Write_FinalSet` does

```
FinalNodeSet_Calc := select_with_org_rel(pcount(LastLinkSet/F1) + pcount(LastLinkSet/F2) > 0);
F1 := invert(FinalNodeSet/org_rel)[LastLinkSet/F1];
F2 := invert(FinalNodeSet/org_rel)[LastLinkSet/F2];
```

If any `LastLinkSet/F1|F2` holds an id outside the node domain that `pcount` ranges over,
that node is never selected into `FinalNodeSet`, `invert(...)[...]` yields undefined, and
the undefined `F2` is written to the `.mmd` — surfacing exactly as
`Link_Node2_rel: out of range or undefined` when the OD builder reads it. Norway, SE2 and
SE3 being the most island-rich areas — i.e. the ones that gain the most disjoint retained
components — fits.

### Proposed fix (from @MaartenHilferink)

Disjoint, non-connected components must get node numbers that cannot coincide with those
of another component. Number the nodes **per connected group**, and give each group's
`NodeId` an offset of the *exclusive* cumulative node count:

```
offset(group) = cumulate(group/nrnodes) - group/nrnodes
```

That makes the ranges provably disjoint and self-sizing, and it replaces the current
hand-rolled `#A`, `#A + #B`, `#A + #B + i` arithmetic with one rule that cannot drift when
the retained node set changes size.

### Notes for whoever picks this up

- Reproduce with `STUDY_AREA=Norway` and
  `run_new_pharmacy_pipeline.bat Norway` (`STEPS="network1 network2 alloc"`), after purging
  `*set_O-1km*` under `C:\LocalData\networkmodel_eu\{Existing,New}Pharmacies\Norway`.
  SE2 and SE3 fail the same way; ITG, PL8, Portugal and 36 others do not.
- This blocks **F1/F2 of the recalculation plan**: the aggregate frontier sums over 41
  disjoint areas, so it cannot be rebuilt while three of them fail.
- The three areas had near-zero unreachable residents before the fix (Norway 3,696,
  SE2 32,226, SE3 475), so they are not expected to move much once fixed — the blocker is
  correctness, not results.
