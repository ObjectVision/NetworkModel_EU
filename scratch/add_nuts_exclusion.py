"""Region exclusion: drop NUTS regions that no road network can serve (issue #49).

Rule, as agreed: for a NUTS region, if MORE THAN 50% of its inhabitant locations are
absent from the OD matrix -- i.e. with or without a road network they cannot reach any
pharmacy within the maximum travel time -- exclude the WHOLE region. Both its population
and its candidate locations drop out of the baseline AND the lambda sweep.

Level: NUTS3 where available, else NUTS2, else NUTS1. The client/facility tables carry a
single NUTS3 code and the three levels are its 5/4/3-character prefixes, so "available"
means the prefix is actually populated for that cell.

Coverage is judged on the EXISTING OD (the baseline network), so the verdict does not
depend on which candidate set a run happens to use, and is identical for baseline and
sweep. The excluded regions are written to scratch/excluded_regions_<country>.csv for the
deck.

Env NUTS_EXCLUSION=0 disables the rule.
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NL = chr(10)

HELPER = '''
# ---------------------------------------------------------------------------
# Region exclusion (issue #49): a NUTS region whose inhabitants cannot reach any
# pharmacy AT ALL is a DATA/coverage gap, not a policy finding. Pricing it at BIG
# inflated Portugal's baseline by ~63% (the Azores and Madeira hold population but
# no pharmacy in the source data). Rule: if > EXCLUDE_SHARE of a region's inhabitant
# locations are absent from the OD matrix, drop the whole region -- population AND
# candidate locations -- from both the baseline and the sweep.
#
# Level: NUTS3 if populated, else NUTS2, else NUTS1 (the table carries one NUTS3 code;
# the coarser levels are its 4- and 3-character prefixes).
# Verdict is taken on the EXISTING OD so it is identical for baseline and sweep.
const EXCLUDE_SHARE = parse(Float64, get(ENV, "NUTS_EXCLUDE_SHARE", "0.5"))

nuts_prefix(code::AbstractString, k::Int) = length(code) >= k ? code[1:k] : ""

"""Return (excluded::Set{String}, level::Int, report::Vector) for `country`.
`excluded` holds codes at the chosen level; `level` is 3, 2 or 1."""
function excluded_nuts_regions(country::AbstractString)
    get(ENV, "NUTS_EXCLUSION", "1") == "1" || return (Set{String}(), 0, [])
    ipath  = joinpath(EXISTING_PATH, "$(country)_i.arrow")
    odpath = joinpath(EXISTING_PATH, "$(country)_od.arrow")
    (isfile(ipath) && isfile(odpath)) || return (Set{String}(), 0, [])
    loc = Arrow.Table(ipath)
    if !(:NUTS in propertynames(loc))
        @warn "$(country): client table has no NUTS column; region exclusion skipped. " *
              "Regenerate the exports with the updated GeoDMS pipeline."
        return (Set{String}(), 0, [])
    end
    od  = Arrow.Table(odpath)
    n   = length(loc[:id])
    inod = falses(n)
    for r in od[:client_rel]; inod[r + 1] = true; end
    pop = client_weight_col(loc)
    codes = loc[:NUTS]

    for k in (5, 4, 3)                       # NUTS3, NUTS2, NUTS1
        groups = Dict{String, Vector{Int}}()
        for r in 1:n
            g = nuts_prefix(String(codes[r]), k)
            isempty(g) && continue
            push!(get!(groups, g, Int[]), r)
        end
        isempty(groups) && continue          # this level is not available: fall back
        report = Tuple{String, Float64, Float64, Int}[]
        for (g, rs) in groups
            share = count(!, inod[rs]) / length(rs)
            share > EXCLUDE_SHARE && push!(report, (g, share, sum(pop[rs]), length(rs)))
        end
        sort!(report, by = t -> -t[3])
        lvl = k == 5 ? 3 : k == 4 ? 2 : 1
        if !isempty(report)
            open(joinpath(@__DIR__, "scratch", "excluded_regions_$(country).csv"), "w") do fh
                println(fh, "country,nuts_level,nuts_code,share_not_in_od,population,cells")
                for (g, s, p, c) in report
                    println(fh, "$country,$lvl,$g,$(round(s, digits=4)),$(round(Int, p)),$c")
                end
            end
            @info "$(country): excluding $(length(report)) NUTS$(lvl) region(s) with " *
                  ">$(round(100*EXCLUDE_SHARE))% of inhabitant locations absent from the OD: " *
                  join(["$(g) ($(round(100*s, digits=1))%, $(round(Int, p)) residents)"
                        for (g, s, p, c) in report], ", ")
        end
        return (Set(t[1] for t in report), lvl, report)
    end
    return (Set{String}(), 0, [])
end

"""Boolean mask over the rows of `tbl` marking rows inside an excluded region."""
function in_excluded_region(tbl, excluded::Set{String}, level::Int)
    (isempty(excluded) || level == 0) && return falses(length(tbl[:id]))
    k = level == 3 ? 5 : level == 2 ? 4 : 3
    (:NUTS in propertynames(tbl)) || return falses(length(tbl[:id]))
    return [nuts_prefix(String(c), k) in excluded for c in tbl[:NUTS]]
end
'''

PATCH_ANCHOR = "function client_weight_col(loc)"

LOADER_OLD = """    facilities_all = Int.(fac[:id])
"""
LOADER_NEW = """    # Region exclusion (issue #49): drop candidate locations in NUTS regions that the
    # rule below excludes, so an uncoverable region contributes neither demand nor supply.
    excl, excl_level, _ = excluded_nuts_regions(country)
    facilities_all = Int.(fac[:id])
    if !isempty(excl)
        facmask = in_excluded_region(fac, excl, excl_level)
        facilities_all = facilities_all[.!facmask]
    end
