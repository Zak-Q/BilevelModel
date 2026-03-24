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
# offer price: variable cost * p + fixed cost * number of units
offer_price = [20, 30, 25, 35, 40, 45] # $/ MWh
# Pmax: Maximun real power * number of units
Pmax = [40, 80, 60, 50, 70, 90] # MW
# For Gen in T2
# offer price: 0
# Constant P = trace * maximum real power * number of units

n_gens = 1:length(Pmax)
# storages
n_storages = [1] #socket for further developments

# Initial SOC for storage
SOC_init = 0  # Initial state of charge, e.g., 50% of capacity

# Variable demands
# Demand = trace * demand trace weight - Constant P

Pdemand = demand_7days .- wind_7days .- solar_7days
println("Demand profile: ", Pdemand)
n_demands = length(Pdemand)

model = BilevelModel(Gurobi.Optimizer,
                    mode = BilevelJuMP.FortunyAmatMcCarlMode(primal_big_M = 1000, dual_big_M = 1000))
                set_optimizer_attribute(model, "TuneTrials", 3) # Tuning of solver parameters
                set_optimizer_attribute(model, "TuneTimeLimit", 3600) # Tuning of solver parameters
                set_optimizer_attribute(model, "TuneOutput", 1) # Tuning of solver parameters
                set_optimizer_attribute(model, "TuneResults", 1) # Tuning of solver parameters

@variable(Lower(model), 0 <= pwr_gen[g in n_gens, t in T] <= Pmax[g])
@variable(Lower(model), 0 <= pwr_charge[s in n_storages, t in T])
@variable(Lower(model), 0 <= pwr_discharge[s in n_storages, t in T])


@variable(Upper(model), 0 <= pwr_charge_up[s in n_storages, t in T] <= 50)
@variable(Upper(model), 0 <= pwr_discharge_up[s in n_storages, t in T] <= 40)
@variable(Upper(model), 0 <= price_charge[s in n_storages, t in T])
@variable(Upper(model), 0 <= price_discharge[s in n_storages, t in T])
@variable(Upper(model), u_charge[s in n_storages, t in T], Bin)
@variable(Upper(model), u_discharge[s in n_storages, t in T], Bin)
@variable(Upper(model), 0 <= SOC[s in n_storages, t in T] <= 200)

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

# Other constraints
for t in T
    for s in n_storages
        @constraint(Upper(model), u_charge[s, t] + u_discharge[s, t] <= 1) #exclusion_ch_dis[s in n_storages, t in T],
        @constraint(Upper(model), pwr_charge[s, t] <= u_charge[s, t] * pwr_charge_up[s, t]) #charge_limit[s in n_storages, t in T]
        @constraint(Upper(model), pwr_discharge[s, t] <= u_discharge[s, t] * pwr_discharge_up[s, t]) #discharge_limit[s in n_storages, t in T], 
    end
end


@constraint(Lower(model), balance[t in T], sum(pwr_gen[g, t] for g in n_gens) + sum(pwr_discharge[s, t] for s in n_storages) 
            == Pdemand[t] + sum(pwr_charge[s, t] for s in n_storages))

@constraint(Lower(model), charge_limit[s in n_storages, t in T], pwr_charge[s, t] <= pwr_charge_up[s, t])
@constraint(Lower(model), discharge_limit[s in n_storages, t in T], pwr_discharge[s, t] <= pwr_discharge_up[s, t])

@variable(Upper(model), Clearing_price[t in T], DualOf(balance[t]))



@objective(Lower(model), Min, sum(price_discharge[s, t] * pwr_discharge[s, t] - price_charge[s, t] * pwr_charge[s, t] for s in n_storages, t in T)
                            +sum(offer_price[g] * pwr_gen[g, t] for g in n_gens, t in T))


@objective(Upper(model), Max, sum((Clearing_price[t] + price_charge[s, t]) * pwr_charge[s, t] for t in T, s in n_storages) 
                            - sum((Clearing_price[t] + price_discharge[s, t]) * pwr_discharge[s, t] for t in T, s in n_storages))

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
df[!, :P_thermal] = [sum(value(pwr_gen[g, t]) for g in n_gens) for t in T]
df[!, :P_demand] = demand_7days

# println(df)
CSV.write("result.csv", df)


