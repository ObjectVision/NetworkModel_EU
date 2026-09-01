"""Make the TomTom Junctions MMD holder bare (GeoDms 20.19 read-holder contract).

Same pattern as Read_Streets: the single derived attribute IsWithinStudyArea moves
NEXT TO the holder, over its domain, so the holder declares only StorageName +
StorageReadOnly and its sub-items (JNCTID, geometry) come from the .mmd dictionary.
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, "cfg", "main", "SourceData", "Infrastructure", "TomTom.dms")
T = chr(9)
Q = chr(34)
NL = chr(10)

OLD = (
    T * 2 + "unit<uint32> Junctions" + NL
    + T * 2 + ": StorageName = " + Q + "=JunctionFileName" + Q + NL
    + T * 2 + ", StorageReadOnly = " + Q + "True" + Q + NL
    + T * 2 + "{" + NL
    + T * 3 + "attribute<bool>               IsWithinStudyArea := =/ModelParameters/Use_NUTS1_selection" + NL
    + T * 4 + "? 'IsDefined(point_in_polygon(geometry, /SourceData/RegionalUnits/NUTS1/Subset/geometry))'" + NL
    + T * 4 + ": 'IsDefined(point_in_polygon(geometry, /SourceData/RegionalUnits/Country/subset/geometry_BB))';" + NL
    + T * 2 + "}" + NL
)

NEW = (
    T * 2 + "// #1154/#1179 (GeoDms 20.19+): bare read holder; JNCTID and geometry come from" + NL
    + T * 2 + "// the .mmd dictionary. The derived IsWithinStudyArea lives next to it." + NL
    + T * 2 + "unit<uint32> Junctions" + NL
    + T * 2 + ": StorageName = " + Q + "=JunctionFileName" + Q + NL
    + T * 2 + ", StorageReadOnly = " + Q + "True" + Q + ";" + NL
    + T * 2 + NL
    + T * 2 + "attribute<bool> IsWithinStudyArea (Junctions) := =/ModelParameters/Use_NUTS1_selection" + NL
    + T * 3 + "? 'IsDefined(point_in_polygon(Junctions/geometry, /SourceData/RegionalUnits/NUTS1/Subset/geometry))'" + NL
    + T * 3 + ": 'IsDefined(point_in_polygon(Junctions/geometry, /SourceData/RegionalUnits/Country/subset/geometry_BB))';" + NL
)


def main():
    with io.open(P, encoding="utf-8", errors="surrogateescape", newline="") as fh:
        s = fh.read()
    eol = chr(13) + chr(10) if (chr(13) + chr(10)) in s else NL

    def fix(x):
        return x.replace(chr(13) + chr(10), NL).replace(NL, eol)

    o, w = fix(OLD), fix(NEW)
    got = s.count(o)
    if got != 1:
        print("ABORT: expected 1, found %d" % got)
        print(repr(o[:240]))
        sys.exit(1)
    s = s.replace(o, w)
    # Junctions/IsWithinStudyArea is referenced from the sibling helpers; it is now a
    # sibling itself, so drop the qualifier where it was addressed through the unit.
    s = s.replace(fix("Junctions/IsWithinStudyArea[F_JNCT_rel]"),
                  fix("IsWithinStudyArea[F_JNCT_rel]"))
    with io.open(P, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(s)
    print("TomTom.dms: Junctions holder made bare, IsWithinStudyArea moved alongside")


if __name__ == "__main__":
    main()
