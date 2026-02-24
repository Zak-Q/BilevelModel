# 快速开始指南

## ⚡ 5分钟快速上手

### 前置条件
- ✅ 已安装 Julia (≥ 1.9)
- ✅ 已安装 Gurobi 并配置许可证

### 三步运行

```bash
# 1. 进入项目目录
cd bilevel_bess

# 2. 安装依赖（首次运行）
julia setup.jl

# 3. 运行模型
julia run.jl
```

就这么简单！🎉

---

## 📂 理解项目结构

```
bilevel_bess/
├── data/              ← 📥 输入数据（CSV格式）
├── src/               ← 🔧 核心源代码
├── results/           ← 📤 输出结果
│   ├── csv/          ← 数据文件
│   ├── figures/      ← 图表
│   └── reports/      ← 分析报告
├── run.jl            ← ▶️ 主运行脚本
└── README.md         ← 📖 完整文档
```

---

## 🎯 查看结果

运行完成后，检查以下位置：

### 1. CSV 结果
```bash
ls results/csv/
```
- `storage_schedule.csv` - 储能调度计划
- `market_prices.csv` - 市场价格
- `profit_breakdown.csv` - 利润分解

### 2. 可视化图表
```bash
open results/figures/
```
- SOC曲线
- 充放电功率
- 市场价格
- 利润分解
- 综合仪表盘

### 3. 分析报告
```bash
open results/reports/optimization_report.md
```

---

## 🔧 修改输入数据

### 修改储能参数
编辑 `data/storage.csv`:
```csv
id,P_ch_max,P_dis_max,...
BESS1,50,50,...          ← 修改这些数值
```

### 修改负荷数据
编辑 `data/loads.csv`:
```csv
id,t1,t2,t3,...
D1,180,170,160,...       ← 修改24小时负荷
```

### 修改场景
编辑 `data/scenarios.csv`:
```csv
t,k,Q_deviation,probability
1,1,-5,0.2              ← 添加或修改场景
```

修改后重新运行 `julia run.jl`

---

## 📊 使用示例

### 示例1: 基础运行
```bash
julia run.jl
```

### 示例2: 定制化分析
```bash
julia example.jl
```

### 示例3: 交互式使用
```bash
julia

# 在 Julia REPL 中
include("run.jl")

# 访问结果
results[:profit][:total]      # 总利润
results[:e]                   # SOC序列
results[:λ_EN]                # 能量价格
```

---

## 💡 常用操作

### 只生成特定图表
```julia
include("src/visualizer.jl")
include("src/data_loader.jl")
include("src/bilevel_model.jl")
include("src/result_extractor.jl")

data = load_all_data("data")
model = build_bilevel_bess_model(data)
solve_model(model)
results = extract_results(model, data)

# 只生成 SOC 图
plot_soc_curve(results, data, "results")
```

### 导出特定数据
```julia
using CSV, DataFrames

# 创建自定义表格
custom_df = DataFrame(
    时段 = 1:24,
    充电 = results[:p_ch],
    放电 = results[:p_dis]
)

CSV.write("my_results.csv", custom_df)
```

### 修改求解参数
编辑 `config/solver_config.jl`:
```julia
const SOLVER_CONFIG = Dict(
    "TimeLimit" => 1800,    # 改为30分钟
    "MIPGap" => 0.02,       # 改为2% gap
    ...
)
```

---

## 🐛 常见问题

### ❌ 找不到 Gurobi
```bash
# 设置环境变量
export GUROBI_HOME="/opt/gurobi1100/linux64"
julia -e 'using Pkg; Pkg.build("Gurobi")'
```

### ❌ 许可证错误
```bash
# 检查许可证
ls ~/gurobi.lic

# 重新激活
grbgetkey YOUR-LICENSE-KEY
```

### ❌ 中文显示问题
编辑 `src/visualizer.jl` 第7行，修改字体名称

### ❌ 求解时间太长
- 减少时段数（修改输入数据）
- 减少场景数
- 增大 MIPGap（`config/solver_config.jl`）

---

## 📚 下一步

- 📖 阅读 [完整文档](README.md)
- 🔧 查看 [安装指南](INSTALL.md)  
- 📝 查看 [更新日志](CHANGELOG.md)
- 💻 运行 [示例代码](example.jl)

---

## 🆘 需要帮助？

1. 检查终端输出的错误信息
2. 阅读 README.md 的"常见问题"部分
3. 查看 Julia/JuMP/Gurobi 官方文档

---

**祝您使用愉快！** 🚀

