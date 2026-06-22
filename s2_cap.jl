# S2 — "reduce the number of pharmacies, keep travel constant" (doc/topics.md).
# MINIMISE the number of pharmacies subject to a MIN catchment threshold (each
# open pharmacy needs enough customers to be viable) and the same max cap as S1.
# Travel is reported against today; set TRAVEL_SLACK to hard-bound served travel
# at baseline*(1+slack).
#
# Pick the rung with RUNG=A|B (default A — Lewis's "start at A"):
#   A  reduce ALL facilities globally (min + max catchment).
#   B  reduce only facilities OUTSIDE urban centres: cells with own pop >=
#      URBAN_POP are held fixed, the min-catchment reduction applies to the rest.
# (S2 Option C is the cost function — use the lambda sweep, not this script.)
#
# Other control via env (see cap_scenario.jl): COUNTRIES, CANDIDATE_DIR,
# EXISTING_DIR, MIN_CAP, MAX_CAP, URBAN_POP, TRAVEL_SLACK, TRAVEL_FUNC.
ENV["SCENARIO"] = "S2"
get(ENV, "PER_CELL", "") == "" && (ENV["PER_CELL"] = "one")
rung = uppercase(get(ENV, "RUNG", "A"))
if rung == "A"
    ENV["URBAN_POP"] = "0"
elseif rung == "B"
    get(ENV, "URBAN_POP", "0") == "0" && (ENV["URBAN_POP"] = "25000")  # ~ NL dense-cell pop
else
    error("RUNG must be A or B for S2 without a cost function (got $rung)")
end
get(ENV, "MIN_CAP", "") == "" && (ENV["MIN_CAP"] = "4000")
get(ENV, "MAX_CAP", "") == "" && (ENV["MAX_CAP"] = "35000")
include("cap_scenario.jl")
