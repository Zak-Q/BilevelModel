using Pkg

pkg.add("Plots")
pkg.add("BilevelJuMP")
pkg.add("Gurobi")
using Plots, BilevelJuMP, Gurobi

#generators 
offer_price = [20, 30, 25] # $/ MWh
Pmax = [40, 80, 60]
n_gens = length(Pmax)
# storages
n_storages = 1 #socket for further developments

# Variable demands
bidding_demand = 150 # $/ MWh
Pdemand = 200
model = BilevelModel(solver=Gurobi.Optimizer,
        mode = BilevelJuMP.FortunyAmatMcCarlMode(primal_big_M = 100, dual_big_M = 100))

@variable(Lower(model), 0 <= pwr_gen[i=1:n_gens] <= Pmax[i])
@variable(Lower(model), 0 <= pwr_load <= Pdemand)
@variable(Lower(model), 0 <= pwr_charge)
@variable(Lower(model), 0 <= pwr_discharge)


@variable(Upper(model), 0 <= pwr_charge_up <= 50)
@variable(Upper(model), 0 <= pwr_discharge_up <= 40)
@variable(Upper(model), 0 <= price_charge)
@variable(Upper(model), 0 <= price_discharge)
@variable(Upper(model), u_charge, Bin)
@variable(Upper(model), u_discharge, Bin)
@variable(Upper(model), 0 <= SOC <= 50)


@constraint(Lower(model), balance, sum(pwr_gen[i] for i in 1:n_gens) + pwr_discharge == pwr_load + pwr_charge)
@constraint(Lower(model), charge_limit, pwr_charge <= pwr_charge_up)
@constraint(Lower(model), discharge_limit, pwr_discharge <= pwr_discharge_up)
@objective(Lower(model), Min, sum(price_discharge * pwr_discharge - price_charge * pwr_charge for i in 1:n_storages))