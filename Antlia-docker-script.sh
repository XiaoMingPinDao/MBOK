#!/bin/bash

# Antlia 通用部署脚本 - 支持所有Linux发行版 (VENV 轻量优化版)
# 版本: 2025/08/24
# 适配各种包管理器，支持编译安装，专为非交互式环境（如 Docker, CI/CD）优化

set -o pipefail

# =============================================================================
# 路径与常量定义
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/bot"
VENV_DIR="$DEPLOY_DIR/venv" # 使用 VENV 虚拟环境
DEPLOY_STATUS_FILE="$SCRIPT_DIR/bot/deploy.status"
GITHUB_PROXY=""
PKG_MANAGER=""
DISTRO=""
COMPILE_INSTALL=false

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
        if wget --no-verbose -O "$output" "$url" 2>/dev/null || curl -s -L -o "$output" "$url" 2>/dev/null; then
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

# 编译安装函数
compile_install() {
    # ... [此函数内容保持不变] ...
    local package="$1"
    local source_url="$2"
    local configure_opts="$3"
    info "开始编译安装 $package..."
    local temp_dir="/tmp/${package}_build"
    mkdir -p "$temp_dir"; cd "$temp_dir"
    download_with_retry "$source_url" "${package}.tar.gz"
    tar -xzf "${package}.tar.gz" || err "解压 $package 失败"
    local source_dir=$(find . -maxdepth 1 -type d -name "${package}*" | head -1)
    [[ -z "$source_dir" ]] && err "未找到 $package 源码目录"
    cd "$source_dir"
    if [[ -f "configure" ]]; then
        ./configure $configure_opts || err "$package configure 失败"
    fi
    make -j$(nproc) || err "$package 编译失败"
    sudo make install || err "$package 安装失败"
    cd /; rm -rf "$temp_dir"
    ok "$package 编译安装完成"
}

# =============================================================================
# 包管理器检测
# =============================================================================
detect_package_manager() {
    info "检测包管理器..."
    local managers=("pacman:Arch Linux" "apt:Debian/Ubuntu" "dnf:Fedora/RHEL/CentOS" "yum:RHEL/CentOS (老版本)" "zypper:openSUSE" "apk:Alpine Linux")
    for manager_info in "${managers[@]}"; do
        local manager="${manager_info%%:*}"
        local distro="${manager_info##*:}"
        if command_exists "$manager"; then
            PKG_MANAGER="$manager"; DISTRO="$distro"
            ok "检测到包管理器: $PKG_MANAGER ($DISTRO)"
            return 0
        fi
    done
    err "未检测到支持的包管理器。脚本无法继续。"
}

# =============================================================================
# 系统检测
# =============================================================================
detect_system() {
    print_title "检测系统环境"
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|aarch64|arm64) ok "系统架构: $ARCH (支持)" ;;
        *) warn "架构 $ARCH 可能不被完全支持，继续尝试..." ;;
    esac
    if [[ -f /etc/os-release ]]; then source /etc/os-release; ok "检测到系统: $NAME"; fi
    detect_package_manager
}

# =============================================================================
# 通用包安装函数
# =============================================================================
install_package() {
    # ... [此函数内容保持不变, sudo 权限已满足] ...
    local package="$1"; local alt_package="$2"
    case $PKG_MANAGER in
        pacman) sudo pacman -S --noconfirm "$package" || ([ -n "$alt_package" ] && sudo pacman -S --noconfirm "$alt_package") ;;
        apt) sudo apt-get update -qq 2>/dev/null || true; sudo apt-get install -y "$package" || ([ -n "$alt_package" ] && sudo apt-get install -y "$alt_package") ;;
        dnf) sudo dnf install -y "$package" || ([ -n "$alt_package" ] && sudo dnf install -y "$alt_package") ;;
        yum) sudo yum install -y "$package" || ([ -n "$alt_package" ] && sudo yum install -y "$alt_package") ;;
        zypper) sudo zypper install -y "$package" || ([ -n "$alt_package" ] && sudo zypper install -y "$alt_package") ;;
        apk) sudo apk add "$package" || ([ -n "$alt_package" ] && sudo apk add "$alt_package") ;;
    esac
}

# =============================================================================
# 系统依赖安装
# =============================================================================
install_system_dependencies() {
    print_title "安装系统依赖"
    local packages=("redis" "tmux" "git" "curl" "wget" "tar" "jq" "screen")
    
    # 在 Dockerfile 中已安装 python3, 这里确保 venv 模块存在
    info "确保 python3-venv 存在..."
    case $PKG_MANAGER in
        apt) install_package "python3-venv" ;;
        dnf|yum) install_package "python3-virtualenv" ;;
    esac

    info "安装必需的系统包..."
    for package in "${packages[@]}"; do
        if ! command_exists "$package"; then
            info "安装 $package..."
            install_package "$package"
        else
            ok "$package 已安装"
        fi
    done
    ok "系统依赖安装完成"
}

# =============================================================================
# Python 虚拟环境 (VENV)
# =============================================================================
create_python_venv() {
    print_title "创建 Python 虚拟环境 (VENV)"
    if [[ -d "$VENV_DIR" ]]; then
        ok "VENV 环境 '$VENV_DIR' 已存在，跳过创建"
        return
    fi
    if ! command_exists python3; then err "未找到 python3"; fi
    
    info "正在创建 VENV 环境..."
    python3 -m venv "$VENV_DIR" || err "创建 VENV 失败"
    ok "VENV 环境创建成功"
}

