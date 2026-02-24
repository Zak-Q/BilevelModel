# 报告生成模块
# 自动生成Markdown格式的结果报告

using Printf
using Dates
using Statistics

"""
    generate_report(results, data, output_dir; solve_time=0.0)

生成完整的结果分析报告
"""
function generate_report(results, data, output_dir; solve_time=0.0)
    println("\n📝 生成结果报告...")
    
    report_dir = joinpath(output_dir, "reports")
    if !isdir(report_dir)
        mkpath(report_dir)
    end
    
    report_file = joinpath(report_dir, "optimization_report.md")
    
    io = open(report_file, "w")
    
    try
        write_report_header(io, data, solve_time)
        write_executive_summary(io, results, data)
        write_profit_analysis(io, results)
        write_operational_analysis(io, results, data)
        write_market_analysis(io, results, data)
        write_recommendations(io, results, data)
        write_report_footer(io)
        
        close(io)
        
        println("✅ 报告已生成: $report_file\n")
        return report_file
    catch e
        close(io)
        println("⚠️  报告生成失败: $e")
        return nothing
    end
end

"""
    write_report_header(io, data, solve_time)

写入报告头部
"""
function write_report_header(io, data, solve_time)
    write(io, "# 储能系统双层优化求解报告\n\n")
    write(io, "---\n\n")
    write(io, "**生成时间**: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))\n\n")
    write(io, "**模型**: 储能系统在电能与备用市场中的双层优化模型\n\n")
    write(io, "**参考文献**: Nasrolahpour et al. (2018)\n\n")
    write(io, "---\n\n")
    
    write(io, "## 📋 模型配置\n\n")
    write(io, "| 参数 | 值 |\n")
    write(io, "|------|----|\n")
    write(io, "| 优化时段数 | $(data.T) 小时 |\n")
    write(io, "| 场景数量 | $(data.K) 个 |\n")
    write(io, "| 发电机数量 | $(data.n_gen) 台 |\n")
    write(io, "| 负荷节点数 | $(data.n_load) 个 |\n")
    write(io, "| 储能系统数 | $(data.n_stor) 个 |\n")
    @printf(io, "| 求解时间 | %.2f 秒 |\n", solve_time)
    write(io, "\n")
    
    # 储能参数
    stor = data.storage[1, :]
    write(io, "### 储能系统参数\n\n")
    write(io, "| 参数 | 值 |\n")
    write(io, "|------|----|\n")
    @printf(io, "| 最大充电功率 | %.2f MW |\n", stor.P_ch_max)
    @printf(io, "| 最大放电功率 | %.2f MW |\n", stor.P_dis_max)
    @printf(io, "| 能量容量 | %.2f MWh |\n", stor.E_max)
    @printf(io, "| 初始能量 | %.2f MWh |\n", stor.E_init)
    @printf(io, "| 充电效率 | %.1f%% |\n", stor.eta_ch * 100)
    @printf(io, "| 放电效率 | %.1f%% |\n", stor.eta_dis * 100)
    @printf(io, "| 充电边际成本 | \$%.2f/MWh |\n", stor.MC_ch)
    @printf(io, "| 放电边际成本 | \$%.2f/MWh |\n", stor.MC_dis)
    write(io, "\n---\n\n")
end

