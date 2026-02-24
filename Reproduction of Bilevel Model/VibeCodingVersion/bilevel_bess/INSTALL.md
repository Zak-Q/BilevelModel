# 安装指南

## 系统要求

### 操作系统
- macOS 10.14+
- Linux (Ubuntu 18.04+, CentOS 7+)
- Windows 10+

### 软件要求
- Julia 1.9 或更高版本
- Gurobi Optimizer 9.0 或更高版本

---

## 详细安装步骤

### 第一步：安装 Julia

#### macOS

```bash
# 使用 Homebrew
brew install julia

# 或从官网下载 DMG 安装包
# https://julialang.org/downloads/
```

#### Linux

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install julia

# 或使用 juliaup (推荐)
curl -fsSL https://install.julialang.org | sh
```

#### Windows

从官网下载安装器：https://julialang.org/downloads/

验证安装：
```bash
julia --version
```

---

### 第二步：安装 Gurobi

#### 1. 下载 Gurobi

访问：https://www.gurobi.com/downloads/

#### 2. 获取学术许可证（免费）

如果您是学生/教师/研究人员：
1. 访问：https://www.gurobi.com/academia/academic-program-and-licenses/
2. 注册账号并申请学术许可证
3. 获取许可证文件 `gurobi.lic`

#### 3. 安装 Gurobi


**Windows:**
1. 运行 `.msi` 安装器
2. 设置环境变量 `GUROBI_HOME`
3. 在命令提示符中运行 `grbgetkey YOUR-LICENSE-KEY`

#### 4. 验证 Gurobi 安装

```bash
gurobi_cl --version
```

---

### 第三步：配置项目环境

#### 1. 克隆或下载项目

```bash
cd /path/to/your/workspace
# 如果是git仓库
# git clone <repository-url>

cd bilevel_bess
```

#### 2. 自动安装依赖

```bash
julia setup.jl
```

这个脚本会自动：
- 激活项目环境
- 安装所有依赖包
- 构建 Gurobi.jl
- 测试环境配置

#### 3. 手动安装（可选）

如果自动安装失败，可以手动安装：

```bash
julia
```

在 Julia REPL 中：

```julia
using Pkg

# 激活项目
Pkg.activate(".")

# 安装依赖
Pkg.add("JuMP")
Pkg.add("Gurobi")
Pkg.add("CSV")
Pkg.add("DataFrames")
Pkg.add("Plots")
Pkg.add("StatsPlots")

# 构建 Gurobi
Pkg.build("Gurobi")

# 实例化所有依赖
Pkg.instantiate()
```

---

### 第四步：验证安装

运行测试脚本：

```bash
julia -e 'using JuMP, Gurobi; m = Model(Gurobi.Optimizer); @variable(m, x >= 0); @objective(m, Max, x); @constraint(m, x <= 10); optimize!(m); println("测试成功! x = ", value(x))'
```

如果输出 `测试成功! x = 10.0`，说明环境配置正确。

---

## 常见问题

### Q1: Julia 找不到 Gurobi

**错误信息**: `ERROR: could not load library "libgurobi110.so"`

**解决方法**:
```bash
# 确保设置了正确的环境变量

# 重新构建 Gurobi.jl
```

### Q2: Gurobi 许可证错误

**错误信息**: `No Gurobi license found`

**解决方法**:
1. 确保运行了 `grbgetkey YOUR-LICENSE-KEY`
2. 检查许可证文件 `gurobi.lic` 是否存在
3. 许可证文件应该在以下位置之一：
   - Linux/macOS: `$HOME/gurobi.lic` 或 `/opt/gurobi/gurobi.lic`
   - Windows: `C:\gurobi\gurobi.lic`

### Q3: Plots 中文字体问题

**解决方法**:

编辑 `src/visualizer.jl`:

```julia
# macOS
chinese_font = "PingFang SC"

# Windows
chinese_font = "Microsoft YaHei"

# Linux (需要先安装中文字体)
chinese_font = "WenQuanYi Micro Hei"
```

Linux 安装中文字体：
```bash
sudo apt-get install fonts-wqy-microhei
```

### Q4: 包安装速度慢

**解决方法**:

配置 Julia 国内镜像（中国用户）：

```julia
# 在 Julia REPL 中
ENV["JULIA_PKG_SERVER"] = "https://mirrors.tuna.tsinghua.edu.cn/julia"

# 或者
ENV["JULIA_PKG_SERVER"] = "https://mirrors.ustc.edu.cn/julia"
```

---

## 升级说明

### 升级 Julia 包

```bash
julia -e 'using Pkg; Pkg.update()'
```

### 升级 Gurobi

1. 下载新版本 Gurobi
2. 安装到新目录
3. 更新 `GUROBI_HOME` 环境变量
4. 重新构建 Gurobi.jl：
   ```bash
   julia -e 'using Pkg; Pkg.build("Gurobi")'
   ```

---

## 技术支持

如果遇到其他问题：

1. 查看 Julia 官方文档：https://docs.julialang.org/
2. 查看 JuMP 文档：https://jump.dev/
3. 查看 Gurobi 文档：https://www.gurobi.com/documentation/

---

安装完成后，运行：
```bash
julia run.jl
```

开始使用本项目！

