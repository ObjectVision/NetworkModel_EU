using Arrow, JuMP, HiGHS, Random

const LOCAL_DATA_DIR       = "C:\\LocalData"
const PROJ_NAME            = "networkmodel_eu"
const LOCAL_DATA_PROJ_DIR  = joinpath(LOCAL_DATA_DIR, PROJ_NAME)
const ANALYSIS             = get(ENV, "ANALYSIS", "ExistingPharmacies")  # ExistingPharmacies | NewPharmacies | ExistingSchools | NewSchools
const ANALYSIS_DIR         = joinpath(LOCAL_DATA_PROJ_DIR, ANALYSIS)

# full set: Albania Austria Belgium Bulgaria Switzerland Denmark Spain Estonia Greece Cyprus Czechia Germany France Finland Croatia Hungary Ireland Iceland Italy Liechtenstein Lithuania Luxembourg Latvia Malta Netherlands Norway Romania Poland Portugal Sweden Slovenia Slovakia
const COUNTRIES = split(get(ENV, "COUNTRIES", "France Italy Netherlands Sweden"))

# Which Arrow column to use as per-client weight in the LP objective.
# Available columns in `<country>_i.arrow`: pop (= configured ModelParameters.Client, e.g. 6..12 y/o),
# total_pop (= total grid-cell population). Falls back to `pop` if the configured column is missing.
const CLIENT_WEIGHT = get(ENV, "CLIENT_WEIGHT", "total_pop")

const FACILITY_MIN_COSTS    = parse(Int, get(ENV, "FACILITY_MIN_COSTS",    "100000"))
const FACILITY_CLIENT_COSTS = parse(Int, get(ENV, "FACILITY_CLIENT_COSTS", "3333"))

# Scale-up test knob: keep only every K-th facility row (and the OD rows
# referencing those facilities). 1 = keep all (default), 10 = keep 10%.
# Pass `apply_factor=false` to a loader when you want to bypass it (e.g. for
# the baseline ExistingPharmacies dataset, which should stay full-size).
const LOCATION_SELECTION_FACTOR = parse(Int, get(ENV, "LOCATION_SELECTION_FACTOR", "1"))

const FUNC_LINEAR    = 1
const FUNC_QUADRATIC = 2
const FUNC_PIECEWISE = 3
const FUNC_LOGISTIC  = 4
const FUNC_FLOOR     = 5
const FUNC_CONCAVE   = 6

const FUNC_NAMES = Dict(
    "LINEAR"    => FUNC_LINEAR,
    "QUADRATIC" => FUNC_QUADRATIC,
    "PIECEWISE" => FUNC_PIECEWISE,
    "LOGISTIC"  => FUNC_LOGISTIC,
    "FLOOR"     => FUNC_FLOOR,
    "CONCAVE"   => FUNC_CONCAVE,
)

parse_func(envname, default) = FUNC_NAMES[get(ENV, envname, default)]

travel_func   = parse_func("TRAVEL_FUNC",   "QUADRATIC")
facility_func = parse_func("FACILITY_FUNC", "LINEAR")

# LP-relaxation → integer open-set rounding rule used by the warm-start sweep.
# All three keep the same count p=round(sum_x); only WHICH facilities differ.
#   "topp"      — open the p facilities with the largest x_relaxed.
#   "greedy"    — x≈1 seed, then greedily grab the fractional with the largest
#                 marginal travel-cost reduction until p are open.
#   "multistart"— x-weighted randomized seeds (plus top-p & greedy as seeds 1-2),
#                 each polished by swap local search; keep the lowest-travel set.
#                 Guaranteed ≤ min(topp, greedy) since both are seeds.
const ROUNDING = get(ENV, "ROUNDING", "multistart")

# Multi-start local-search knobs (only used when comparing/selecting multistart).
const MS_RESTARTS = parse(Int, get(ENV, "MS_RESTARTS", "10"))  # incl. topp+greedy seeds
const MS_ROUNDS   = parse(Int, get(ENV, "MS_ROUNDS",   "12"))  # max swaps per restart
const MS_SEED     = parse(Int, get(ENV, "MS_SEED",     "20240601"))

