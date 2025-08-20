#!/bin/bash

# Eridanus 部署脚本 - 专为 Arch Linux (pacman) 优化
# 版本: 2025/08/20

set -o pipefail

# =============================================================================
# 路径与常量定义
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/bot"
DEPLOY_STATUS_FILE="$SCRIPT_DIR/bot/deploy.status"
GITHUB_PROXY=""

# =============================================================================
# 日志函数
# =============================================================================
info() { echo "[INFO] $1"; }
ok() { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
err() { echo "[ERROR] $1"; exit 1; }
print_title() { echo; echo "=== $1 ==="; echo; }

# =============================================================================
# 工具函数
# =============================================================================
command_exists() { 
    command -v "$1" >/dev/null 2>&1
}

download_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        info "下载尝试 $attempt/$max_attempts: $url"
        if wget -O "$output" "$url"; then
            ok "下载成功: $output"
            return 0
        fi
        warn "第 $attempt 次下载失败"
        if [[ $attempt -lt $max_attempts ]]; then
            info "5秒后重试..."
            sleep 5
        fi
        ((attempt++))
    done
    err "所有下载尝试都失败了"
}

# =============================================================================
# GitHub 代理选择
# =============================================================================
select_github_proxy() {
    print_title "选择 GitHub 代理"
    echo "请根据您的网络环境选择一个合适的下载代理："
    echo
    echo "1. Akams 镜像 (推荐)"
    echo "2. GHFAST.top 镜像"
    echo "3. GHProxy.Net"
    echo "4. 不使用代理"
    echo
    
    read -t 30 -p "请输入选择 (1-4, 默认1, 30秒后自动选择): " proxy_choice
    proxy_choice=${proxy_choice:-1}
    
    case $proxy_choice in
        1) GITHUB_PROXY="https://github.akams.cn/"; ok "已选择: Akams 镜像" ;;
        2) GITHUB_PROXY="https://ghfast.top/"; ok "已选择: GHFAST.top 镜像" ;;
        3) GITHUB_PROXY="https://ghproxy.net/"; ok "已选择: GHProxy.Net" ;;
        4) GITHUB_PROXY=""; ok "已选择: 不使用代理" ;;
        *)
            warn "无效输入，使用默认代理"
            GITHUB_PROXY="https://github.akams.cn/"
            ok "已选择: Akams 镜像 (默认)"
            ;;
    esac
}

# =============================================================================
# 系统检测
# =============================================================================
detect_system() {
    print_title "检测系统环境"
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) 
            ok "系统架构: $ARCH (支持)" 
            ;;
        *) 
            err "不支持的架构: $ARCH。本脚本仅支持 x86_64 架构。" 
            ;;
    esac
    
    # 检测包管理器 - 仅支持 pacman
    if command_exists pacman; then
        ok "检测到 Arch Linux (pacman)"
    else
        err "本脚本仅支持 Arch Linux (pacman) 系统。当前系统不受支持。"
    fi
}

# =============================================================================
# 系统依赖安装
# =============================================================================
install_system_dependencies() {
    print_title "安装系统依赖"
    
    local packages=(
        "redis"
        "tmux" 
        "git"
        "curl"
        "wget"
        "tar"
        "jq"
        "screen"
        "base-devel"
        "python"
        "python-pip"
    )
    
    info "更新系统包数据库..."
    sudo pacman -Sy --noconfirm || err "系统更新失败"
    
    info "安装必需的系统包..."
    sudo pacman -S --noconfirm "${packages[@]}" || err "依赖安装失败"
    
    ok "系统依赖安装完成"
}

# =============================================================================
# Conda 环境安装
# =============================================================================
install_conda_environment() {
    print_title "安装和配置 Conda 环境"
    
    if [[ -d "$HOME/miniconda3/envs/Eridanus" ]]; then
        ok "检测到 Conda 环境 'Eridanus' 已存在，跳过安装"
        return
    fi
    
    info "下载 Miniconda 安装脚本..."
    local miniconda_url="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    download_with_retry "$miniconda_url" "miniconda.sh"

    info "安装 Miniconda..."
    bash miniconda.sh -b -u -p "$HOME/miniconda3" || err "Miniconda 安装失败"
    rm -f miniconda.sh

    info "初始化 Conda..."
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda init --all || err "conda init 失败"
    source ~/.bashrc 2>/dev/null || true
    ok "Conda 安装成功"
    
    info "自动接受 Anaconda 服务条款..."
    conda config --set anaconda_tos_accepted yes || true
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
    ok "服务条款已接受"

    info "配置 Conda 镜像源..."
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/ >/dev/null 2>&1
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/ >/dev/null 2>&1

    info "创建 Python 3.11 虚拟环境 (Eridanus)..."
    conda create -n Eridanus python=3.11 -y || err "虚拟环境创建失败"
    conda activate Eridanus
    
    info "安装图形库依赖..."
    conda install pycairo -y || warn "pycairo 安装失败，可能需要手动安装"
    
    ok "Conda 环境配置完成"
}

