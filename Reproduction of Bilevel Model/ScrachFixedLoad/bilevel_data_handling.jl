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

# =============================================================================
# Create dictionaries for buses, generators, and utility storage (push into dataframes)
# =============================================================================

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
Bus_data_keys = keys(Bus_data_dic) # Bus names

# Filter generators not connected to grid (Connected_Grid != 1)
UGen = Set(key for key in Generator_data_keys if Generator_data_dic[key]["Connected_Grid"] == 1)

# Filter utility storage not connected to grid (Connected_to_Grid != 1)
UStorage = Set(key for key in Utility_data_keys if Utility_storage_data_dic[key]["Connected_to_Grid"] == 1)

UBus = Set(Bus_data_keys)
UBus_orig = UBus
N = length(UBus)

# ====================================================================
# Create sets and Cross links for model building and result processing
# ====================================================================

# Generator to bus links
Gen_Bus_links = Set()
for value in UGen
    Location_bus = Generator_data_dic[value]["Location_Bus"]
    println("Generator ", value, " connected to Bus ", Location_bus)
    push!(Gen_Bus_links, (value, Location_bus))
end
Gen_Bus_links_orig = Gen_Bus_links # Save original Bus_Region_links for use in different network model details

# Storage to bus links
Storage_Bus_links = Set()
for value in UStorage
    Location_bus = Utility_storage_data_dic[value]["Location_Bus"]
    println("Utility Storage ", value, " connected to Bus ", Location_bus)
    push!(Storage_Bus_links, (value, Location_bus))
end

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

# Generator to technology links
Gen_Tech_links = Set()
for value in UGen
    Gen_tech = Generator_data_dic[value]["Generation_Tech"]
    Plot_color = Generator_data_dic[value]["Plot_Color"]
    # println("Generator: ", value, " Technology: ", Gen_tech)
    push!(Gen_Tech_links, (value, Gen_tech)) 
end

# Generator to plot color links
Gen_Color_links = Set()
for value in UGen
    Plot_color = Generator_data_dic[value]["Plot_Color"]
    push!(Gen_Color_links, (value, Plot_color))
end

# Storage to plot color links
Storage_Color_links = Set()
for value in UStorage
    Plot_color = Utility_storage_data_dic[value]["Plot_Color"]
    push!(Storage_Color_links, (value, Plot_color))
end

# Technology to plot color links
Tech_Color_links = Set()
for value in UGen
    Gen_tech = Generator_data_dic[value]["Generation_Tech"]
    Plot_color = Generator_data_dic[value]["Plot_Color"]
    # println("Generator: ", value, " Technology: ", Gen_tech, " PlotColor: ", Plot_color)
    push!(Tech_Color_links, (value, Gen_tech, Plot_color)) 
end

# ==============
# Initial values
# ==============

# Global technical parameters
SOC_utl_ini = 0.0 # Initial state of charge of batteries (Utility-scale)

# Generation intial values
# Slack_bus = determine_slack_bus(Generator_data_dic, Bus_data_dic, UGen, UBus) # Calls function to determine slack bus
Base_power = Bus_data_dic[Slack_bus]["Base_kV"] # Determine base power from slack bus
Pwr_Gen_ini_v = zeros(length(UGen), 1)
Status_ini_v = zeros(length(UGen), 1) # Numbers of Units online for each generator
S_Down_ini_v = zeros(length(UGen), 1)
# MUT_ini_v = zeros(length(UGen), T)
# MDT_ini_v = zeros(length(UGen), T)
Status_ini = Dict()
Pwr_Gen_ini = Dict()
S_Down_ini = Dict()
# MUT_ini = Dict()
# MDT_ini = Dict()

for (index, value) in enumerate(UGen)
    Status_ini[value] = Status_ini_v[index]
    Pwr_Gen_ini[value] = Pwr_Gen_ini_v[index]
    S_Down_ini[value] = S_Down_ini_v[index]
end
# for (index, value) in enumerate(UGen)
#     for t in subhorizon_total
#         MUT_ini[(value, t)] = MUT_ini_v[index, t]
#         MDT_ini[(value, t)] = MDT_ini_v[index, t]
#     end
# end

# Utility storage initial values
Chrg_rate_strg = Dict(value => Utility_storage_data_dic[value]["Maximum_Charge_Rate_MWh"] for value in UStorage)
Dchrg_rate_strg = Dict(value => Utility_storage_data_dic[value]["Maximum_Discharge_Rate_MWh"] for value in UStorage)
Min_SOC_strg = Dict(value => Utility_storage_data_dic[value]["Minimum_Storage_Capacity_MWh"] for value in UStorage)
Max_SOC_strg = Dict(value => Utility_storage_data_dic[value]["Maximum_Storage_Capacity_MWh"] for value in UStorage)
Charging_eff = Dict(value => Utility_storage_data_dic[value]["Charging_Efficiency"] / 100 for value in UStorage)
Discharging_eff = Dict(value => Utility_storage_data_dic[value]["Discharging_Efficiency"] / 100 for value in UStorage)
Enrg_Strg_ini = Dict(value => SOC_utl_ini for value in UStorage)


# Initialize dictionaries for passing states
prev_Status_var = Dict(g => Status_ini[g] for g in UGen)
prev_SOC = Dict(s => Enrg_Strg_ini[s] for s in UStorage)
prev_Pwr_Gen_var = Dict(g => Pwr_Gen_ini[g] for g in GenT1)
# prev_psm_batt_egy = Dict(n => SOC_psm_ini for n in UBus_orig)
# prev_S_Up_var = Dict(g => 0 for g in UGen)  # Track previous startups
# prev_S_Down_var = Dict(g => 0 for g in UGen)  # Track previous shutdowns

# =============================================================================
# Copper plate model data handling: Redefine sets and links for copper plate model (all buses aggregated into one "System" bus)
# =============================================================================

if network_model in Cu_plate
# Redefine UBus as a single "system" bus
    global UBus = Set(["System"])
    global N = length(UBus)
    global Slack_bus = "System"
    println("Copper plate aggregating all buses into system bus " , UBus)
    println("Number of buses: ", N)

    # Map all generators to the single "System" bus
    global GenT1_Bus_links = Set()
    for value in GenT1
        push!(GenT1_Bus_links, (value, "System"))
        println("Mapped generator $value to system bus")
    end
    # println("GenT1_Bus_links for Cu_plate: ", GenT1_Bus_links)

    global GenT2_Bus_links = Set()
    for value in GenT2
        push!(GenT2_Bus_links, (value, "System"))
        println("Mapped generator $value to system bus")
    end
    # println("GenT2_Bus_links for Cu_plate: ", GenT2_Bus_links)

    # Map all storage to the single "System" bus
    global Storage_Bus_links = Set()
    for value in UStorage
        push!(Storage_Bus_links, (value, "System"))
        println("Mapped storage $value to system bus")
    end
    # println("Storage_Bus_links for copper plate: ", Storage_Bus_links)
end