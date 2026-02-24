# # 双层储能市场优化模型
# # 基于 Nasrolahpour et al. (2018) 论文实现

# using JuMP
# using Gurobi
# using LinearAlgebra
# using Printf

# """
#     build_bilevel_bess_model(data; verbose=true, time_limit=3600)

# 构建并求解双层储能系统优化模型
# 将MPEC转换为MILP使用Big-M方法

# # 参数
# - `data`: 包含所有输入数据的命名元组
# - `verbose`: 是否打印详细信息
# - `time_limit`: 求解器时间限制(秒)

# # 返回
# - `model`: JuMP模型对象
# - `results`: 包含所有结果的字典
# """

# List of required packages
required_packages = ["CSV", "DataFrames", "DataFramesMeta", "JuMP", "Gurobi", "HiGHS", "Plots", "VegaLite", "XLSX", "JSON", "Logging", "Colors",  "Measures"]

# Function to check and install missing packages
using Pkg

function install_required_packages(packages)
    # Get the list of packages in the current environment
    installed_pkgs = [dep.name for dep in values(Pkg.dependencies()) if !dep.is_direct_dep]
    installed_pkgs_direct = [dep.name for dep in values(Pkg.dependencies()) if dep.is_direct_dep]
    
    for pkg in packages
        if pkg in installed_pkgs_direct
            println("$pkg is already installed as a direct dependency.")
        elseif pkg in installed_pkgs
            println("$pkg is already installed as a transitive dependency.")
            # Optionally upgrade to direct dependency if needed
            # Pkg.add(pkg)
        else
            println("Installing $pkg...")
            Pkg.add(pkg)
        end
    end
end

# Install packages if missing
install_required_packages(required_packages)

using CSV, DataFrames, DataFramesMeta, JuMP, Gurobi, Plots, VegaLite, XLSX, JSON, Logging, ArgParse, Measures, Plots

# Load config file with fallback
function load_config(config_path::String)
    if isfile(config_path)
        return JSON.parsefile(config_path)
    else
        println("Warning: Config file '$config_path' not found. Using default values.")
        return Dict(
            "data_directory" => "models",
            "model_file" => "Test.xlsx",
            "demand_directory" => "ESOO_2013_Load_Traces",
            "solar_directory" => "Solar_Trace",
            "wind_directory" => "0910_Wind_Traces",
            "trace" => Dict("year" => 2020, "month" => 7, "day" => 1),
            "planning" => Dict("horizon_days" => 3, "rolling_horizon_days" => 2, "overlap_days" => 1, "voll" => 18600, "curtailment_penalty" => 600),
            "network_model" => "Nodal",
            "loss_factor" => 0.1,
            "reserve_margin" => 0.1,
            "solver_name" => "Gurobi",
            "mipgap" => 0.01,
            "plot_horizon_days": 3
        )
    end
end