"""
    write_executive_summary(io, results, data)

写入执行摘要
"""
function write_executive_summary(io, results, data)
    profit = results[:profit]
    
    write(io, "## 📊 执行摘要\n\n")
    
    write(io, "### 关键指标\n\n")
    write(io, "| 指标 | 数值 |\n")
    write(io, "|------|------|\n")
    @printf(io, "| **总利润** | **\$%.2f** |\n", profit[:total])
    @printf(io, "| 能量市场收益 | \$%.2f |\n", profit[:energy])
    @printf(io, "| 备用市场收益 | \$%.2f |\n", profit[:reserve_up] + profit[:reserve_dn])
    @printf(io, "| 平衡市场收益 | \$%.2f |\n", profit[:balancing])
    @printf(io, "| 运营成本 | \$%.2f |\n", profit[:operating_cost])
    
    # 计算收益率
    total_revenue = profit[:energy] + profit[:reserve_up] + profit[:reserve_dn] + profit[:balancing]
    profit_margin = (profit[:total] / total_revenue) * 100
    @printf(io, "| **利润率** | **%.2f%%** |\n", profit_margin)
    write(io, "\n")
    
    # 运行统计
    total_charge = sum(results[:p_ch])
    total_discharge = sum(results[:p_dis])
    
    write(io, "### 运行统计\n\n")
    write(io, "| 指标 | 数值 |\n")
    write(io, "|------|------|\n")
    @printf(io, "| 总充电量 | %.2f MWh |\n", total_charge)
    @printf(io, "| 总放电量 | %.2f MWh |\n", total_discharge)
    
    # 计算往返效率
    if total_discharge > 0
        roundtrip_eff = (total_discharge / total_charge) * 100
        @printf(io, "| 往返效率 | %.2f%% |\n", roundtrip_eff)
    end
    
    n_charge = sum(results[:u_ch] .> 0.5)
    n_discharge = sum(results[:u_dis] .> 0.5)
    @printf(io, "| 充电时段数 | %d / %d |\n", n_charge, data.T)
    @printf(io, "| 放电时段数 | %d / %d |\n", n_discharge, data.T)
    
    avg_soc = mean(results[:e])
    soc_utilization = (avg_soc / data.storage[1, :E_max]) * 100
    @printf(io, "| 平均SOC | %.2f MWh (%.1f%%) |\n", avg_soc, soc_utilization)
    
    write(io, "\n---\n\n")
end

"""
    write_profit_analysis(io, results)

写入利润分析
"""
function write_profit_analysis(io, results)
    profit = results[:profit]
    total_revenue = profit[:energy] + profit[:reserve_up] + profit[:reserve_dn] + profit[:balancing]
    
    write(io, "## 💰 利润分析\n\n")
    
    write(io, "### 收益结构\n\n")
    write(io, "| 市场 | 收益(\$) | 占比(%) |\n")
    write(io, "|------|----------|----------|\n")
    @printf(io, "| 能量市场 | %.2f | %.2f |\n", profit[:energy], profit[:energy]/total_revenue*100)
    @printf(io, "| 上备用市场 | %.2f | %.2f |\n", profit[:reserve_up], profit[:reserve_up]/total_revenue*100)
    @printf(io, "| 下备用市场 | %.2f | %.2f |\n", profit[:reserve_dn], profit[:reserve_dn]/total_revenue*100)
    @printf(io, "| 平衡市场 | %.2f | %.2f |\n", profit[:balancing], profit[:balancing]/total_revenue*100)
    @printf(io, "| **总收益** | **%.2f** | **100.00** |\n", total_revenue)
    write(io, "\n")
    
    write(io, "### 成本分析\n\n")
    write(io, "| 项目 | 金额(\$) |\n")
    write(io, "|------|----------|\n")
    @printf(io, "| 运营成本 | %.2f |\n", profit[:operating_cost])
    @printf(io, "| **净利润** | **%.2f** |\n", profit[:total])
    write(io, "\n")
    
    write(io, "**关键洞察**:\n\n")
    
    # 找出主要收益来源
    revenues = Dict(
        "能量市场" => profit[:energy],
        "上备用市场" => profit[:reserve_up],
        "下备用市场" => profit[:reserve_dn],
        "平衡市场" => profit[:balancing]
    )
    
    max_source = argmax(revenues)
    max_pct = revenues[max_source] / total_revenue * 100
    
    write(io, "- 主要收益来源为**$(max_source)**, ")
    @printf(io, "占总收益的 **%.1f%%**\n", max_pct)
    
    if profit[:balancing] > 0
        bal_pct = profit[:balancing] / total_revenue * 100
        @printf(io, "- 通过参与实时平衡市场获得 \$%.2f 收益 (%.1f%%)\n", profit[:balancing], bal_pct)
    end
    
    profit_margin = (profit[:total] / total_revenue) * 100
    @printf(io, "- 利润率为 **%.2f%%**, ", profit_margin)
    if profit_margin > 20
        write(io, "表现优秀\n")
    elseif profit_margin > 10
        write(io, "表现良好\n")
    else
        write(io, "有提升空间\n")
    end
    
    write(io, "\n---\n\n")
