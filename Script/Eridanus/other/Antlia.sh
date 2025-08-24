#!/bin/bash

# Antlia 通用部署脚本 - 支持所有Linux发行版
# 版本: 2025/08/23
# 适配各种包管理器，支持编译安装

set -o pipefail

# =============================================================================
# 路径与常量定义
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/bot"
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
        if wget -O "$output" "$url" 2>/dev/null || curl -L -o "$output" "$url" 2>/dev/null; then
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
    local package="$1"
    local source_url="$2"
    local configure_opts="$3"
    
    info "开始编译安装 $package..."
    
    local temp_dir="/tmp/${package}_build"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # 下载源码
    download_with_retry "$source_url" "${package}.tar.gz"
    
    # 解压
    tar -xzf "${package}.tar.gz" || err "解压 $package 失败"
    
    # 找到解压后的目录
    local source_dir=$(find . -maxdepth 1 -type d -name "${package}*" | head -1)
    [[ -z "$source_dir" ]] && err "未找到 $package 源码目录"
    
    cd "$source_dir"
    
    # 配置、编译、安装
    if [[ -f "configure" ]]; then
        ./configure $configure_opts || err "$package configure 失败"
    elif [[ -f "Makefile" ]]; then
        info "$package 使用现有 Makefile"
    else
        err "$package 无法找到配置文件"
    fi
    
    make -j$(nproc) || err "$package 编译失败"
    sudo make install || err "$package 安装失败"
    
    # 清理
    cd /
    rm -rf "$temp_dir"
    
    ok "$package 编译安装完成"
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
# 包管理器检测与安装
# =============================================================================
detect_or_install_package_manager() {
    info "检测或安装包管理器..."
    
    # 按优先级检测包管理器
    local managers=(
        "pacman:Arch Linux"
        "emerge:Gentoo"
        "apt:Debian/Ubuntu"
        "dnf:Fedora/RHEL/CentOS"
        "yum:RHEL/CentOS (老版本)"
        "zypper:openSUSE"
        "apk:Alpine Linux"
        "xbps-install:Void Linux"
        "pkg:FreeBSD"
        "brew:macOS (Homebrew)"
    )
    
    for manager_info in "${managers[@]}"; do
        local manager="${manager_info%%:*}"
        local distro="${manager_info##*:}"
        
        if command_exists "$manager"; then
            PKG_MANAGER="$manager"
            DISTRO="$distro"
            ok "检测到包管理器: $PKG_MANAGER ($DISTRO)"
            return 0
        fi
    done
    
    warn "未检测到已知的包管理器"
    
    # 尝试安装包管理器或提供编译选项
    print_title "包管理器安装选项"
    echo "未找到支持的包管理器，请选择："
    echo "1. 尝试安装 Homebrew (适用于大多数Linux系统)"
    echo "2. 使用编译安装模式 (从源码编译所有依赖)"
    echo "3. 退出 (手动安装包管理器后重试)"
    echo
    
    read -p "请选择 (1-3): " install_choice
    
    case $install_choice in
        1)
            install_homebrew
            ;;
        2)
            COMPILE_INSTALL=true
            PKG_MANAGER="compile"
            DISTRO="Custom/源码编译"
            warn "已启用编译安装模式，这将需要更长时间"
            ;;
        3)
            info "用户选择退出"
            exit 0
            ;;
        *)
            err "无效选择"
            ;;
    esac
}

install_homebrew() {
    info "安装 Homebrew..."
    
    # 检查是否已安装
    if command_exists brew; then
        ok "Homebrew 已安装"
        PKG_MANAGER="brew"
        DISTRO="Homebrew"
        return 0
    fi
    
    # 确保有基本工具
    if ! command_exists curl && ! command_exists wget; then
        err "需要 curl 或 wget 来安装 Homebrew，请先手动安装"
    fi
    
    # 安装 Homebrew
    if command_exists curl; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || err "Homebrew 安装失败"
    else
        /bin/bash -c "$(wget -O- https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || err "Homebrew 安装失败"
    fi
    
    # 添加到 PATH
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    
    if command_exists brew; then
        PKG_MANAGER="brew"
        DISTRO="Homebrew"
        ok "Homebrew 安装成功"
    else
        err "Homebrew 安装失败"
    fi
}

# =============================================================================
# 系统检测
# =============================================================================
detect_system() {
    print_title "检测系统环境"
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|aarch64|arm64) 
            ok "系统架构: $ARCH (支持)" 
            ;;
        *) 
            warn "架构 $ARCH 可能不被完全支持，继续尝试..." 
            ;;
    esac
    
    # 检测操作系统
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        ok "检测到系统: $NAME"
    else
        warn "无法检测具体系统版本"
    fi
    
    # 检测或安装包管理器
    detect_or_install_package_manager
}

