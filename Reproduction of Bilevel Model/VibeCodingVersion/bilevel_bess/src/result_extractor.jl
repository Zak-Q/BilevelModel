# 结果提取和导出模块

using JuMP
using DataFrames
using CSV
using Printf
using Dates
using Statistics

"""
    extract_results(model, data)

从求解后的模型中提取所有结果

# 参数
- `model`: 已求解的JuMP模型
- `data`: 输入数据

# 返回
包含所有结果的字典
"""
function extract_results(model, data)
    println("\n📦 提取求解结果...")
    
    T = data.T
    K = data.K
    n_gen = data.n_gen
    n_load = data.n_load
    
    results = Dict()
    
    # 提取储能变量
    results[:p_ch] = value.(model[:p_ch])
    results[:p_dis] = value.(model[:p_dis])
    results[:e] = value.(model[:e])
    results[:r_up_ch] = value.(model[:r_up_ch])
    results[:r_up_dis] = value.(model[:r_up_dis])
    results[:r_dn_ch] = value.(model[:r_dn_ch])
    results[:r_dn_dis] = value.(model[:r_dn_dis])
    results[:u_ch] = value.(model[:u_ch])
    results[:u_dis] = value.(model[:u_dis])
    
    # 提取实时市场调度
    results[:q_up_ch] = value.(model[:q_up_ch])
    results[:q_up_dis] = value.(model[:q_up_dis])
    results[:q_dn_ch] = value.(model[:q_dn_ch])
    results[:q_dn_dis] = value.(model[:q_dn_dis])
    
    # 提取市场价格
    results[:λ_EN] = value.(model[:λ_EN])
    results[:λ_UP] = value.(model[:λ_UP])
    results[:λ_DN] = value.(model[:λ_DN])
    results[:λ_BL] = value.(model[:λ_BL])
    
    # 提取发电机和负荷
    results[:p_g] = value.(model[:p_g])
    results[:p_d] = value.(model[:p_d])
    results[:r_up_g] = value.(model[:r_up_g])
    results[:r_dn_g] = value.(model[:r_dn_g])
    
    # 计算储能各项收益
    results[:profit] = calculate_profit_breakdown(results, data)
    
    # 总利润
    results[:total_profit] = objective_value(model)
    
    println("✅ 结果提取完成\n")
    
    return results
end

"""
    calculate_profit_breakdown(results, data)

计算储能在各个市场的收益分解
"""
function calculate_profit_breakdown(results, data)
    T = data.T
    K = data.K
    stor = data.storage[1, :]
    
    profit = Dict()
    
    # 日前能量市场收益
    energy_revenue = sum(
        results[:λ_EN][t] * results[:p_dis][t] - 
        results[:λ_EN][t] * results[:p_ch][t]
        for t in 1:T
    )
    
    # 日前备用市场收益
    reserve_up_revenue = sum(
        results[:λ_UP][t] * (results[:r_up_ch][t] + results[:r_up_dis][t])
        for t in 1:T
    )
    
    reserve_dn_revenue = sum(
        results[:λ_DN][t] * (results[:r_dn_ch][t] + results[:r_dn_dis][t])
        for t in 1:T
    )
    
    # 实时平衡市场期望收益
    balancing_revenue = 0.0
    for t in 1:T, k in 1:K
        scen_row = filter(row -> row.t == t && row.k == k, data.scenarios)
        prob = scen_row[1, :probability]
        
        bal_power = (results[:q_up_dis][t,k] - results[:q_dn_dis][t,k]) - 
                    (results[:q_up_ch][t,k] - results[:q_dn_ch][t,k])
        
        balancing_revenue += prob * results[:λ_BL][t,k] * bal_power
    end
    
    # 运营成本
    operating_cost = sum(
        stor.MC_ch * results[:p_ch][t] + stor.MC_dis * results[:p_dis][t]
        for t in 1:T
    )
    
    profit[:energy] = energy_revenue
    profit[:reserve_up] = reserve_up_revenue
    profit[:reserve_dn] = reserve_dn_revenue
    profit[:balancing] = balancing_revenue
    profit[:operating_cost] = operating_cost
    profit[:total] = energy_revenue + reserve_up_revenue + reserve_dn_revenue + 
                     balancing_revenue - operating_cost
    
    return profit
end

