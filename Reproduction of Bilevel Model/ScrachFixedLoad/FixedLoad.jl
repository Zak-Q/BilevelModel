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



function main()

    include("bilevel_data_handling.jl")

    # DataFrame to collect all variables across subhorizons
    all_vars_df = DataFrame(Time=Int[])
    pivoted_all_vars_df = DataFrame(Time=Int[])

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

            model = BilevelModel(Gurobi.Optimizer,
                    mode = BilevelJuMP.FortunyAmatMcCarlMode(primal_big_M = 1000, dual_big_M = 1000))
                set_optimizer_attribute(model, "MIPGap", mipgap)
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
            else
                println("No solution available (status: ", termination_status(model), ")")
            end
        end
    end
end
main()