end

"""
    write_operational_analysis(io, results, data)

写入运行分析
"""
function write_operational_analysis(io, results, data)
    write(io, "## ⚡ 运行分析\n\n")
    
    write(io, "### 充放电策略\n\n")
    
    # 找出最大充放电时段
    max_ch_t = argmax(results[:p_ch])
    max_dis_t = argmax(results[:p_dis])
    
    @printf(io, "- **最大充电**: 时段 %d, 功率 %.2f MW\n", max_ch_t, results[:p_ch][max_ch_t])
    @printf(io, "- **最大放电**: 时段 %d, 功率 %.2f MW\n", max_dis_t, results[:p_dis][max_dis_t])
    write(io, "\n")
    
    # SOC分析
    write(io, "### SOC管理\n\n")
    write(io, "| 指标 | 数值 |\n")
    write(io, "|------|------|\n")
    @printf(io, "| 最大SOC | %.2f MWh (时段 %d) |\n", maximum(results[:e]), argmax(results[:e]))
    @printf(io, "| 最小SOC | %.2f MWh (时段 %d) |\n", minimum(results[:e]), argmin(results[:e]))
    @printf(io, "| 平均SOC | %.2f MWh |\n", mean(results[:e]))
    @printf(io, "| SOC标准差 | %.2f MWh |\n", std(results[:e]))
    write(io, "\n")
    
    # 备用容量分析
    write(io, "### 备用容量投标\n\n")
    write(io, "| 类型 | 平均值(MW) | 最大值(MW) | 总量(MWh) |\n")
    write(io, "|------|------------|------------|------------|\n")
    @printf(io, "| 上备用-充电 | %.2f | %.2f | %.2f |\n", 
            mean(results[:r_up_ch]), maximum(results[:r_up_ch]), sum(results[:r_up_ch]))
    @printf(io, "| 上备用-放电 | %.2f | %.2f | %.2f |\n", 
            mean(results[:r_up_dis]), maximum(results[:r_up_dis]), sum(results[:r_up_dis]))
    @printf(io, "| 下备用-充电 | %.2f | %.2f | %.2f |\n", 
            mean(results[:r_dn_ch]), maximum(results[:r_dn_ch]), sum(results[:r_dn_ch]))
    @printf(io, "| 下备用-放电 | %.2f | %.2f | %.2f |\n", 
            mean(results[:r_dn_dis]), maximum(results[:r_dn_dis]), sum(results[:r_dn_dis]))
    write(io, "\n")
    
    write(io, "---\n\n")
end

