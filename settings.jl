using Arrow, JuMP, HiGHS

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

logistic_midpoint = 30.0  # minutes
logistic_scale    = 15.0  # minutes

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
    factor         = apply_factor ? LOCATION_SELECTION_FACTOR : 1
    facilities_all = Int.(fac[:id])
    facilities     = facilities_all[1:factor:length(facilities_all)]
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
