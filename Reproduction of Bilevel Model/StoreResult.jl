function store_subhorizon_variables(model::JuMP.Model)
    df = DataFrame(Time=Int[], VariableName=String[], Index=String[], Value=Float64[], VarIndex=String[])
    vars = all_variables(model)