# =============================================================================
# 项目克隆
# =============================================================================
clone_eridanus() {
    print_title "克隆 Eridanus 项目"
    
    cd "$DEPLOY_DIR"
    
    if [[ -d "Eridanus" ]]; then
        warn "检测到 Eridanus 文件夹已存在"
        read -p "是否删除并重新克隆? (y/n, 默认n): " del_choice
        if [[ "$del_choice" =~ ^[Yy]$ ]]; then
            rm -rf "Eridanus"
            ok "已删除旧的 Eridanus 文件夹"
        else
            warn "跳过 Eridanus 仓库克隆"
            return
        fi
    fi
    
    local repo_url="${GITHUB_PROXY}https://github.com/avilliai/Eridanus.git"
    info "开始克隆 Eridanus 仓库..."
    
    if ! git clone --depth 1 "$repo_url" Eridanus; then
        err "项目克隆失败，请检查网络或代理设置"
    fi
    
    ok "Eridanus 项目克隆完成"
}

# =============================================================================
# Python 依赖安装
# =============================================================================
install_python_dependencies() {
    print_title "安装 Python 依赖"
    
    cd "$DEPLOY_DIR/Eridanus" || err "无法进入 Eridanus 目录"
    
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda activate Eridanus
    
    info "配置 pip 镜像源..."
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple > /dev/null 2>&1
    
    info "升级 pip..."
    python -m pip install --upgrade pip || warn "pip 升级失败"
    
    info "安装项目依赖..."
    pip install -r requirements.txt || err "依赖安装失败"
    
    ok "Python 依赖已安装"
}

# =============================================================================
# Lagrange 安装
# =============================================================================
install_lagrange() {
    print_title "安装 Lagrange"

    cd "$DEPLOY_DIR"
    mkdir -p Lagrange tmp || err "无法创建目录"

    local TMP_DIR="$DEPLOY_DIR/tmp"
    cd "$TMP_DIR" || err "进入临时目录失败"

    info "获取 Lagrange 最新版本..."
    local github_url
    github_url=$(curl -s "https://api.github.com/repos/LagrangeDev/Lagrange.Core/releases/tags/nightly" | jq -r '.assets[] | select(.name | test("linux-x64.*.tar.gz")) | .browser_download_url')
    
    [[ -z "$github_url" ]] && err "无法获取 Lagrange 最新版本链接"

    local download_url="${GITHUB_PROXY}${github_url}"
    download_with_retry "$download_url" "Lagrange.tar.gz"

    info "解压 Lagrange..."
    tar -xzf "Lagrange.tar.gz" || err "解压失败"

    info "查找 Lagrange.OneBot 可执行文件..."
    local executable_path
    executable_path=$(find . -name "Lagrange.OneBot" -type f 2>/dev/null | head -1)

    if [[ -z "$executable_path" ]]; then
        err "未找到 Lagrange.OneBot 可执行文件"
    fi

    info "找到可执行文件: $executable_path"
    info "复制到目标目录..."

    cp "$executable_path" "$DEPLOY_DIR/Lagrange/Lagrange.OneBot" || err "复制失败"
    chmod +x "$DEPLOY_DIR/Lagrange/Lagrange.OneBot"

    [[ -f "$DEPLOY_DIR/Lagrange/Lagrange.OneBot" ]] || err "复制后仍未找到 Lagrange.OneBot"

    # 下载配置文件
    cd "$DEPLOY_DIR/Lagrange"
    wget -O appsettings.json https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/appsettings/appsettings-Eridanus.json

    # 清理临时目录
    info "清理临时文件..."
    rm -rf "$TMP_DIR"

    ok "Lagrange 安装完成"
}

# =============================================================================
# 启动脚本生成
# =============================================================================
generate_start_script() {
    print_title "生成启动脚本"
    
    cd "$SCRIPT_DIR"
    wget -O start.sh https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Eridanus/start.sh
    chmod +x start.sh
    
    ok "启动脚本已生成"
}

# =============================================================================
# 保存部署状态
# =============================================================================
save_deploy_status() {
    echo "PACKAGE_MANAGER=pacman" > "$DEPLOY_STATUS_FILE"
    echo "LAGRANGE_DEPLOYED=1" >> "$DEPLOY_STATUS_FILE"
    ok "部署状态已保存到 $DEPLOY_STATUS_FILE"
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    print_title "Eridanus 部署脚本 - Arch Linux 专版"
    echo "本脚本专为 Arch Linux 系统优化，仅支持 Lagrange 协议端"
    echo
    
    # 创建部署目录
    mkdir -p "$DEPLOY_DIR"
    cd "$SCRIPT_DIR" || exit
    
    # 执行部署步骤
    select_github_proxy
    detect_system
    install_system_dependencies
    install_conda_environment
    install_lagrange
    clone_eridanus
    install_python_dependencies
    generate_start_script
    save_deploy_status
    
    print_title "🎉 部署完成! 🎉"
    echo "所有操作已成功完成。"
    echo "下一步: 请运行 './start.sh' 来启动和管理您的机器人服务。"
}

# 执行主函数
main
