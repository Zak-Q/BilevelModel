# 可视化模块
# 生成各类结果图表

using Plots
using StatsPlots
using DataFrames
using Printf

# 设置中文字体 (根据系统调整)
# 在macOS上,可以使用以下字体
chinese_font = "PingFang SC"

# 设置绘图默认参数
default(
    fontfamily = chinese_font,
    titlefontsize = 14,
    guidefontsize = 12,
    tickfontsize = 10,
    legendfontsize = 10,
    linewidth = 2,
    markersize = 4,
    size = (1000, 600),
    dpi = 150
)

"""
    plot_soc_curve(results, data, output_dir)

绘制储能SOC曲线
"""
function plot_soc_curve(results, data, output_dir)
    T = data.T
    stor = data.storage[1, :]
    
    p = plot(
        1:T, 
        results[:e],
        label = "荷电状态 (SOC)",
        xlabel = "时段",
        ylabel = "能量 (MWh)",
        title = "储能系统荷电状态曲线",
        lw = 3,
        color = :blue,
        marker = :circle,
        markersize = 3,
        grid = true,
        legend = :topright
    )
    
    # 添加上下限线
    hline!([stor.E_max], label="最大容量", linestyle=:dash, color=:red, lw=2)
    hline!([stor.E_min], label="最小容量", linestyle=:dash, color=:orange, lw=2)
    hline!([stor.E_init], label="初始能量", linestyle=:dot, color=:green, lw=2)
    
    # 保存图片
    fig_path = joinpath(output_dir, "figures", "soc_curve.png")
    savefig(p, fig_path)
    println("  ✓ 已生成: soc_curve.png")
    
    return p
end

"""
    plot_power_schedule(results, data, output_dir)

绘制充放电功率曲线
"""
function plot_power_schedule(results, data, output_dir)
    T = data.T
    
    p = plot(
        xlabel = "时段",
        ylabel = "功率 (MW)",
        title = "储能充放电功率调度",
        legend = :topright,
        grid = true
    )
    
    # 放电功率 (正值)
    plot!(p, 1:T, results[:p_dis], 
        label = "放电功率", 
        color = :red, 
        lw = 3,
        marker = :circle,
        markersize = 3
    )
    
    # 充电功率 (负值显示)
    plot!(p, 1:T, -results[:p_ch], 
        label = "充电功率 (负值)", 
        color = :blue, 
        lw = 3,
        marker = :square,
        markersize = 3
    )
    
    hline!([0], color=:black, linestyle=:dash, label="", lw=1)
    
    fig_path = joinpath(output_dir, "figures", "power_schedule.png")
    savefig(p, fig_path)
    println("  ✓ 已生成: power_schedule.png")
    
    return p
end

"""
    plot_market_prices(results, data, output_dir)

绘制市场价格曲线
"""
function plot_market_prices(results, data, output_dir)
    T = data.T
    
    p1 = plot(
        1:T,
        results[:λ_EN],
        label = "能量市场价格",
        xlabel = "时段",
        ylabel = "价格 (\$/MWh)",
        title = "日前市场价格曲线",
        color = :purple,
        lw = 3,
        marker = :circle,
        markersize = 3,
        grid = true,
        legend = :topright
    )
    
    p2 = plot(
        xlabel = "时段",
        ylabel = "价格 (\$/MW)",
        title = "备用市场价格",
        legend = :topright,
        grid = true
    )
    
    plot!(p2, 1:T, results[:λ_UP], 
        label = "上备用价格", 
        color = :green, 
        lw = 3,
        marker = :circle,
        markersize = 3
    )
    
    plot!(p2, 1:T, results[:λ_DN], 
        label = "下备用价格", 
        color = :orange, 
        lw = 3,
        marker = :square,
        markersize = 3
    )
    
    # 组合图
    p = plot(p1, p2, layout = (2, 1), size = (1000, 800))
    
    fig_path = joinpath(output_dir, "figures", "market_prices.png")
    savefig(p, fig_path)
    println("  ✓ 已生成: market_prices.png")
    
    return p
end

"""
    plot_reserve_capacity(results, data, output_dir)

绘制备用容量投标
"""
function plot_reserve_capacity(results, data, output_dir)
    T = data.T
    
    p1 = plot(
        xlabel = "时段",
        ylabel = "上备用容量 (MW)",
        title = "上备用容量投标",
        legend = :topright,
        grid = true
    )
    
    plot!(p1, 1:T, results[:r_up_ch], 
        label = "充电上备用", 
        color = :skyblue, 
        lw = 2,
        marker = :circle
    )
    
    plot!(p1, 1:T, results[:r_up_dis], 
        label = "放电上备用", 
        color = :coral, 
        lw = 2,
        marker = :square
    )
    
    p2 = plot(
        xlabel = "时段",
        ylabel = "下备用容量 (MW)",
        title = "下备用容量投标",
        legend = :topright,
        grid = true
    )
    
    plot!(p2, 1:T, results[:r_dn_ch], 
        label = "充电下备用", 
        color = :lightblue, 
        lw = 2,
        marker = :circle
    )
    
    plot!(p2, 1:T, results[:r_dn_dis], 
        label = "放电下备用", 
        color = :salmon, 
        lw = 2,
        marker = :square
    )
    
    p = plot(p1, p2, layout = (2, 1), size = (1000, 800))
    
    fig_path = joinpath(output_dir, "figures", "reserve_capacity.png")
    savefig(p, fig_path)
    println("  ✓ 已生成: reserve_capacity.png")
    
    return p
end

