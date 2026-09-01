"""Follow-up to apply_modelclient.py.

Allocate_T (Analyses.dms:264-504) is instantiated for BOTH pharmacies (Org =
ModelClient) and schools (Org = Client), and both reader templates
(ReadResults_T / ReadSweepResults_T) are only ever instantiated from inside it
(callers at :361-364 and :381-388). So everything INSIDE that family must follow
the template's own `Org` parameter -- exactly the generalisation Chris applied to
`client_rel` in 79cb58b -- and must NOT hard-code Client or ModelClient.

Only the pharmacy-specific code OUTSIDE the template keeps an explicit ModelClient:
the two allocation call sites and the descriptives at :42-44.
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, "cfg", "main", "Analyses.dms")

EDITS = [
    # the two reader templates: their ids index the OD client domain = Org
    ("ClientTravelTime            (ModelClient) := rjoin(ID(ModelClient), "
     "convert(ResultingClientAssignment/id, ModelClient), ResultingClientAssignment/t_ij);",
     "ClientTravelTime            (Org) := rjoin(ID(Org), "
     "convert(ResultingClientAssignment/id, Org), ResultingClientAssignment/t_ij);", 2),
    ("ClientTravelTime_Classified (ModelClient) :=",
     "ClientTravelTime_Classified (Org) :=", 2),
    # the OD export inside Allocate_T
    ("attribute<Client>    Client_rel   (OD) := ../client_rel;",
     "attribute<Org>       Client_rel   (OD) := ../client_rel;", 1),
    # travel-time deltas vs baseline
    ("attribute<min_f> dT_lin_S1  (Client) :=", "attribute<min_f> dT_lin_S1  (Org) :=", 1),
    ("attribute<min_f> dT_lin_S2  (Client) :=", "attribute<min_f> dT_lin_S2  (Org) :=", 1),
    ("attribute<min_f> dT_quad_S1 (Client) :=", "attribute<min_f> dT_quad_S1 (Org) :=", 1),
    ("attribute<min_f> dT_quad_S2 (Client) :=", "attribute<min_f> dT_quad_S2 (Org) :=", 1),
    ("attribute<min_f> dT_log_S1  (Client) :=", "attribute<min_f> dT_log_S1  (Org) :=", 1),
    ("attribute<min_f> dT_log_S2  (Client) :=", "attribute<min_f> dT_log_S2  (Org) :=", 1),
    # Summary container
    ("ClientTravelTime_lp_central                (Client)        :=",
     "ClientTravelTime_lp_central                (Org)           :=", 1),
    ("ClientTravelTime_Classified_lp_central     (Client)        :=",
     "ClientTravelTime_Classified_lp_central     (Org)           :=", 1),
    ("ClientTravelTime_lp_nearest                (Client)        :=",
     "ClientTravelTime_lp_nearest                (Org)           :=", 1),
    ("ClientTravelTime_Classified_lp_nearest     (Client)        :=",
     "ClientTravelTime_Classified_lp_nearest     (Org)           :=", 1),
    ("ClientTravelTime_greedy_central            (Client)        :=",
     "ClientTravelTime_greedy_central            (Org)           :=", 1),
    ("ClientTravelTime_Classified_greedy_central (Client)        :=",
     "ClientTravelTime_Classified_greedy_central (Org)           :=", 1),
    ("ClientTravelTime_greedy_nearest            (Client)        :=",
     "ClientTravelTime_greedy_nearest            (Org)           :=", 1),
    ("ClientTravelTime_Classified_greedy_nearest (Client)        :=",
     "ClientTravelTime_Classified_greedy_nearest (Org)           :=", 1),
]


def main():
    with io.open(P, encoding="utf-8", errors="surrogateescape", newline="") as fh:
        s = fh.read()
    eol = chr(13) + chr(10) if (chr(13) + chr(10)) in s else chr(10)

    def fix(x):
        return x.replace(chr(13) + chr(10), chr(10)).replace(chr(10), eol)

    for old, new, n in EDITS:
        old, new = fix(old), fix(new)
        got = s.count(old)
        if got != n:
            print("ABORT: expected %d, found %d for: %s" % (n, got, old[:90]))
            sys.exit(1)
        s = s.replace(old, new)
    with io.open(P, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(s)
    print("Analyses.dms patched (template internals -> Org)")

    print("  ModelClient use sites:")
    for i, line in enumerate(s.split(eol), 1):
        if "ModelClient" in line and not line.strip().startswith("//"):
            print("    %4d  %s" % (i, line.strip()[:95]))
    print("  remaining hard-coded (Client) / <Client>:")
    hits = 0
    for i, line in enumerate(s.split(eol), 1):
        t = line.strip()
        if t.startswith("//") or "ModelClient" in line:
            continue
        if "(Client)" in line or "<Client>" in line:
            print("    %4d  %s" % (i, t[:95]))
            hits += 1
    if not hits:
        print("    none")


if __name__ == "__main__":
    main()
