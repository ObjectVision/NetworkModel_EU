"""Split the read-only MMD holder from the derived items it used to declare.

GeoDms 20.19 (engine issues #1154/#1179/#1180) enforces the read-holder contract in
MmdStorageManager::DoUpdateTree: a holder with StorageReadOnly=True must declare ONLY
itself -- StorageName + StorageReadOnly -- and every sub-item comes from the .mmd's own
dictionary (0Dictionary.dms), which the engine merges in. A reader-declared sub-item
would collide with its dictionary namesake, so it is now refused loudly instead of
being silently merged over.

cfg/main/Templates.dms declared the whole derived tree (OrgNode_rel, OD_nodes,
Length_Direct, geometry, Export, store, ...) INSIDE that holder. Split it:

  container FinalSet_stored  -- the bare read holder; FinalNodeSet / FinalLinkSet /
                                ChangesTracker arrive from the dictionary
  container FinalSet         -- keeps the OUTER name, so every external reference
                                (Analyses.dms:274/275/510/511, NetworkSetup.dms:67)
                                stays valid; its units alias the stored ones and carry
                                the derived attributes as before
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, "cfg", "main", "Templates.dms")
T = chr(9)

OLD_HEADER = (
    T * 3 + "container FinalSet" + chr(10)
    + T * 3 + ": StorageName = " + chr(34) + "= propvalue(Write_FinalSet, 'StorageName')" + chr(34) + chr(10)
    + T * 3 + ", StorageReadOnly = " + chr(34) + "True" + chr(34) + chr(10)
    + T * 3 + "{" + chr(10)
    + T * 4 + "unit<uint32> FinalNodeSet " + chr(10)
)

NEW_HEADER = (
    T * 3 + "// #1154/#1179 (GeoDms 20.19+): a read-only MMD holder must declare ONLY" + chr(10)
    + T * 3 + "// StorageName + StorageReadOnly. Every sub-item comes from the .mmd's own" + chr(10)
    + T * 3 + "// dictionary (0Dictionary.dms), which the engine merges in; a reader-declared" + chr(10)
    + T * 3 + "// sub-item would collide with its dictionary namesake and is now refused." + chr(10)
    + T * 3 + "// So the holder is bare, and the DERIVED items live in the sibling container." + chr(10)
    + T * 3 + "container FinalSet_stored" + chr(10)
    + T * 3 + ": StorageName = " + chr(34) + "= propvalue(Write_FinalSet, 'StorageName')" + chr(34) + chr(10)
    + T * 3 + ", StorageReadOnly = " + chr(34) + "True" + chr(34) + chr(10)
    + T * 3 + "{" + chr(10)
    + T * 3 + "}" + chr(10)
    + chr(10)
    + T * 3 + "// Keeps the OUTER name FinalSet, so every external reference stays valid." + chr(10)
    + T * 3 + "container FinalSet" + chr(10)
    + T * 3 + "{" + chr(10)
    + T * 4 + "unit<uint32> FinalNodeSet := FinalSet_stored/FinalNodeSet" + chr(10)
)

OLD_LINK = T * 4 + "unit<uint32> FinalLinkSet" + chr(10)
NEW_LINK = T * 4 + "unit<uint32> FinalLinkSet := FinalSet_stored/FinalLinkSet" + chr(10)


def main():
    with io.open(P, encoding="utf-8", errors="surrogateescape", newline="") as fh:
        s = fh.read()
    eol = chr(13) + chr(10) if (chr(13) + chr(10)) in s else chr(10)

    def fix(x):
        return x.replace(chr(13) + chr(10), chr(10)).replace(chr(10), eol)

    for label, old, new, n in (
        ("holder header", OLD_HEADER, NEW_HEADER, 1),
        ("FinalLinkSet header", OLD_LINK, NEW_LINK, 1),
    ):
        o, w = fix(old), fix(new)
        got = s.count(o)
        if got != n:
            print("ABORT %s: expected %d, found %d" % (label, n, got))
            print("   " + repr(o[:160]))
            sys.exit(1)
        s = s.replace(o, w)

    with io.open(P, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(s)
    print("Templates.dms: read holder split into FinalSet_stored + FinalSet")


if __name__ == "__main__":
    main()
