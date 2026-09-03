# Export the S1/S2 open-facility locations for every study area (issues #45 / #49).
#
# Reads the sweep's own scenario output:
#   <NewPharmacies>/<area>/lambda_sweep/<FUNC>/<S1|S2>/assignment.arrow   (id, open)
# joined to <area>_j.arrow (id -> x, y) — the j-id space is per-file LOCAL, so the join
# must go through that file and not through any global id.
#
# Naming: <area>_<s1|s2>_<linear|logistic>_open.arrow -- the form that
# cfg/main/SourceData/Locations.dms `services_allocated` reads literally. The #45 batches
# used <area>_<S1|S2>_<LINEAR|LOGISTIC>_open.arrow; on Windows those are the SAME file
# (case-insensitive), so writing both was pointless -- but a zip stores whatever name was
# written, and on a case-sensitive filesystem only one of the two would resolve. Writing
# the form the config asks for is therefore the safe choice, and the delivery note must
# say the naming changed.
using Arrow

const BASE = get(ENV, "NEWPH_DIR", "C:/LocalData/networkmodel_eu/NewPharmacies")
const OUT  = get(ENV, "S1S2_OUT",  "E:/prj/JRC/NetworkModel_EU/scratch/s1s2_open_locations")

areas = if !isempty(ARGS)
    ARGS
else
    # every area with a candidate-side j.arrow, i.e. every swept study area
    [replace(f, "_j.arrow" => "") for f in readdir(BASE) if endswith(f, "_j.arrow")]
end

mkpath(OUT)
nfiles = 0; nrows = 0; nmiss = 0
missing_list = String[]

for area in sort(areas)
    jpath = joinpath(BASE, "$(area)_j.arrow")
    isfile(jpath) || continue
    jt  = Arrow.Table(jpath)
    jid = Int.(jt.id); jx = Float64.(jt.x); jy = Float64.(jt.y)
    pos = Dict(jid[k] => k for k in 1:length(jid))

    for func in ("LINEAR", "LOGISTIC"), scen in ("S1", "S2")
        f = joinpath(BASE, area, "lambda_sweep", func, scen, "assignment.arrow")
        if !isfile(f)
            global nmiss += 1; push!(missing_list, "$area/$func/$scen"); continue
        end
        a = Arrow.Table(f)
        openids = Int.(a.id)[Int.(a.open) .== 1]
        xs = Float64[]; ys = Float64[]
        for id in openids
            haskey(pos, id) || continue
            r = pos[id]; push!(xs, jx[r]); push!(ys, jy[r])
        end
        out = joinpath(OUT, "$(area)_$(lowercase(scen))_$(lowercase(func))_open.arrow")
        Arrow.write(out, (x = xs, y = ys))
        global nfiles += 1; global nrows += length(xs)
    end
end

println("wrote $nfiles files for $(length(areas)) areas, $nrows open locations")
if nmiss > 0
    println("  MISSING $nmiss scenario outputs:")
    for m in first(missing_list, 20); println("    $m"); end
end
