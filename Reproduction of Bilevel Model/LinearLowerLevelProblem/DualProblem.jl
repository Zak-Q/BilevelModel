# market_clearing_example_dual.jl
using JuMP, Gurobi, DataFrames, CSV

# ----- Problem data (示例) -----
T = 24
M = 10^6  # set a sufficiently large value for Big-M
M_dual = 10000.0  # Big-M for dual variables
M_price = M_dual
gens = ["G1","G2","G3","G4","G5"]
demands = ["D1"]  # Only one demand node for simplicity
cap = Dict("G1"=>1000.0, "G2"=>3000.0, "G3"=>2000.0, "G4"=>1500.0, "G5"=>1500.0)         # MW
cost = Dict("G1"=>20.0,  "G2"=>40.0, "G3"=>35.0, "G4"=>30.0, "G5"=>30.0)        # $/MWh
demand = [8339.690568	7851.47463	7284.357931	6886.846545	6744.396371	6910.633349	7399.321633	8167.709441	8936.556139	9321.113933	9350.342226	9113.091468	9048.39332	9101.115123	9220.046064	9434.099785	9876.420404	10349.44104	10233.89669	9712.021448	9322.566269	8943.195127	8591.832867	8213.969352
]  # MW, demand use sinewave
# Time-varying demand offers (示例：每小时价格，单位 $/MWh 或 $/MWh 等价于 $/MWh 因为 Δt=1)
offer = Dict((d,t) => 30.0 + 5.0*sin(2*pi*(t-1)/24) for d in demands, t in 1:T)

batt = ["B1"]
P_batt_max = Dict("B1"=>1000.0)   # MW charge/discharge limit
E_batt_max = Dict("B1"=>2000.0)  # MWh energy capacity
eta_c = Dict("B1"=>0.95)        # charge efficiency
eta_d = Dict("B1"=>0.95)        # discharge efficiency
soc0 = Dict("B1"=>1000.0)         # initial SOC (MWh)
Δt = 1.0                        # hour

# ----- Model -----
model = Model(optimizer_with_attributes(Gurobi.Optimizer,
    "OutputFlag"=>1,
    "TimeLimit"=>60.0,
    "MIPGap"=>1e-4,
    "Threads"=>Sys.CPU_THREADS,
    "Presolve"=>2,
    "Cuts"=>2,
    "MIPFocus"=>1))

# Variables (reuse same index sets as primal for consistency)
@variable(model, 0 <= pg[g in gens, t=1:T] <= cap[g])          # thermal generation (MW)
@variable(model, 0 <= p_ch[b in batt, t=1:T] <= P_batt_max[b])   # battery charge (MW)
@variable(model, 0 <= p_dis[b in batt, t=1:T] <= P_batt_max[b])  # battery discharge (MW)
@variable(model, 0 <= soc[b in batt, t=0:T] <= E_batt_max[b])    # SOC (MWh)
@variable(model, 0 <= p_demand[d in demands, t=1:T] <= demand[t])  # served demand (MW)
# Initial SOC
@constraint(model, [b in batt], soc[b,0] == soc0[b])

# SOC dynamics (线性)：soc_t = soc_{t-1} + η_c * p_ch * Δt - (1/η_d) * p_dis * Δt
@constraint(model, [b in batt, t in 1:T],
    soc[b,t] == soc[b,t-1] + eta_c[b] * p_ch[b,t] * Δt - (1/eta_d[b]) * p_dis[b,t] * Δt)

# Optional: generator min outputs, ramping, reserve, etc. can be added similarly.

# Objective: minimize production cost (可为每小时成本之和)

# ========================================
# Dual Variables of Lower Level Problem
# ========================================

# Energy only market Price
@variable(model, Lambda_EN[t=1:T] <= M_price)

# Dual of Generator Power limits (indexed by same gens/time sets)
@variable(model, 0 <= Mu_g_max[g in gens, t=1:T] <= M_dual)
@variable(model, u_Gen_max_pwr[g in gens, t=1:T], Bin)
@variable(model, 0 <= Mu_g_min[g in gens, t=1:T] <= M_dual)
@variable(model, u_Gen_min_pwr[g in gens, t=1:T], Bin)

