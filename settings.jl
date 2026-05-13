using Arrow, JuMP, HiGHS

const LOCAL_DATA_DIR       = "C:\\LocalData"
const PROJ_NAME            = "networkmodel_eu"
const LOCAL_DATA_PROJ_DIR  = joinpath(LOCAL_DATA_DIR, PROJ_NAME)
const EXISTING_SCHOOLS_DIR = joinpath(LOCAL_DATA_PROJ_DIR, "ExistingSchools")

const COUNTRIES = ["Albania", "Austria", "Belgium", "Bulgaria", "Switzerland", "Denmark", "Spain", "Estonia", "Greece", "Cyprus", "Czechia", "Germany", "France", "Finland", "Croatia", "Hungary", "Ireland", "Iceland", "Italy", "Liechtenstein", "Lithuania", "Luxembourg", "Latvia", "Malta", "Netherlands", "Norway", "Romania", "Poland", "Portugal", "Sweden", "Slovenia", "Slovakia"]

const FACILITY_COST = 99699

travel = "quadratic"  # "linear", "quadratic", or "piecewise"

function c(t)
    if travel == "quadratic"
        return 0.05 * t^2 + 0.5 * t
    elseif travel == "piecewise"
        if t <= 15
            return 1.0 * t
        elseif t <= 30
            return 2.0 * t
        else
            return 4.0 * t
        end
    elseif travel == "linear"
        return t
    end
end

input_path(country, suffix) =
    joinpath(EXISTING_SCHOOLS_DIR, "$(country)_$(suffix).arrow")

# script: "lp" or "greedy"; assignment: "nearest" or "central"; kind: "assignment" or "traveltime"
function output_path(country, script, assignment, kind)
    dir = joinpath(EXISTING_SCHOOLS_DIR, country, script, assignment)
    mkpath(dir)
    joinpath(dir, "$(kind).arrow")
end

function load_country(country)
    od  = Arrow.Table(input_path(country, "od"))
    loc = Arrow.Table(input_path(country, "i"))
    fac = Arrow.Table(input_path(country, "j"))

    clients_col    = Int.(od[:client_rel])
    facilities_col = Int.(od[:facility_rel])
    t_ij_col       = od[:t_ij] ./ 60
    population     = loc[:pop]
    facilities     = Int.(fac[:id])

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

    return (; N, M, facilities, wpop, clients_col, t_ij_col, facilities_col,
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
