# S1 — "reduce travel, keep the number of pharmacies constant" (doc/topics.md).
# Place a FIXED number of pharmacies (TARGET_COUNT, default = today's cell count)
# to MINIMISE travel, with a max catchment cap so the optimum doesn't collapse
# every dense cell to one pharmacy and scatter the rest across the countryside.
#
# Pick the rung with RUNG=A|B|C (default A — Lewis's "start at A"):
#   A  allow MULTIPLE pharmacies per grid cell (x[j] integer >= 0); for a true
#      packing test set TARGET_COUNT to the raw pharmacy count (e.g. 1992 for NL).
#   B  at most ONE pharmacy per grid cell (combine within a cell first).
#   C  hold URBAN-centre pharmacies fixed (cells with own pop >= URBAN_POP) and
#      only model the rest of the territory.
#
# Other control via env (see cap_scenario.jl): COUNTRIES, CANDIDATE_DIR,
# EXISTING_DIR, MAX_CAP, TARGET_COUNT, URBAN_POP, TRAVEL_FUNC.
ENV["SCENARIO"] = "S1"
rung = uppercase(get(ENV, "RUNG", "A"))
if rung == "A"
    get(ENV, "PER_CELL", "") == "" && (ENV["PER_CELL"] = "multi")
    ENV["URBAN_POP"] = "0"
elseif rung == "B"
    get(ENV, "PER_CELL", "") == "" && (ENV["PER_CELL"] = "one")
    ENV["URBAN_POP"] = "0"
elseif rung == "C"
    get(ENV, "PER_CELL", "") == "" && (ENV["PER_CELL"] = "one")
    get(ENV, "URBAN_POP", "0") == "0" && (ENV["URBAN_POP"] = "25000")  # ~ NL dense-cell pop
else
    error("RUNG must be A, B or C for S1 (got $rung)")
end
include("cap_scenario.jl")
