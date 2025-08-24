#!/bin/bash

# Eridanus Docker 内部专用部署脚本
# 在一个 Debian-based (slim) 环境中运行

set -e

info() { echo "[INFO] $1"; }
ok() { echo "[OK] $1"; }
err() { echo "[ERROR] $1"; exit 1; }

info "开始在 Docker 内部执行部署..."

# =============================================================================
# 1. 安装系统依赖
# =============================================================================
info "安装系统依赖 (使用 apt-get)..."

# build-essential 包含 gcc, make 等编译工具
# python3-dev 包含 Python 的头文件
# git 用于克隆源码
# pkg-config 和 libcairo2-dev 用于构建 pycairo
apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3-dev \
    redis-server \
    curl \
    ca-certificates \
    git \
    pkg-config \
    libcairo2-dev || err "系统依赖安装失败"

ok "系统依赖安装完成。"

# =============================================================================
# 2. 克隆 Eridanus 源码
# =============================================================================
info "克隆 Eridanus 源码..."
git clone --depth 1 https://github.com/avilliai/Eridanus.git /app/Eridanus || err "源码克隆失败"
ok "源码克隆完成。"


# =============================================================================
# 3. 创建 Python 虚拟环境并安装依赖
# =============================================================================
info "创建 Python 虚拟环境 (venv)..."

cd /app
python3 -m venv venv || err "创建 venv 失败"

info "激活虚拟环境并安装 Python 依赖..."

# 激活 venv 并使用清华镜像源安装依赖
. venv/bin/activate
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
pip install --upgrade pip

if [ -f /app/Eridanus/requirements.txt ]; then
    pip install -r /app/Eridanus/requirements.txt || err "Python 依赖安装失败"
else
    err "在 /app/Eridanus/ 中未找到 requirements.txt"
fi

info "安装 Playwright 浏览器依赖..."
# --with-deps 会自动使用 apt-get 安装所有浏览器依赖
playwright install --with-deps || err "Playwright 浏览器安装失败"

deactivate
ok "Python 环境配置完成。"

# =============================================================================
# 4. 清理工作
# =============================================================================
info "清理不必要的编译工具和 git..."

apt-get purge -y --auto-remove build-essential python3-dev git pkg-config libcairo2-dev
rm -rf /var/lib/apt/lists/*

ok "清理完成。"

info "Docker 内部部署脚本执行完毕！"