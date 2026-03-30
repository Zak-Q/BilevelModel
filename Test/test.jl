using Pkg

Pkg.add("Plots")
Pkg.add("BilevelJuMP")
Pkg.add("Gurobi")
Pkg.add("CSV")
Pkg.add("DataFrames")
Pkg.add("XLSX")

using Plots, BilevelJuMP, Gurobi
using CSV, DataFrames, JuMP, XLSX



# change from hardcoded values to parameters for easier testing and further developments
# time parameters
T = 1:24 # To be 1 week of hourly data
# generators 


# For Gen in T1
# offer price: variable cost * p + (fixed cost * number of units) first part in variables, second part in objective function
offer_price = [20, 40, 50, 60, 65, 225] # $/ MWh, solely for variable cost, generator_dict["variable_cost_$"]
# Pmax: Maximun real power * number of units
Pmax = [30, 40, 60, 50, 70, 20] # MW, generator_dict["maximum_real_power_MW"] * generator_dict["number_units"]
# For Gen in T2
# offer price: 0
# Constant P = trace * maximum real power * number of units

n_gens = 1:length(Pmax) # should change to be generator_dict["generator_name"]
# storages
n_storages = [1] # should change to be utility_storage_dict["utility_storage_name"]

# Initial SOC for storage
SOC_init = 0  # Initial state of charge, e.g., 50% of capacity

# Variable demands
# Demand = trace * demand trace weight - Constant P
Pdemand = [
    80, 75, 70, 70, 75, 90,
    110, 130, 150, 170, 180, 190,
    200, 210, 220, 230, 240, 250,
    260, 250, 220, 180, 140, 100
]
# Pdemand = demand_7days .- wind_7days .- solar_7days
println("Demand profile: ", Pdemand)
n_demands = length(Pdemand)



model = BilevelModel()

set_optimizer(model, Gurobi.Optimizer)

# 仍然使用 Fortuny-Amat + Big-M
BilevelJuMP.set_mode(
    model,
    BilevelJuMP.FortunyAmatMcCarlMode(
        dual_big_M = 250.0,
        primal_big_M = 150.0
    )
)

# 关键：允许非凸二次项
set_optimizer_attribute(model, "NonConvex", 2)

# 可选调参
set_optimizer_attribute(model, "OutputFlag", 1)
set_optimizer_attribute(model, "MIPGap", 1e-4)
set_optimizer_attribute(model, "TimeLimit", 600)
# model = BilevelModel(Gurobi.Optimizer, mode = BilevelJuMP.FortunyAmatMcCarlMode(big_M = 10^6))
#                 set_optimizer_attribute(model, "TuneTrials", 3) # Tuning of solver parameters
#                 set_optimizer_attribute(model, "TuneTimeLimit", 3600) # Tuning of solver parameters
#                 set_optimizer_attribute(model, "TuneOutput", 1) # Tuning of solver parameters
#                 set_optimizer_attribute(model, "TuneResults", 1) # Tuning of solver parameters

@variable(Lower(model), 0 <= pwr_gen[g in n_gens, t in T] <= Pmax[g])
@variable(Lower(model), 0 <= pwr_charge[s in n_storages, t in T]<= 100) # Assuming a maximum charge power of 100 MW for simplicity
@variable(Lower(model), 0 <= pwr_discharge[s in n_storages, t in T]<= 100) # Assuming a maximum discharge power of 100 MW for simplicity


@variable(Upper(model), 0 <= pwr_charge_up[s in n_storages, t in T]<= 100) # Assuming a maximum charge power of 100 MW for simplicity
@variable(Upper(model), 0 <= pwr_discharge_up[s in n_storages, t in T]<= 100) # Assuming a maximum discharge power of 100 MW for simplicity
@variable(Upper(model), 0 <= price_charge[s in n_storages, t in T])
@variable(Upper(model), 0 <= price_discharge[s in n_storages, t in T])
@variable(Upper(model), u_charge[s in n_storages, t in T], Bin)
@variable(Upper(model), u_discharge[s in n_storages, t in T], Bin)
@variable(Upper(model), 0 <= SOC[s in n_storages, t in T] <= 1000)

# Initial SOC constraint
for s in n_storages
    @constraint(Upper(model), SOC[s, 1] == SOC_init + pwr_charge[s, 1] - pwr_discharge[s, 1])
end

# SOC dynamics for t=2 to T
for t in T[2:end]
    for s in n_storages
        @constraint(Upper(model), SOC[s, t] == SOC[s, t-1] + pwr_charge[s, t] - pwr_discharge[s, t])
    end
end
# @constraint(Upper(model), sum(pwr_discharge[s,t] for s in n_storages, t in T) >= 20) # tuning
# Other constraints
for t in T
    for s in n_storages
        @constraint(Upper(model), u_charge[s, t] + u_discharge[s, t] <= 1) #exclusion_ch_dis[s in n_storages, t in T],
        @constraint(Upper(model), pwr_charge_up[s, t] <= u_charge[s, t] .* 100) #charge_limit[s in n_storages, t in T]
        @constraint(Upper(model), pwr_discharge_up[s, t] <= u_discharge[s, t] .* 100) #discharge_limit[s in n_storages, t in T], 
    end
end


@constraint(Lower(model), balance[t in T], sum(pwr_gen[g, t] for g in n_gens) + sum(pwr_discharge[s, t] for s in n_storages) 
            == Pdemand[t] + sum(pwr_charge[s, t] for s in n_storages))

@constraint(Lower(model), charge_limit[s in n_storages, t in T], pwr_charge[s, t] - pwr_charge_up[s, t] <= 0)
@constraint(Lower(model), discharge_limit[s in n_storages, t in T], pwr_discharge[s, t] - pwr_discharge_up[s, t] <= 0)

@variable(Upper(model), Clearing_price[t in T], DualOf(balance[t]))
for t in T
    set_lower_bound(Clearing_price[t], 0.0)
    set_upper_bound(Clearing_price[t], 230.0)  # Assuming a reasonable upper bound for the clearing price
end


@objective(Lower(model), Min, sum(price_discharge[s, t] * pwr_discharge[s, t] - price_charge[s, t] * pwr_charge[s, t] for s in n_storages, t in T)
                            + sum(offer_price[g] * pwr_gen[g, t] for g in n_gens, t in T))


@objective(Upper(model), Max, sum((Clearing_price[t] - 2) * pwr_discharge[s, t] for t in T, s in n_storages)
                             - sum((Clearing_price[t] + 5) * pwr_charge[s, t] for t in T, s in n_storages))

# solve the bilevel model
optimize!(model)

vars = all_variables(model)

# println("All variables in the model:")
# for var in vars
#     println(var)
# end

df = DataFrame(Time = collect(T))

df[!, :P_ch] = [sum(value(pwr_charge[s, t]) for s in n_storages) for t in T]
df[!, :P_dis] = [sum(value(pwr_discharge[s, t]) for s in n_storages) for t in T]
df[!, :SOC] = [sum(value(SOC[s, t]) for s in n_storages) for t in T]
for g in n_gens
    col_name = Symbol("P_thermal_", g)
    df[!, col_name] = [value(pwr_gen[g, t]) for t in T]
end
df[!, :P_demand] = Pdemand
df[!, :Clearing_price] = [value(Clearing_price[t]) for t in T]
df[!, :price_charge] = [sum(value(price_charge[s, t]) for s in n_storages) for t in T]
df[!, :price_discharge] = [sum(value(price_discharge[s, t]) for s in n_storages) for t in T]

# println(df)
CSV.write("result02.csv", df)


