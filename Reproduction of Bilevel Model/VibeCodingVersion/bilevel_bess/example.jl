#!/usr/bin/env julia

"""
使用示例脚本
展示如何使用各个模块进行定制化分析
"""

push!(LOAD_PATH, @__DIR__)

include("src/data_loader.jl")
include("src/bilevel_model.jl")
include("src/result_extractor.jl")
include("src/visualizer.jl")
include("src/report_generator.jl")

using .Main: load_all_data, validate_data
using .Main: build_bilevel_bess_model, solve_model
using .Main: extract_results, print_summary_results
using .Main: plot_soc_curve, plot_power_schedule, plot_market_prices, plot_profit_breakdown

println("\n" * "=" ^ 60)
println("双层储能优化 - 定制化使用示例")
println("=" ^ 60 * "\n")

# ========================================
# 示例 1: 基础工作流
# ========================================
println("【示例 1】 基础工作流\n")

# 1. 加载数据
data = load_all_data("data")

# 2. 构建模型
model = build_bilevel_bess_model(data, verbose=false)

# 3. 求解
println("开始求解...")
success = solve_model(model, verbose=true)

if !success
    println("求解失败")
    exit(1)
end

# 4. 提取结果
results = extract_results(model, data)

# 5. 打印摘要
print_summary_results(results, data)

# ========================================
# 示例 2: 单独生成特定图表
# ========================================
println("\n【示例 2】 生成特定图表\n")

output_dir = "results"

# 只生成 SOC 曲线
println("生成 SOC 曲线...")
plot_soc_curve(results, data, output_dir)

# 只生成功率调度图
println("生成功率调度图...")
plot_power_schedule(results, data, output_dir)

# 只生成利润分解图
println("生成利润分解图...")
plot_profit_breakdown(results, data, output_dir)

# ========================================
# 示例 3: 访问特定结果数据
# ========================================
println("\n【示例 3】 访问特定结果\n")

# 获取最大充电时段
max_charge_time = argmax(results[:p_ch])
max_charge_power = results[:p_ch][max_charge_time]
println("最大充电: 时段 $max_charge_time, 功率 $max_charge_power MW")

# 获取最大放电时段
max_discharge_time = argmax(results[:p_dis])
max_discharge_power = results[:p_dis][max_discharge_time]
println("最大放电: 时段 $max_discharge_time, 功率 $max_discharge_power MW")

# 获取最高和最低能量价格
max_price = maximum(results[:λ_EN])
min_price = minimum(results[:λ_EN])
max_price_time = argmax(results[:λ_EN])
min_price_time = argmin(results[:λ_EN])
println("\n能量价格:")
println("  最高: 时段 $max_price_time, \$$max_price/MWh")
println("  最低: 时段 $min_price_time, \$$min_price/MWh")

# ========================================
# 示例 4: 自定义分析
# ========================================
println("\n【示例 4】 自定义分析\n")

# 计算峰谷套利收益
peak_hours = [18, 19, 20]  # 假设18-20点为高峰
valley_hours = [1, 2, 3, 4]  # 假设1-4点为低谷

peak_discharge = sum(results[:p_dis][t] for t in peak_hours)
valley_charge = sum(results[:p_ch][t] for t in valley_hours)

println("峰谷套利策略:")
println("  谷时充电总量: $valley_charge MWh")
println("  峰时放电总量: $peak_discharge MWh")

# 计算特定时段的利润贡献
t_analyze = 12  # 分析第12时段
energy_profit_t = results[:λ_EN][t_analyze] * results[:p_dis][t_analyze] - 
                  results[:λ_EN][t_analyze] * results[:p_ch][t_analyze]
reserve_profit_t = results[:λ_UP][t_analyze] * (results[:r_up_ch][t_analyze] + results[:r_up_dis][t_analyze]) +
                   results[:λ_DN][t_analyze] * (results[:r_dn_ch][t_analyze] + results[:r_dn_dis][t_analyze])

println("\n时段 $t_analyze 利润贡献:")
println("  能量市场: \$$energy_profit_t")
println("  备用市场: \$$reserve_profit_t")

# ========================================
# 示例 5: 导出自定义CSV
# ========================================
println("\n【示例 5】 导出自定义数据\n")

using DataFrames, CSV

# 创建自定义结果表
custom_results = DataFrame(
    时段 = 1:data.T,
    充电功率 = results[:p_ch],
    放电功率 = results[:p_dis],
    SOC = results[:e],
    能量价格 = results[:λ_EN],
    时段利润 = [
        results[:λ_EN][t] * (results[:p_dis][t] - results[:p_ch][t])
        for t in 1:data.T
    ]
)

# 保存
custom_file = joinpath(output_dir, "csv", "custom_analysis.csv")
CSV.write(custom_file, custom_results)
println("已保存自定义分析结果: $custom_file")

# ========================================
# 示例 6: 参数敏感性分析 (概念性)
# ========================================
println("\n【示例 6】 参数敏感性分析示例\n")
println("(这里只展示框架,实际运行会比较耗时)")

# 可以修改储能容量重新求解
# for capacity in [150, 200, 250]
#     data_modified = deepcopy(data)
#     data_modified.storage[1, :E_max] = capacity
#     
#     model_new = build_bilevel_bess_model(data_modified, verbose=false)
#     solve_model(model_new, verbose=false)
#     results_new = extract_results(model_new, data_modified)
#     
#     println("容量 $capacity MWh: 利润 \$$(results_new[:profit][:total])")
# end

println("\n" * "=" ^ 60)
println("✅ 示例运行完成")
println("=" ^ 60 * "\n")

