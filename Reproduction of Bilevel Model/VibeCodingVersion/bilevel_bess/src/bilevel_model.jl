# 双层储能市场优化模型
# 基于 Nasrolahpour et al. (2018) 论文实现

using JuMP
using Gurobi
using LinearAlgebra
using Printf

"""
    build_bilevel_bess_model(data; verbose=true, time_limit=3600)

构建并求解双层储能系统优化模型
将MPEC转换为MILP使用Big-M方法

# 参数
- `data`: 包含所有输入数据的命名元组
- `verbose`: 是否打印详细信息
- `time_limit`: 求解器时间限制(秒)

# 返回
- `model`: JuMP模型对象
- `results`: 包含所有结果的字典
"""
function build_bilevel_bess_model(data; verbose=true, time_limit=3600)
    
    println("\n" * "=" ^ 60)
    println("🔨 开始构建双层优化模型")
    println("=" ^ 60)
    
    # 提取数据
    T = data.T
    K = data.K
    n_gen = data.n_gen
    n_load = data.n_load
    
    # 储能参数
    stor = data.storage[1, :]
    P_ch_max = stor.P_ch_max
    P_dis_max = stor.P_dis_max
    R_ch_max = stor.R_ch_max
    R_dis_max = stor.R_dis_max
    E_max = stor.E_max
    E_min = stor.E_min
    E_init = stor.E_init
    MC_ch = stor.MC_ch
    MC_dis = stor.MC_dis
    η_ch = stor.eta_ch
    η_dis = stor.eta_dis
    
    # Big-M 参数
    M_price = 1000.0  # 价格的Big-M
    M_power = 500.0   # 功率的Big-M
    M_dual = 10000.0  # 对偶变量的Big-M
    
    println("✓ 提取参数完成")
    println("  时段数: $T, 场景数: $K")
    println("  发电机: $n_gen, 负荷: $n_load")
    
    # 创建模型
    model = Model(Gurobi.Optimizer)
    
    # 设置求解器参数
    set_optimizer_attribute(model, "TimeLimit", time_limit)
    set_optimizer_attribute(model, "MIPGap", 0.01)  # 1% gap
    set_optimizer_attribute(model, "NonConvex", 2)  # 允许非凸问题
    if !verbose
        set_silent(model)
    end
    
    println("✓ 创建Gurobi模型")
    
    # ========================================
    # 上层决策变量 (储能)
    # ========================================
    
    # 储能充放电功率 (日前)
    @variable(model, 0 <= p_ch[t=1:T] <= P_ch_max)
    @variable(model, 0 <= p_dis[t=1:T] <= P_dis_max)
    
    # 储能备用容量投标
    @variable(model, 0 <= r_up_ch[t=1:T] <= R_ch_max)
    @variable(model, 0 <= r_up_dis[t=1:T] <= R_dis_max)
    @variable(model, 0 <= r_dn_ch[t=1:T] <= R_ch_max)
    @variable(model, 0 <= r_dn_dis[t=1:T] <= R_dis_max)
    
    # 储能SOC
    @variable(model, E_min <= e[t=1:T] <= E_max)
    
    # 充放电二进制变量 (防止同时充放电)
    @variable(model, u_ch[t=1:T], Bin)
    @variable(model, u_dis[t=1:T], Bin)
    
    # 储能报价 (上层决策,简化为固定值或可优化)
    # 这里简化为参数,可扩展为变量
    o_ch = MC_ch * ones(T)  # 充电报价
    o_dis = MC_dis * ones(T)  # 放电报价
    o_r_up = 3.0 * ones(T)  # 上备用报价
    o_r_dn = 3.0 * ones(T)  # 下备用报价
    
    # 实时市场调度 (场景相关)
    @variable(model, 0 <= q_up_ch[t=1:T, k=1:K])
    @variable(model, 0 <= q_up_dis[t=1:T, k=1:K])
    @variable(model, 0 <= q_dn_ch[t=1:T, k=1:K])
    @variable(model, 0 <= q_dn_dis[t=1:T, k=1:K])
    
    println("✓ 定义上层变量 (储能决策)")
    
    # ========================================
    # 下层决策变量 (市场出清)
    # ========================================
    
    # 发电机功率
    @variable(model, data.generators[g, :Pmin] <= p_g[g=1:n_gen, t=1:T] <= data.generators[g, :Pmax])
    
    # 发电机备用
    @variable(model, 0 <= r_up_g[g=1:n_gen, t=1:T] <= data.generators[g, :r_up_max])
    @variable(model, 0 <= r_dn_g[g=1:n_gen, t=1:T] <= data.generators[g, :r_dn_max])
    
    # 负荷功率 (可减载)
    @variable(model, 0 <= p_d[d=1:n_load, t=1:T])
    
    # 实时市场发电机调节
    @variable(model, 0 <= q_up_g[g=1:n_gen, t=1:T, k=1:K])
    @variable(model, 0 <= q_dn_g[g=1:n_gen, t=1:T, k=1:K])
    
    # 实时市场切负荷
    @variable(model, 0 <= l_shed[d=1:n_load, t=1:T, k=1:K])
    
    # 市场价格 (对偶变量,通过KKT条件引入)
    @variable(model, 0 <= λ_EN[t=1:T] <= M_price)     # 能量市场价格
    @variable(model, 0 <= λ_UP[t=1:T] <= M_price)     # 上备用价格
    @variable(model, 0 <= λ_DN[t=1:T] <= M_price)     # 下备用价格
    @variable(model, 0 <= λ_BL[t=1:T, k=1:K] <= M_price)  # 平衡市场价格
    
    println("✓ 定义下层变量 (市场出清)")
    
    # ========================================
    # KKT对偶变量 (用于表示下层最优性条件)
    # ========================================
    
    # 发电机功率的对偶变量
    @variable(model, 0 <= μ_g_max[g=1:n_gen, t=1:T] <= M_dual)
    @variable(model, 0 <= μ_g_min[g=1:n_gen, t=1:T] <= M_dual)
    
    # 储能功率的对偶变量
    @variable(model, 0 <= μ_s_ch_max[t=1:T] <= M_dual)
    @variable(model, 0 <= μ_s_dis_max[t=1:T] <= M_dual)
    
    println("✓ 定义KKT对偶变量")
    
    # ========================================
    # 上层约束 (储能物理约束)
    # ========================================
    
    # 充放电互斥约束
    @constraint(model, mutex[t=1:T], u_ch[t] + u_dis[t] <= 1)
    
    # 充电功率受二进制变量约束
    @constraint(model, ch_bin[t=1:T], p_ch[t] <= P_ch_max * u_ch[t])
    @constraint(model, dis_bin[t=1:T], p_dis[t] <= P_dis_max * u_dis[t])
    
    # SOC动态约束
    @constraint(model, soc_init, e[1] == E_init + η_ch * p_ch[1] - p_dis[1] / η_dis)
    @constraint(model, soc_dyn[t=2:T], e[t] == e[t-1] + η_ch * p_ch[t] - p_dis[t] / η_dis)
    
    # 终端能量约束 (循环条件)
    @constraint(model, soc_final, e[T] >= E_init)
    
    # 备用容量约束
    @constraint(model, reserve_ch_up[t=1:T], p_ch[t] + r_up_ch[t] <= P_ch_max * u_ch[t])
    @constraint(model, reserve_ch_dn[t=1:T], p_ch[t] >= r_dn_ch[t])
    @constraint(model, reserve_dis_up[t=1:T], p_dis[t] + r_up_dis[t] <= P_dis_max * u_dis[t])
    @constraint(model, reserve_dis_dn[t=1:T], p_dis[t] >= r_dn_dis[t])
    
    # 能量储备约束 (确保有足够能量提供备用)
    @constraint(model, energy_up[t=1:T], e[t] + η_ch * r_up_ch[t] <= E_max)
    @constraint(model, energy_dn[t=1:T], e[t] >= E_min + r_dn_dis[t] / η_dis)
    
    # 实时调用备用约束
    @constraint(model, rt_up_ch_limit[t=1:T, k=1:K], q_up_ch[t,k] <= r_up_ch[t])
    @constraint(model, rt_up_dis_limit[t=1:T, k=1:K], q_up_dis[t,k] <= r_up_dis[t])
    @constraint(model, rt_dn_ch_limit[t=1:T, k=1:K], q_dn_ch[t,k] <= r_dn_ch[t])
    @constraint(model, rt_dn_dis_limit[t=1:T, k=1:K], q_dn_dis[t,k] <= r_dn_dis[t])
    
    println("✓ 添加上层约束 (储能物理)")
    
    # ========================================
    # 下层约束 (市场出清条件)
    # ========================================
    
    # 日前能量平衡
    @constraint(model, energy_balance[t=1:T],
        sum(p_g[g,t] for g in 1:n_gen) + p_dis[t] - p_ch[t] == 
        sum(p_d[d,t] for d in 1:n_load)
    )
    
    # 上备用平衡
    @constraint(model, reserve_up_balance[t=1:T],
        sum(r_up_g[g,t] for g in 1:n_gen) + r_up_ch[t] + r_up_dis[t] >= 
        data.market_req[t, :R_UP_req]
    )
    
    # 下备用平衡
    @constraint(model, reserve_dn_balance[t=1:T],
        sum(r_dn_g[g,t] for g in 1:n_gen) + r_dn_ch[t] + r_dn_dis[t] >= 
        data.market_req[t, :R_DN_req]
    )
    
    # 负荷上限
    for d in 1:n_load, t in 1:T
        P_d_max = data.loads_timeseries[d, t]
        @constraint(model, p_d[d,t] <= P_d_max)
    end
    
    # 实时平衡市场约束
    for t in 1:T, k in 1:K
        # 获取场景偏差
        scen_row = filter(row -> row.t == t && row.k == k, data.scenarios)
        if nrow(scen_row) > 0
            Q_dev = scen_row[1, :Q_deviation]
        else
            Q_dev = 0.0
        end
        
        # 实时功率平衡
        @constraint(model,
            sum(q_up_g[g,t,k] - q_dn_g[g,t,k] for g in 1:n_gen) +
            (q_up_dis[t,k] - q_dn_dis[t,k]) - (q_up_ch[t,k] - q_dn_ch[t,k]) +
            sum(l_shed[d,t,k] for d in 1:n_load) == Q_dev
        )
        
        # 上调用量限制
        for g in 1:n_gen
            @constraint(model, q_up_g[g,t,k] <= r_up_g[g,t])
        end
        
        # 下调用量限制
        for g in 1:n_gen
            @constraint(model, q_dn_g[g,t,k] <= r_dn_g[g,t])
        end
        
        # 切负荷限制
        for d in 1:n_load
            @constraint(model, l_shed[d,t,k] <= p_d[d,t])
        end
    end
    
    println("✓ 添加下层约束 (市场出清)")
    
    # ========================================
    # KKT最优性条件 (简化形式)
    # ========================================
    # 注意:完整KKT条件非常复杂,这里实现核心的互补松弛条件
    
    # 发电机出力的KKT条件: offer_price - λ_EN + μ_max - μ_min = 0
    for g in 1:n_gen, t in 1:T
        offer = data.generators[g, :offer_price]
        # 简化的KKT:忽略小的二阶项
        @constraint(model, μ_g_max[g,t] <= M_dual * (1 - (p_g[g,t] - data.generators[g, :Pmin]) / M_power))
        @constraint(model, μ_g_min[g,t] <= M_dual * (1 - (data.generators[g, :Pmax] - p_g[g,t]) / M_power))
    end
    
    # 储能充放电的KKT条件:简化处理,价格应等于边际成本附近
    for t in 1:T
        # 放电: λ_EN ≈ MC_dis (当有放电时)
        @constraint(model, λ_EN[t] >= MC_dis - M_price * (1 - u_dis[t]))
        
        # 充电: λ_EN ≈ MC_ch (当有充电时)  
        @constraint(model, λ_EN[t] <= MC_ch + M_price * (1 - u_ch[t]))
    end
    
    println("✓ 添加KKT条件 (简化)")
    
    # ========================================
    # 目标函数 (上层:储能期望利润最大化)
    # ========================================
    
    # 日前能量市场收益
    energy_revenue = sum(
        λ_EN[t] * p_dis[t] - λ_EN[t] * p_ch[t]
        for t in 1:T
    )
    
    # 日前备用市场收益
    reserve_revenue = sum(
        λ_UP[t] * (r_up_ch[t] + r_up_dis[t]) +
        λ_DN[t] * (r_dn_ch[t] + r_dn_dis[t])
        for t in 1:T
    )
    
    # 实时平衡市场期望收益
    balancing_revenue = sum(
        filter(row -> row.t == t && row.k == k, data.scenarios)[1, :probability] *
        λ_BL[t,k] * ((q_up_dis[t,k] - q_dn_dis[t,k]) - (q_up_ch[t,k] - q_dn_ch[t,k]))
        for t in 1:T, k in 1:K
    )
    
    # 总运营成本
    operating_cost = sum(
        MC_ch * p_ch[t] + MC_dis * p_dis[t]
        for t in 1:T
    )
    
    # 总利润 = 收益 - 成本
    @objective(model, Max, 
        energy_revenue + reserve_revenue + balancing_revenue - operating_cost
    )
    
    println("✓ 设置目标函数 (储能利润最大化)")
    
    println("=" ^ 60)
    println("✅ 模型构建完成")
    println("  变量数: $(num_variables(model))")
    println("  约束数: $(num_constraints(model, count_variable_in_set_constraints=true))")
    println("=" ^ 60 * "\n")
    
    return model
end

"""
    solve_model(model; verbose=true)

求解优化模型并返回结果
"""
function solve_model(model; verbose=true)
    println("\n" * "⏰" ^ 30)
    println("🚀 开始求解模型...")
    println("⏰" ^ 30 * "\n")
    
    start_time = time()
    optimize!(model)
    solve_time = time() - start_time
    
    status = termination_status(model)
    
    println("\n" * "=" ^ 60)
    println("📊 求解状态")
    println("=" ^ 60)
    println("状态: $status")
    @printf("求解时间: %.2f 秒\n", solve_time)
    
    if has_values(model)
        obj_value = objective_value(model)
        @printf("目标值 (储能利润): \$%.2f\n", obj_value)
        
        if verbose
            gap = relative_gap(model)
            @printf("相对Gap: %.4f%%\n", gap * 100)
        end
        
        println("=" ^ 60 * "\n")
        return true
    else
        println("⚠️  模型未找到可行解")
        println("=" ^ 60 * "\n")
        return false
    end
end

export build_bilevel_bess_model, solve_model

