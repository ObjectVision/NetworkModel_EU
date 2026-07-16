# Policy typology per modeled region, from doc/Typology_Countries_to_share.pptx
# (Archetypes of countries' posture — use case pharmacy, slides 11–16).
#
# Two country-level attributes:
#   archetype    1 Rule-of-law–anchored | 2 Consensual-pluralist |
#                3 Public-interest majoritarian | 4 Segmented-federal
#   formalisation  HIGH | MEDIUM | LOW | VARIES  (the deck's colour legend)
# Colour codes taken verbatim from the slide-11 legend chips.
#
# Writes doc/policy_typology.csv: region,iso,country,archetype,archetype_name,formalisation,color
import os, csv

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FORM_COLOR = {"HIGH": "C0392B", "MEDIUM": "E67E22", "LOW": "27AE60", "VARIES": "8E44AD"}
ARCH_NAME = {1: "Rule-of-law–anchored", 2: "Consensual-pluralist",
             3: "Public-interest majoritarian", 4: "Segmented-federal"}

# country ISO -> (name, archetype, formalisation)  [from slides 13–16 "Formal." column]
COUNTRY = {
    "AT": ("Austria", 1, "HIGH"),   "BE": ("Belgium", 1, "MEDIUM"),
    "FR": ("France", 1, "HIGH"),    "IT": ("Italy", 1, "HIGH"),
    "LU": ("Luxembourg", 1, "HIGH"),"PL": ("Poland", 1, "HIGH"),
    "PT": ("Portugal", 1, "HIGH"),  "SI": ("Slovenia", 1, "HIGH"),
    "LV": ("Latvia", 1, "MEDIUM"),
    "DK": ("Denmark", 2, "HIGH"),   "EE": ("Estonia", 2, "MEDIUM"),
    "CZ": ("Czechia", 3, "LOW"),    "IE": ("Ireland", 3, "LOW"),
    "LT": ("Lithuania", 3, "LOW"),  "NL": ("Netherlands", 3, "LOW"),
    "NO": ("Norway", 3, "LOW"),     "SE": ("Sweden", 3, "LOW"),
}

# modeled region -> country ISO
REGION_ISO = {
    "Netherlands": "NL", "Luxembourg": "LU", "Estonia": "EE", "Latvia": "LV",
    "Slovenia": "SI", "Lithuania": "LT", "Ireland": "IE", "Norway": "NO",
    "Denmark": "DK", "Austria": "AT", "Portugal": "PT", "Czechia": "CZ",
    "Belgium": "BE", "Poland": "PL",
    **{r: "FR" for r in ("FR1", "FRB", "FRC", "FRD", "FRE", "FRF", "FRG",
                          "FRH", "FRI", "FRJ", "FRK", "FRL", "FRM")},
    **{r: "IT" for r in ("ITC", "ITF", "ITG", "ITH", "ITI")},
    **{r: "SE" for r in ("SE1", "SE2", "SE3")},
    **{r: "PL" for r in ("PL2", "PL4", "PL5", "PL6", "PL7", "PL8", "PL9")},
}

rows = []
for reg, iso in REGION_ISO.items():
    name, arch, form = COUNTRY[iso]
    rows.append([reg, iso, name, arch, ARCH_NAME[arch], form, FORM_COLOR[form]])

dest = os.path.join(ROOT, "doc", "policy_typology.csv")
with open(dest, "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["region", "iso", "country", "archetype", "archetype_name",
                "formalisation", "color"])
    w.writerows(sorted(rows))
print(f"wrote {dest}  ({len(rows)} regions)")
for r in sorted(rows, key=lambda r: (r[3], r[5], r[0])):
    print(f"  {r[0]:>12}  T{r[3]} {r[5]:>7}  #{r[6]}  {r[4]}")