function store_subhorizon_variables(model::JuMP.Model, sub::Int, subhorizon, abs_subhorizon)
    df = DataFrame(Subhorizon=Int[], Time=Int[], VariableName=String[], Index=String[], Value=Float64[], VarIndex=String[])
    vars = all_variables(model)
    
    for var in vars
        var_name = name(var)
        if !isempty(var_name)
            base_name = split(var_name, "[")[1]  # e.g., "Pwr_Gen_var"
            index_str = occursin("[", var_name) ? split(var_name, "[")[2][1:end-1] : "scalar"  # e.g., "gen1,73"
            indices = split(index_str, ",")
            if length(indices) == 2
                id, t_local = indices  # "generator_name", "local subhorizon time index"
                t_local_global = parse(Int, t_local)  # Global time index
                t_local_idx = t_local_global - first(subhorizon) + 1  # Convert to local subhorizon time index
                if t_local_idx < 1 || t_local_idx > length(subhorizon)
                    println("Warning: t_local $t_local_global (local idx $t_local_idx) out of bounds for $subhorizon in $var_name")
                    continue  # Skip if out of bounds
                end
                t_global = subhorizon[t_local_idx]  # Map local index to global time
                # Only store if t_global is within the abstracted subhorizon
                if t_global in abs_subhorizon
                    val = value(var)
                    var_index = string(base_name, "_", id)  # e.g., "S_Up_var_G1"
                    push!(df, (Subhorizon=sub, Time=t_global, VariableName=base_name, Index=id, Value=val, VarIndex=var_index))
                end
            elseif length(indices) == 1
                val = value(var)
                # Only store scalar variables (e.g., Build_line) in the first subhorizon
                if sub == 1
                    var_index = string(base_name, "_", index_str)
                    push!(df, (Subhorizon=sub, Time=0, VariableName=base_name, Index=index_str, Value=val, VarIndex=var_index))
                end
            end
        else
            println("Unnamed variable found: ", var)
        end
    end

    obj_value = objective_value(model)
        push!(df, (Subhorizon=sub, Time=first(abs_subhorizon), VariableName="Objective", Index="Subhorizon_$sub", Value=obj_value, VarIndex="Objective_Subhorizon_$sub"))

    fixed_cost = sum(Generator_data_dic[g]["Fix_Cost"] * value(model[:Status_var][g, t]) for g in UGen for t in abs_subhorizon)
    startup_cost = sum(Generator_data_dic[g]["Start_up_Cost"] * value(model[:S_Up_var][g, t]) for g in UGen for t in abs_subhorizon)
    shutdown_cost = sum(Generator_data_dic[g]["Shut_down_Cost"] * value(model[:S_Down_var][g, t]) for g in UGen for t in abs_subhorizon)
    variable_cost = sum(Generator_data_dic[g]["Variable_Cost"] * value(model[:Pwr_Gen_var][g, t]) for g in UGen for t in abs_subhorizon)
    unserved_demand_cost = sum(value(model[:unserved_demand][n, t]) * voll for n in UBus for t in abs_subhorizon)

    # Store cost components
    push!(df, (Subhorizon=sub, Time=first(abs_subhorizon), VariableName="Fixed_Cost", Index="Subhorizon_$sub", Value=fixed_cost, VarIndex="Fixed_Cost_Subhorizon_$sub"))
    push!(df, (Subhorizon=sub, Time=first(abs_subhorizon), VariableName="Startup_Cost", Index="Subhorizon_$sub", Value=startup_cost, VarIndex="Startup_Cost_Subhorizon_$sub"))
    push!(df, (Subhorizon=sub, Time=first(abs_subhorizon), VariableName="Shutdown_Cost", Index="Subhorizon_$sub", Value=shutdown_cost, VarIndex="Shutdown_Cost_Subhorizon_$sub"))
    push!(df, (Subhorizon=sub, Time=first(abs_subhorizon), VariableName="Variable_Cost", Index="Subhorizon_$sub", Value=variable_cost, VarIndex="Variable_Cost_Subhorizon_$sub"))
    push!(df, (Subhorizon=sub, Time=first(abs_subhorizon), VariableName="Unserved_Demand_Cost", Index="Subhorizon_$sub", Value=unserved_demand_cost, VarIndex="Unserved_Demand_Cost_Subhorizon_$sub"))
    
    return df
end


