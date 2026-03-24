required_packages = ["CSV", "Dates", "DataFrames", "DataFramesMeta", "BilevelJuMP", "Gurobi", "Plots", "VegaLite", "XLSX", "JSON", "Logging", "Colors",  "Measures"]

# Function to check and install missing packages
using Pkg

function install_required_packages(packages)
    # Get the list of packages in the current environment
    installed_pkgs = [dep.name for dep in values(Pkg.dependencies()) if !dep.is_direct_dep]
    installed_pkgs_direct = [dep.name for dep in values(Pkg.dependencies()) if dep.is_direct_dep]
    
    for pkg in packages
        if pkg in installed_pkgs_direct
            println("$pkg is already installed as a direct dependency.")
        elseif pkg in installed_pkgs
            println("$pkg is already installed as a transitive dependency.")
            # Optionally upgrade to direct dependency if needed
            # Pkg.add(pkg)
        else
            println("Installing $pkg...")
            Pkg.add(pkg)
        end
    end
end

# Install packages if missing
install_required_packages(required_packages)

using CSV, Dates, DataFrames, DataFramesMeta, BilevelJuMP, Gurobi, Plots, VegaLite, XLSX, JSON, Logging, ArgParse, Measures, Plots

#-------------------------------------------------------------------------------------------------------------------------------------------

 # Initialize

 # Load config file
 const config_path = joinpath(@__DIR__, "config.json")
 config = JSON.parsefile(config_path)
 # Select model and input files
 const DATA_DIR = joinpath(@__DIR__, config["data_directory"])
 const Data_Demand_DIR = joinpath(@__DIR__, config["demand_directory"])
 const Data_Solar_DIR = joinpath(@__DIR__, config["solar_directory"])
 const Data_Wind_DIR = joinpath(@__DIR__, config["wind_directory"])
 const ModelFile = config["model_file"]
 const network_model = config["network_model"] # Network model detail - Cu_plate, Nodal or Regional

 # Identification of different generator types
 const BlCoal_Tech = Set(["BlCT", "Coal", "Black Coal", "Sub Critical"])
 const BrCoal_Tech = Set(["BrCT", "Brown Coal"])
 const Hydro_Tech = Set(["HYD", "HYDR", "Hydro", "Water", "Hydro RoR", "Hydropower", "Hydroelectric", "Run-of-River", "Large Hydro", "Small Hydro", "Pumped Hydro", "Dam-type Hydro"])
 const Gas_Tech = Set(["OCGT", "CCGT", "Gas", "Natural Gas", "NatGas", "Cogen", "NG", "CHP", "Gas Turbine", "Gas Engine", "GT"])
 const Solar_Tech = Set(["PV", "Solar", "SOLR", "Solar PV", "CST", "CSP", "Utility Solar", "Solar Thermal", "Photovoltaic"])
 const Wind_Tech = Set(["WND", "Wind", "Onshore Wind", "Offshore Wind", "Wind Turbine"])

 # Identification of network detail options
 const Cu_plate = Set(["Cu_plate", "Cu Plate" ,"Copper Plate", "Copperplate", "Copper plate", "Single-bus", "Single Bus"])

 # Trace date selection
 const selected_year = config["trace"]["year"]
 const selected_month = config["trace"]["month"]
 const selected_day = config["trace"]["day"]

 # Planning horizon parameters
 const D = config["planning"]["operational_days"]  # Number of operational days
 const hours_per_day = 24
 const T = D * hours_per_day  # Calculated value

  # Results storage (for post-processing)
  results = Dict(# "Status_var" => [],
                "Pwr_Gen_var" => [], 
                "SOC" => [], 
                "P_chrg" => [], 
                "P_dischrg" => [], 
                "U_bin" => [], 
                "Fixed_Cost" => [],
                "Variable_Cost" => [],
                "Total_Cost" => []
                )
 
const RESULTS_DIR = joinpath(@__DIR__, "results")

# Gen and Bus data loading
function load_gen_bus_data(file_path::String)
    result = Dict{String, DataFrame}()
    XLSX.openxlsx(file_path) do xf
        for sheet in XLSX.sheetnames(xf)
            result[sheet] = DataFrame(XLSX.gettable(xf[sheet]))
        end
    end
    return result
end

Model_data = load_gen_bus_data(joinpath(DATA_DIR, ModelFile))
# println("Model_data: ", Model_data)

Bus_data_dic = Dict()
for i in 1:nrow(Model_data["Bus Data"])
    # Base dictionary with all mandatory fields
    bus_dict = Dict(
        "Demand_Trace_Weightage" => Model_data["Bus Data"][!, "Demand Trace Weightage"][i],
        "Demand_Trace_Name" => Model_data["Bus Data"][!, "Demand Trace Name"][i],
        "Wind_Trace_Name" => Model_data["Bus Data"][!, "Wind Trace Name"][i],
        "PV_Trace_Name" => Model_data["Bus Data"][!, "PV Trace Name"][i],
    )
    Bus_data_dic[Model_data["Bus Data"][!, "Bus Name"][i]] = bus_dict
