#-------------------------------------------------------------------------------------------------------------------------------------------

 # Initialize

 # Load config file
 const config_path = joinpath(@__DIR__, "config.json")
 config = load_config(config_path)

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
 const Nodal = Set(["Nodal", "Node", "Full Network", "Whole Network", "Full"])
 const Regional = Set(["Regional", "Region", "Zonal", "Zone"])

 # Trace date selection
 const selected_year = config["trace"]["year"]
 const selected_month = config["trace"]["month"]
 const selected_day = config["trace"]["day"]

 # Planning horizon parameters
 const D = config["planning"]["operational_days"]  # Number of operational days
 const hours_per_day = 24
 const T = D * hours_per_day  # Calculated value

#  # Plotting parameters
#  const plot_horizon_days = config["plot_horizon_days"] # Days for plotting
#  const T_plot = plot_horizon_days * hours_per_day  # Total hours for plotting

 # Solver parameters
 const solver_name = config["solver_name"]  # Solver selection (e.g., Gurobi, CPLEX, etc.)
 const mipgap = config["mipgap"]  # MIP gap tolerance

 # Performance Metrics
 global solver_time = 0.0       # Total Gurobi solve time
 global solver_nodes = 0        # Total MIP nodes explored
 global solver_iterations = 0   # Total simplex/barrier iterations
 global total_cost = 0.0        # Total cost of the optimization

  # Results metrics
  global total_cost = 0.0        # Total cost of the optimization
  global gen_capacity = 0.0
  global total_fixed_cost = 0.0
  global total_variable_cost = 0.0


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