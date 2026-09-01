"""Restrict NewPharmacyLocations to countries that have pharmacy supply data.

Agreed on issue #49: the candidate set gets the same coverage filter as ModelClient.
With lambda > 0 the LP would never open a facility that serves nobody, so this does
not change the optimum -- but it stops the reported candidate count M from including
cells that can never be selected, which is confusing in the sweep logs, and it keeps
the candidate universe consistent with the client universe.

covered_country lives in Analyses.dms and is defined over
/SourceData/RegionalUnits/Country/subset; Base_grid_1km/points/Country_rel indexes
that same unit (Geography.dms:77).
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, "cfg", "main", "SourceData", "Locations.dms")
T = chr(9)

OLD = (
    T + "unit<uint32> NewPharmacyLocations := select_with_org_rel(" + chr(10)
    + T * 3 + "   /Geography/Base_grid_1km/points/population >= ModelParameters/MinPopSizeForPharmacyLocation" + chr(10)
    + T * 3 + "|| IsDefined(rlookup(/Geography/Base_grid_1km/points/geometry[Base_grid], Pharmacies/within_StudyArea/uq_cells/values))" + chr(10)
    + T * 2 + ")" + chr(10)
)

NEW = (
    T + "// Issue #49: the candidate set carries the SAME coverage filter as ModelClient --" + chr(10)
    + T + "// only countries for which pharmacy supply data exists. With lambda > 0 the LP would" + chr(10)
    + T + "// never open a facility that serves nobody, so the optimum is unchanged; this keeps" + chr(10)
    + T + "// the candidate universe consistent with the client universe and stops the reported" + chr(10)
    + T + "// candidate count M from including cells that can never be selected." + chr(10)
    + T + "unit<uint32> NewPharmacyLocations := select_with_org_rel(" + chr(10)
    + T * 3 + "   (" + chr(10)
    + T * 3 + "      /Geography/Base_grid_1km/points/population >= ModelParameters/MinPopSizeForPharmacyLocation" + chr(10)
    + T * 3 + "   || IsDefined(rlookup(/Geography/Base_grid_1km/points/geometry[Base_grid], Pharmacies/within_StudyArea/uq_cells/values))" + chr(10)
    + T * 3 + "   )" + chr(10)
    + T * 3 + "&& /Analyses/covered_country[/Geography/Base_grid_1km/points/Country_rel]" + chr(10)
    + T * 2 + ")" + chr(10)
)


def main():
    with io.open(P, encoding="utf-8", errors="surrogateescape", newline="") as fh:
        s = fh.read()
    eol = chr(13) + chr(10) if (chr(13) + chr(10)) in s else chr(10)

    def fix(x):
        return x.replace(chr(13) + chr(10), chr(10)).replace(chr(10), eol)

    o, w = fix(OLD), fix(NEW)
    got = s.count(o)
    if got != 1:
        print("ABORT: expected 1, found %d" % got)
        print(repr(o[:200]))
        sys.exit(1)
    with io.open(P, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(s.replace(o, w))
    print("Locations.dms: NewPharmacyLocations restricted to covered countries")


if __name__ == "__main__":
    main()
