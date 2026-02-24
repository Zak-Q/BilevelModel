# 求解器配置文件

"""
Gurobi 求解器参数配置
可根据具体问题调整
"""

# 基础配置
const SOLVER_CONFIG = Dict(
    # 时间限制 (秒)
    "TimeLimit" => 3600,
    
    # MIP 相对误差容忍度
    "MIPGap" => 0.01,
    
    # 线程数 (0 = 自动)
    "Threads" => 0,
    
    # 允许非凸问题
    "NonConvex" => 2,
    
    # 输出日志级别 (0 = 静默, 1 = 正常)
    "OutputFlag" => 1,
    
    # 数值焦点 (0-3, 越高越重视数值稳定性)
    "NumericFocus" => 0,
    
    # 预求解级别 (-1 = 自动, 0 = 关闭, 1 = 保守, 2 = 激进)
    "Presolve" => -1,
    
    # MIP 启发式搜索强度 (0-1, 0 = 关闭)
    "Heuristics" => 0.05,
    
    # 分支变量选择策略 (-1 = 自动, 0-3 = 不同策略)
    "VarBranch" => -1,
    
    # 节点选择策略 (0-3)
    "NodeMethod" => -1
)

# Big-M 参数配置
const BIGM_CONFIG = Dict(
    # 价格的 Big-M
    "M_price" => 1000.0,
    
    # 功率的 Big-M
    "M_power" => 500.0,
    
    # 对偶变量的 Big-M
    "M_dual" => 10000.0,
    
    # 能量的 Big-M
    "M_energy" => 1000.0
)

# 模型参数配置
const MODEL_CONFIG = Dict(
    # 是否打印详细信息
    "verbose" => true,
    
    # 是否生成图表
    "generate_plots" => true,
    
    # 是否生成报告
    "generate_report" => true,
    
    # 图表DPI
    "plot_dpi" => 150,
    
    # 数值容差
    "numerical_tolerance" => 1e-6
)

# 场景配置
const SCENARIO_CONFIG = Dict(
    # 默认场景数
    "default_scenarios" => 3,
    
    # 场景生成方法 ("manual", "normal", "uniform")
    "generation_method" => "manual"
)

"""
    apply_solver_config!(model)

将配置应用到 JuMP 模型
"""
function apply_solver_config!(model)
    for (param, value) in SOLVER_CONFIG
        try
            set_optimizer_attribute(model, param, value)
        catch e
            @warn "设置参数 $param 失败: $e"
        end
    end
end

export SOLVER_CONFIG, BIGM_CONFIG, MODEL_CONFIG, SCENARIO_CONFIG
export apply_solver_config!

