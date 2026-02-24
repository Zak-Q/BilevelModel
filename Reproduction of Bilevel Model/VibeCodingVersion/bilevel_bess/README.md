# 储能系统双层优化建模与求解系统

## 📖 项目简介

本项目实现了基于 Nasrolahpour et al. (2018) 论文的**储能系统在电能与备用市场中的双层优化模型**。采用 Julia 语言 + JuMP 建模框架 + Gurobi 求解器,实现了从数据输入、模型求解、结果输出到可视化分析的完整工作流。

### 核心功能

- ✅ **双层优化模型**: 上层储能利润最大化,下层市场出清
- ✅ **多市场参与**: 日前能量、上/下备用、实时平衡市场
- ✅ **MPEC转换**: 通过KKT条件将双层问题转为MILP
- ✅ **场景建模**: 支持多场景实时市场不确定性分析
- ✅ **完整输出**: CSV结果、可视化图表、自动化报告

---

## 🏗️ 项目结构

```
bilevel_bess/
│
├── data/                          # 输入数据文件夹
│   ├── generators.csv             # 发电机参数
│   ├── loads.csv                  # 负荷数据(时序)
│   ├── storage.csv                # 储能系统参数
│   ├── scenarios.csv              # 不确定性场景
│   └── market_req.csv             # 市场备用需求
│
├── src/                           # 源代码模块
│   ├── data_loader.jl             # 数据加载与验证
│   ├── bilevel_model.jl           # 双层模型构建
│   ├── result_extractor.jl        # 结果提取与导出
│   ├── visualizer.jl              # 可视化模块
│   └── report_generator.jl        # 报告生成
│
├── results/                       # 输出结果文件夹
│   ├── csv/                       # CSV结果文件
│   ├── figures/                   # 图表文件(PNG)
│   └── reports/                   # Markdown报告
│
├── config/                        # 配置文件(可选)
├── Project.toml                   # Julia项目依赖
├── run.jl                         # 主运行脚本
└── README.md                      # 本文件

```

---

## 🚀 快速开始

### 1. 环境准备

#### 必需软件

