#!/usr/bin/env julia

"""
环境配置脚本
自动安装所有依赖包
"""

using Pkg

println("=" ^ 60)
println("开始配置双层储能优化项目环境")
println("=" ^ 60)

# 激活当前项目
println("\n📦 激活项目环境...")
Pkg.activate(".")

# 安装依赖
println("\n📥 安装依赖包...")
required_packages = [
    "JuMP",
    "Gurobi", 
    "CSV",
    "DataFrames",
    "Plots",
    "StatsPlots",
    "Printf",
    "Dates",
    "LinearAlgebra"
]

for pkg in required_packages
    println("  → 安装 $pkg...")
    try
        Pkg.add(pkg)
        println("    ✓ $pkg 安装成功")
    catch e
        println("    ✗ $pkg 安装失败: $e")
    end
end

# 构建 Gurobi
println("\n🔧 构建 Gurobi...")
try
    Pkg.build("Gurobi")
    println("  ✓ Gurobi 构建成功")
catch e
    println("  ⚠️  Gurobi 构建失败: $e")
    println("  请确保已安装 Gurobi 并配置了有效的许可证")
end

# 测试环境
println("\n🧪 测试环境配置...")
try
    import JuMP
    import Gurobi
    import CSV
    import DataFrames
    import Plots
    
    # 测试创建模型
    test_model = JuMP.Model(Gurobi.Optimizer)
    JuMP.set_silent(test_model)
    JuMP.@variable(test_model, x >= 0)
    JuMP.@objective(test_model, Max, x)
    JuMP.@constraint(test_model, x <= 10)
    JuMP.optimize!(test_model)
    
    if JuMP.has_values(test_model)
        println("  ✓ 所有包加载成功")
        println("  ✓ Gurobi 测试通过")
    else
        println("  ✗ Gurobi 测试失败")
    end
    
catch e
    println("  ✗ 环境测试失败: $e")
end

println("\n" * "=" ^ 60)
println("✅ 环境配置完成!")
println("=" ^ 60)
println("\n运行以下命令开始求解:")
println("  julia run.jl")
println("\n")