end
# println("Bus_data_dic: ", Bus_data_dic)

Generator_data_dic = Dict(
    Model_data["Generator Data"][!, "Generator Name"][i] => Dict(
        "Location_Bus" => Model_data["Generator Data"][!, "Location Bus"][i],
        "Number_Units" => Model_data["Generator Data"][!, "Number of Units"][i],        
        "Fix_Cost" => Model_data["Generator Data"][!, "Fix Cost (\$)"][i],
        "Variable_Cost" => Model_data["Generator Data"][!, "Variable Cost (\$/MW)"][i],
        "Maximum_Real_Power" => Model_data["Generator Data"][!, "Maximum Real Power (MW)"][i],
        "Minimum_Real_Power" => Model_data["Generator Data"][!, "Minimum Real Power (MW)"][i],
        "Generation_Type" => Model_data["Generator Data"][!, "Generation Type"][i],        
        "Generation_Tech" => Model_data["Generator Data"][!, "Generation Tech"][i]
    )
    for i in 1:nrow(Model_data["Generator Data"])
)
# println("Generator_data_dic: ", Generator_data_dic)

Utility_storage_data_dic = Dict()
for i in 1:nrow(Model_data["Utility Storage Data"])
    # Base dictionary with all mandatory fields
    utility_dict = Dict(
        "Location_Bus" => Model_data["Utility Storage Data"][!, "Location Bus"][i],
        "Maximum_Storage_Capacity_MWh" => Model_data["Utility Storage Data"][!, "Maximum Storage Capacity (MWh)"][i],
        "Minimum_Storage_Capacity_MWh" => Model_data["Utility Storage Data"][!, "Minimum Storage Capacity (MWh)"][i],
        "Maximum_Charge_Rate_MWh" => Model_data["Utility Storage Data"][!, "Maximum Charge Rate (MW/h)"][i], # Assuming this is charge power
        "Maximum_Discharge_Rate_MWh" => Model_data["Utility Storage Data"][!, "Maximum Discharge Rate (MW/h)"][i], # Assuming this is discharge power
    )

    # Check for efficiency columns
    if "Storage Efficiency (%)" in names(Model_data["Utility Storage Data"])
        # Use Storage Efficiency for both charging and discharging
        utility_dict["Charging_Efficiency"] = Model_data["Utility Storage Data"][!, "Storage Efficiency (%)"][i]
        utility_dict["Discharging_Efficiency"] = Model_data["Utility Storage Data"][!, "Storage Efficiency (%)"][i]
    elseif "Charging Efficiency (%)" in names(Model_data["Utility Storage Data"]) && "Discharging Efficiency (%)" in names(Model_data["Utility Storage Data"])
        # Use separate Charging and Discharging Efficiency
        utility_dict["Charging_Efficiency"] = Model_data["Utility Storage Data"][!, "Charging Efficiency (%)"][i]
        utility_dict["Discharging_Efficiency"] = Model_data["Utility Storage Data"][!, "Discharging Efficiency (%)"][i]
    else
        # Neither set of columns is present; throw an error or set a default
        error("No efficiency columns found in Utility_data_df for utility storage $(Model_data["Utility Storage Data"][!, "Utility Storage Name"][i])")
    end
    # Assign the dictionary to the utility storage name
    Utility_storage_data_dic[Model_data["Utility Storage Data"][!, "Utility Storage Name"][i]] = utility_dict
end
# println("Utility_storage_data_dic: ", Utility_storage_data_dic)

Generator_data_keys = keys(Generator_data_dic) # Generator names
Utility_data_keys = keys(Utility_storage_data_dic) # Utility storage names
Bus_data_keys = keys(Bus_data_dic) # Bus names

# Filter generators not connected to grid (Connected_Grid != 1)
UGen = Set(key for key in Generator_data_keys)

# Filter utility storage not connected to grid (Connected_to_Grid != 1)
UStorage = Set(key for key in Utility_data_keys)

UBus = Set(Bus_data_keys)
UBus_orig = UBus # Save original bus set, keep mapping relationships.
N = length(UBus)

# println("Generators connected to grid: ", UGen)
# println("Utility storage connected to grid: ", UStorage)
# println("Buses in the system: ", UBus)

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
    # println("Generator: ", value, " Technology: ", Gen_tech)
    push!(Gen_Tech_links, (value, Gen_tech)) 
end

# println("Generator to Bus links: ", Gen_Bus_links)
# println("Storage to Bus links: ", Storage_Bus_links)
# println("Generator Type 1 (GenT1): ", GenT1)
# println("Generator Type 2 (GenT2): ", GenT2)
# println("Generator to Technology links: ", Gen_Tech_links)


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
    println("GenT1_Bus_links for Cu_plate: ", GenT1_Bus_links)

    global GenT2_Bus_links = Set()
    for value in GenT2
        push!(GenT2_Bus_links, (value, "System"))
        println("Mapped generator $value to system bus")
    end
    println("GenT2_Bus_links for Cu_plate: ", GenT2_Bus_links)

    # Map all storage to the single "System" bus
    global Storage_Bus_links = Set()
    for value in UStorage
        push!(Storage_Bus_links, (value, "System"))
        println("Mapped storage $value to system bus")
    end
    println("Storage_Bus_links for Cu_plate: ", Storage_Bus_links)
