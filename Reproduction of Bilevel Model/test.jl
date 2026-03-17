using Pkg

Pkg.add("Plots")
Pkg.add("BilevelJuMP")
Pkg.add("Gurobi")
Pkg.add("CSV")
Pkg.add("DataFrames")
using Plots, BilevelJuMP, Gurobi
using CSV, DataFrames, JuMP


# change from hardcoded values to parameters for easier testing and further developments
# time parameters
T = 1:24 # To be 1 week of hourly data
# generators 

offer_price = [20, 30, 25, 35, 40, 45] # $/ MWh
Pmax = [40, 80, 60, 50, 70, 90] # MW
n_gens = 1:length(Pmax)
# storages
n_storages = [1] #socket for further developments

# Initial SOC for storage
SOC_init = 0  # Initial state of charge, e.g., 50% of capacity

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

    # Save optimization results to CSV files
    market_rows = Vector{NamedTuple{(:timestamp, :type, :unit, :value), Tuple{Int, String, String, Float64}}}()

    for t in T
        for g in n_gens
            push!(market_rows, (timestamp=t, type="gen", unit="G$(g)", value=Float64(gen[g, t])))
        end
        for s in n_storages
            push!(market_rows, (timestamp=t, type="batt_ch", unit="B$(s)", value=Float64(charge[s, t])))
            push!(market_rows, (timestamp=t, type="batt_dis", unit="B$(s)", value=Float64(discharge[s, t])))
            push!(market_rows, (timestamp=t, type="soc", unit="B$(s)", value=Float64(value(SOC[s, t]))))
        end
        push!(market_rows, (timestamp=t, type="clearing_price", unit="market", value=Float64(clearing_price[t])))
    end

    market_df = DataFrame(market_rows)
    CSV.write(joinpath(@__DIR__, "market_results.csv"), market_df)

    summary_df = DataFrame(
        metric=["termination_status", "upper_objective", "lower_objective"],
        value=[string(termination_status(model)), string(objective_value(Upper(model))), string(objective_value(Lower(model)))]
    )
    CSV.write(joinpath(@__DIR__, "market_results_summary.csv"), summary_df)
    println("CSV files saved: market_results.csv, market_results_summary.csv")

    # 每个发电机一条曲线
    gen_colors = [:dodgerblue3, :orange2, :seagreen3, :goldenrod2, :firebrick2, :slateblue3]
    p = plot(legend=:outertopright)
    for (idx, g) in enumerate(n_gens)
        g_series = [gen[g, t] for t in T]
        plot!(
            T,
            g_series,
            color=gen_colors[mod1(idx, length(gen_colors))],
            lw=2.5,
            marker=:circle,
            ms=3,
            label="Gen $g"
        )
    end

    # 每个储能一条净功率曲线：每时段(放电-充电)
    storage_colors = [:black, :magenta3, :teal, :brown, :gray30]
    for (idx, s) in enumerate(n_storages)
        storage_net = [discharge[s, t] - charge[s, t] for t in T]
        plot!(
            T,
            storage_net,
            color=storage_colors[mod1(idx, length(storage_colors))],
            lw=2.5,
            linestyle=:dash,
            marker=:diamond,
            ms=3,
            label="Storage $s net (discharge-charge)"
        )
    end


    xlabel!("Hour")
    ylabel!("Power (MW)")
    title!("Generator and Storage Net Power Curves")
    gui()
    savefig(p, "plot.png")  # Save the plot as a PNG file
else
    println("No solution available (status: ", termination_status(model), ")")
end