# =============================================================================
# 项目克隆
# =============================================================================
clone_eridanus() {
    print_title "克隆 Eridanus 项目"
    cd "$DEPLOY_DIR"
    if [[ -d "Eridanus" ]]; then
        warn "检测到 Eridanus 文件夹已存在，跳过克隆。"
        return
    fi
    local repo_url="${GITHUB_PROXY}https://github.com/avilliai/Eridanus.git"
    info "开始克隆 Eridanus 仓库..."
    git clone --depth 1 "$repo_url" Eridanus || err "项目克隆失败"
    ok "Eridanus 项目克隆完成"
}

# =============================================================================
# Python 依赖安装
# =============================================================================
install_python_dependencies() {
    print_title "安装 Python 依赖"
    cd "$DEPLOY_DIR/Eridanus" || err "无法进入 Eridanus 目录"
    
    info "激活 VENV 并安装依赖..."
    source "$VENV_DIR/bin/activate" || err "激活 VENV 失败"
    
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple >/dev/null 2>&1
    python -m pip install --upgrade pip || warn "pip 升级失败"
    
    if [[ -f requirements.txt ]]; then
        pip install -r requirements.txt || err "依赖安装失败"
    else
        warn "未找到 requirements.txt"
    fi
    
    deactivate
    ok "Python 依赖已安装"
}

# =============================================================================
# Lagrange 安装
# =============================================================================
install_lagrange() {
    # ... [此函数内容保持不变] ...
    print_title "安装 Lagrange"
    cd "$DEPLOY_DIR"
    mkdir -p Lagrange tmp || err "无法创建目录"
    local TMP_DIR="$DEPLOY_DIR/tmp"; cd "$TMP_DIR" || err "进入临时目录失败"
    info "获取 Lagrange 最新版本..."
    local arch_tag=""
    case $(uname -m) in
        x86_64) arch_tag="linux-x64" ;;
        aarch64|arm64) arch_tag="linux-arm64" ;;
        *) arch_tag="linux-x64"; warn "使用 x64 版本" ;;
    esac
    local github_url=$(curl -s "https://api.github.com/repos/LagrangeDev/Lagrange.Core/releases/tags/nightly" | grep -o "https://[^\"]*${arch_tag}[^\"]*\.tar\.gz" | head -1)
    [[ -z "$github_url" ]] && err "无法获取 Lagrange 最新版本链接"
    download_with_retry "${GITHUB_PROXY}${github_url}" "Lagrange.tar.gz"
    tar -xzf "Lagrange.tar.gz" || err "解压失败"
    local executable_path=$(find . -name "Lagrange.OneBot" -type f 2>/dev/null | head -1)
    [[ -z "$executable_path" ]] && err "未找到 Lagrange.OneBot"
    cp "$executable_path" "$DEPLOY_DIR/Lagrange/Lagrange.OneBot" || err "复制失败"
    chmod +x "$DEPLOY_DIR/Lagrange/Lagrange.OneBot"
    cd "$DEPLOY_DIR/Lagrange"
    download_with_retry "https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/appsettings/appsettings-Eridanus.json" "appsettings.json"
    rm -rf "$TMP_DIR"
    ok "Lagrange 安装完成"
}

# =============================================================================
# 启动脚本生成
# =============================================================================
generate_start_script() {
    print_title "生成启动脚本"
    cd "$SCRIPT_DIR"
    download_with_retry "https://github.com/zhende1113/Antlia/raw/refs/heads/main/Antlia-docker_build_start.sh" "start.sh"
    chmod +x start.sh
    ok "启动脚本已生成"
    mkdir -p /app/bot/temp
    echo "export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1" >> ~/.bashrc
    echo "export DOTNET_BUNDLE_EXTRACT_BASE_DIR=/app/temp" >> ~/.bashrc
    echo 'echo "执行 bash /app/start.sh 来启动喵"' >> ~/.bashrc

}

# =============================================================================
# 保存部署状态
# =============================================================================
save_deploy_status() {
    {
        echo "PACKAGE_MANAGER=$PKG_MANAGER"
        echo "DISTRO=$DISTRO"
        echo "VENV_DEPLOYED=1"
        echo "LAGRANGE_DEPLOYED=1"
        echo "DEPLOY_DATE=$(date)"
    } > "$DEPLOY_STATUS_FILE"
    ok "部署状态已保存到 $DEPLOY_STATUS_FILE"
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    print_title "Antlia 通用部署脚本"
    mkdir -p "$DEPLOY_DIR"
    cd "$SCRIPT_DIR" || exit
    
    detect_system
    install_system_dependencies
    create_python_venv
    install_lagrange
    clone_eridanus
    install_python_dependencies
    generate_start_script
    save_deploy_status
    
    print_title "🎉 部署完成! 🎉"
    echo "系统信息: $DISTRO ($PKG_MANAGER)"
    echo "下一步: 请运行 './start.sh' 来启动和管理您的机器人服务。"
}

# 执行主函数
main