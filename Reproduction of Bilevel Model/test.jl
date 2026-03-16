using Pkg

Pkg.add("Plots")
Pkg.add("BilevelJuMP")
Pkg.add("Gurobi")
using Plots, BilevelJuMP, Gurobi
# change from hardcoded values to parameters for easier testing and further developments
# time parameters
T = 1:24
# generators 

offer_price = [20, 30, 25] # $/ MWh
Pmax = [40, 80, 60]
n_gens = 1:length(Pmax)
# storages
n_storages = [1] #socket for further developments

# Initial SOC for storage
SOC_init = 25  # Initial state of charge, e.g., 50% of capacity

# Variable demands
Pdemand_pu = [0.500984632, 0.457898237, 0.429643446, 0.415074058, 0.412996743, 0.418405645, 0.436150152, 0.447392694, 0.466319927, 0.477533855, 0.479361727, 0.478336055, 0.480954767, 0.486920206, 0.49496966, 0.510942916, 0.531998696, 0.540347797, 0.538768426, 0.553131553, 0.552731912, 0.544345579, 0.532461005, 0.504119974]
Pdemand= [Pdemand_pu[t] * sum(Pmax) for t in T]
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
@variable(Upper(model), 0 <= SOC[s in n_storages, t in T] <= 50)

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

# check termination status before querying results
println("Termination status: ", termination_status(model))

if termination_status(model) == MOI.OPTIMAL || termination_status(model) == MOI.FEASIBLE
    println("The optimal value of the upper-level problem is: ", objective_value(Upper(model)))
    println("The optimal value of the lower-level problem is: ", objective_value(Lower(model)))
    # 获取变量值
    gen = value.(pwr_gen)
    charge = value.(pwr_charge)
    discharge = value.(pwr_discharge)
    clearing_price = value.(Clearing_price)
    # 绘制发电机出力（黑色）
    p = plot()
    for g in n_gens
        plot!(T, [gen[g, t] for t in T], label="Gen $g", color=:black, lw=2)
    end
    # 绘制储能充电功率（蓝色虚线）
    for s in n_storages
        plot!(T, [charge[s, t] - discharge[s, t] for t in T], label="Storage power $s", color=:blue, lw=2, linestyle=:dash)
        #plot!(T, [discharge[s, t] for t in T], label="Storage Discharge $s", color=:blue, lw=2, linestyle=:solid)
    end
    xlabel!("Hour")
    ylabel!("Power (MW)")
    title!("Generation (black) & Storage (blue)")
    gui()
    savefig(p, "plot.png")  # Save the plot as a PNG file
else
    println("No solution available (status: ", termination_status(model), ")")
end
