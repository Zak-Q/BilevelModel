# market_clearing_example.jl
using JuMP, Gurobi, DataFrames, CSV

# ----- Problem data (示例) -----
T = 24
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
model = Model(optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag"=>1, "TimeLimit"=>60.0))

# Variables
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

# Energy balance (market clearing) at each time
@constraint(model, [t in 1:T],
    sum(pg[g,t] for g in gens) + sum(p_dis[b,t] for b in batt) - sum(p_ch[b,t] for b in batt) == sum(p_demand[d,t] for d in demands))

# Optional: generator min outputs, ramping, reserve, etc. can be added similarly.

# Objective: minimize production cost (可为每小时成本之和)
@objective(model, Min,
    sum(cost[g] * pg[g,t] * Δt for g in gens, t in 1:T)
    - sum(offer[(d,t)] * p_demand[d,t] for d in demands, t in 1:T)
    + 0.01 * sum(p_ch[b,t] + p_dis[b,t] for b in batt, t in 1:T))
# charge and discharge offer price was set to 0.1.

# ----- Solve -----
optimize!(model)

# ----- Extract results -----
status = termination_status(model)
println("Status: ", status)

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
CSV.write("market_results.csv", df)
println("Results written to market_results.csv")