- **Julia** ≥ 1.9 ([下载地址](https://julialang.org/downloads/))
- **Gurobi Optimizer** ([获取许可证](https://www.gurobi.com/))
  - 学术用户可免费获取许可证
  - 需要配置环境变量 `GUROBI_HOME`

#### 安装依赖

在项目根目录打开 Julia REPL:

```bash
cd bilevel_bess
julia
```

在 Julia REPL 中:

```julia
# 激活项目环境
using Pkg
Pkg.activate(".")

# 安装所有依赖
Pkg.instantiate()

# 或手动添加依赖
Pkg.add(["JuMP", "Gurobi", "CSV", "DataFrames", "Plots", "StatsPlots"])
```

### 2. 配置 Gurobi

```julia
using Pkg
Pkg.add("Gurobi")
Pkg.build("Gurobi")

# 测试安装
using Gurobi
using JuMP
model = Model(Gurobi.Optimizer)
# 如果没有报错,说明配置成功
```

### 3. 运行模型

**方式一: 命令行运行**

```bash
julia run.jl
```

**方式二: Julia REPL 运行**

```julia
include("run.jl")
```

**方式三: 交互式运行**

```julia
# 加载模块
include("src/data_loader.jl")
include("src/bilevel_model.jl")

# 加载数据
data = load_all_data("data")

# 构建并求解模型
model = build_bilevel_bess_model(data)
solve_model(model)

# ... 后续分析
```

---

## 📊 输入数据说明

### 1. `generators.csv` - 发电机参数

| 字段 | 说明 | 单位 |
|------|------|------|
| id | 发电机编号 | - |
| Pmax | 最大出力 | MW |
| Pmin | 最小出力 | MW |
| offer_price | 能量市场报价 | $/MWh |
| reserve_up_cost | 上备用成本 | $/MW |
| reserve_dn_cost | 下备用成本 | $/MW |
| r_up_max | 最大上备用容量 | MW |
| r_dn_max | 最大下备用容量 | MW |

### 2. `loads.csv` - 负荷数据

| 字段 | 说明 | 单位 |
|------|------|------|
| id | 负荷节点编号 | - |
| t1, t2, ..., t24 | 24小时负荷功率 | MW |
| bid_price | 负荷出价 | $/MWh |
| shedding_cost | 切负荷惩罚成本 | $/MWh |

### 3. `storage.csv` - 储能参数

| 字段 | 说明 | 单位 |
|------|------|------|
| id | 储能编号 | - |
| P_ch_max | 最大充电功率 | MW |
| P_dis_max | 最大放电功率 | MW |
| R_ch_max | 充电最大备用容量 | MW |
| R_dis_max | 放电最大备用容量 | MW |
| E_max | 能量容量上限 | MWh |
| E_min | 能量容量下限 | MWh |
| E_init | 初始能量 | MWh |
| MC_ch | 充电边际成本 | $/MWh |
| MC_dis | 放电边际成本 | $/MWh |
| eta_ch | 充电效率 | - |
| eta_dis | 放电效率 | - |

### 4. `scenarios.csv` - 场景数据

| 字段 | 说明 | 单位 |
|------|------|------|
| t | 时段 | - |
| k | 场景编号 | - |
| Q_deviation | 功率偏差 | MW |
| probability | 场景概率 | - |

### 5. `market_req.csv` - 市场需求

| 字段 | 说明 | 单位 |
|------|------|------|
| t | 时段 | - |
| R_UP_req | 上备用需求 | MW |
| R_DN_req | 下备用需求 | MW |

---

## 📈 输出结果说明

### CSV 文件

- `storage_schedule.csv`: 储能逐时段充放电、备用计划
- `market_prices.csv`: 能量和备用市场价格
- `balancing_prices.csv`: 实时平衡市场价格(分场景)
- `generator_dispatch.csv`: 发电机调度结果
- `profit_breakdown.csv`: 储能利润分解
- `realtime_dispatch_expected.csv`: 实时市场调度期望值

### 图表文件

1. **soc_curve.png**: 储能SOC曲线
2. **power_schedule.png**: 充放电功率调度
3. **market_prices.png**: 市场价格曲线
4. **reserve_capacity.png**: 备用容量投标
5. **profit_breakdown.png**: 利润分解图
6. **balancing_prices_heatmap.png**: 平衡价格热力图
7. **comprehensive_dashboard.png**: 综合仪表盘(4宫格)

### 报告文件

- `optimization_report.md`: 完整的结果分析报告
  - 模型配置
  - 执行摘要
  - 利润分析
  - 运行分析
  - 市场分析
  - 建议与展望

---

## 🔬 模型说明

### 双层优化结构

```
上层问题 (储能系统):
  决策变量: 充放电功率、备用容量投标、SOC
  目标函数: max 期望利润
  约束条件: 充放电互斥、SOC动态、容量限制
  
下层问题 (市场出清):
  决策变量: 发电机出力、负荷、市场价格
  目标函数: max 社会福利
  约束条件: 功率平衡、备用平衡、容量限制
```

### 求解方法

1. **KKT条件**: 用下层最优性条件替代下层问题
2. **Big-M方法**: 线性化互补约束
3. **MILP求解**: 使用Gurobi求解混合整数线性规划

---

## ⚙️ 参数调整

### 修改求解器参数

编辑 `src/bilevel_model.jl` 中的参数:

```julia
# 时间限制
set_optimizer_attribute(model, "TimeLimit", 3600)  # 秒

# MIP Gap
set_optimizer_attribute(model, "MIPGap", 0.01)  # 1%

# Big-M 参数
M_price = 1000.0
M_power = 500.0
M_dual = 10000.0
```

### 修改场景数据

可以通过编辑 `data/scenarios.csv` 增加或减少场景数量,改变不确定性建模的精度。

---

## 📚 参考文献

> Nasrolahpour, E., Kazempour, J., Zareipour, H., & Rosehart, W. D. (2018).  
> "A Bilevel Model for Participation of a Storage System in Energy and Reserve Markets."  
> *IEEE Transactions on Sustainable Energy*, 9(2), 582-598.  
> DOI: [10.1109/TSTE.2017.2749434](https://doi.org/10.1109/TSTE.2017.2749434)

---

## 🐛 常见问题

### Q1: Gurobi 许可证错误

**A**: 确保已安装有效的 Gurobi 许可证:
```bash
gurobi_cl --license
```

### Q2: 中文字体显示问题

**A**: 修改 `src/visualizer.jl` 中的字体设置:
```julia
# macOS
chinese_font = "PingFang SC"

# Windows
chinese_font = "Microsoft YaHei"

# Linux
chinese_font = "WenQuanYi Micro Hei"
```

### Q3: 求解时间过长

**A**: 可以尝试:
- 减少场景数量
- 增大 MIPGap
- 减少时段数 T
- 调整 Big-M 参数

### Q4: 模型无可行解

**A**: 检查:
- 储能容量参数是否合理
- 备用需求是否过高
- 发电机容量是否能满足负荷

---

## 🛠️ 扩展开发

### 添加多储能支持

修改 `data/storage.csv` 添加多行,并在 `bilevel_model.jl` 中扩展循环:

```julia
for s in 1:n_stor
    # 为每个储能系统创建变量和约束
end
```

### 增加网络约束

引入节点和线路数据,添加潮流约束:

```julia
# 直流潮流
@constraint(model, power_flow[l in lines, t in T],
    f[l,t] == B[l] * (θ[from[l],t] - θ[to[l],t])
)
```

### 考虑储能退化

添加循环次数约束和退化成本:

```julia
# 等效循环次数
cycles = sum(p_dis[t] for t in 1:T) / (2 * E_max)

# 退化成本
degradation_cost = cycles * cost_per_cycle
```

---

## 📧 联系方式

如有问题或建议,请通过以下方式联系:

- **项目地址**: (根据实际情况填写)
- **邮箱**: (根据实际情况填写)

---

## 📄 许可证

本项目仅供学术研究使用。

---

## 🙏 致谢

- 感谢 [JuMP.jl](https://jump.dev/) 提供优秀的建模框架
- 感谢 [Gurobi](https://www.gurobi.com/) 提供强大的求解器
- 感谢原论文作者的开创性工作

---

**最后更新**: 2025-11-02

