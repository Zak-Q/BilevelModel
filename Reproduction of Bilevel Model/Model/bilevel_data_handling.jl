worksheet = joinpath(DATA_DIR, ModelFile)

# Filter until end of dataset
function filter_data_end(df)
    for (i, row) in enumerate(eachrow(df))
        # Check if "END OF DATA" is in any column AND there’s at least one missing value
        row_values = collect(row)  # Convert row to array for easier checking
        has_end_of_data = any(x -> x isa String && x == "END OF DATA", row_values)
        has_missing = any(ismissing, row_values)
        if has_end_of_data && has_missing
            # Return rows up to (but not including) this row
            return df[1:i-1, :]
        end
    end
    # If "END OF DATA" is not found, return the whole DataFrame
    return df
end

#Create dataframes （Generator data for thermal unit, solar, and wind; Utility storage data for BESS system）
Generator_data_df = filter_data_end(DataFrame(XLSX.readtable(worksheet, "Generator Data")))
Utility_data_df = filter_data_end(DataFrame(XLSX.readtable(worksheet, "Utility Storage Data")))

# Considering only copper plate model, no need line information.

# Create Bus_data_dic from Bus_data_df
Bus_data_dic = Dict()
for i in 1:nrow(Bus_data_df)
    # Base dictionary with all mandatory fields
    bus_dict = Dict(
        "Bus_Region" => Bus_data_df[!, "Bus Region"][i],
        "Bus_Type" => Bus_data_df[!, "Bus Type"][i],
        "Demand_Trace_Weightage" => Bus_data_df[!, "Demand Trace Weightage"][i],
        "Power_Factor" => Bus_data_df[!, "Power Factor"][i],
        "Prosumer_Demand_p" => Bus_data_df[!, "Prosumer Demand (%)"][i],
        "Rooftop_PV_Capacity_MW" => Bus_data_df[!, "Rooftop PV Capacity (MW)"][i],
        "Feedin_Price_Ratio" => Bus_data_df[!, "Feedin Price Ratio"][i],
        "Maximum_Battery_Capacity_MWh" => Bus_data_df[!, "Maximum Battery Capacity (MWh)"][i],
        "Minimum_Battery_Capacity_MWh" => Bus_data_df[!, "Minimum Battery Capacity (MWh)"][i],
        "Maximum_Charge_Rate" => Bus_data_df[!, "Maximum Charge Rate (MW/h)"][i],
        "Maximum_Discharge_Rate" => Bus_data_df[!, "Maximum Discharge Rate (MW/h)"][i],
        "Battery_Efficiency" => Bus_data_df[!, "Battery Efficiency (%)"][i],
        "Minimum_Voltage" => Bus_data_df[!, "Minimum Voltage (pu)"][i],
        "Maximum_Voltage" => Bus_data_df[!, "Maximum Voltage (pu)"][i],
        "Base_kV" => Bus_data_df[!, "Base_kV"][i],
        "Demand_Trace_Name" => Bus_data_df[!, "Demand Trace Name"][i],
        "Wind_Trace_Name" => Bus_data_df[!, "Wind Trace Name"][i],
        "PV_Trace_Name" => Bus_data_df[!, "PV Trace Name"][i],
        "CST_Trace_Name" => Bus_data_df[!, "CST Trace Name"][i],
        "Rooftop_PV_Trace_Name" => Bus_data_df[!, "Rooftop PV Trace Name"][i]
    )

    # Conditionally add Bus_Subregion if the "Sub-region" column exists
    if "Sub-region" in names(Bus_data_df)
        bus_dict["Bus_Subregion"] = Bus_data_df[!, "Sub-region"][i]
    end

    # Conditionally add Bus_REZ if the "REZ" column exists
    if "REZ" in names(Bus_data_df)
        bus_dict["Bus_REZ"] = Bus_data_df[!, "REZ"][i]
    end

    # Assign the dictionary to the bus name
    Bus_data_dic[Bus_data_df[!, "Bus Name"][i]] = bus_dict
end

