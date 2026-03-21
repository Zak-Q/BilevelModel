using Pkg

Pkg.add("Plots")
Pkg.add("BilevelJuMP")
Pkg.add("Gurobi")
Pkg.add("CSV")
Pkg.add("DataFrames")
using Plots, BilevelJuMP, Gurobi
using CSV, DataFrames, JuMP

df = CSV.read("result.csv", DataFrame)


gr()

# 时间轴
x = df.Time

# 储能净出力
p_bess_net = df.P_dis .- df.P_ch

# 堆叠数据矩阵：每一列是一层
tech_data =[df.P_thermal df.P_dis]
# hcat(p_bess_net, df.P_thermal)

# 标签
tech_labels = ["P_thermal" "P_dis"]

# 主图：堆叠面积图
p1 = areaplot(
    x,
    tech_data,
    label = tech_labels,
    stack = :stack,
    xlabel = "Time",
    ylabel = "Power (MW)",
    legend = :outerright,
    linewidth = 0,
    size = (1000, 500)
)

p_ch_neg = .-df.P_ch

plot!(
    p1,
    x,
    p_ch_neg,
    fillrange = 0,
    fillalpha = 0.5,
    color = :purple,
    linewidth = 1.5,
    label = "P_ch",
    xlabel = "Time",
    ylabel = "Power (MW)",
    title = "Charging Power as Negative Area"
)

# 叠加负载曲线
plot!(
    p1,
    x,
    df.P_demand,
    label = "P_demand",
    linewidth = 3
)

# SOC 图
p2 = plot(
    x,
    df.SOC,
    label = "SOC",
    xlabel = "Time",
    ylabel = "Energy (MWh)",
    linewidth = 2.5,
    marker = :circle,
    legend = :topright,
    size = (1000, 300)
)

# 两张图放一起
plot(p1, p2, layout = (2,1), size = (1000, 800))