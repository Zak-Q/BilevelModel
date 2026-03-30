using Pkg

Pkg.add("Plots")
Pkg.add("BilevelJuMP")
Pkg.add("Gurobi")
Pkg.add("CSV")
Pkg.add("DataFrames")
Pkg.add("StatsPlots")
using Plots, BilevelJuMP, Gurobi
using CSV, DataFrames, JuMP, StatsPlots

function save_numbered_plot(fig; folder = "results", prefix = "bilevel_results", ext = "png", digits = 2)
    output_dir = joinpath(@__DIR__, folder)
    isdir(output_dir) || mkpath(output_dir)

    pattern = Regex("^" * prefix * "(\\d+)\\." * ext)
    max_id = 0

    for file in readdir(output_dir)
        m = match(pattern, file)
        if m !== nothing
            max_id = max(max_id, parse(Int, m.captures[1]))
        end
    end

    next_id = max_id + 1
    filename = prefix * lpad(string(next_id), digits, '0') * "." * ext
    filepath = joinpath(output_dir, filename)

    savefig(fig, filepath)
    println("Saved plot to: ", filepath)
    return filepath
end

df = CSV.read("G:\\github\\Test\\result01.csv", DataFrame)

println(round.(df.P_demand))
gr()

# 时间轴
x = df.Time

# Keep for further plotting of all technologies
# tech_data = [p_blc p_brc p_hyd p_wnd p_sol p_batd p_gas p_unserved]
# tech_labels = ["BlackCoal" "BrownCoal" "Hydro" "Wind" "UtilitySolar" "UtilityStorage" "Gas" "UnservedDemand"]
# tech_colors = [:black :brown :navy :MediumSpringGreen :DarkOrange :purple :Salmon :gray]

tech_data =[df.P_thermal df.P_dis]
# hcat(p_bess_net, df.P_thermal)

# 标签
tech_labels = ["P_thermal" "P_dis"]
p_ch_neg = .-df.P_ch
p_demand = df.P_demand
soc = df.SOC

# 第一张图：无缝条形图 + 阶梯负载线
p1 = groupedbar(
    x,
    tech_data,
    bar_width = 1.0,
    bar_position = :stack,
    label = tech_labels,
    color = [:orange :green],
    linecolor = :transparent,
    xlabel = "Hours",
    ylabel = "Power (MW)",
    legend = :outerright,
    xticks = 1:24
)


# 在 0 轴下方画充电功率
bar!(
    p1,
    x,
    p_ch_neg,
    bar_width = 1.0,
    bottom = 0,
    label = "P_ch",
    color = :purple,
    linecolor = :transparent
)

# 叠加阶梯状负载线
plot!(
    p1,
    vcat(x .- 0.5, x[end] + 0.5 ),
    vcat(p_demand, p_demand[end]),
    seriestype = :steppost,
    color = :blue,
    linewidth = 3,
    label = "P_demand"
)

# 第二张图：SOC
p2 = plot(
    x,
    soc,
    color = :black,
    linewidth = 2.5,
    marker = :circle,
    label = "SOC",
    xlabel = "Hours",
    ylabel = "Energy (MWh)",
    xticks = 1:24,
    legend = :topright,
    size = (1200, 300)
)

bilevel_plot= plot(p1, p2, layout = (2,1), size = (1300, 900))
save_numbered_plot(bilevel_plot)