# S2 — cap scenario with a minimum-catchment threshold (doc/topics.md).
# "Fewer, right-sized pharmacies, travel no worse than today": minimise the
# NUMBER of pharmacies subject to BOTH a MIN_CAP (no pharmacy serves fewer than
# MIN_CAP residents — eliminates tiny inefficient pharmacies) and a MAX_CAP
# (no pharmacy serves more than MAX_CAP residents). The honest travel cost is
# reported against the baseline so you can confirm it does not get worse.
#
# As in S1, "which pharmacies (all / rural-only / one-per-cell)" is controlled
# entirely by CANDIDATE_DIR. Sweep several thresholds by passing space-separated
# lists, e.g. MIN_CAP="1000 2000 4000".
#
# Control via env (see cap_scenario.jl):
#   COUNTRIES, CANDIDATE_DIR, EXISTING_DIR, MIN_CAP, MAX_CAP (residents), TRAVEL_FUNC.
get(ENV, "MIN_CAP",  "") == "" && (ENV["MIN_CAP"]  = "4000")
get(ENV, "MAX_CAP",  "") == "" && (ENV["MAX_CAP"]  = "35000")
get(ENV, "SCENARIO", "") == "" && (ENV["SCENARIO"] = "S2")
include("cap_scenario.jl")