# Canonical name of the active travel-cost function (for output paths / labels).
const FUNC_INT_TO_NAME = Dict(v => k for (k, v) in FUNC_NAMES)
travel_func_name = FUNC_INT_TO_NAME[travel_func]

# Adapted logit (doc/todo.md C8; roadmap "apply adapted logit"): midpoint 25 / scale 10
# tracks Lewis's ~5 & ~45-min kinks — lower below ~10 min (indifferent to minor
# relocations), saturating by ~45 min (caps remote weight). See the deck's travel-cost
# page. Env-overridable; the pre-recalc variant was LOGISTIC_MIDPOINT=30 SCALE=15.
logistic_midpoint = parse(Float64, get(ENV, "LOGISTIC_MIDPOINT", "25"))  # minutes
logistic_scale    = parse(Float64, get(ENV, "LOGISTIC_SCALE",    "10"))  # minutes

function c(t)
    if travel_func == FUNC_QUADRATIC
        return 0.05 * t^2 + 0.5 * t
    elseif travel_func == FUNC_PIECEWISE
        if t <= 15
            return 1.0 * t
        elseif t <= 30
            return 2.0 * t
        else
            return 4.0 * t
        end
    elseif travel_func == FUNC_LINEAR
        return t
    elseif travel_func == FUNC_LOGISTIC
        return 1.0 / (1.0 + exp(-(t - logistic_midpoint) / logistic_scale))
    end
end

# Stranded-client price (BIG). Fixed at the MAX_TRAVELTIME_MIN=120 OD cutoff EVERYWHERE for
# linear-type costs (2026-07-12) — NOT each region's observed t_max, which ranged 42–120 min
# across regions and priced stranding inconsistently (Paris 42 vs Norway 120), breaking the
# cross-region aggregate. For LINEAR, c(120)=120 exactly. LOGISTIC saturates, so BIG=1.0.
# Env override BIG_TRAVELTIME_MIN for experiments.
const MAX_TRAVELTIME_MIN = parse(Float64, get(ENV, "BIG_TRAVELTIME_MIN", "120"))
big_cost() = travel_func == FUNC_LOGISTIC ? 1.0 : c(MAX_TRAVELTIME_MIN)

function facility_cost(q)
    if facility_func == FUNC_LINEAR
        return FACILITY_MIN_COSTS + q * FACILITY_CLIENT_COSTS
    elseif facility_func == FUNC_FLOOR
        return max(FACILITY_MIN_COSTS, q * FACILITY_CLIENT_COSTS)
    elseif facility_func == FUNC_CONCAVE
        return 51712 * q^0.465
    end
end

input_path(country, suffix) =
    joinpath(ANALYSIS_DIR, "$(country)_$(suffix).arrow")

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

function client_weight_col(loc)
    sym = Symbol(CLIENT_WEIGHT)
    if sym in propertynames(loc)
        return loc[sym]
    else
        @warn "Arrow file lacks column '$CLIENT_WEIGHT'; falling back to 'pop'. Regenerate with the updated GeoDMS pipeline to get the new column."
        return loc[:pop]
    end
end

# script: "lp" or "greedy"; assignment: "nearest" or "central"; kind: "assignment" or "traveltime"
function output_path(country, script, assignment, kind)
    dir = joinpath(ANALYSIS_DIR, country, script, assignment)
    mkpath(dir)
    joinpath(dir, "$(kind).arrow")
end

struct CountryData
    N::Int
    M::Int
    facilities::Vector{Int}
    wpop::Vector{Float32}
    clients_col::Vector{Int}
    t_ij_col::Vector{Float32}
    facilities_col::Vector{Int}
    locations::Dict{Int, Vector{Int}}
    facility_rows::Dict{Int, Vector{Int}}
    client_pop::Dict{Int, Float32}
    nearest_facility::Dict{Int, Int}
end