# Dual of Load Power limits
@variable(model, 0 <= Mu_d_max[d in demands, t=1:T] <= M_dual)
@variable(model, u_Load_max_pwr[d in demands, t=1:T], Bin)
@variable(model, 0 <= Mu_d_min[d in demands, t=1:T] <= M_dual)
@variable(model, u_Load_min_pwr[d in demands, t=1:T], Bin)
# Dual of Utility Storage Power limits
@variable(model, 0 <= Mu_s_ch_max[b in batt, t=1:T] <= M_dual)
@variable(model, u_Charge_max_pwr[b in batt, t=1:T], Bin)
@variable(model, 0 <= Mu_s_ch_min[b in batt, t=1:T] <= M_dual)
@variable(model, u_Charge_min_pwr[b in batt, t=1:T], Bin)
@variable(model, 0 <= Mu_s_dis_max[b in batt, t=1:T] <= M_dual)
@variable(model, u_Discharge_max_pwr[b in batt, t=1:T], Bin)
@variable(model, 0 <= Mu_s_dis_min[b in batt, t=1:T] <= M_dual)
@variable(model, u_Discharge_min_pwr[b in batt, t=1:T], Bin)

# ====================================================================================
# Lower lever problem in KKT conditions (with power balance constraint)
# ====================================================================================

@constraint(model, power_balance_constraint[t in 1:T],
    sum(pg[g,t] for g in gens) + sum(p_dis[b,t] for b in batt) - sum(p_ch[b,t] for b in batt) == sum(p_demand[d,t] for d in demands)
)




# KKT Conditions (Strong Duality part)
@constraint(model, [g in gens, t in 1:T], cost[g] - Lambda_EN[t] + Mu_g_max[g,t] - Mu_g_min[g,t] == 0)
@constraint(model, [d in demands, t in 1:T], offer[(d,t)] + Lambda_EN[t] + Mu_d_max[d,t] - Mu_d_min[d,t] == 0)
@constraint(model, [b in batt, t in 1:T], -0.1 + Lambda_EN[t] + Mu_s_ch_max[b,t] - Mu_s_ch_min[b,t] == 0)
@constraint(model, [b in batt, t in 1:T], 0.1 - Lambda_EN[t] + Mu_s_dis_max[b,t] - Mu_s_dis_min[b,t] == 0)
# @constraint(model, L_to_gen_power[t=1:T], O_Energy[g,t] -Lambda_EN[t] + Mu_g_max[g,t] - Mu_g_min[g,t] == 0)
# @constraint(model, L_to_load_power[t=1:T], U_Energy[d,t] + Lambda_EN[t] + Mu_d_max[d,t] - Mu_d_min[d,t] == 0)
# @constraint(model, L_to_charge_power[t=1:T], - o_ch[t] + Lambda_EN[t] + Mu_s_ch_max[t] - Mu_s_ch_min[t] == 0)
# @constraint(model, L_to_discharge_power[t=1:T], o_dis[t] - Lambda_EN[t] + Mu_s_dis_max[t] - Mu_s_dis_min[t] == 0)

# KKT Conditions (Complementary Slackness part)未改
@constraint(model, [g in gens, t in 1:T], pg[g,t] <= u_Gen_min_pwr[g,t] * cap[g])
@constraint(model, [g in gens, t in 1:T], Mu_g_min[g,t] <= (1-u_Gen_min_pwr[g,t]) * M_dual)
@constraint(model, [g in gens, t in 1:T], (cap[g] - pg[g,t]) <= u_Gen_max_pwr[g,t] * cap[g])
@constraint(model, [g in gens, t in 1:T], Mu_g_max[g,t] <= (1-u_Gen_max_pwr[g,t]) * M_dual)

@constraint(model, [d in demands, t in 1:T], p_demand[d,t] <= u_Load_min_pwr[d,t] * demand[t])
@constraint(model, [d in demands, t in 1:T], Mu_d_min[d,t] <= (1-u_Load_min_pwr[d,t]) * M_dual)
@constraint(model, [d in demands, t in 1:T], (demand[t] - p_demand[d,t]) <= u_Load_max_pwr[d,t] * demand[t])
@constraint(model, [d in demands, t in 1:T], Mu_d_max[d,t] <= (1-u_Load_max_pwr[d,t]) * M_dual)

