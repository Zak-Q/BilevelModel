using Pkg

Pkg.add("Plots")
Pkg.add("BilevelJuMP")
Pkg.add("Gurobi")
using Plots, BilevelJuMP, Gurobi

#generators 
offer_price = [20, 30, 25] # $/ MWh
Pmax = [40, 80, 60]
n_gens = length(Pmax)
# storages
n_storages = 1 #socket for further developments

# Variable demands
bidding_demand = [20, 30] # $/ MWh
Pdemand = [120, 80]
n_demands = length(Pdemand)
model = BilevelModel(Gurobi.Optimizer,
        mode = BilevelJuMP.FortunyAmatMcCarlMode(primal_big_M = 1000, dual_big_M = 1000))

@variable(Lower(model), 0 <= pwr_gen[i=1:n_gens] <= Pmax[i])
@variable(Lower(model), 0 <= pwr_load[i=1:n_demands] <= Pdemand[i])
@variable(Lower(model), 0 <= pwr_charge)
@variable(Lower(model), 0 <= pwr_discharge)


@variable(Upper(model), 0 <= pwr_charge_up <= 50)
@variable(Upper(model), 0 <= pwr_discharge_up <= 40)
@variable(Upper(model), 0 <= price_charge)
@variable(Upper(model), 0 <= price_discharge)
@variable(Upper(model), u_charge, Bin)
@variable(Upper(model), u_discharge, Bin)
@variable(Upper(model), 0 <= SOC <= 50)



@constraint(Lower(model), balance, sum(pwr_gen[i] for i in 1:n_gens) + pwr_discharge == sum(pwr_load[i] for i in 1:n_demands) + pwr_charge)
@constraint(Lower(model), charge_limit, pwr_charge <= pwr_charge_up)
@constraint(Lower(model), discharge_limit, pwr_discharge <= pwr_discharge_up)

@variable(Upper(model), Clearing_price, DualOf(balance))

@objective(Lower(model), Min, sum(price_discharge * pwr_discharge - price_charge * pwr_charge for i in 1:n_storages)
                              + sum(offer_price[i] * pwr_gen[i] for i in 1:n_gens)
                              - sum(bidding_demand[i] * pwr_load[i] for i in 1:n_demands))


@objective(Upper(model), Max, sum((Clearing_price + price_charge) * pwr_charge for i in 1:n_storages) 
                              - sum((Clearing_price + price_discharge) * pwr_discharge for i in 1:n_storages))


# solve the bilevel model
optimize!(model)

# check termination status before querying results
println("Termination status: ", termination_status(model))

if termination_status(model) == MOI.OPTIMAL || termination_status(model) == MOI.FEASIBLE
    println("The optimal value of the upper-level problem is: ", objective_value(Upper(model)))
    println("The optimal value of the lower-level problem is: ", objective_value(Lower(model)))
    println("The optimal generation is: ", value.(pwr_gen))
    println("The optimal load is: ", value.(pwr_load))
    println("The optimal charging power is: ", value.(pwr_charge))
    println("The optimal discharging power is: ", value.(pwr_discharge))
    println("The optimal clearing price is: ", value.(Clearing_price))
    println("The optimal price for charging is: ", value.(price_charge))
    println("The optimal price for discharging is: ", value.(price_discharge))  
else
    println("No solution available (status: ", termination_status(model), ")")
end

# The optimal value of the upper-level problem is: 53000.0
# The optimal value of the lower-level problem is: -50700.0
# The optimal generation is: [40.0, 30.0, 60.0]
# The optimal load is: [0.0, 80.0]
# The optimal charging power is: 50.0
# The optimal discharging power is: 0.0
# The optimal clearing price is: 30.0
# The optimal price for charging is: 1030.0
# The optimal price for discharging is: 0.0