# =============================================================================
# 通用包安装函数
# =============================================================================
install_package() {
    local package="$1"
    local alt_package="$2"
    
    if [[ "$COMPILE_INSTALL" == true ]]; then
        install_package_by_compile "$package" "$alt_package"
        return
    fi
    
    case $PKG_MANAGER in
        pacman)
            sudo pacman -S --noconfirm "$package" || \
            ([ -n "$alt_package" ] && sudo pacman -S --noconfirm "$alt_package")
            ;;
        emerge)
            install_package_gentoo "$package" "$alt_package"
            ;;
        apt)
            sudo apt update -qq 2>/dev/null || true
            sudo apt install -y "$package" || \
            ([ -n "$alt_package" ] && sudo apt install -y "$alt_package")
            ;;
        dnf)
            sudo dnf install -y "$package" || \
            ([ -n "$alt_package" ] && sudo dnf install -y "$alt_package")
            ;;
        yum)
            sudo yum install -y "$package" || \
            ([ -n "$alt_package" ] && sudo yum install -y "$alt_package")
            ;;
        zypper)
            sudo zypper install -y "$package" || \
            ([ -n "$alt_package" ] && sudo zypper install -y "$alt_package")
            ;;
        apk)
            sudo apk add "$package" || \
            ([ -n "$alt_package" ] && sudo apk add "$alt_package")
            ;;
        xbps-install)
            sudo xbps-install -y "$package" || \
            ([ -n "$alt_package" ] && sudo xbps-install -y "$alt_package")
            ;;
        brew)
            brew install "$package" || \
            ([ -n "$alt_package" ] && brew install "$alt_package")
            ;;
        *)
            warn "未知包管理器 $PKG_MANAGER，尝试编译安装: $package"
            install_package_by_compile "$package" "$alt_package"
            ;;
    esac
}

install_package_gentoo() {
    local package="$1"
    local alt_package="$2"
    
    local emerge_opts="--ask=n --quiet"
    case $package in
        redis) sudo emerge $emerge_opts dev-db/redis ;;
        tmux) sudo emerge $emerge_opts app-misc/tmux ;;
        git) sudo emerge $emerge_opts dev-vcs/git ;;
        curl) sudo emerge $emerge_opts net-misc/curl ;;
        wget) sudo emerge $emerge_opts net-misc/wget ;;
        tar) sudo emerge $emerge_opts app-arch/tar ;;
        jq) sudo emerge $emerge_opts app-misc/jq ;;
        screen) sudo emerge $emerge_opts app-misc/screen ;;
        *) sudo emerge $emerge_opts "$package" || \
           ([ -n "$alt_package" ] && sudo emerge $emerge_opts "$alt_package") ;;
    esac
}

install_package_by_compile() {
    local package="$1"
    local alt_package="$2"
    
    case $package in
        redis)
            compile_install "redis" "https://download.redis.io/redis-stable.tar.gz" "--prefix=/usr/local"
            ;;
        tmux)
            # tmux 需要先安装依赖
            install_package_by_compile "libevent"
            install_package_by_compile "ncurses"
            compile_install "tmux" "https://github.com/tmux/tmux/releases/download/3.3a/tmux-3.3a.tar.gz" "--prefix=/usr/local"
            ;;
        git)
            compile_install "git" "https://github.com/git/git/archive/v2.42.0.tar.gz" "--prefix=/usr/local"
            ;;
        jq)
            compile_install "jq" "https://github.com/jqlang/jq/releases/download/jq-1.7/jq-1.7.tar.gz" "--prefix=/usr/local"
            ;;
        screen)
            # screen 需要先安装 ncurses
            install_package_by_compile "ncurses"
            compile_install "screen" "https://ftp.gnu.org/gnu/screen/screen-4.9.1.tar.gz" "--prefix=/usr/local"
            ;;
        libevent)
            compile_install "libevent" "https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz" "--prefix=/usr/local"
            ;;
        ncurses)
            compile_install "ncurses" "https://ftp.gnu.org/gnu/ncurses/ncurses-6.4.tar.gz" "--prefix=/usr/local --with-shared"
            ;;
        *)
            warn "不知道如何编译安装 $package，跳过"
            ;;
    esac
}

update_system() {
    if [[ "$COMPILE_INSTALL" == true ]]; then
        info "编译模式，跳过系统更新"
        return
    fi
    
    info "更新系统包数据库..."
    case $PKG_MANAGER in
        pacman) sudo pacman -Sy --noconfirm ;;
        emerge) sudo emerge --sync --quiet || sudo emaint sync -A ;;
        apt) sudo apt update ;;
        dnf) sudo dnf makecache ;;
        yum) sudo yum makecache ;;
        zypper) sudo zypper refresh ;;
        apk) sudo apk update ;;
        xbps-install) sudo xbps-install -S ;;
        brew) brew update ;;
        *) warn "未知包管理器，跳过系统更新" ;;
    esac
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
    )
    
    # 基础工具检查
    if ! command_exists curl && ! command_exists wget; then
        err "系统缺少 curl 和 wget，无法继续。请先安装其中一个。"
    fi
    
    update_system || warn "系统更新失败，继续安装依赖"
    
    info "安装必需的系统包..."
    for package in "${packages[@]}"; do
        if command_exists "$package"; then
            ok "$package 已安装"
        else
            info "安装 $package..."
            install_package "$package"
        fi
    done
    
    # 安装开发工具
    install_build_tools
    
    ok "系统依赖安装完成"
}