@constraint(model, [b in batt, t in 1:T], p_ch[b,t] <= u_Charge_min_pwr[b,t] * P_batt_max[b])
@constraint(model, [b in batt, t in 1:T], Mu_s_ch_min[b,t] <= (1-u_Charge_min_pwr[b,t]) * M_dual)

@constraint(model, [b in batt, t in 1:T], (P_batt_max[b] - p_ch[b,t]) <= u_Charge_max_pwr[b,t] * P_batt_max[b])
@constraint(model, [b in batt, t in 1:T], Mu_s_ch_max[b,t] <= (1-u_Charge_max_pwr[b,t]) * M_dual)

@constraint(model, [b in batt, t in 1:T], p_dis[b,t] <= u_Discharge_min_pwr[b,t] * P_batt_max[b])
@constraint(model, [b in batt, t in 1:T], Mu_s_dis_min[b,t] <= (1-u_Discharge_min_pwr[b,t]) * M_dual)

@constraint(model, [b in batt, t in 1:T], (P_batt_max[b] - p_dis[b,t]) <= u_Discharge_max_pwr[b,t] * P_batt_max[b])
@constraint(model, [b in batt, t in 1:T], Mu_s_dis_max[b,t] <= (1-u_Discharge_max_pwr[b,t]) * M_dual)

# Use a feasibility/objective-0 formulation: enforce KKT (stationarity, feasibility,
# complementary slackness, and (optionally) strong duality) and minimize 0 to check
# whether KKT conditions admit a feasible point. This avoids optimizing a different
# objective that would conflict with the primal original objective.
@objective(model, Min, 0)
# charge and discharge offer price was set to 0.1.
# ----- Solve -----
optimize!(model)

# ----- Extract results -----
status = termination_status(model)
println("Status: ", status)

# ------------------ Diagnostics ------------------
using Printf

obj_val = try
    objective_value(model)
catch
    NaN
end
println("objective_value(model) = ", obj_val)

primal_like = sum(cost[g] * value(pg[g,t]) * Δt for g in gens, t in 1:T) -
    sum(offer[(d,t)] * value(p_demand[d,t]) for d in demands, t in 1:T) +
    0.01 * sum(value(p_ch[b,t]) + value(p_dis[b,t]) for b in batt, t in 1:T)
@printf("primal_like (from dual model solution) = %.6f\n", primal_like)

max_balance = maximum([abs(sum(value(pg[g,t]) for g in gens) + sum(value(p_dis[b,t]) for b in batt)
                        - sum(value(p_ch[b,t]) for b in batt) - sum(value(p_demand[d,t]) for d in demands))
                        for t in 1:T])
@printf("max power balance residual = %.6e\n", max_balance)

max_comp_gen = maximum([abs(value(pg[g,t]) * value(Mu_g_min[g,t])) for g in gens, t in 1:T])
@printf("max gen min complementarity product ≈ %.6e\n", max_comp_gen)
max_comp_load = maximum([abs(value(p_demand[d,t]) * value(Mu_d_min[d,t])) for d in demands, t in 1:T])
@printf("max load min complementarity product ≈ %.6e\n", max_comp_load)

println("sample u_Gen_min_pwr values (first 6): ", [value(u_Gen_min_pwr[g,t]) for g in gens, t in 1:min(3,T)])
println("sample u_Load_max_pwr values (first 6): ", [value(u_Load_max_pwr[d,t]) for d in demands, t in 1:min(3,T)])
lambda_vals = [value(Lambda_EN[t]) for t in 1:T]
@printf("Lambda_EN range: [%.6f, %.6f]\n", minimum(lambda_vals), maximum(lambda_vals))

# --------------------------------------------------

rows = Vector{NamedTuple{(:timestamp,:type,:unit,:value),Tuple{Int,String,String,Float64}}}()
for t in 1:T
    for g in gens
        push!(rows, (timestamp=t, type="gen", unit=g, value=value(pg[g,t])))
    end
    for b in batt
        push!(rows, (timestamp=t, type="batt_ch", unit=b, value=value(p_ch[b,t])))
        push!(rows, (timestamp=t, type="batt_dis", unit=b, value=value(p_dis[b,t])))
        push!(rows, (timestamp=t, type="soc", unit=b, value=value(soc[b,t])))
    end
end

df = DataFrame(rows)
CSV.write("market_results_dual.csv", df)
println("Results written to market_results.csv")