end

# -------------------------------------------------------------------------------------------------------------------------------------------

# 7-day trace loading

# Trace data loading function
function get_7days_dataframe(file_path::String)
    df = CSV.read(file_path, DataFrame)
    # Use tryparse to skip invalid dates (e.g. Feb 29 in non-leap years)
    df.Date = [tryparse(Date, string(r.Year, "-", lpad(r.Month, 2, '0'), "-", lpad(r.Day, 2, '0'))) for r in eachrow(df)]
    filter!(row -> !isnothing(row.Date), df)
    sort!(df, :Date)
    start_date = Date(selected_year, selected_month, selected_day)
    df_7days = filter(row -> start_date <= row.Date <= start_date + Day(6), df)
    df_result = select(df_7days, Not(:Year, :Month, :Day, :Date))

    long_vector = vcat([collect(row) for row in eachrow(df_result)]...)
    return long_vector
end

# Load demand traces for all buses and aggregate to system bus
system_demand_7days = zeros(length(get_7days_dataframe(joinpath(Data_Demand_DIR, Bus_data_dic[first(keys(Bus_data_dic))]["Demand_Trace_Name"] * ".csv"))))

for (index, bus_name) in enumerate(UBus_orig)
    demand_trace_name = Bus_data_dic[bus_name]["Demand_Trace_Name"]
    demand_weightage = Bus_data_dic[bus_name]["Demand_Trace_Weightage"]
    bus_demand_7days = get_7days_dataframe(joinpath(Data_Demand_DIR, demand_trace_name * ".csv"))
    
    # Add weighted demand to system total
    system_demand_7days .+= demand_weightage .* bus_demand_7days
    println("Added demand from bus $bus_name with weightage $demand_weightage")
end

demand_7days = system_demand_7days
# println("Aggregated system demand for 7 days: ", demand_7days)

wind_generators = filter(g -> Generator_data_dic[g]["Generation_Tech"] in Wind_Tech, UGen)

# Aggregate wind power across all wind generators: wind_trace * max_real_power
first_wind_gen = first(wind_generators)
first_wind_bus = Generator_data_dic[first_wind_gen]["Location_Bus"]
first_wind_trace = Bus_data_dic[first_wind_bus]["Wind_Trace_Name"] * ".csv"
system_wind_7days = zeros(length(get_7days_dataframe(joinpath(Data_Wind_DIR, first_wind_trace))))

for gen in wind_generators
    location_bus = Generator_data_dic[gen]["Location_Bus"]
    wind_trace_name = Bus_data_dic[location_bus]["Wind_Trace_Name"] * ".csv"
    max_power = Generator_data_dic[gen]["Maximum_Real_Power"]
    units = Generator_data_dic[gen]["Number_Units"]
    max_power_total = max_power * units
    gen_wind_7days = get_7days_dataframe(joinpath(Data_Wind_DIR, wind_trace_name))

    system_wind_7days .+= max_power_total .* gen_wind_7days
    println("Added wind power from generator $gen (bus: $location_bus, max: $max_power_total MW)")
end

wind_7days = system_wind_7days
# println("Aggregated system wind power for 7 days: ", wind_7days)

solar_generators = filter(g -> Generator_data_dic[g]["Generation_Tech"] in Solar_Tech, UGen)

# Aggregate solar power across all solar generators: solar_trace * max_real_power
first_solar_gen = first(solar_generators)
first_solar_bus = Generator_data_dic[first_solar_gen]["Location_Bus"]
first_solar_trace = Bus_data_dic[first_solar_bus]["PV_Trace_Name"] * ".csv"
system_solar_7days = zeros(length(get_7days_dataframe(joinpath(Data_Solar_DIR, first_solar_trace))))

for gen in solar_generators
    location_bus = Generator_data_dic[gen]["Location_Bus"]
    solar_trace_name = Bus_data_dic[location_bus]["PV_Trace_Name"] * ".csv"
    max_power = Generator_data_dic[gen]["Maximum_Real_Power"]
    units = Generator_data_dic[gen]["Number_Units"]
    max_power_total = max_power * units
    gen_solar_7days = get_7days_dataframe(joinpath(Data_Solar_DIR, solar_trace_name))

    system_solar_7days .+= max_power_total .* gen_solar_7days
    println("Added solar power from generator $gen (bus: $location_bus, max: $max_power_total MW)")
end

solar_7days = system_solar_7days
# println("Aggregated system solar power for 7 days: ", solar_7days)

# ----------------------------------------------------------------------------------------------------------------------------------------------------

# GenT1: Conventional generators with offer price = variable cost * p + fixed cost * number of units