"""
    write_market_analysis(io, results, data)

写入市场分析
"""
function write_market_analysis(io, results, data)
    write(io, "## 📈 市场分析\n\n")
    
    write(io, "### 市场价格统计\n\n")
    write(io, "| 市场 | 平均价格 | 最高价格 | 最低价格 | 标准差 |\n")
    write(io, "|------|----------|----------|----------|--------|\n")
    @printf(io, "| 能量市场(\$/MWh) | %.2f | %.2f | %.2f | %.2f |\n",
            mean(results[:λ_EN]), maximum(results[:λ_EN]), 
            minimum(results[:λ_EN]), std(results[:λ_EN]))
    @printf(io, "| 上备用(\$/MW) | %.2f | %.2f | %.2f | %.2f |\n",
            mean(results[:λ_UP]), maximum(results[:λ_UP]), 
            minimum(results[:λ_UP]), std(results[:λ_UP]))
    @printf(io, "| 下备用(\$/MW) | %.2f | %.2f | %.2f | %.2f |\n",
            mean(results[:λ_DN]), maximum(results[:λ_DN]), 
            minimum(results[:λ_DN]), std(results[:λ_DN]))
    @printf(io, "| 平衡市场(\$/MWh) | %.2f | %.2f | %.2f | %.2f |\n",
            mean(results[:λ_BL]), maximum(results[:λ_BL]), 
            minimum(results[:λ_BL]), std(results[:λ_BL]))
    write(io, "\n")
    
    write(io, "### 价格-运行相关性\n\n")
    
    # 找高价和低价时段的运行状态
    high_price_t = argmax(results[:λ_EN])
    low_price_t = argmin(results[:λ_EN])
    
    @printf(io, "- **最高价格时段** (t=%d, \$%.2f/MWh): ", high_price_t, results[:λ_EN][high_price_t])
    if results[:p_dis][high_price_t] > 0.1
        @printf(io, "放电 %.2f MW\n", results[:p_dis][high_price_t])
    elseif results[:p_ch][high_price_t] > 0.1
        @printf(io, "充电 %.2f MW (异常)\n", results[:p_ch][high_price_t])
    else
        write(io, "待机\n")
    end
    
    @printf(io, "- **最低价格时段** (t=%d, \$%.2f/MWh): ", low_price_t, results[:λ_EN][low_price_t])
    if results[:p_ch][low_price_t] > 0.1
        @printf(io, "充电 %.2f MW\n", results[:p_ch][low_price_t])
    elseif results[:p_dis][low_price_t] > 0.1
        @printf(io, "放电 %.2f MW (异常)\n", results[:p_dis][low_price_t])
    else
        write(io, "待机\n")
    end
    
    write(io, "\n---\n\n")
end

"""
    write_recommendations(io, results, data)

写入建议
"""
function write_recommendations(io, results, data)
    write(io, "## 💡 建议与展望\n\n")
    
    write(io, "### 运营建议\n\n")
    
    profit = results[:profit]
    total_revenue = profit[:energy] + profit[:reserve_up] + profit[:reserve_dn] + profit[:balancing]
    
    # 基于分析给出建议
    if profit[:energy] / total_revenue < 0.4
        write(io, "1. **能量市场参与度偏低** - 建议增加能量套利机会,关注峰谷价差\n")
    end
    
    if (profit[:reserve_up] + profit[:reserve_dn]) / total_revenue > 0.5
        write(io, "2. **备用市场收益占比高** - 当前策略侧重备用市场,建议保持\n")
    end
    
    avg_soc = mean(results[:e])
    if avg_soc / data.storage[1, :E_max] < 0.4
        write(io, "3. **SOC利用率偏低** - 建议适当提高能量吞吐量以提升资产利用率\n")
    end
    
    if sum(results[:u_ch] .> 0.5) + sum(results[:u_dis] .> 0.5) < data.T * 0.6
        write(io, "4. **运行时间占比低** - 考虑扩大市场参与时段以增加收益\n")
    end
    
    write(io, "\n### 模型扩展方向\n\n")
    write(io, "- 引入多储能系统协同优化\n")
    write(io, "- 考虑储能退化成本\n")
    write(io, "- 增加更多实时场景\n")
    write(io, "- 考虑网络约束(多节点模型)\n")
    write(io, "- 引入碳价格影响分析\n")
    
    write(io, "\n---\n\n")
end

"""
    write_report_footer(io)

写入报告尾部
"""
function write_report_footer(io)
    write(io, "## 📌 附录\n\n")
    write(io, "### 模型说明\n\n")
    write(io, "本报告基于以下论文的双层优化模型:\n\n")
    write(io, "> Nasrolahpour, E., Kazempour, J., Zareipour, H., & Rosehart, W. D. (2018). \n")
    write(io, "> \"A Bilevel Model for Participation of a Storage System in Energy and Reserve Markets.\" \n")
    write(io, "> *IEEE Transactions on Sustainable Energy*, 9(2), 582-598.\n\n")
    
    write(io, "### 求解方法\n\n")
    write(io, "- **建模工具**: JuMP.jl (Julia语言)\n")
    write(io, "- **求解器**: Gurobi Optimizer\n")
    write(io, "- **模型类型**: 混合整数线性规划 (MILP)\n")
    write(io, "- **转换方法**: KKT条件 + Big-M线性化\n\n")
    
    write(io, "---\n\n")
    write(io, "*报告结束*\n")
end

export generate_report

