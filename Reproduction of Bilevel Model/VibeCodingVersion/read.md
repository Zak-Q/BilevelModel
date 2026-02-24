非常好——你现在要做的是把 **Nasrolahpour et al. (2018)** 论文的双层储能市场模型落地成一个 **可运行的 Julia + Gurobi 实现**，并且支持 **从 CSV 输入数据、输出结果图表与报告**。
下面是为交付准备的完整 **技术文档（Technical Specification Document）** 草稿，后续我可以再分阶段给出代码和图表。

---

# ⚙️ 技术文档：储能系统在电能与备用市场中的双层优化建模与求解（Julia + Gurobi实现）

## 1 总体目标

实现 Nasrolahpour et al. (2018) 提出的 **储能系统多市场参与双层优化模型**。
采用 **Julia 语言 + JuMP 建模 + Gurobi 求解器**，以 CSV 文件作为输入输出接口。
实现功能：

* 支持储能、电源、负荷等基础参数的导入；
* 求解 **储能期望利润最大化** 的双层问题；
* 输出储能最优报价与出力序列；
* 生成价格曲线、储能荷电状态曲线、收益对比等结果图；
* 自动生成结果说明文档（Markdown 或 PDF）。

---

## 2 模型结构概述

### 2.1 模型层次

| 层次            | 决策者                   | 目标函数    | 主要变量                   | 描述                 |
| ------------- | --------------------- | ------- | ---------------------- | ------------------ |
| 上层 (Leader)   | 储能系统 (Strategic BESS) | 最大化期望利润 | 报价 (ô)、投标量 (p̂)、储能SOC | 储能决定其在各市场的报价与容量投标  |
| 下层 (Follower) | 市场清算机制                | 最大化社会福利 | 发电出力、负荷、储能调度、价格λ       | 市场根据报价与负荷平衡决定价格与调度 |

最终通过 KKT 条件将下层嵌入上层，形成 MPEC → MILP 模型。

---

## 3 数学建模要点

### 3.1 上层问题：储能期望利润最大化

[
\max_{\Xi_{UL}}
\sum_t \Big[
(\lambda_t^{EN} - MC^{dis})p^{dis}_{s,t}

* (\lambda_t^{EN} + MC^{ch})p^{ch}_{s,t}

- \lambda_t^{UP}(r^{UP,ch}*{s,t}+r^{UP,dis}*{s,t})
- \lambda_t^{DN}(r^{DN,ch}*{s,t}+r^{DN,dis}*{s,t})
  \Big]
  +\sum_{t,k} \Phi_k \Big[
  (\lambda_{t,k}^{BL}-MC^{dis})(q^{UP,dis}*{s,t,k}-q^{DN,dis}*{s,t,k})
  +(\lambda_{t,k}^{BL}+MC^{ch})(q^{UP,ch}*{s,t,k}-q^{DN,ch}*{s,t,k})
  \Big]
  ]

约束包括充放电互斥、容量限制、SOC 动态约束、终端能量约束等。

### 3.2 下层问题（1）：日前联合能量与备用市场清算

最大化社会福利：
[
\max_{p,r}\sum_d U_{d,t}p_{d,t}
-\sum_g O_{g,t}p_{g,t}
-\sum_s (\hat{o}^{ch}*{s,t}p^{ch}*{s,t}-\hat{o}^{dis}*{s,t}p^{dis}*{s,t})
-\text{reserve cost terms}
]

约束包括能量平衡、上/下备用平衡、机组与储能容量限制。

### 3.3 下层问题（2）：实时平衡市场（多场景）

最小化社会失衡成本：
[
\min_{q,l}\sum_d V_d l_{d,t,k}
+\sum_g O_g (q^{UP}_g - q^{DN}_g)
+\sum_s \hat{o}_s (q^{UP}_s - q^{DN}_s)
]

约束：功率平衡（含场景偏差 Q_{t,k}）、备用可用量限制。

### 3.4 求解方法

1. 将两层模型转化为 **MPEC**：用下层 KKT 条件替代原下层问题。
2. 利用 **Big-M 方法** 线性化互补约束。
3. 对双线性项（价格 × 出力）使用 **二进制展开或分段线性化**。
4. 得到 **混合整数线性规划（MILP）**，用 Gurobi 求解。

---

## 4 输入输出设计

### 4.1 输入 CSV 文件格式

| 文件               | 内容     | 关键字段                                                      |
| ---------------- | ------ | --------------------------------------------------------- |
| `generators.csv` | 发电机参数  | id, Pg, offer_price, reserve_cost, r_up, r_dn             |
| `loads.csv`      | 负荷参数   | id, Pd_t, bid_price, shedding_cost                        |
| `storage.csv`    | 储能参数   | id, P_ch, P_dis, R_ch, R_dis, E, E_init, MC_ch, MC_dis, η |
| `scenarios.csv`  | 不确定性场景 | t, k, Q_tk, prob                                          |
| `market_req.csv` | 市场需求   | t, R_UP_t, R_DN_t                                         |

### 4.2 输出

* `results_storage.csv`: 储能的最优 p_ch, p_dis, r_up, r_dn, SOC, profit；
* `market_prices.csv`: λ_EN, λ_UP, λ_DN, λ_BL；
* 图表：

  * 价格曲线；
  * SOC 曲线；
  * 各市场利润分解；
* 自动生成 `report.md` 或 `report.pdf`。

---

## 5 Julia 实现框架

```julia
using JuMP, Gurobi, CSV, DataFrames, Plots

# 1. 读取输入
gen = CSV.read("generators.csv", DataFrame)
load = CSV.read("loads.csv", DataFrame)
stor = CSV.read("storage.csv", DataFrame)
scen = CSV.read("scenarios.csv", DataFrame)

# 2. 定义模型
model = Model(Gurobi.Optimizer)
set_silent(model)

# 3. 定义变量
@variables(model,
    p_ch[t in T] >= 0,
    p_dis[t in T] >= 0,
    e[t in T] >= 0,
    u_ch[t in T, Bin],
    u_dis[t in T, Bin],
    λ_en[t in T],
    ...
)

# 4. 约束 & 目标函数（按论文公式实现）

# 5. 求解
optimize!(model)

# 6. 输出结果
CSV.write("results_storage.csv", DataFrame(...))
plot(...)
```

---

## 6 结果展示标准

| 图表  | 内容             | 说明           |
| --- | -------------- | ------------ |
| 图 1 | 储能 SOC 曲线      | 反映充放电策略与能量平衡 |
| 图 2 | 能源/备用/平衡市场价格曲线 | 不同时段市场价格变化   |
| 图 3 | 储能分市场利润堆叠图     | 各业务贡献占比      |
| 图 4 | 不同场景收益箱线图      | 不确定性敏感性分析    |

---

## 7 交付物清单

1. **源代码文件**：

   * `bilevel_bess.jl`（完整 JuMP 模型）
   * `run_all.jl`（批处理脚本）
2. **数据样例**：五个 CSV 文件；
3. **结果图表**： `/figures/*.png`；
4. **结果报告**： `/doc/report.md ` 或 `report.pdf`；
5. **README.md**：使用说明与依赖环境。

---

## 8 可扩展方向

* 支持多储能、多节点网络（添加网络潮流约束）；
* 扩展到价格-taker 模式；
* 增加 Monte Carlo 场景生成模块；
* 引入 Carbon Pricing 或 Flexibility 分析。

---

是否希望我接下来直接生成 👉 **Julia 源代码框架（含输入输出模板和求解流程）**？
可以先做基础版（单储能、单节点、3 场景）便于验证，再扩展成完整版本。