function build_bilevel_bess_model(data; verbose=true, time_limit=3600)
    
    println("\n" * "=" ^ 60)
    println("🔨 开始构建双层优化模型")
    println("=" ^ 60)
    
    # this part should be replaced by a data handeling module.
    T = data.T
    K = data.K
    n_gen = data.n_gen
    n_load = data.n_load
    
    # These are parameters for BESS, it should comes directely from model input.
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
    
    
    

    
    # # 创建模型
    # model = Model(Gurobi.Optimizer)
    
    # # 设置求解器参数
    # set_optimizer_attribute(model, "TimeLimit", time_limit)
    # set_optimizer_attribute(model, "MIPGap", 0.01)  # 1% gap
    # set_optimizer_attribute(model, "NonConvex", 2)  # 允许非凸问题
    # if !verbose
    #     set_silent(model)
    # end
    # Rolling horizon optimization loop
        opt_time = @elapsed begin
            for sub in 1:N_subhorizons

                println("\nStarting Subhorizon $sub")

                # Define the time window for the current subhorizon in hours
                t_start = max(1, (sub - 1) * (H - overlap_days) * hours_per_day + 1)  # Start of subhorizon, including overlap
                t_end = min(t_start + (H * hours_per_day) - 1, T)  # End of subhorizon
                subhorizon = t_start:t_end
                T_sub = length(subhorizon)  # Length of current subhorizon in hours

                # Define the effective subhorizon (non-overlapping portion) for storing results
                abs_t_start = (sub - 1) * abs_step_hours + 1  # Start of non-overlapping portion
                abs_t_end = min(sub * abs_step_hours, T)  # End of non-overlapping portion
                abs_subhorizon = abs_t_start:abs_t_end  # Non-overlapping portion to store

                println("Subhorizon $sub: t_start = $t_start, t_end = $t_end, subhorizon = $subhorizon")
                println("Effective subhorizon = $abs_subhorizon")

                model = Model(Gurobi.Optimizer)
                    set_optimizer_attribute(model, "MIPGap", mipgap)
                    set_optimizer_attribute(model, "TuneTrials", 3) # Tuning of solver parameters
                    set_optimizer_attribute(model, "TuneTimeLimit", 3600) # Tuning of solver parameters
                    set_optimizer_attribute(model, "TuneOutput", 1) # Tuning of solver parameters
                    set_optimizer_attribute(model, "TuneResults", 1) # Tuning of solver parameters
    
                # Big-M 
                M =1^6  # set a sufficiently large value for Big-M
                M_dual = 10000.0  # Big-M for dual variables
                alpha = 0.1       # energy left in BESS at the end of horizon (10% of initial energy)
                # ========================================
                # Upper Level Problem Variables
                # ========================================
                
                # Utility offer/bidding Capacity
                @variable(model, 0 <= p_offer_ch[s=1:n_storage, t=1:T] <= P_ch_max)
                @variable(model, 0 <= p_offer_dis[s=1:n_storage, t=1:T] <= P_dis_max)
                
                # Binary Variables for charge and discharge
                @variable(model, u_ch[s=1:n_storage, t=1:T], Bin)
                @variable(model, u_dis[s=1:n_storage, t=1:T], Bin)
                
                # Utility Storage SOC
                @variable(model, E_min <= e[s=1:n_storage, t=1:T] <= E_max)
                
                # Offer Price of Utility Storage (Marginal Cost MC_ch and MC_dis)
                @variable(model, o_ch[s=1:n_storage, t=1:T])
                @variable(model, o_dis[s=1:n_storage, t=1:T])

                # ========================================
                # Upper Level Problem Constraints
                # ========================================
                
                # Charging and discharging mutex constraint
                @constraint(model, mutex[s=1:n_storage, t=1:T], u_ch[s,t] + u_dis[s,t] <= 1)
                
                # Charging power constraint
                @constraint(model, ch_bin[s=1:n_storage, t=1:T], p_offer_ch[s,t] <= P_ch_max * u_ch[s,t])
                @constraint(model, dis_bin[s=1:n_storage, t=1:T], p_offer_dis[s,t] <= P_dis_max * u_dis[s,t])
                
                # SOC dynamic constraint

                for s in 1:Ns  # 遍历每个储能
                    for t in 1:Nt  # 遍历每个时段
                        if t == 1  # 时段1：初始荷电状态为E_s_ini
                            @constraint(model, e[s,t] == E_s_ini - p_dis[s,t] + η_s * p_ch[s,t])
                        else  # 时段t ≥2：基于前一时段的荷电状态递推
                            @constraint(model, e[s,t] == e[s,t-1] - p_dis[s,t] + η_s * p_ch[s,t] )
                        end
                    end
                end

                # @constraint(model, soc_init, e[1] == E_init + eta_ch * p_ch[1] - p_dis[1] / eta_dis)
                # @constraint(model, soc_dyn[t=2:T], e[t] == e[t-1] + eta_ch * p_ch[t] - p_dis[t] / eta_dis)
                
                # Terminal energy constraint (loop condition)
                @constraint(model, soc_final, e[T] >= alpha * E_init)
                
                # ========================================
                # Lower Level Problem Variables
                # ========================================
                
                # Generators Capacity
                @variable(model, data.generators[g, :Pmin] <= p_g[g=1:n_gen, t=1:T] <= data.generators[g, :Pmax])
                
                # Load Capacity
                @variable(model, 0 <= p_d[d=1:n_load, t=1:T])
                    for d in 1:n_load, t in 1:T
                        P_d_max = data.loads_timeseries[d, t]
                        @constraint(model, p_d[d,t] <= P_d_max)
                    end
                
                # Utility actual Capacity
                @variable(model, 0 <= p_ch[t=1:T])
                @variable(model, 0 <= p_dis[t=1:T])
                @constraint(model, Charging_capacity_upper_limit[t=1:T], p_ch[t] <= p_offer_ch[t])
                @constraint(model, Discharging_capacity_upper_limit[t=1:T], p_dis[t] <= p_offer_dis[t])

                
                # ========================================
                # Dual Variables of Lower Level Problem
                # ========================================

                # Energy only market Price
                @variable(model, Lambda_EN[t=1:T] <= M_price)
                
                # Dual of Generator Power limits
                @variable(model, 0 <= Mu_g_max[g=1:n_gen, t=1:T] <= M_dual)
                @variable(model, u_Gen_max_pwr[g=1:n_gen, t=1:T], Bin)
                @variable(model, 0 <= Mu_g_min[g=1:n_gen, t=1:T] <= M_dual)
                @variable(model, u_Gen_min_pwr[g=1:n_gen, t=1:T], Bin)

                # Dual of Load Power limits
                @variable(model, 0 <= Mu_d_max[d=1:n_load, t=1:T] <= M_dual)
                @variable(model, u_Load_max_pwr[d=1:n_gen, t=1:T], Bin)
                @variable(model, 0 <= Mu_d_min[d=1:n_load, t=1:T] <= M_dual)
                @variable(model, u_Load_min_pwr[d=1:n_gen, t=1:T], Bin)
                # Dual of Utility Storage Power limits
                @variable(model, 0 <= Mu_s_ch_max[s=1:n_storage, t=1:T] <= M_dual)
                @variable(model, u_Charge_max_pwr[s=1:n_storage, t=1:T], Bin)
                @variable(model, 0 <= Mu_s_ch_min[t=1:T] <= M_dual)
                @variable(model, u_Charge_min_pwr[s=1:n_storage, t=1:T], Bin)
                @variable(model, 0 <= Mu_s_dis_max[s=1:n_storage, t=1:T] <= M_dual)
                @variable(model, u_Discharge_max_pwr[s=1:n_storage, t=1:T], Bin)
                @variable(model, 0 <= Mu_s_dis_min[s=1:n_storage, t=1:T] <= M_dual)
                @variable(model, u_Discharge_min_pwr[s=1:n_storage, t=1:T], Bin)
                
                # ====================================================================================
                # Lower lever problem in KKT conditions (with power balance constraint)
                # ====================================================================================
            
                @constraint(model, power_balance_constraint[t=1:T],
                    sum(p_g[g,t] for g in 1:n_gen) + p_dis[t] - p_ch[t] == 
                    sum(p_d[d,t] for d in 1:n_load)
                )
                
                
                
                
                # KKT Conditions (Strong Duality part)
                for g in 1:n_gen, t in 1:T
                    @constraint(model, L_to_gen_power[g,t], O_Energy[g,t] -Lambda_EN[t] + Mu_g_max[g,t] - Mu_g_min[g,t] == 0)
                end
                for d in 1:n_load, t in 1:T
                    @constraint(model, L_to_load_power[d,t], U_Energy[d,t] + Lambda_EN[t] + Mu_d_max[d,t] - Mu_d_min[d,t] == 0)
                end
                for t in 1:T
                    @constraint(model, L_to_charge_power[t], - o_ch[t] + Lambda_EN[t] + Mu_s_ch_max[t] - Mu_s_ch_min[t] == 0)
                end
                for t in 1:T
                    @constraint(model, L_to_discharge_power[t], o_dis[t] - Lambda_EN[t] + Mu_s_dis_max[t] - Mu_s_dis_min[t] == 0)
                end
                # @constraint(model, L_to_gen_power[t=1:T], O_Energy[g,t] -Lambda_EN[t] + Mu_g_max[g,t] - Mu_g_min[g,t] == 0)
                # @constraint(model, L_to_load_power[t=1:T], U_Energy[d,t] + Lambda_EN[t] + Mu_d_max[d,t] - Mu_d_min[d,t] == 0)
                # @constraint(model, L_to_charge_power[t=1:T], - o_ch[t] + Lambda_EN[t] + Mu_s_ch_max[t] - Mu_s_ch_min[t] == 0)
                # @constraint(model, L_to_discharge_power[t=1:T], o_dis[t] - Lambda_EN[t] + Mu_s_dis_max[t] - Mu_s_dis_min[t] == 0)

                # KKT Conditions (Complementary Slackness part)未改
                for g in 1:n_gen, t in 1:T
                @constraint(model, gen_pwr_min_complementary[g=1:n_gen, t=1:T], p_g[g,t] <= u_Gen_min_pwr[g,t] * M)
                @constraint(model, gen_pwr_min_dual_complementary[g=1:n_gen, t=1:T], Mu_g_min[g,t] <= (1-u_Gen_min_pwr[g,t]) * M)
                @constraint(model, gen_pwr_max_complementary[g=1:n_gen, t=1:T], (data.generators[g, :Pmax] - p_g[g,t]) <= u_Gen_max_pwr[g,t] * M)
                @constraint(model, gen_pwr_max_dual_complementary[g=1:n_gen, t=1:T], Mu_g_max[g,t] <= (1-u_Gen_max_pwr[g,t]) * M)
                end

                for d in 1:n_load, t in 1:T
                @constraint(model, load_pwr_min_complementary[d=1:n_load, t=1:T], p_d[d,t] <= u_Load_min_pwr[d,t] * M)
                @constraint(model, load_pwr_min_dual_complementary[d=1:n_load, t=1:T], Mu_d_min[d,t] <= (1-u_Load_min_pwr[d,t]) * M)
                @constraint(model, load_pwr_max_complementary[d=1:n_load, t=1:T], (data.loads_timeseries[d, t] - p_d[d,t]) <= u_Load_max_pwr[d,t] * M)
                @constraint(model, load_pwr_max_dual_complementary[d=1:n_load, t=1:T], Mu_d_max[d,t] <= (1-u_Load_max_pwr[d,t]) * M)
                end

                for s in 1:n_storage, t in 1:T
                @constraint(model, charge_pwr_min_complementary[s=1:n_storage, t=1:T], p_ch[s,t] <= u_Charge_min_pwr[s,t] * M)
                @constraint(model, charge_pwr_min_dual_complementary[s=1:n_storage, t=1:T], Mu_s_ch_min[s,t] <= (1-u_Charge_min_pwr[s,t]) * M)

                @constraint(model, charge_pwr_max_complementary[s=1:n_storage, t=1:T], (p_offer_ch[s=1:n_storage, t=1:T]-p_ch[s,t]) <= u_Charge_max_pwr[s,t] * M)
                @constraint(model, charge_pwr_max_dual_complementary[s=1:n_storage, t=1:T], Mu_s_ch_max[s,t] <= (1-u_Charge_max_pwr[s,t]) * M)

                @constraint(model, discharge_pwr_min_complementary[s=1:n_storage, t=1:T], p_dis[s,t] <= u_Discharge_min_pwr[s,t] * M)
                @constraint(model, discharge_pwr_min_dual_complementary[s=1:n_storage, t=1:T], Mu_s_dis_min[s,t] <= (1-u_Discharge_min_pwr[s,t]) * M)

                @constraint(model, discharge_pwr_max_complementary[s=1:n_storage, t=1:T], (p_offer_dis[s=1:n_storage, t=1:T]-p_dis[s,t]) <= u_Discharge_max_pwr[s,t] * M)
                @constraint(model, discharge_pwr_max_dual_complementary[s=1:n_storage, t=1:T], Mu_s_dis_max[s,t] <= (1-u_Discharge_max_pwr[s,t]) * M)
                
                # # 发电机出力的KKT条件: offer_price - λ_EN + μ_max - μ_min = 0
                # for g in 1:n_gen, t in 1:T
                #     offer = data.generators[g, :offer_price]
                #     # 简化的KKT:忽略小的二阶项
                #     @constraint(model, μ_g_max[g,t] <= M_dual * (1 - (p_g[g,t] - data.generators[g, :Pmin]) / M_power))
                #     @constraint(model, μ_g_min[g,t] <= M_dual * (1 - (data.generators[g, :Pmax] - p_g[g,t]) / M_power))
                # end
                
                # # 储能充放电的KKT条件:简化处理,价格应等于边际成本附近
                # for t in 1:T
                #     # 放电: λ_EN ≈ MC_dis (当有放电时)
                #     @constraint(model, λ_EN[t] >= MC_dis - M_price * (1 - u_dis[t]))
                    
                #     # 充电: λ_EN ≈ MC_ch (当有充电时)  
                #     @constraint(model, λ_EN[t] <= MC_ch + M_price * (1 - u_ch[t]))
                # end
                
                # println("✓ 添加KKT条件 (简化)")
                
                # ========================================
                # Objective Function
                # ========================================
                    
                @objective(model, Min,
                                sum(sum((o_ch[s,t]) * p_ch[s, t] +(o_dis[s,t]) * p_dis[s, t] for s in 1:n_storage)                                                                                    
                                        +
                                    sum((O[g][t]) * p_g[g, t] for g in 1:n_gen)
                                        +
                                    sum((U[d][t]) * p_d[d, t] for d in 1:n_load)
                                        -
                                    sum(mu_g_max[g, t] * p_g_max[g, t] for g in 1:n_gen)
                                        -
                                    sum(mu_d_max[d, t] * p_d_max[d, t] for d in 1:n_load)
                                    )
                                    for t in 1:T)
                optimize!(model)

                #followed by storing results and preparing for next subhorizon
                
    # println("=" ^ 60)
    # println("✅ 模型构建完成")
    # println("  变量数: $(num_variables(model))")
    # println("  约束数: $(num_constraints(model, count_variable_in_set_constraints=true))")
    # println("=" ^ 60 * "\n")
    
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

