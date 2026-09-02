"""Export the NUTS3 code with the client and facility tables (issue #49 / #51).

The region-exclusion rule needs, per client cell, the NUTS region it falls in. NUTS3's
NUTS_CODE carries all three levels by prefix (5 chars = NUTS3, 4 = NUTS2, 3 = NUTS1), so
one string is enough and the Julia side can pick the finest available level.

Clients get it via point-in-polygon on the NUTS3 layer; facilities the same, so an
excluded region drops its candidate locations as well as its population.
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, "cfg", "main", "Analyses.dms")
T = chr(9)
NL = chr(10)

OLD_CLIENT = (
    T * 4 + "attribute<float64> x         (Org) := Org/x;" + NL
    + T * 4 + "attribute<float64> y         (Org) := Org/y;" + NL
)
NEW_CLIENT = (
    T * 4 + "attribute<float64> x         (Org) := Org/x;" + NL
    + T * 4 + "attribute<float64> y         (Org) := Org/y;" + NL
    + T * 4 + "// NUTS3 code of the cell. NUTS_CODE carries all three levels by prefix" + NL
    + T * 4 + "// (5 = NUTS3, 4 = NUTS2, 3 = NUTS1), so the region-exclusion rule can pick" + NL
    + T * 4 + "// the finest level that is actually populated. Empty where the cell falls" + NL
    + T * 4 + "// outside every NUTS3 polygon." + NL
    + T * 4 + "attribute<string>  nuts      (Org) := MakeDefined(" + NL
    + T * 5 + "/SourceData/RegionalUnits/NUTS3/NUTS_CODE[" + NL
    + T * 5 + "   point_in_polygon(Org/geometry, /SourceData/RegionalUnits/NUTS3/geometry)], '');" + NL
)

OLD_FAC = (
    T * 4 + "attribute<float64> x   (Facility) := Get_X( Facility/geometry );" + NL
    + T * 4 + "attribute<float64> y   (Facility) := Get_Y( Facility/geometry );" + NL
)
NEW_FAC = (
    T * 4 + "attribute<float64> x   (Facility) := Get_X( Facility/geometry );" + NL
    + T * 4 + "attribute<float64> y   (Facility) := Get_Y( Facility/geometry );" + NL
    + T * 4 + "// same NUTS code, so an excluded region drops its CANDIDATE locations too" + NL
    + T * 4 + "attribute<string>  nuts(Facility) := MakeDefined(" + NL
    + T * 5 + "/SourceData/RegionalUnits/NUTS3/NUTS_CODE[" + NL
    + T * 5 + "   point_in_polygon(Facility/geometry, /SourceData/RegionalUnits/NUTS3/geometry)], '');" + NL
)


def main():
    with io.open(P, encoding="utf-8", errors="surrogateescape", newline="") as fh:
        s = fh.read()
    eol = chr(13) + chr(10) if (chr(13) + chr(10)) in s else NL

    def fix(x):
        return x.replace(chr(13) + chr(10), NL).replace(NL, eol)

    for label, old, new in (("ClientExport", OLD_CLIENT, NEW_CLIENT),
                            ("FacilityExport", OLD_FAC, NEW_FAC)):
        o, w = fix(old), fix(new)
        n = s.count(o)
        if n != 1:
            print("ABORT %s: expected 1, found %d" % (label, n))
            sys.exit(1)
        s = s.replace(o, w)
    with io.open(P, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(s)
    print("Analyses.dms: nuts code added to ClientExport and FacilityExport")


if __name__ == "__main__":
    main()
