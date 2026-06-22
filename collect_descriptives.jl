# Collect the per-study-area Pharmacies_Descriptives/<area>.arrow files (written by
# /Analyses/Pharmacies/Descriptives/Table) into CSV tables for the deck:
#   <out_csv>            country level (NL + the countries with data)
#   <out_csv>_nuts1.csv  same, with each country's NUTS1 regions listed below it
#   julia collect_descriptives.jl <arrow_dir> [out_csv]
using Arrow

dir      = length(ARGS) >= 1 ? ARGS[1] : "C:/LocalData/networkmodel_eu/Pharmacies_Descriptives"
out_csv  = length(ARGS) >= 2 ? ARGS[2] : joinpath(dir, "descriptive_table.csv")
nuts_csv = replace(out_csv, r"\.csv$" => "_nuts1.csv")

country_order = ["Netherlands", "France", "Italy", "Sweden"]
nuts1_order   = ["Netherlands",
                 "France", "FR1", "FRB", "FRC", "FRD", "FRE", "FRF", "FRG", "FRH", "FRI", "FRJ", "FRK", "FRL", "FRM",
                 "Italy", "ITC", "ITF", "ITG", "ITH", "ITI",
                 "Sweden", "SE1", "SE2", "SE3"]

fmt(x) = x isa AbstractFloat ? (isinteger(x) ? string(Int(round(x))) : string(round(x; digits = 1))) : string(x)

function write_table(order, path)
    files = [(a, joinpath(dir, a * ".arrow")) for a in order]
    files = [(a, f) for (a, f) in files if isfile(f)]
    isempty(files) && (println("  (no arrow files for $path)"); return files)
    cols = collect(propertynames(Arrow.Table(files[1][2])))
    open(path, "w") do io
        println(io, join(string.(cols), ","))
        for (a, f) in files
            t = Arrow.Table(f)
            println(io, join([fmt(getproperty(t, c)[1]) for c in cols], ","))
        end
    end
    println("wrote $path  ($(length(files)) rows, $(length(cols)) cols)")
    return files
end

write_table(country_order, out_csv)
files = write_table(nuts1_order, nuts_csv)

# compact echo of the headline columns (full table)
key = [:study_area, :n_pharmacies, :n_pharmacy_cells, :residents_per_pharmacy, :max_pharm_in_cell, :cell_p50]
key = filter(in(collect(propertynames(Arrow.Table(files[1][2])))), key)
println(join(rpad.(string.(key), 14), " "))
for (a, f) in files
    t = Arrow.Table(f)
    println(join([rpad(fmt(getproperty(t, c)[1]), 14) for c in key], " "))
end
