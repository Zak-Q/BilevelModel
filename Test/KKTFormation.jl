# Generator_data_dic = Dict(Model_data["Generator Data"][!, "Generator Name"][i] => 
#     Dict(
#         "Location_Bus" => Model_data["Generator Data"][!, "Location Bus"][i],
#         "Number_Units" => Model_data["Generator Data"][!, "Number of Units"][i],        
#         "Fix_Cost" => Model_data["Generator Data"][!, "Fix Cost (\$)"][i],
#         "Variable_Cost" => Model_data["Generator Data"][!, "Variable Cost (\$/MW)"][i],
#         "Maximum_Real_Power" => Model_data["Generator Data"][!, "Maximum Real Power (MW)"][i],
#         "Minimum_Real_Power" => Model_data["Generator Data"][!, "Minimum Real Power (MW)"][i],
#         "Generation_Type" => Model_data["Generator Data"][!, "Generation Type"][i],        
#         "Generation_Tech" => Model_data["Generator Data"][!, "Generation Tech"][i]
#          )
#     for i in 1:nrow(Model_data["Generator Data"])
# 
# Utility_storage_data_dic = Dict()
# for i in 1:nrow(Model_data["Utility Storage Data"])
#     utility_dict = 
#    Dict(
#         "Location_Bus" => Model_data["Utility Storage Data"][!, "Location Bus"][i],
#         "Maximum_Storage_Capacity_MWh" => Model_data["Utility Storage Data"][!, "Maximum Storage Capacity (MWh)"][i],
#         "Minimum_Storage_Capacity_MWh" => Model_data["Utility Storage Data"][!, "Minimum Storage Capacity (MWh)"][i],
#         "Maximum_Charge_Rate_MWh" => Model_data["Utility Storage Data"][!, "Maximum Charge Rate (MW/h)"][i], # Assuming this is charge power
#         "Maximum_Discharge_Rate_MWh" => Model_data["Utility Storage Data"][!, "Maximum Discharge Rate (MW/h)"][i], # Assuming this is discharge power
#         "Marginal_Cost_Charge" => Model_data["Utility Storage Data"][!, "Marginal Cost Charge ($/MWh)"][i],
#         "Marginal_Cost_Discharge" => Model_data["Utility Storage Data"][!, "Marginal Cost Discharge ($/MWh)"][i]
#         )
required_packages = ["CSV", "DataFrames", "DataFramesMeta", "JuMP", "Gurobi", "Plots", "VegaLite", "XLSX", "JSON", "Logging", "ArgParse", "Colors",  "Measures"]

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

using CSV, DataFrames, DataFramesMeta, JuMP, Gurobi, Plots, VegaLite, XLSX, JSON, Logging, ArgParse, Measures, Plots

function main()

    include("Initialise.jl")

    # UGen = Set(key for key in Generator_data_keys)
    # UStorage = Set(key for key in Utility_data_keys)
    # Demands = demand_7days
    # Wind = wind_7days
    # Solar = solar_7days
    Sys_demand = demand_7days .- wind_7days .- solar_7days

    model = Model(Gurobi.Optimizer)

    # 常用求解器参数
    set_optimizer_attribute(model, "OutputFlag", 1)
    set_optimizer_attribute(model, "TimeLimit", 300.0)
    set_optimizer_attribute(model, "MIPGap", 1e-4)
    set_optimizer_attribute(model, "Threads", 0)

    #-------------------Upper-level decision variables-------------------#
    @variable(model, 0 <= p_dis_up[s in n_storages, t in T] <= 100)

    @variable(model, 0 <= p[g in data.G, t in data.T] <= data.pmax[g])
    @variable(model, shed[t in data.T] >= 0)  # 负荷切除(高罚值)

    @objective(model, Min,
        sum(data.c[g] * p[g, t] for g in data.G, t in data.T) +
        1e4 * sum(shed[t] for t in data.T)
    )

    @constraint(model, balance[t in data.T],
        sum(p[g, t] for g in data.G) + shed[t] == data.demand[t]
    )
end