function load_country(country; apply_factor::Bool=true)::CountryData
    od  = Arrow.Table(input_path(country, "od"))
    loc = Arrow.Table(input_path(country, "i"))
    fac = Arrow.Table(input_path(country, "j"))

    # Subsample facilities (every K-th row); filter OD to references that survive.
    # ALWAYS keep candidate cells that coincide with an existing (baseline) pharmacy —
    # a blind stride drops most baseline locations (FRI factor=3 kept only 35%), so the
    # frontier can no longer reproduce the current network: it stops dominating the
    # baseline and S1/S2 land on the wrong side (S2 ends up with MORE facilities than
    # baseline). Only the NON-baseline extras are strided. Env PROTECT_BASELINE=0 to
    # restore the old blind-stride behaviour.
    factor         = apply_factor ? LOCATION_SELECTION_FACTOR : 1
    facilities_all = Int.(fac[:id])
    protect        = get(ENV, "PROTECT_BASELINE", "1") == "1"
    expath         = joinpath(LOCAL_DATA_PROJ_DIR, "ExistingPharmacies", "$(country)_j.arrow")
    if factor > 1 && protect && isfile(expath) && (:x in propertynames(fac))
        exj  = Arrow.Table(expath)
        base = Set(zip(Int.(round.(collect(exj.x))), Int.(round.(collect(exj.y)))))
        fx   = Int.(round.(collect(fac[:x]))); fy = Int.(round.(collect(fac[:y])))
        isb  = [(fx[i], fy[i]) in base for i in eachindex(facilities_all)]
        rest = facilities_all[.!isb]
        facilities = sort(unique(vcat(facilities_all[isb], rest[1:factor:end])))
        @info "load_country($country): protected $(count(isb)) baseline candidates; " *
              "kept $(length(facilities)) of $(length(facilities_all)) (factor=$factor)"
    else
        facilities = facilities_all[1:factor:length(facilities_all)]
    end
    fset           = Set(facilities)
    od_facrel_all  = Int.(od[:facility_rel])
    mask           = factor == 1 ? trues(length(od_facrel_all)) :
                                   [f ∈ fset for f in od_facrel_all]

    clients_col    = Int.(od[:client_rel])[mask]
    facilities_col = od_facrel_all[mask]
    t_ij_col       = (od[:t_ij] ./ 60)[mask]
    population     = client_weight_col(loc)

    N = length(clients_col)
    M = length(facilities)

    wpop = [population[clients_col[k]+1] for k in 1:N]

    locations = Dict{Int, Vector{Int}}()
    for k in 1:N
        i = clients_col[k]
        haskey(locations, i) ? push!(locations[i], k) : (locations[i] = [k])
    end

    facility_rows = Dict{Int, Vector{Int}}()
    for k in 1:N
        j = facilities_col[k]
        if !haskey(facility_rows, j)
            facility_rows[j] = Int[]
        end
        push!(facility_rows[j], k)
    end
    for j in facilities
        if !haskey(facility_rows, j)
            facility_rows[j] = Int[]
        end
    end

    client_pop = Dict(i => population[i+1] for i in keys(locations))

    nearest_facility = Dict{Int, Int}()
    for (i, rows) in locations
        best_k = rows[argmin(c(t_ij_col[k]) for k in rows)]
        nearest_facility[i] = facilities_col[best_k]
    end

    return CountryData(N, M, facilities, wpop, clients_col, t_ij_col, facilities_col,
                       locations, facility_rows, client_pop, nearest_facility)
end

# Returns the country's data NamedTuple, or `nothing` when the country has no
# usable input (missing arrow files or zero OD rows). Prints a one-line
# "skipped" message in both cases so per-country loops can `continue`.
function try_load_country(country)
    local data
    try
        data = load_country(country)
    catch e
        if e isa SystemError
            println("\n$country — skipped (input file missing: $(e.prefix))")
            return nothing
        else
            rethrow()
        end
    end
    if data.N == 0
        println("\n$country — skipped (no OD rows / no clients in input data)")
        return nothing
    end
    return data
end