"""
    save_results_to_csv(results, data, output_dir)

将结果保存为CSV文件
"""
function save_results_to_csv(results, data, output_dir)
    println("\n💾 保存结果到CSV文件...")
    
    csv_dir = joinpath(output_dir, "csv")
    if !isdir(csv_dir)
        mkpath(csv_dir)
    end
    
    T = data.T
    K = data.K
    
    # 1. 储能运行结果
    storage_df = DataFrame(
        时段 = 1:T,
        充电功率_MW = results[:p_ch],
        放电功率_MW = results[:p_dis],
        荷电状态_MWh = results[:e],
        上备用充电_MW = results[:r_up_ch],
        上备用放电_MW = results[:r_up_dis],
        下备用充电_MW = results[:r_dn_ch],
        下备用放电_MW = results[:r_dn_dis],
        充电状态 = results[:u_ch],
        放电状态 = results[:u_dis]
    )
    CSV.write(joinpath(csv_dir, "storage_schedule.csv"), storage_df)
    println("  ✓ storage_schedule.csv")
    
    # 2. 市场价格
    price_df = DataFrame(
        时段 = 1:T,
        能量价格_dollar_MWh = results[:λ_EN],
        上备用价格_dollar_MW = results[:λ_UP],
        下备用价格_dollar_MW = results[:λ_DN]
    )
    CSV.write(joinpath(csv_dir, "market_prices.csv"), price_df)
    println("  ✓ market_prices.csv")
    
    # 3. 平衡市场价格 (按场景)
    balance_price_rows = []
    for t in 1:T, k in 1:K
        push!(balance_price_rows, (时段=t, 场景=k, 平衡价格_dollar_MWh=results[:λ_BL][t,k]))
    end
    balance_price_df = DataFrame(balance_price_rows)
    CSV.write(joinpath(csv_dir, "balancing_prices.csv"), balance_price_df)
    println("  ✓ balancing_prices.csv")
    
    # 4. 发电机调度
    gen_rows = []
    for g in 1:data.n_gen, t in 1:T
        push!(gen_rows, (
            发电机ID = data.generators[g, :id],
            时段 = t,
            出力_MW = results[:p_g][g,t],
            上备用_MW = results[:r_up_g][g,t],
            下备用_MW = results[:r_dn_g][g,t]
        ))
    end
    gen_df = DataFrame(gen_rows)
    CSV.write(joinpath(csv_dir, "generator_dispatch.csv"), gen_df)
    println("  ✓ generator_dispatch.csv")
    
    # 5. 利润分解
    profit_df = DataFrame(
        市场类型 = ["能量市场", "上备用市场", "下备用市场", "平衡市场", "运营成本", "总利润"],
        金额_dollar = [
            results[:profit][:energy],
            results[:profit][:reserve_up],
            results[:profit][:reserve_dn],
            results[:profit][:balancing],
            -results[:profit][:operating_cost],
            results[:profit][:total]
        ]
    )
    CSV.write(joinpath(csv_dir, "profit_breakdown.csv"), profit_df)
    println("  ✓ profit_breakdown.csv")
    
    # 6. 实时调度 (汇总,取期望)
    rt_dispatch_rows = []
    for t in 1:T
        # 计算期望值
        exp_up_ch = sum(filter(row -> row.t == t && row.k == k, data.scenarios)[1, :probability] * 
                        results[:q_up_ch][t,k] for k in 1:K)
        exp_up_dis = sum(filter(row -> row.t == t && row.k == k, data.scenarios)[1, :probability] * 
                         results[:q_up_dis][t,k] for k in 1:K)
        exp_dn_ch = sum(filter(row -> row.t == t && row.k == k, data.scenarios)[1, :probability] * 
                        results[:q_dn_ch][t,k] for k in 1:K)
        exp_dn_dis = sum(filter(row -> row.t == t && row.k == k, data.scenarios)[1, :probability] * 
                         results[:q_dn_dis][t,k] for k in 1:K)
        
        push!(rt_dispatch_rows, (
            时段 = t,
            期望上调充电_MW = exp_up_ch,
            期望上调放电_MW = exp_up_dis,
            期望下调充电_MW = exp_dn_ch,
            期望下调放电_MW = exp_dn_dis
        ))
    end
    rt_dispatch_df = DataFrame(rt_dispatch_rows)
    CSV.write(joinpath(csv_dir, "realtime_dispatch_expected.csv"), rt_dispatch_df)
    println("  ✓ realtime_dispatch_expected.csv")
    
    println("✅ 所有CSV文件已保存到: $csv_dir\n")
    
    return csv_dir
end

"""
    print_summary_results(results, data)

打印结果摘要
"""
function print_summary_results(results, data)
    println("\n" * "=" ^ 60)
    println("📈 求解结果摘要")
    println("=" ^ 60)
    
    profit = results[:profit]
    
    println("\n【储能利润分解】")
    @printf("  能量市场收益:    \$%12.2f\n", profit[:energy])
    @printf("  上备用市场收益:  \$%12.2f\n", profit[:reserve_up])
    @printf("  下备用市场收益:  \$%12.2f\n", profit[:reserve_dn])
    @printf("  平衡市场收益:    \$%12.2f\n", profit[:balancing])
    @printf("  运营成本:        \$%12.2f\n", profit[:operating_cost])
    println("  " * "-" ^ 40)
    @printf("  总利润:          \$%12.2f\n", profit[:total])
    
    println("\n【储能运行统计】")
    total_charge = sum(results[:p_ch])
    total_discharge = sum(results[:p_dis])
    @printf("  总充电量:        %12.2f MWh\n", total_charge)
    @printf("  总放电量:        %12.2f MWh\n", total_discharge)
    @printf("  平均SOC:         %12.2f MWh\n", mean(results[:e]))
    @printf("  最大SOC:         %12.2f MWh\n", maximum(results[:e]))
    @printf("  最小SOC:         %12.2f MWh\n", minimum(results[:e]))
    
    # 计算充放电循环次数
    n_charge = sum(results[:u_ch] .> 0.5)
    n_discharge = sum(results[:u_dis] .> 0.5)
    @printf("  充电时段数:      %12d\n", n_charge)
    @printf("  放电时段数:      %12d\n", n_discharge)
    
    println("\n【市场价格统计】")
    @printf("  平均能量价格:    \$%12.2f /MWh\n", mean(results[:λ_EN]))
    @printf("  最高能量价格:    \$%12.2f /MWh\n", maximum(results[:λ_EN]))
    @printf("  最低能量价格:    \$%12.2f /MWh\n", minimum(results[:λ_EN]))
    @printf("  平均上备用价格:  \$%12.2f /MW\n", mean(results[:λ_UP]))
    @printf("  平均下备用价格:  \$%12.2f /MW\n", mean(results[:λ_DN]))
    
    println("\n" * "=" ^ 60 * "\n")
end

export extract_results, save_results_to_csv, print_summary_results

