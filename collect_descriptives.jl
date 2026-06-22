# Collect the per-study-area Pharmacies_Descriptives/<area>.arrow files (written by
# /Analyses/Pharmacies/Descriptives/Table) into one CSV table.
#   julia collect_descriptives.jl <arrow_dir> [out_csv]
using Arrow

dir     = length(ARGS) >= 1 ? ARGS[1] : "C:/LocalData/networkmodel_eu/Pharmacies_Descriptives"
out_csv = length(ARGS) >= 2 ? ARGS[2] : joinpath(dir, "descriptive_table.csv")

# display order: country level only (NUTS1 dropped for now). Add countries here as
# their pharmacy data arrives.
order = ["Netherlands", "France", "Italy", "Sweden"]

files = [(a, joinpath(dir, a * ".arrow")) for a in order]
files = [(a, f) for (a, f) in files if isfile(f)]
isempty(files) && error("no per-area arrow files found in $dir")

cols = collect(propertynames(Arrow.Table(files[1][2])))

fmt(x) = x isa AbstractFloat ? (isinteger(x) ? string(Int(round(x))) : string(round(x; digits = 1))) : string(x)

open(out_csv, "w") do io
    println(io, join(string.(cols), ","))
    for (a, f) in files
        t = Arrow.Table(f)
        println(io, join([fmt(getproperty(t, c)[1]) for c in cols], ","))
    end
end
println("wrote $out_csv  ($(length(files)) study areas, $(length(cols)) columns)")

# also echo a compact view of the headline columns
key = [:study_area, :n_pharmacies, :n_pharmacy_cells, :n_residents, :residents_per_pharmacy,
       :n_cells_multi, :max_pharm_in_cell, :cell_p50, :pharm_p50]
key = filter(in(cols), key)
println(join(rpad.(string.(key), 13), " "))
for (a, f) in files
    t = Arrow.Table(f)
    println(join([rpad(fmt(getproperty(t, c)[1]), 13) for c in key], " "))
end
