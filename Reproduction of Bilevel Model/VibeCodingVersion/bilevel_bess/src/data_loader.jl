# 数据加载模块
# 负责从CSV文件读取所有输入数据

using CSV
using DataFrames
using Printf
using Statistics

"""
    load_all_data(data_dir::String)

从指定目录加载所有市场和系统数据

# 参数
- `data_dir`: 包含所有CSV文件的目录路径

# 返回
返回包含所有数据的命名元组
"""
function load_all_data(data_dir::String)
    println("━" ^ 60)
    println("📁 开始加载数据...")
    println("━" ^ 60)
    
    # 加载发电机数据
    gen_file = joinpath(data_dir, "generators.csv")
    if !isfile(gen_file)
        error("❌ 找不到发电机数据文件: $gen_file")
    end
    generators = CSV.read(gen_file, DataFrame)
    println("✓ 发电机数据: $(nrow(generators)) 台发电机")
    
    # 加载负荷数据
    load_file = joinpath(data_dir, "loads.csv")
    if !isfile(load_file)
        error("❌ 找不到负荷数据文件: $load_file")
    end
    loads_raw = CSV.read(load_file, DataFrame)
    println("✓ 负荷数据: $(nrow(loads_raw)) 个负荷节点")
    
    # 加载储能数据
    stor_file = joinpath(data_dir, "storage.csv")
    if !isfile(stor_file)
        error("❌ 找不到储能数据文件: $stor_file")
    end
    storage = CSV.read(stor_file, DataFrame)
    println("✓ 储能数据: $(nrow(storage)) 个储能系统")
    
    # 加载场景数据
    scen_file = joinpath(data_dir, "scenarios.csv")
    if !isfile(scen_file)
        error("❌ 找不到场景数据文件: $scen_file")
    end
    scenarios = CSV.read(scen_file, DataFrame)
    
    # 提取时段数和场景数
    T = maximum(scenarios.t)
    K = maximum(scenarios.k)
    println("✓ 场景数据: $T 个时段, $K 个场景")
    
    # 加载市场备用需求
    market_file = joinpath(data_dir, "market_req.csv")
    if !isfile(market_file)
        error("❌ 找不到市场需求文件: $market_file")
    end
    market_req = CSV.read(market_file, DataFrame)
    println("✓ 市场需求数据: $(nrow(market_req)) 个时段")
    
    # 处理负荷时序数据
    load_cols = [Symbol("t$i") for i in 1:T]
    loads_timeseries = Matrix(loads_raw[:, load_cols])
    
    println("━" ^ 60)
    println("✅ 数据加载完成")
    println("━" ^ 60)
    
    return (
        generators = generators,
        loads = loads_raw,
        loads_timeseries = loads_timeseries,
        storage = storage,
        scenarios = scenarios,
        market_req = market_req,
        T = T,
        K = K,
        n_gen = nrow(generators),
        n_load = nrow(loads_raw),
        n_stor = nrow(storage)
    )
end

"""
    validate_data(data)

验证加载的数据的完整性和合理性
"""
function validate_data(data)
    println("\n🔍 验证数据...")
    
    # 验证储能参数
    stor = data.storage[1, :]
    @assert stor.P_ch_max > 0 "充电功率必须大于0"
    @assert stor.P_dis_max > 0 "放电功率必须大于0"
    @assert stor.E_max > stor.E_min "最大能量必须大于最小能量"
    @assert stor.E_init >= stor.E_min && stor.E_init <= stor.E_max "初始能量必须在范围内"
    @assert stor.eta_ch > 0 && stor.eta_ch <= 1 "充电效率必须在(0,1]"
    @assert stor.eta_dis > 0 && stor.eta_dis <= 1 "放电效率必须在(0,1]"
    
    # 验证场景概率
    for t in 1:data.T
        scen_t = filter(row -> row.t == t, data.scenarios)
        prob_sum = sum(scen_t.probability)
        if !isapprox(prob_sum, 1.0, atol=1e-6)
            @warn "时段 $t 的场景概率和为 $prob_sum, 不等于1"
        end
    end
    
    # 验证发电机参数
    for i in 1:data.n_gen
        gen = data.generators[i, :]
        @assert gen.Pmax >= gen.Pmin "发电机最大功率必须 >= 最小功率"
        @assert gen.offer_price >= 0 "报价必须非负"
    end
    
    println("✅ 数据验证通过\n")
end

"""
    print_data_summary(data)

打印数据摘要信息
"""
function print_data_summary(data)
    println("\n" * "=" ^ 60)
    println("📊 数据摘要")
    println("=" ^ 60)
    
    println("\n【时间维度】")
    println("  时段数: $(data.T)")
    println("  场景数: $(data.K)")
    
    println("\n【发电侧】")
    println("  发电机数量: $(data.n_gen)")
    total_cap = sum(data.generators.Pmax)
    println("  总装机容量: $(total_cap) MW")
    avg_price = mean(data.generators.offer_price)
    @printf("  平均报价: %.2f \$/MWh\n", avg_price)
    
    println("\n【负荷侧】")
    println("  负荷节点数: $(data.n_load)")
    total_load = sum(data.loads_timeseries[:, 1])
    max_load = maximum(data.loads_timeseries)
    min_load = minimum(data.loads_timeseries)
    @printf("  总负荷(t=1): %.2f MW\n", total_load)
    @printf("  峰值负荷: %.2f MW\n", max_load)
    @printf("  谷值负荷: %.2f MW\n", min_load)
    
    println("\n【储能系统】")
    stor = data.storage[1, :]
    println("  储能ID: $(stor.id)")
    @printf("  充电功率: %.2f MW\n", stor.P_ch_max)
    @printf("  放电功率: %.2f MW\n", stor.P_dis_max)
    @printf("  能量容量: %.2f MWh\n", stor.E_max)
    @printf("  初始能量: %.2f MWh\n", stor.E_init)
    @printf("  充电效率: %.2f%%\n", stor.eta_ch * 100)
    @printf("  放电效率: %.2f%%\n", stor.eta_dis * 100)
    
    println("\n【备用需求】")
    @printf("  平均上备用: %.2f MW\n", mean(data.market_req.R_UP_req))
    @printf("  平均下备用: %.2f MW\n", mean(data.market_req.R_DN_req))
    
    println("\n" * "=" ^ 60 * "\n")
end

export load_all_data, validate_data, print_data_summary

