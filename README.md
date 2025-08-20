# Eridanus & Antlia 部署工具

专为 **Arch Linux** 系统优化的 Eridanus QQ 机器人自动化部署与管理工具。

## 🌟 特性

- ✅ **专为 Arch Linux 优化**：仅支持 pacman 包管理器，确保最佳兼容性
- 🚀 **一键部署**：自动安装所有依赖和环境配置
- 🎯 **简化架构**：专注于 Eridanus + Lagrange 组合
- 📱 **交互式管理**：提供直观的菜单界面
- 🔧 **后台运行**：支持 tmux/screen 会话管理
- 📊 **日志管理**：完整的日志记录和查看功能

## 📋 系统要求

- **操作系统**：Arch Linux
- **架构**：x86_64
- **权限**：sudo 权限（用于安装系统包）
- **网络**：稳定的互联网连接

## 🚀 快速开始

### 1. 下载脚本

```bash
# 下载部署脚本
wget -O Antlia.sh https://github.com/zhende1113/Antlia/raw/refs/heads/main/Antlia.sh
chmod +x Antlia.sh
```

### 2. 运行部署

```bash
# 执行自动部署
./Antlia.sh
```

部署过程包括：
- 选择 GitHub 代理源
- 安装系统依赖包
- 配置 Miniconda 环境
- 安装 Lagrange 协议端
- 克隆 Eridanus 项目
- 安装 Python 依赖
- 生成启动脚本

### 3. 启动服务

部署完成后：

```bash
# 启动管理界面
./start.sh
```

## 📁 目录结构

```
项目根目录/
├── Antlia.sh          # 部署脚本
├── start.sh           # 启动管理脚本
└── bot/               # 部署目录
    ├── Eridanus/      # Eridanus 项目
    ├── Lagrange/      # Lagrange 协议端
    ├── logs/          # 日志文件
    └── deploy.status  # 部署状态文件
```

## 🎮 使用指南

### 主菜单功能

1. **启动所有服务（推荐）**
   - 自动配置 Eridanus 兼容 Lagrange
   - 后台启动 Eridanus
   - 交互式启动 Lagrange（用于扫码登录）

2. **停止所有服务**
   - 安全停止所有运行中的服务

3. **管理 Eridanus**
   - 后台启动/前台调试
   - 查看日志
   - 服务控制

4. **管理 Lagrange**
   - 交互式启动（扫码登录）
   - 后台运行
   - 日志查看

### 会话管理

- **Eridanus**：运行在 tmux 会话 `eridanus-main`
- **Lagrange**：运行在 screen 会话 `eridanus-lagrange`

#### 手动附加到会话

```bash
# 附加到 Eridanus 会话
tmux attach -t eridanus-main

# 附加到 Lagrange 会话
screen -r eridanus-lagrange
```

#### 从会话分离

- **tmux**：`Ctrl+b, d`
- **screen**：`Ctrl+a, d`

## 🔧 配置说明

### GitHub 代理选择

脚本提供多个代理源选择：

1. **Akams 镜像**（推荐）
2. **GHFAST.top 镜像**
3. **GHProxy.Net**
4. **不使用代理**

根据网络环境选择最适合的代理源。

### 自动配置

- **Conda 环境**：Python 3.11，名称为 `Eridanus`
- **镜像源**：使用清华大学镜像源加速下载
- **依赖管理**：自动安装所有必需的系统包和 Python 包

## 📝 日志文件

- **Lagrange 日志**：`bot/logs/lagrange.log`
- **Eridanus 日志**：`bot/Eridanus/log/YYYY-MM-DD.log`

## ⚠️ 注意事项

1. **系统限制**：仅支持 Arch Linux 系统
2. **权限要求**：需要 sudo 权限安装系统包
3. **网络要求**：确保网络连接稳定，建议使用代理源
4. **首次登录**：Lagrange 首次运行需要扫码登录
5. **服务管理**：建议使用提供的管理界面操作服务

## 🛠️ 故障排除

### 常见问题

1. **部署失败**
   - 检查网络连接
   - 尝试不同的 GitHub 代理源
   - 确认 sudo 权限

2. **服务启动失败**
   - 检查依赖安装是否完整
   - 查看相关日志文件
   - 确认 Conda 环境激活

3. **连接问题**
   - 检查 Lagrange 配置文件
   - 确认端口未被占用
   - 重新扫码登录

### 重新部署

如需重新部署：

```bash
# 清理旧环境
rm -rf bot/
conda env remove -n Eridanus

# 重新运行部署
./Antlia.sh
```

## 📚 相关项目

- [Eridanus](https://github.com/avilliai/Eridanus) - QQ 机器人框架
- [Lagrange.Core](https://github.com/LagrangeDev/Lagrange.Core) - QQ 协议端

## 📄 许可证

本项目遵循相关开源项目的许可证条款。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目！

---

**版本**：2025/08/20  
**支持系统**：Arch Linux (x86_64)  
**协议端**：Lagrange
