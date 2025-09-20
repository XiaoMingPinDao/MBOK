#!/bin/bash
set -o pipefail

# ================================
# 颜色定义
# ================================
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'

# ================================
# 全局变量
# ================================
TARGET_FOLDER="/opt/QQ"
NAPCAT_CONFIG="${TARGET_FOLDER}/resources/app/app_launcher/napcat/config"
SUDO=""
force="n"
PKG_MANAGER=""
DISTRO=""
system_arch=""
GITHUB_PROXY=""

# ================================
# 日志函数
# ================================
info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
ok() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
err() { echo -e "${RED}[ERROR]${RESET} $1"; }
print_title() { echo -e "${BOLD}${CYAN}--- $1 ---${RESET}"; }

# ================================
# 工具函数
# ================================
command_exists() { command -v "$1" >/dev/null 2>&1; }

download_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts=3
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        info "下载尝试 $attempt/$max_attempts: $url"
        if command_exists wget && wget -O "$output" "$url"; then
            ok "下载成功: $output"
            return 0
        elif command_exists curl && curl -L -o "$output" "$url" 2>/dev/null; then
            ok "下载成功: $output"
            return 0
        fi
        warn "第 $attempt 次下载失败"
        ((attempt++))
        sleep 5
    done
    return 1
}

parse_github_url() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --GITHUB-URL)
                if [[ -n "$2" && "$2" != --* ]]; then
                    GITHUB_PROXY="$2"
                    info "使用的代理地址: $GITHUB_PROXY"
                    shift 2
                else
                    GITHUB_PROXY=""
                    info "未定义代理地址，无代理"
                    shift 2
                fi
                ;;
            *)
                err "未知参数: $1"
                return 1
                ;;
        esac
    done
}

check_root_or_sudo() {
    if [[ "$(id -u)" -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            SUDO="sudo"
        fi
    fi

    if command_exists pacman; then
        if [[ "$(id -u)" -eq 0 ]]; then
            err "错误：在 Arch Linux 上不能以 root 身份运行脚本"
            exit 1
        elif [[ -n "$SUDO_USER" ]]; then
            err "错误：在 Arch Linux 上不能使用 sudo 运行"
            exit 1
        fi
    else
        [[ "$(id -u)" -eq 0 ]] && echo -e "\e[33m警告：您当前以 root 身份运行脚本。\e[0m"
        [[ -n "$SUDO_USER" ]] && echo -e "\e[33m警告：您当前在使用 sudo 运行脚本。\e[0m"
    fi
}

get_system_arch() {
    system_arch=$(uname -m)
    [[ "$system_arch" == "x86_64" ]] && system_arch="amd64"
    [[ "$system_arch" == "aarch64" ]] && system_arch="arm64"
}

# ================================
# 包管理器 & 系统依赖
# ================================
detect_package_manager() {
    info "检测包管理器..."
    local managers=("apt:Debian/Ubuntu" "pacman:Arch Linux" "dnf:Fedora/RHEL/CentOS" "yum:RHEL/CentOS (老版本)" "zypper:openSUSE" "apk:Alpine Linux")
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
    err "未检测到支持的包管理器，请手动安装"
    exit 1
}

install_package() {
    local package="$1"
    info "安装 $package..."
    case $PKG_MANAGER in
        pacman) $SUDO pacman -S --noconfirm "$package" ;;
        apt) $SUDO apt update -qq 2>/dev/null || true; $SUDO apt install -y "$package" ;;
        dnf) $SUDO dnf install -y "$package" ;;
        yum) $SUDO yum install -y "$package" ;;
        zypper) $SUDO zypper install -y "$package" ;;
        apk) $SUDO apk add "$package" ;;
        *) warn "未知包管理器 $PKG_MANAGER，请手动安装 $package" ;;
    esac
}

install_system_dependencies() {
    print_title "安装系统依赖"
    local packages=("tmux" "tar" "findutils" "gzip" "unzip" "zip" "jq" "xvfb" "xauth" "procps")
    [[ ! $(command_exists curl) && ! $(command_exists wget) ]] && packages+=("curl")
    [[ "$PKG_MANAGER" == "pacman" ]] && packages+=("base-devel" "git")
    for pkg in "${packages[@]}"; do
        command_exists "$pkg" && ok "$pkg 已安装" || install_package "$pkg"
    done
    ok "系统依赖安装完成"
}

# ================================
# LinuxQQ 版本管理
# ================================
get_qq_target_version() {
    linuxqq_target_version="3.2.19-39038"
    linuxqq_target_build="${linuxqq_target_version##*-}"
}

