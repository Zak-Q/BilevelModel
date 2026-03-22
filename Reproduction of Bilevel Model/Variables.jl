function store_subhorizon_variables(model::JuMP.Model)
    df = DataFrame(Time=Int[], VariableName=String[], Index=String[], Value=Float64[], VarIndex=String[])
    vars = all_variables(model)
    
    for var in vars
        var_name = name(var)
        if !isempty(var_name)
            base_name = split(var_name, "[")[1]  # e.g., "Pwr_Gen_var"
            index_str = occursin("[", var_name) ? split(var_name, "[")[2][1:end-1] : "scalar"  # e.g., "gen1,73"
            indices = split(index_str, ",") # e.g., ["gen1", "73"]
            if length(indices) == 2
                id, t_local = indices  # "generator_name", "local subhorizon time index"
                t_local_global = parse(Int, t_local)  # Global time index string to integer
                t_local_idx = t_local_global - first(subhorizon) + 1  # Convert to local subhorizon time index
                if t_local_idx < 1 || t_local_idx > length(subhorizon)
                    println("Warning: t_local $t_local_global (local idx $t_local_idx) out of bounds for $subhorizon in $var_name")
                    continue  # Skip if out of bounds
                end
                t_global = subhorizon[t_local_idx]  # Map local index to global time e.g., subhorizon[23]
                # Only store if t_global is within the abstracted subhorizon
                if t_global in abs_subhorizon
                    val = value(var)
                    var_index = string(base_name, "_", id)  # e.g., "S_Up_var_G1"
                    push!(df, (Subhorizon=sub, Time=t_global, VariableName=base_name, Index=id, Value=val, VarIndex=var_index))
                end
            elseif length(indices) == 1
                val = value(var)
                # Only store scalar variables (e.g., Build_line) in the first subhorizon
                if sub == 1
                    var_index = string(base_name, "_", index_str)
                    push!(df, (Subhorizon=sub, Time=0, VariableName=base_name, Index=index_str, Value=val, VarIndex=var_index))
                end
            end
        else
            println("Unnamed variable found: ", var)
        end
    end

    obj_value = objective_value(model)
    push!(df, (Subhorizon=sub, Time=first(abs_subhorizon), VariableName="Objective", Index="Subhorizon_$sub", Value=obj_value, VarIndex="Objective_Subhorizon_$sub"))

    fixed_cost = sum(Generator_data_dic[g]["Fix_Cost"] * value(model[:Status_var][g, t]) for g in UGen for t in abs_subhorizon)
    # startup_cost = sum(Generator_data_dic[g]["Start_up_Cost"] * value(model[:S_Up_var][g, t]) for g in UGen for t in abs_subhorizon)
    # shutdown_cost = sum(Generator_data_dic[g]["Shut_down_Cost"] * value(model[:S_Down_var][g, t]) for g in UGen for t in abs_subhorizon)
    variable_cost = sum(Generator_data_dic[g]["Variable_Cost"] * value(model[:Pwr_Gen_var][g, t]) for g in UGen for t in abs_subhorizon)
    # unserved_demand_cost = sum(value(model[:unserved_demand][n, t]) * voll for n in UBus for t in abs_subhorizon)

    # Store cost components
    push!(df, (Subhorizon=sub, Time=first(abs_subhorizon), VariableName="Fixed_Cost", Index="Subhorizon_$sub", Value=fixed_cost, VarIndex="Fixed_Cost_Subhorizon_$sub"))
    push!(df, (Subhorizon=sub, Time=first(abs_subhorizon), VariableName="Startup_Cost", Index="Subhorizon_$sub", Value=startup_cost, VarIndex="Startup_Cost_Subhorizon_$sub"))
    push!(df, (Subhorizon=sub, Time=first(abs_subhorizon), VariableName="Shutdown_Cost", Index="Subhorizon_$sub", Value=shutdown_cost, VarIndex="Shutdown_Cost_Subhorizon_$sub"))
    push!(df, (Subhorizon=sub, Time=first(abs_subhorizon), VariableName="Variable_Cost", Index="Subhorizon_$sub", Value=variable_cost, VarIndex="Variable_Cost_Subhorizon_$sub"))
    push!(df, (Subhorizon=sub, Time=first(abs_subhorizon), VariableName="Unserved_Demand_Cost", Index="Subhorizon_$sub", Value=unserved_demand_cost, VarIndex="Unserved_Demand_Cost_Subhorizon_$sub"))
    
    return df
end