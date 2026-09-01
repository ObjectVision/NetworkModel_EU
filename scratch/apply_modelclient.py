"""Introduce ModelClient as the single client unit shared by baseline and LP.

Client      : the demand UNIVERSE  -- every inhabited cell in the study area.
ModelClient : the demand we can MODEL -- inhabited cells in countries for which
              pharmacy supply data exists. Baseline and LP must both use this one,
              or S1/S2 and the frontier compare different populations.

Renames the existing Client_pharmacy_coverage to ModelClient rather than adding an
alias on top of it: Analyses.dms itself warns that "a `unit := other` alias does not
expose the other's named sub-items", and an extra unit layer is exactly the kind of
domain-identity ambiguity this change is meant to remove.

Schools (AllocateKidsTo*Schools) deliberately stay on Client: covered_country is
defined from PHARMACY coverage, so it must not gate school runs.
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, "cfg", "main", "Analyses.dms")

TAB = chr(9)

# (old, new, expected_count)
EDITS = [
    # 1. the definition: rename + document the pair
    (
        TAB + "attribute<bool> covered_country",
        TAB + "// Client      : the demand UNIVERSE -- every inhabited cell in the study area." + chr(10)
        + TAB + "// ModelClient : the demand we can legitimately MODEL -- inhabited cells in" + chr(10)
        + TAB + "//               countries for which pharmacy supply data exists. covered_country" + chr(10)
        + TAB + "//               states DATA AVAILABILITY, not accessibility: residents of a" + chr(10)
        + TAB + "//               country without pharmacy records are not badly served, we simply" + chr(10)
        + TAB + "//               do not know how they are served, and pricing them at BIG would" + chr(10)
        + TAB + "//               let a data gap masquerade as a policy finding (issue #49)." + chr(10)
        + TAB + "//               BASELINE and LP must BOTH use ModelClient -- S1/S2, the frontier," + chr(10)
        + TAB + "//               its rectangle and the diagonal crossing are all defined relative" + chr(10)
        + TAB + "//               to the baseline point, so the two sides must carry the SAME" + chr(10)
        + TAB + "//               population (doc/todo.md B3). Schools keep plain Client: this" + chr(10)
        + TAB + "//               filter is pharmacy-specific." + chr(10)
        + TAB + "attribute<bool> covered_country",
        1,
    ),
    (
        TAB + "unit<uint32> Client_pharmacy_coverage:=",
        TAB + "unit<uint32> ModelClient:=",
        1,
    ),
    # 2. baseline side
    (
        TAB * 3 + "  Client_pharmacy_coverage" + chr(10),
        TAB * 3 + "  ModelClient" + chr(10),
        1,
    ),
    # 3. LP side + the s1/s2 reporting containers (their travel times are compared
    #    with the baseline, so they must share its client set)
    (
        TAB * 3 + "  Client" + chr(10)
        + TAB * 3 + ", SourceData/Locations/NewPharmacyLocations/within_StudyArea",
        TAB * 3 + "  ModelClient" + chr(10)
        + TAB * 3 + ", SourceData/Locations/NewPharmacyLocations/within_StudyArea",
        1,
    ),
    (
        TAB * 3 + "  Client" + chr(10)
        + TAB * 3 + ", /SourceData/Locations/services_allocated/resultfiles_s1_logistic",
        TAB * 3 + "  ModelClient" + chr(10)
        + TAB * 3 + ", /SourceData/Locations/services_allocated/resultfiles_s1_logistic",
        1,
    ),
    (
        TAB * 3 + "  Client" + chr(10)
        + TAB * 3 + ", /SourceData/Locations/services_allocated/resultfiles_s2_logistic",
        TAB * 3 + "  ModelClient" + chr(10)
        + TAB * 3 + ", /SourceData/Locations/services_allocated/resultfiles_s2_logistic",
        1,
    ),
    # 4. descriptives over the EXISTING allocation: client_rel now follows Org
    (
        "best_od                     (Client) :=",
        "best_od                     (ModelClient) :=",
        1,
    ),
    (
        "nearest_cell_by_road_client (Client) :=",
        "nearest_cell_by_road_client (ModelClient) :=",
        1,
    ),
    (
        "attribute<Client> grid_client_rel             (grid)   := rlookup("
        "Base_grid_1km/points/grid_domain_rel, Client/grid_domain_rel);",
        "attribute<ModelClient> grid_client_rel        (grid)   := rlookup("
        "Base_grid_1km/points/grid_domain_rel, ModelClient/grid_domain_rel);",
        1,
    ),
    # 5. the two result readers: their ids index the OD client domain
    (
        "ClientTravelTime            (Client) := rjoin(ID(Client), "
        "convert(ResultingClientAssignment/id, Client), ResultingClientAssignment/t_ij);",
        "ClientTravelTime            (ModelClient) := rjoin(ID(ModelClient), "
        "convert(ResultingClientAssignment/id, ModelClient), ResultingClientAssignment/t_ij);",
        2,
    ),
    (
        "ClientTravelTime_Classified (Client) :=",
        "ClientTravelTime_Classified (ModelClient) :=",
        2,
    ),
]


def main():
    with io.open(P, encoding="utf-8", errors="surrogateescape", newline="") as fh:
        s = fh.read()
    orig = s
    # Analyses.dms is CRLF in the working tree; build the patterns with the file's
    # own line ending so a CRLF/LF mismatch cannot silently match nothing.
    eol = chr(13) + chr(10) if (chr(13) + chr(10)) in s else chr(10)
    def fix(x):
        return x.replace(chr(13) + chr(10), chr(10)).replace(chr(10), eol)
    for old, new, n in EDITS:
        old, new = fix(old), fix(new)
        got = s.count(old)
        if got != n:
            print("ABORT: expected %d occurrence(s), found %d for:" % (n, got))
            print("   " + old.replace(chr(10), " <NL> ")[:120])
            sys.exit(1)
        s = s.replace(old, new)
    if s == orig:
        print("no change")
        sys.exit(1)
    with io.open(P, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(s)
    print("Analyses.dms patched")
    print("  remaining bare 'Client' refs (should be schools + the Client definition):")
    for i, line in enumerate(s.split(chr(10)), 1):
        t = line.strip()
        if "ModelClient" in line:
            continue
        if ("Client" in line and not t.startswith("//")
                and ("(Client)" in line or "  Client" == line.rstrip()
                     or "<Client>" in line)):
            print("    %4d  %s" % (i, t[:100]))


if __name__ == "__main__":
    main()