compare_linuxqq_versions() {
    local ver1="${1}" ver2="${2}"
    IFS='.-' read -r -a ver1_parts <<<"$ver1"
    IFS='.-' read -r -a ver2_parts <<<"$ver2"
    local length=${#ver1_parts[@]}
    (( ${#ver2_parts[@]} < length )) && length=${#ver2_parts[@]}
    for ((i=0;i<length;i++)); do
        (( ${ver1_parts[i]:-0} < ${ver2_parts[i]:-0} )) && { force="y"; return; }
        (( ${ver1_parts[i]:-0} > ${ver2_parts[i]:-0} )) && { force="n"; return; }
    done
    (( ${#ver1_parts[@]} < ${#ver2_parts[@]} )) && force="y" || force="n"
}

# ================================
# LinuxQQ 安装函数
# ================================
uninstall_linuxqq() {
    local pkg="linuxqq"
    command_exists rpm && $SUDO rpm -q $pkg &>/dev/null && $SUDO dnf remove -y $pkg
    command_exists dpkg && dpkg -l | grep "^ii" | grep -q "$pkg" && $SUDO apt-get remove --purge -y -qq $pkg
}

install_rpm_package() {
    local file="$1"
    if command_exists zypper; then $SUDO zypper install -y "./$file"
    elif command_exists dnf; then $SUDO dnf install -y "./$file"
    elif command_exists yum; then $SUDO yum localinstall -y "./$file"
    else err "未检测到支持的 rpm 包管理器，请手动安装 $file"; return 1; fi
}

install_deb_package() {
    local file="$1"
    info "安装: $file"
    
    # 更新包列表
    info "更新软件包列表..."
    $SUDO apt-get update -qq
    
    # 先安装基础依赖
    info "安装基础依赖包..."
    $SUDO apt-get install -y -qq libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 xdg-utils libatspi2.0-0 libsecret-1-0 libgbm1 || true
    
    # 再尝试安装包
    info "安装 LinuxQQ 包..."
    if ! $SUDO dpkg -i "$file"; then
        info "修复依赖关系..."
        $SUDO apt-get install -f -y
    fi
    
    # 尝试安装音频依赖
    if ! $SUDO apt-get install -y -qq libasound2 2>/dev/null; then
        warn "libasound2 安装失败，可能不影响 QQ 基本功能"
    fi
    
    ok "LinuxQQ 安装完成"
}

install_linuxqq() {
    get_system_arch
    local url file_name
    
    # 根据系统架构和包管理器选择正确的包
    if command_exists rpm; then
        case "$system_arch" in
            amd64) 
                url="https://dldir1.qq.com/qqfile/qq/QQNT/c773cdf7/linuxqq_3.2.19-39038_x86_64.rpm"
                ;;
            arm64) 
                url="https://dldir1.qq.com/qqfile/qq/QQNT/c773cdf7/linuxqq_3.2.19-39038_aarch64.rpm"
                ;;
            *)
                err "不支持的架构: $system_arch"
                return 1
                ;;
        esac
    else
        case "$system_arch" in
            amd64) 
                url="https://dldir1.qq.com/qqfile/qq/QQNT/c773cdf7/linuxqq_3.2.19-39038_amd64.deb"
                ;;
            arm64) 
                url="https://dldir1.qq.com/qqfile/qq/QQNT/c773cdf7/linuxqq_3.2.19-39038_arm64.deb"
                ;;
            *)
                err "不支持的架构: $system_arch"
                return 1
                ;;
        esac
    fi
    
    file_name=$(basename "$url")
    info "下载 LinuxQQ: $file_name"
    
    if [[ ! -f "$file_name" ]]; then
        if ! download_with_retry "$url" "$file_name"; then
            err "下载 LinuxQQ 失败"
            return 1
        fi
    fi
    
    if [[ "$file_name" == *.rpm ]]; then
        install_rpm_package "$file_name"
    else
        install_deb_package "$file_name"
    fi
    
    rm -f "$file_name"
}

# ================================
# Pacman / AUR 特殊安装逻辑
# ================================
check_and_install_linuxqq_pacman() {
    local pkg="linuxqq"
    local target_version="3.2.19-39038"
    local installed_version=""

    if pacman -Q "$pkg" &>/dev/null; then
        installed_version=$(pacman -Q "$pkg" | awk '{print $2}')
        info "检测到已安装版本: $installed_version"
        compare_linuxqq_versions "$installed_version" "$target_version"
    else
        info "未检测到已安装版本"
        force="y"
    fi

    if [[ "$force" == "y" ]]; then
        info "版本不满足要求或未安装，准备卸载旧版并安装新版本..."
        pacman -Q "$pkg" &>/dev/null && $SUDO pacman -Rns --noconfirm "$pkg"

        info "开始安装 LinuxQQ (AUR)..."
        if ! git clone --depth 1 https://aur.archlinux.org/linuxqq.git linuxqq; then
            err "AUR 项目克隆失败，请检查网络或代理设置"
            return 1
        fi

        cd linuxqq || { err "无法进入 linuxqq 目录"; return 1; }
        makepkg -si --noconfirm || { err "无法编译/安装软件包"; cd ..; return 1; }
        cd ..
        rm -rf linuxqq
        ok "安装完成: $target_version"
    else
        info "已安装版本满足要求: $installed_version"
    fi
}

install_linuxqq_unified() {
    get_system_arch
    if [[ "$PKG_MANAGER" == "pacman" ]]; then
        check_and_install_linuxqq_pacman
    else
        get_qq_target_version
        local installed_version=""
        command_exists rpm && installed_version=$(rpm -q --queryformat '%{VERSION}' linuxqq 2>/dev/null || echo "")
        command_exists dpkg && installed_version=$(dpkg -l | grep "^ii" | grep linuxqq | awk '{print $3}' || echo "")
        [[ -n "$installed_version" ]] && compare_linuxqq_versions "$installed_version" "$linuxqq_target_version" || force="y"
        if [[ "$force" == "y" ]]; then
            info "版本不匹配或未安装，准备安装 LinuxQQ..."
            backup_path=$(backup_napcat_config)
            uninstall_linuxqq
            install_linuxqq
            restore_napcat_config "$backup_path"
        else
            info "已安装版本满足要求: $installed_version"
        fi
    fi
}

# ================================
# NapCat 配置备份/恢复
# ================================
backup_napcat_config() {
    local backup_path="/tmp/napcat_config_backup_$(date +%s)"
    [[ -d "$NAPCAT_CONFIG" ]] && { 
        mkdir -p "$backup_path"
        cp -a "${NAPCAT_CONFIG}/." "$backup_path/"
        echo "$backup_path"
    }
}

restore_napcat_config() {
    local backup_path="$1"
    [[ -d "$backup_path" ]] && { 
        $SUDO mkdir -p "$NAPCAT_CONFIG"
        $SUDO cp -a "${backup_path}/." "$NAPCAT_CONFIG/"
        $SUDO chmod -R +x "$NAPCAT_CONFIG"
        rm -rf "$backup_path"
    }
}

install_napcat(){
    info "安装 NapCat..."
    napcat_dir="/opt/QQ/resources/app/napcat"
    $SUDO mkdir -p "$napcat_dir"

    # 下载带重试
    download_with_retry "${GITHUB_PROXY}https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip" "NapCat.Shell.zip"

    $SUDO unzip -o NapCat.Shell.zip -d "$napcat_dir"
    rm -f NapCat.Shell.zip

    echo "创建加载脚本..."
    $SUDO tee /opt/QQ/resources/app/loadNapCat.cjs > /dev/null <<'EOF'
const fs = require("fs");
const path = require("path");
const CurrentPath = path.dirname(__filename);
const hasNapcatParam = process.argv.includes("--no-sandbox");
if (hasNapcatParam) {
    (async () => {
        await import("file://" + path.join(CurrentPath, "./napcat/napcat.mjs"));
    })();
} else {
    require("./application/app_launcher/index.js");
    setTimeout(() => {
        global.launcher.installPathPkgJson.main = "./application.asar/app_launcher/index.js";
    }, 0);
}
EOF

    # 修改权限和配置
    $SUDO chmod -R +x "$napcat_dir"
    $SUDO jq '.main="./loadNapCat.cjs"' /opt/QQ/resources/app/package.json | $SUDO tee /opt/QQ/resources/app/package.json > /dev/null

    ok "NapCat 安装完成"
}

# ================================
# 主程序入口
# ================================
main() {
    print_title "LinuxQQ + NapCat 自动安装脚本"
    check_root_or_sudo
    detect_package_manager
    install_system_dependencies
    parse_github_url "$@"
    print_title "安装 LinuxQQ"
    install_linuxqq_unified
    print_title "安装 NapCat"
    install_napcat
    ok "所有组件安装完成！"
}

main "$@"

