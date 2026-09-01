"""Make the TomTom Read_Streets MMD holder bare (GeoDms 20.19 read-holder contract).

MmdStorageManager::DoUpdateTree refuses a read-only MMD holder that declares sub-items:
they come from the .mmd's own dictionary. Read_Streets declared four derived selection
helpers inside it. Only Streets_Selection_Condition is used outside (TomTom.dms:82), the
other three are its inputs, so all four move NEXT TO the holder, over its domain --
no alias layer, so the dictionary attributes (F_JNCTID, FRC_rel, Direction, ...) keep
resolving directly on Read_Streets.
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
    T * 2 + "unit<uint32> Read_Streets" + NL
    + T * 2 + ": StorageName = " + Q + "=StreetFileName" + Q + NL
    + T * 2 + ", StorageReadOnly = " + Q + "True" + Q + NL
    + T * 2 + "{" + NL
    + T * 3 + "attribute<Junctions>          F_JNCT_rel                          := rlookup(F_JNCTID, Junctions/JNCTID);" + NL
    + T * 3 + "attribute<bool>               Streets_IsJunctionWithinStudyArea   := Junctions/IsWithinStudyArea[F_JNCT_rel];" + NL
    + T * 3 + "attribute<bool>               Streets_IsStreetTypeSubsetSelectie  := ='FRC_rel <= '+ModelParameters/StreetTypeSubsetSelectie;" + NL
    + T * 3 + NL
    + T * 3 + "attribute<bool>               Streets_Selection_Condition         := =ModelParameters/UseStreetTypeSubset ? 'Streets_IsStreetTypeSubsetSelectie && Streets_IsJunctionWithinStudyArea' : 'Streets_IsJunctionWithinStudyArea';" + NL
    + T * 2 + "}" + NL
)

NEW = (
    T * 2 + "// #1154/#1179 (GeoDms 20.19+): a read-only MMD holder declares ONLY StorageName" + NL
    + T * 2 + "// and StorageReadOnly -- every sub-item comes from the .mmd's own dictionary," + NL
    + T * 2 + "// which the engine merges in. The derived selection helpers therefore live" + NL
    + T * 2 + "// NEXT TO the holder, over its domain, instead of inside it. No alias layer, so" + NL
    + T * 2 + "// the dictionary attributes (F_JNCTID, FRC_rel, Direction, ...) keep resolving" + NL
    + T * 2 + "// directly on Read_Streets." + NL
    + T * 2 + "unit<uint32> Read_Streets" + NL
    + T * 2 + ": StorageName = " + Q + "=StreetFileName" + Q + NL
    + T * 2 + ", StorageReadOnly = " + Q + "True" + Q + ";" + NL
    + T * 2 + NL
    + T * 2 + "attribute<Junctions> F_JNCT_rel                         (Read_Streets) := rlookup(Read_Streets/F_JNCTID, Junctions/JNCTID);" + NL
    + T * 2 + "attribute<bool>      Streets_IsJunctionWithinStudyArea  (Read_Streets) := Junctions/IsWithinStudyArea[F_JNCT_rel];" + NL
    + T * 2 + "attribute<bool>      Streets_IsStreetTypeSubsetSelectie (Read_Streets) := ='Read_Streets/FRC_rel <= '+ModelParameters/StreetTypeSubsetSelectie;" + NL
    + T * 2 + "attribute<bool>      Streets_Selection_Condition        (Read_Streets) := =ModelParameters/UseStreetTypeSubset ? 'Streets_IsStreetTypeSubsetSelectie && Streets_IsJunctionWithinStudyArea' : 'Streets_IsJunctionWithinStudyArea';" + NL
)

OLD_SEL = "select_with_attr_by_cond(Read_Streets, Read_Streets/Streets_Selection_Condition)"
NEW_SEL = "select_with_attr_by_cond(Read_Streets, Streets_Selection_Condition)"


def main():
    with io.open(P, encoding="utf-8", errors="surrogateescape", newline="") as fh:
        s = fh.read()
    eol = chr(13) + chr(10) if (chr(13) + chr(10)) in s else NL

    def fix(x):
        return x.replace(chr(13) + chr(10), NL).replace(NL, eol)

    for label, old, new, n in (("holder", OLD, NEW, 1), ("selection", OLD_SEL, NEW_SEL, 1)):
        o, w = fix(old), fix(new)
        got = s.count(o)
        if got != n:
            print("ABORT %s: expected %d, found %d" % (label, n, got))
            print(repr(o[:220]))
            sys.exit(1)
        s = s.replace(o, w)
    with io.open(P, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(s)
    print("TomTom.dms: Read_Streets holder made bare, helpers moved alongside")


if __name__ == "__main__":
    main()