Generator_data_dic = Dict(
    Generator_data_df[!, "Generator Name"][i] => Dict(
        # "Location_Bus" => Generator_data_df[!, "Location Bus"][i],
        "Number_Units" => Generator_data_df[!, "Number of Units"][i],
        "Connected_Grid" => Generator_data_df[!, "Connected to Grid"][i],
        "Apparent_Power_Rating" => Generator_data_df[!, "Apparent Power Rating (MVA)"][i],
        "Fix_Cost" => Generator_data_df[!, "Fix Cost (\$)"][i],
        "Start_up_Cost" => Generator_data_df[!, "Start up Cost (\$)"][i],
        "Shut_down_Cost" => Generator_data_df[!, "Shut down Cost (\$)"][i],
        "Variable_Cost" => Generator_data_df[!, "Variable Cost (\$/MW)"][i],
        "Maximum_Real_Power" => Generator_data_df[!, "Maximum Real Power (MW)"][i],
        "Minimum_Real_Power" => Generator_data_df[!, "Minimum Real Power (MW)"][i],
        "Maximum_Reactive_Power" => Generator_data_df[!, "Maximum Reactive Power (MVar)"][i],
        "Minimum_Reactive_Power" => Generator_data_df[!, "Minimum Reactive Power (MVar)"][i],
        # "Ramp_Up_Rate" => Generator_data_df[!, "Ramp Up Rate (MW/h)"][i],
        # "Ramp_Down_Rate" => Generator_data_df[!, "Ramp Down Rate (MW/h)"][i],
        # "MUT_h" => Generator_data_df[!, "MUT (hour)"][i],
        # "MDT_h" => Generator_data_df[!, "MDT (hour)"][i],
        "Generation_Type" => Generator_data_df[!, "Generation Type"][i],
        "Plot_Color" => Generator_data_df[!, "Plot Color"][i],
        "Generation_Tech" => Generator_data_df[!, "Generation Tech"][i]
    )
    for i in 1:nrow(Generator_data_df)
)

# Create Utility_storage_data_dic from Utility_data_df
Utility_storage_data_dic = Dict()
for i in 1:nrow(Utility_data_df)
    # Base dictionary with all mandatory fields
    utility_dict = Dict(
        # "Location_Bus" => Utility_data_df[!, "Location Bus"][i],
        "Connected_to_Grid" => Utility_data_df[!, "Connected to Grid"][i],
        "Maximum_Storage_Capacity_MWh" => Utility_data_df[!, "Maximum Storage Capacity (MWh)"][i],
        "Minimum_Storage_Capacity_MWh" => Utility_data_df[!, "Minimum Storage Capacity (MWh)"][i],
        "Maximum_Charge_Rate_MWh" => Utility_data_df[!, "Maximum Charge Rate (MW/h)"][i], # Assuming this is charge power
        "Maximum_Discharge_Rate_MWh" => Utility_data_df[!, "Maximum Discharge Rate (MW/h)"][i], # Assuming this is discharge power
        "Plot_Color" => Utility_data_df[!, "Plot Color"][i]
    )

    # Check for efficiency columns
    if "Storage Efficiency (%)" in names(Utility_data_df)
        # Use Storage Efficiency for both charging and discharging
        utility_dict["Charging_Efficiency"] = Utility_data_df[!, "Storage Efficiency (%)"][i]
        utility_dict["Discharging_Efficiency"] = Utility_data_df[!, "Storage Efficiency (%)"][i]
    elseif "Charging Efficiency (%)" in names(Utility_data_df) && "Discharging Efficiency (%)" in names(Utility_data_df)
        # Use separate Charging and Discharging Efficiency
        utility_dict["Charging_Efficiency"] = Utility_data_df[!, "Charging Efficiency (%)"][i]
        utility_dict["Discharging_Efficiency"] = Utility_data_df[!, "Discharging Efficiency (%)"][i]
    else
        # Neither set of columns is present; throw an error or set a default
        error("No efficiency columns found in Utility_data_df for utility storage $(Utility_data_df[!, "Utility Storage Name"][i])")
        # Default values if not found:
        # utility_dict["Charging_Efficiency"] = 0.9 (90%)
        # utility_dict["Discharging_Efficiency"] = 0.9 (90%)
    end

    # Assign the dictionary to the utility storage name
    Utility_storage_data_dic[Utility_data_df[!, "Utility Storage Name"][i]] = utility_dict
end


Generator_data_keys = keys(Generator_data_dic) # Generator names
Utility_data_keys = keys(Utility_storage_data_dic) # Utility storage names

# Filter generators not connected to grid (Connected_Grid != 1)
UGen = Set(key for key in Generator_data_keys if Generator_data_dic[key]["Connected_Grid"] == 1)

# Filter utility storage not connected to grid (Connected_to_Grid != 1)
UStorage = Set(key for key in Utility_data_keys if Utility_storage_data_dic[key]["Connected_to_Grid"] == 1)


# Generator type 1 set
GenT1 = Set()
for value in UGen
    Generation_type = Generator_data_dic[value]["Generation_Type"]
    if Generation_type == 1
        println("Generator ", value, " is Type ", Generation_type)
        push!(GenT1, (value))
    end
end

# Define GenT2 for wind and solar generators
GenT2 = Set()
for value in UGen
    Generation_type = Generator_data_dic[value]["Generation_Type"]
    if Generation_type == 2  # Wind and Solar
        println("Generator ", value, " is Type ", Generation_type)
        push!(GenT2, (value))
    end
end