"""
    plot_profit_breakdown(results, data, output_dir)

绘制利润分解图
"""
function plot_profit_breakdown(results, data, output_dir)
    profit = results[:profit]
    
    # 分市场利润
    categories = ["能量\n市场", "上备用\n市场", "下备用\n市场", "平衡\n市场"]
    revenues = [
        profit[:energy],
        profit[:reserve_up],
        profit[:reserve_dn],
        profit[:balancing]
    ]
    
    # 堆叠柱状图
    p1 = bar(
        categories,
        revenues,
        xlabel = "市场类型",
        ylabel = "收益 (\$)",
        title = "储能分市场收益对比",
        legend = false,
        color = [:purple, :green, :orange, :cyan],
        grid = true,
        bar_width = 0.6
    )
    
    # 添加数值标签
    for (i, v) in enumerate(revenues)
        annotate!(i, v + 50, text(@sprintf("\$%.0f", v), 10, :center))
    end
    
    # 饼图
    labels = ["能量市场\n$(round(profit[:energy]/profit[:total]*100, digits=1))%",
              "上备用\n$(round(profit[:reserve_up]/profit[:total]*100, digits=1))%",
              "下备用\n$(round(profit[:reserve_dn]/profit[:total]*100, digits=1))%",
              "平衡市场\n$(round(profit[:balancing]/profit[:total]*100, digits=1))%"]
    
    p2 = pie(
        labels,
        revenues,
        title = "收益占比分布",
        legend = :outerright,
        colors = [:purple, :green, :orange, :cyan]
    )
    
    p = plot(p1, p2, layout = (1, 2), size = (1400, 600))
    
    fig_path = joinpath(output_dir, "figures", "profit_breakdown.png")
    savefig(p, fig_path)
    println("  ✓ 已生成: profit_breakdown.png")
    
    return p
end

"""
    plot_balancing_prices_heatmap(results, data, output_dir)

绘制平衡市场价格热力图
"""
function plot_balancing_prices_heatmap(results, data, output_dir)
    T = data.T
    K = data.K
    
    # 提取平衡价格矩阵 (时段 x 场景)
    price_matrix = zeros(T, K)
    for t in 1:T, k in 1:K
        price_matrix[t, k] = results[:λ_BL][t, k]
    end
    
    p = heatmap(
        1:K,
        1:T,
        price_matrix,
        xlabel = "场景",
        ylabel = "时段",
        title = "实时平衡市场价格热力图",
        color = :viridis,
        colorbar_title = "价格(\$/MWh)"
    )
    
    fig_path = joinpath(output_dir, "figures", "balancing_prices_heatmap.png")
    savefig(p, fig_path)
    println("  ✓ 已生成: balancing_prices_heatmap.png")
    
    return p
end

"""
    plot_comprehensive_dashboard(results, data, output_dir)

生成综合仪表盘 (4宫格)
"""
function plot_comprehensive_dashboard(results, data, output_dir)
    T = data.T
    profit = results[:profit]
    
    # 1. SOC曲线
    p1 = plot(
        1:T, 
        results[:e],
        label = "SOC",
        ylabel = "能量(MWh)",
        title = "荷电状态",
        color = :blue,
        lw = 2,
        grid = true,
        legend = false
    )
    
    # 2. 充放电功率
    p2 = plot(
        xlabel = "时段",
        ylabel = "功率(MW)",
        title = "充放电功率",
        legend = :topright,
        grid = true
    )
    plot!(p2, 1:T, results[:p_dis], label = "放电", color = :red, lw = 2)
    plot!(p2, 1:T, -results[:p_ch], label = "充电", color = :blue, lw = 2)
    hline!(p2, [0], color=:black, linestyle=:dash, label="", lw=1)
    
    # 3. 能量市场价格
    p3 = plot(
        1:T,
        results[:λ_EN],
        label = "价格",
        xlabel = "时段",
        ylabel = "价格(\$/MWh)",
        title = "能量市场价格",
        color = :purple,
        lw = 2,
        grid = true,
        legend = false
    )
    
    # 4. 利润饼图
    categories = ["能量", "上备用", "下备用", "平衡"]
    revenues = [
        profit[:energy],
        profit[:reserve_up],
        profit[:reserve_dn],
        profit[:balancing]
    ]
    
    p4 = pie(
        categories,
        revenues,
        title = "收益分解",
        legend = false,
        colors = [:purple, :green, :orange, :cyan]
    )
    
    p = plot(p1, p2, p3, p4, layout = (2, 2), size = (1400, 1000))
    
    fig_path = joinpath(output_dir, "figures", "comprehensive_dashboard.png")
    savefig(p, fig_path)
    println("  ✓ 已生成: comprehensive_dashboard.png")
    
    return p
end

"""
    generate_all_plots(results, data, output_dir)

生成所有图表
"""
function generate_all_plots(results, data, output_dir)
    println("\n📊 生成可视化图表...")
    
    # 创建figures目录
    fig_dir = joinpath(output_dir, "figures")
    if !isdir(fig_dir)
        mkpath(fig_dir)
    end
    
    try
        plot_soc_curve(results, data, output_dir)
        plot_power_schedule(results, data, output_dir)
        plot_market_prices(results, data, output_dir)
        plot_reserve_capacity(results, data, output_dir)
        plot_profit_breakdown(results, data, output_dir)
        plot_balancing_prices_heatmap(results, data, output_dir)
        plot_comprehensive_dashboard(results, data, output_dir)
        
        println("✅ 所有图表已生成到: $fig_dir\n")
        return true
    catch e
        println("⚠️  图表生成出现错误: $e")
        return false
    end
end

export generate_all_plots, plot_soc_curve, plot_power_schedule, 
       plot_market_prices, plot_profit_breakdown