"""

POP_OLD = """    population     = client_weight_col(loc)
"""
POP_NEW = """    population     = collect(client_weight_col(loc))
    if !isempty(excl)
        # zero the weight of every client in an excluded region: it then contributes
        # nothing to travel cost, nothing to the BIG penalty, and nothing to the
        # reported client population -- in the baseline and in the sweep alike.
        cmask = in_excluded_region(loc, excl, excl_level)
        population[cmask] .= 0
    end
"""


def main():
    sp = os.path.join(ROOT, "settings.jl")
    s = io.open(sp, encoding="utf-8", newline="").read()
    if "excluded_nuts_regions" not in s:
        i = s.index(PATCH_ANCHOR)
        s = s[:i] + HELPER.strip() + NL + NL + s[i:]
        io.open(sp, "w", encoding="utf-8", newline="").write(s)
        print("settings.jl: exclusion helpers added")
    else:
        print("settings.jl: helpers already present")

    lp = os.path.join(ROOT, "lambda_sweep_simplex.jl")
    t = io.open(lp, encoding="utf-8", newline="").read()
    CRLF = chr(13) + chr(10)
    eol = CRLF if CRLF in t else NL

    def fix(x):
        return x.replace(CRLF, NL).replace(NL, eol)

    for label, old, new in (("facilities", LOADER_OLD, LOADER_NEW),
                            ("population", POP_OLD, POP_NEW)):
        old, new = fix(old), fix(new)
        if new.strip().splitlines()[0] in t:
            print("lambda_sweep_simplex.jl: %s already patched" % label)
            continue
        if t.count(old) != 1:
            print("ABORT %s: expected 1, found %d" % (label, t.count(old)))
            sys.exit(1)
        t = t.replace(old, new)
    io.open(lp, "w", encoding="utf-8", newline="").write(t)
    print("lambda_sweep_simplex.jl: exclusion applied in load_from")


if __name__ == "__main__":
    main()
