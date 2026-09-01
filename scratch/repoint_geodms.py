"""Repoint the pharmacy pipeline scripts from the GeoDMS engine BUILD TREE to the
INSTALLED GeoDms 20.19.1.m.

Why: C:\\dev\\GeoDMS_2026\\bin\\Release\\x64 is the live build output of the GeoDMS
engine project. Running GeoDmsRun from there (a) loads binaries that may be mid-relink,
and (b) holds a handle on Dm*.dll, which makes the next engine link silently skip.
"""
import io
import os

OLD = "C:" + chr(92) + "dev" + chr(92) + "GeoDMS_2026" + chr(92) + "bin" + chr(92) \
      + "Release" + chr(92) + "x64" + chr(92) + "GeoDmsRun.exe"
NEW = "C:" + chr(92) + "Program Files" + chr(92) + "ObjectVision" + chr(92) \
      + "GeoDms20.19.1.m" + chr(92) + "GeoDmsRun.exe"

NOTE = [
    "REM Use the INSTALLED GeoDms, NOT the engine build tree at C:" + chr(92) + "dev" + chr(92) + "GeoDMS_2026:",
    "REM a run from there loads binaries that may be mid-relink, and holds a handle on",
    "REM Dm*.dll which makes the next engine link silently skip.",
]

BATS = ["run_pharmacy_pipeline.bat", "run_new_pharmacy_pipeline.bat",
        "make_descriptive_table.bat"]
PS1 = "scratch/rebuild_italy_country.ps1"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(p):
    with io.open(os.path.join(ROOT, p), encoding="utf-8", errors="surrogateescape",
                 newline="") as fh:
        return fh.read()


def write(p, s):
    with io.open(os.path.join(ROOT, p), "w", encoding="utf-8",
                 errors="surrogateescape", newline="") as fh:
        fh.write(s)


def main():
    for p in BATS:
        s = read(p)
        if OLD not in s:
            print("  skip (already repointed?):", p)
            continue
        eol = "\r\n" if "\r\n" in s else "\n"
        out = []
        for line in s.split(eol):
            if line.strip().startswith('if "%GEODMS_EXE%"==""') and OLD in line:
                out.extend(NOTE)
                out.append(line.replace(OLD, NEW))
            elif "Install GeoDms 20.0.3.m or set GEODMS_EXE" in line:
                out.append(line.replace("20.0.3.m", "20.19.1.m"))
            else:
                out.append(line)
        write(p, eol.join(out))
        print("  patched:", p)

    s = read(PS1)
    if OLD in s:
        write(PS1, s.replace(OLD, NEW))
        print("  patched:", PS1)
    else:
        print("  skip:", PS1)


if __name__ == "__main__":
    main()
