# S1 — cap scenario, ladder rungs A & B (doc/topics.md).
# "Same kind of coverage as today, but cap each pharmacy's catchment": minimise
# the NUMBER of pharmacies needed so everyone is served and no pharmacy exceeds
# MAX_CAP residents. No minimum-catchment threshold (MIN_CAP = 0).
#
#   Rung A (multiple pharmacies per cell)  vs  rung B (combine within a cell,
#   one per cell) is chosen by the candidate data you point CANDIDATE_DIR at —
#   provide the multi-per-cell export for A, the one-per-cell export for B.
#   "All vs rural-only" is likewise just a different CANDIDATE_DIR.
#
# Control via env (see cap_scenario.jl for the full list):
#   COUNTRIES, CANDIDATE_DIR, EXISTING_DIR, MAX_CAP (residents), TRAVEL_FUNC.
get(ENV, "MIN_CAP",  "") == "" && (ENV["MIN_CAP"]  = "0")
get(ENV, "SCENARIO", "") == "" && (ENV["SCENARIO"] = "S1")
include("cap_scenario.jl")
