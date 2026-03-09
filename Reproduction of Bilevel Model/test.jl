using Pkg

Pkg.add("Plots")
Pkg.add("BilevelJuMP")
Pkg.add("Gurobi")
using Plots, BilevelJuMP, Gurobi
# change from hardcoded values to parameters for easier testing and further developments
# time parameters
# generators 
offer_price = [20, 30, 25] # $/ MWh
Pmax = [40, 80, 60]
n_gens = length(Pmax)
# storages
n_storages = 1 #socket for further developments

# Variable demands
Pdemand = [120, 80]
n_demands = length(Pdemand)

model = BilevelModel(Gurobi.Optimizer,
                    mode = BilevelJuMP.FortunyAmatMcCarlMode(primal_big_M = 1000, dual_big_M = 1000))
                set_optimizer_attribute(model, "TuneTrials", 3) # Tuning of solver parameters
                set_optimizer_attribute(model, "TuneTimeLimit", 3600) # Tuning of solver parameters
                set_optimizer_attribute(model, "TuneOutput", 1) # Tuning of solver parameters
                set_optimizer_attribute(model, "TuneResults", 1) # Tuning of solver parameters

@variable(Lower(model), 0 <= pwr_gen[i=1:n_gens] <= Pmax[i])
@variable(Lower(model), 0 <= pwr_charge)
@variable(Lower(model), 0 <= pwr_discharge)


@variable(Upper(model), 0 <= pwr_charge_up <= 50)
@variable(Upper(model), 0 <= pwr_discharge_up <= 40)
@variable(Upper(model), 0 <= price_charge)
@variable(Upper(model), 0 <= price_discharge)
@variable(Upper(model), u_charge, Bin)
@variable(Upper(model), u_discharge, Bin)
@variable(Upper(model), 0 <= SOC <= 50)

@constraint(Lower(model), balance, sum(pwr_gen[i] for i in 1:n_gens) + pwr_discharge == sum(Pdemand[i] for i in 1:n_demands) + pwr_charge)
@constraint(Lower(model), charge_limit, pwr_charge <= pwr_charge_up)
@constraint(Lower(model), discharge_limit, pwr_discharge <= pwr_discharge_up)

@variable(Upper(model), Clearing_price, DualOf(balance))


@objective(Lower(model), Min, sum(price_discharge * pwr_discharge - price_charge * pwr_charge for i in 1:n_storages)
                            +sum(offer_price[i] * pwr_gen[i] for i in 1:n_gens))


@objective(Upper(model), Max, sum((Clearing_price + price_charge) * pwr_charge for i in 1:n_storages) 
                            - sum((Clearing_price + price_discharge) * pwr_discharge for i in 1:n_storages))

# solve the bilevel model
optimize!(model)

vars = all_variables(model)

# check termination status before querying results
println("Termination status: ", termination_status(model))

if termination_status(model) == MOI.OPTIMAL || termination_status(model) == MOI.FEASIBLE
    println("The optimal value of the upper-level problem is: ", objective_value(Upper(model)))
    println("The optimal value of the lower-level problem is: ", objective_value(Lower(model)))
    println("The optimal generation is: ", value.(pwr_gen))
    println("The optimal charging power is: ", value.(pwr_charge))
    println("The optimal discharging power is: ", value.(pwr_discharge))
    println("The optimal clearing price is: ", value.(Clearing_price))
    println("The optimal price for charging is: ", value.(price_charge))
    println("The optimal price for discharging is: ", value.(price_discharge))
    println("All variables: ", vars)
    println("Var names: ", [name(var) for var in vars])
else
    println("No solution available (status: ", termination_status(model), ")")
end