install_build_tools() {
    info "安装开发工具..."
    
    case $PKG_MANAGER in
        pacman)
            install_package "base-devel"
            ;;
        emerge)
            install_package "@system" # Gentoo 的系统集合
            sudo emerge --ask=n --quiet sys-devel/gcc sys-devel/make
            ;;
        apt)
            install_package "build-essential"
            install_package "python3-dev"
            ;;
        dnf|yum)
            if [[ "$PKG_MANAGER" == "dnf" ]]; then
                sudo dnf groupinstall -y "Development Tools" || warn "开发工具组安装失败"
            else
                sudo yum groupinstall -y "Development Tools" || warn "开发工具组安装失败"
            fi
            ;;
        zypper)
            sudo zypper install -y -t pattern devel_basis || warn "开发工具安装失败"
            ;;
        apk)
            install_package "build-base"
            install_package "python3-dev"
            ;;
        brew)
            # Homebrew 通常包含必要的开发工具
            brew install gcc || warn "gcc 安装失败"
            ;;
        compile)
            warn "编译模式下，假设已有基础开发工具"
            ;;
        *)
            warn "未知包管理器，跳过开发工具安装"
            ;;
    esac
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
    local arch_suffix=""
    case $(uname -m) in
        x86_64) arch_suffix="x86_64" ;;
        aarch64|arm64) arch_suffix="aarch64" ;;
        *) arch_suffix="x86_64"; warn "使用 x86_64 版本，可能不兼容" ;;
    esac
    
    local miniconda_url="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-${arch_suffix}.sh"
    download_with_retry "$miniconda_url" "miniconda.sh"

    info "安装 Miniconda..."
    bash miniconda.sh -b -u -p "$HOME/miniconda3" || err "Miniconda 安装失败"
    rm -f miniconda.sh

    info "初始化 Conda..."
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda init --all || err "conda init 失败"
    
    # 重新加载 shell 配置
    if [[ -f ~/.bashrc ]]; then
        source ~/.bashrc 2>/dev/null || true
    fi
    if [[ -f ~/.zshrc ]]; then
        source ~/.zshrc 2>/dev/null || true
    fi
    
    ok "Conda 安装成功"
    
    info "自动接受 Anaconda 服务条款..."
    conda config --set anaconda_tos_accepted yes || true
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>/dev/null || true
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r 2>/dev/null || true
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
    if [[ -f requirements.txt ]]; then
        pip install -r requirements.txt || err "依赖安装失败"
    else
        warn "未找到 requirements.txt，跳过依赖安装"
    fi
    
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
    
    # 确定架构标识
    local arch_tag=""
    case $(uname -m) in
        x86_64) arch_tag="linux-x64" ;;
        aarch64|arm64) arch_tag="linux-arm64" ;;
        *) arch_tag="linux-x64"; warn "使用 x64 版本，可能不兼容当前架构" ;;
    esac
    
    local github_url
    if command_exists jq; then
        github_url=$(curl -s "https://api.github.com/repos/LagrangeDev/Lagrange.Core/releases/tags/nightly" | jq -r ".assets[] | select(.name | test(\"${arch_tag}.*.tar.gz\")) | .browser_download_url")
    else
        # 如果没有 jq，使用简单的文本处理
        github_url=$(curl -s "https://api.github.com/repos/LagrangeDev/Lagrange.Core/releases/tags/nightly" | grep -o "https://[^\"]*${arch_tag}[^\"]*\.tar\.gz" | head -1)
    fi
    
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
    if command_exists wget; then
        wget -O appsettings.json https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/appsettings/appsettings-Eridanus.json
    elif command_exists curl; then
        curl -L -o appsettings.json https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/appsettings/appsettings-Eridanus.json
    else
        warn "无法下载配置文件，请手动配置"
    fi

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
    
    if command_exists wget; then
        wget -O start.sh https://github.com/zhende1113/Antlia/raw/refs/heads/main/start.sh
    elif command_exists curl; then
        curl -L -o start.sh https://github.com/zhende1113/Antlia/raw/refs/heads/main/start.sh
    else
        warn "无法下载启动脚本，需要手动创建"
        return
    fi
    
    chmod +x start.sh
    
    ok "启动脚本已生成"
}

# =============================================================================
# 保存部署状态
# =============================================================================
save_deploy_status() {
    {
        echo "PACKAGE_MANAGER=$PKG_MANAGER"
        echo "DISTRO=$DISTRO"
        echo "COMPILE_INSTALL=$COMPILE_INSTALL"
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
    echo "本脚本支持各种Linux发行版，包括自编译系统"
    echo "⚠️  这是实验性脚本，如遇问题请自行解决"
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
    echo "系统信息: $DISTRO ($PKG_MANAGER)"
    if [[ "$COMPILE_INSTALL" == true ]]; then
        echo "安装方式: 源码编译"
    fi
    echo "下一步: 请运行 './start.sh' 来启动和管理您的机器人服务。"
    echo
    warn "注意: 这是通用兼容脚本，可能存在兼容性问题"
    echo "如遇问题，请参考项目文档或切换到专用脚本"
}

# 执行主函数
main