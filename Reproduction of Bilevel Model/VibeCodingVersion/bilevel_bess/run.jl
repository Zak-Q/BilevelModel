#!/usr/bin/env julia

"""
主运行脚本
完整执行双层储能市场优化模型的求解流程
"""

# 添加当前目录到加载路径
push!(LOAD_PATH, @__DIR__)

# 加载所有模块
include("src/data_loader.jl")
include("src/bilevel_model.jl")
include("src/result_extractor.jl")
include("src/visualizer.jl")
include("src/report_generator.jl")

using .Main: load_all_data, validate_data, print_data_summary
using .Main: build_bilevel_bess_model, solve_model
using .Main: extract_results, save_results_to_csv, print_summary_results
using .Main: generate_all_plots
using .Main: generate_report

using Printf
using Dates

"""
    main()

主执行函数
"""
function main()
    # 打印欢迎信息
    println("\n" * "=" ^ 80)
    println(" " ^ 20 * "储能系统双层优化模型求解系统")
    println(" " ^ 15 * "Bilevel Energy Storage Market Optimization")
    println("=" ^ 80)
    println("\n📅 运行时间: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
    println("🖥️  Julia 版本: $(VERSION)")
    println("\n")
    
    # ========================================
    # 第一步: 加载数据
    # ========================================
    data_dir = joinpath(@__DIR__, "data")
    output_dir = joinpath(@__DIR__, "results")
    
    if !isdir(output_dir)
        mkpath(output_dir)
    end
    
    println("【步骤 1/6】 数据加载")
    data = load_all_data(data_dir)
    
    # ========================================
    # 第二步: 数据验证
    # ========================================
    println("【步骤 2/6】 数据验证")
    validate_data(data)
    print_data_summary(data)
    
    # ========================================
    # 第三步: 构建模型
    # ========================================
    println("【步骤 3/6】 模型构建与求解")
    
    # 构建模型
    model = build_bilevel_bess_model(
        data, 
        verbose = true,
        time_limit = 3600  # 1小时时间限制
    )
    
    # 求解模型
    start_time = time()
    success = solve_model(model, verbose=true)
    solve_time = time() - start_time
    
    if !success
        println("❌ 模型求解失败,程序退出")
        return
    end
    
    # ========================================
    # 第四步: 提取结果
    # ========================================
    println("【步骤 4/6】 结果提取与分析")
    results = extract_results(model, data)
    print_summary_results(results, data)
    
    # ========================================
    # 第五步: 保存结果
    # ========================================
    println("【步骤 5/6】 结果保存")
    csv_dir = save_results_to_csv(results, data, output_dir)
    
    # ========================================
    # 第六步: 生成可视化和报告
    # ========================================
    println("【步骤 6/6】 可视化与报告生成")
    
    # 生成图表
    generate_all_plots(results, data, output_dir)
    
    # 生成报告
    report_file = generate_report(results, data, output_dir, solve_time=solve_time)
    
    # ========================================
    # 完成
    # ========================================
    println("\n" * "=" ^ 80)
    println("✅ 所有任务完成!")
    println("=" ^ 80)
    println("\n📂 输出文件位置:")
    println("   • CSV结果:  $(joinpath(output_dir, "csv"))")
    println("   • 图表:      $(joinpath(output_dir, "figures"))")
    println("   • 报告:      $(report_file)")
    println("\n总运行时间: $(@sprintf("%.2f", solve_time)) 秒")
    println("\n" * "=" ^ 80 * "\n")
    
    # 保存关键结果摘要到终端
    println("💡 关键结果摘要:")
    profit = results[:profit]
    @printf("   储能总利润:     \$%.2f\n", profit[:total])
    @printf("   能量市场收益:   \$%.2f\n", profit[:energy])
    @printf("   备用市场收益:   \$%.2f\n", profit[:reserve_up] + profit[:reserve_dn])
    @printf("   平衡市场收益:   \$%.2f\n", profit[:balancing])
    @printf("   利润率:         %.2f%%\n", (profit[:total]/(profit[:energy] + profit[:reserve_up] + profit[:reserve_dn] + profit[:balancing]))*100)
    println("\n" * "🎉" ^ 40 * "\n")
    
    return results
end

# 运行主函数
if abspath(PROGRAM_FILE) == @__FILE__
    try
        results = main()
        println("程序正常结束。")
    catch e
        println("\n❌ 程序执行出错:")
        println(e)
        Base.show_backtrace(stdout, catch_backtrace())
        println("\n")
    end
end

