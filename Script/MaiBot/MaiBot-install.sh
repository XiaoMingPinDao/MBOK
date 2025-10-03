#!/bin/bash

# 获取脚本绝对路径
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # 获取脚本所在目录
DEPLOY_DIR="$SCRIPT_DIR" # 部署目录
LOG_FILE="$SCRIPT_DIR/script.log" #  日志文件路径
DEPLOY_STATUS_FILE="$SCRIPT_DIR/MaiBot/deploy.status" # 部署状态文件
LOCAL_BIN="$HOME/.local/bin" 
MAIBOT_BIN="$LOCAL_BIN/maibot"

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1 # 检查命令是否存在
}

# =============================================================================
# 日志函数
# =============================================================================
# 定义颜色
RESET='\033[0m'     # 重置颜色
BOLD='\033[1m'      # 加粗
RED='\033[31m'      # 红色
GREEN='\033[32m'    # 绿色
YELLOW='\033[33m'   # 黄色
BLUE='\033[34m'     # 蓝色
CYAN='\033[36m'     # 青色

# 信息日志
info() { echo -e "${BLUE}[INFO]${RESET} $1"; }

# 成功日志
ok() { echo -e "${GREEN}[OK]${RESET} $1"; }

# 警告日志
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }

# 错误日志
err() { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }

# 打印标题
print_title() { echo -e "${BOLD}${CYAN}=== $1 ===${RESET}"; }

download_with_retry() {                                   #定义函数
    local url="$1"                                        #获取参数
    local output="$2"                                     #获取参数
    local max_attempts=3                                  #最大尝试次数
    local attempt=1                                       #当前尝试次数

    while [[ $attempt -le $max_attempts ]]; do            #循环直到达到最大尝试次数
        info "下载尝试 $attempt/$max_attempts: $url"       #打印信息日志
        if command_exists wget; then                      #如果 wget 存在
            if wget -O "$output" "$url" 2>/dev/null; then #使用 wget 下载
                ok "下载成功: $output"                     #打印日志
                return 0                                  #成功返回
            fi                                            #结束条件判断
        elif command_exists curl; then                    #如果 curl 存在
            if curl -L -o "$output" "$url" 2>/dev/null; then #使用 curl 下载
                ok "下载成功: $output"                         #打印日志
                return 0                                      #成功返回
            fi                                                #结束条件判断
        fi                                                    #结束条件判断
        warn "第 $attempt 次下载失败"                           #打印警告日志
        if [[ $attempt -lt $max_attempts ]]; then             #如果还没到最大尝试次数
            info "5秒后重试..."                                #打印信息日志
            sleep 5                                           #等待 5 秒
        fi                                                    #结束条件判断
        ((attempt++))                                         #增加尝试次数
    done                                                      #结束循环
    err "所有下载尝试都失败了"                                   #打印错误日志并退出
}                                                             #结束函数定义

select_github_proxy() {                                               #定义函数
    print_title "选择 GitHub 代理"                                     #打印标题
    echo "请根据您的网络环境选择一个合适的下载代理："                        #打印提示
    echo                                                             #打印空行

    # 使用 select 提供选项
    select proxy_choice in "ghfast.top 镜像 (推荐)" "ghproxy.net 镜像" "不使用代理" "自定义代理"; do
        case $proxy_choice in
            "ghfast.top 镜像 (推荐)") 
                GITHUB_PROXY="https://ghfast.top/"; 
                ok "已选择: ghfast.top 镜像" 
                break
                ;;
            "ghproxy.net 镜像") 
                GITHUB_PROXY="https://ghproxy.net/"; 
                ok "已选择: ghproxy.net 镜像" 
                break
                ;;
            "不使用代理") 
                GITHUB_PROXY=""; 
                ok "已选择: 不使用代理" 
                break
                ;;
            "自定义代理") 
                # 允许用户输入自定义代理
                read -p "请输入自定义 GitHub 代理 URL (必须以斜杠 / 结尾): " custom_proxy
                # 检查自定义代理是否以斜杠结尾
                if [[ -n "$custom_proxy" && "$custom_proxy" != */ ]]; then
                    custom_proxy="${custom_proxy}/" # 如果没有斜杠，自动添加
                    warn "自定义代理 URL 没有以斜杠结尾，已自动添加斜杠"
                fi
                GITHUB_PROXY="$custom_proxy"
                ok "已选择: 自定义代理 - $GITHUB_PROXY"
                break
                ;;
            *) 
                warn "无效输入，使用默认代理"
                GITHUB_PROXY="https://ghfast.top/"
                ok "已选择: ghfast.top 镜像 (默认)"
                break
                ;;
        esac
    done
} #结束函数定义    


check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        # 已经是root，不需要sudo
        SUDO=""
        ok "当前是 root 用户"
    elif command_exists sudo; then
        # 有sudo命令
        SUDO="sudo"
        ok "检测到 sudo 命令"
    else
        # 没有sudo
        SUDO=""
        warn "系统没有 sudo "
    fi
}


# =============================================================================
# 系统检测
# =============================================================================
detect_system() {                               #定义函数
    print_title "检测系统环境"                     #打印标题
    ID="${ID:-}"
    # 检测架构
    ARCH=$(uname -m)                          #获取系统架构
    case $ARCH in # 根据架构打印信息
        x86_64|aarch64|arm64) 
            ok "系统架构: $ARCH (支持)"  #打印信息
            ;;
        *) 
            warn "架构 $ARCH 可能不被完全支持，继续尝试..."  #打印警告
            ;;
    esac
    
    # 检测操作系统
    if [[ -f /etc/os-release ]]; then  #如果文件存在
        source /etc/os-release #加载文件
        ok "检测到系统: $NAME" #打印信息
    else  # 否则
        warn "无法检测具体系统版本" #打印警告 
    fi   #结束条件判断
    
    # 检测包管理器
    check_sudo
    detect_package_manager
}                           #结束函数定义


# =============================================================================
# 包管理器检测
# =============================================================================
detect_package_manager() {                          #定义函数
    info "检测包管理器..."                     #打印信息日志
    
    local managers=(                   #定义包管理器数组
        "apt:Debian/Ubuntu"    
        "pacman:Arch Linux"
        "dnf:Fedora/RHEL/CentOS"
        "yum:RHEL/CentOS (老版本)"
        "zypper:openSUSE"
        "apk:Alpine Linux"
        "brew:macOS/Linux (Homebrew)"
    ) #结束数组定义
    
    for manager_info in "${managers[@]}"; do  #循环遍历数组
        local manager="${manager_info%%:*}"  #提取包管理器名称
        local distro="${manager_info##*:}"   #提取发行版名称
        
        if command_exists "$manager"; then   #如果包管理器存在
            PKG_MANAGER="$manager"           #设置全局变量
            DISTRO="$distro"                 #设置全局变量
            ok "检测到包管理器: $PKG_MANAGER ($DISTRO)" #打印信息日志
            return 0                          #成功返回
        fi                                    #结束条件判断
    done                                   #结束循环
    
    err "未检测到支持的包管理器，请手动安装 git、curl/wget 和 python3" #打印错误日志并退出
}                                          #结束函数定义

install_package() { #定义函数
    local package="$1"                           #获取参数
    
    info "安装 $package..."                  #打印信息日志
    case $PKG_MANAGER in                   #根据包管理器选择安装命令
        pacman)
            $SUDO pacman -Sy --noconfirm "$package" #安装包
            ;;
        apt)
            $SUDO apt update -qq 2>/dev/null || true #更新包列表
            $SUDO apt install -y "$package"          #安装包
            ;;
        dnf)
            $SUDO dnf install -y "$package"   #安装包
            ;;
        yum)
            $SUDO yum install -y "$package"  #安装包
            ;;
        zypper)
            $SUDO zypper install -y "$package" #安装包
            ;;
        apk)
            $SUDO apk add gcc musl-dev linux-headers "$package" #安装包
            ;;
        brew)
            $SUDO install "$package" #安装包
            ;;
        *)
            warn "未知包管理器 $PKG_MANAGER，请手动安装 $package" #打印警告
            ;;
    esac #结束条件判断
} #结束函数定义

#------------------------------------------------------------------------------


# =============================================================================
# 系统依赖安装
# =============================================================================
install_system_dependencies() {   #定义函数
    print_title "安装系统依赖"  #打印标题
    
    local packages=("git" "python3" "tmux" "tar" "findutils" "zip")  #定义必需包数组
    
    # 检查下载工具
    if ! command_exists curl && ! command_exists wget; then  #如果 curl 和 wget 都不存在
        packages+=("curl")   #添加 curl 到数组
    fi                                  #结束条件判断
    
    # Arch 系统特殊处理：添加 uv 到必需包数组
    if [[ "$ID" == "arch" ]]; then
        # 只有 Arch 才用包管理器安装 uv
        packages+=("uv")
        info "已将 uv 添加到 Arch 的必需安装包列表"
    fi

    info "安装必需的系统包..."                                 #打印信息日志
    for package in "${packages[@]}"; do                     #循环遍历包数组
        if command_exists "${package/python3-pip/pip3}"; then #如果包已安装
            ok "$package 已安装"                               #打印信息日志
        else                                                  #否则
            install_package "$package"                        #安装包
        fi                                                    #结束条件判断
    done                                                      #结束循环
    
    ok "系统依赖安装完成"  #打印成功日志
}                          #结束函数定义

install_uv_environment() {
    print_title "安装和配置 uv 环境"
    
    if command_exists uv; then
        ok "uv 已安装"
    else
        info "安装 uv..."
        bash <(curl -sSL "${GITHUB_PROXY}https://github.com/Astriora/Antlia/raw/refs/heads/main/Script/UV/uv_install.sh") --GITHUB-URL "$GITHUB_PROXY"
    fi
    set +u
    [[ -f ~/.bashrc ]] && source ~/.bashrc
    set -u
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
}

clone_maibot() {
            local CLONE_URL="${GITHUB_PROXY}https://github.com/MaiM-with-u/MaiBot.git" # 选择官方源
            local CLONE_URL1="${GITHUB_PROXY}https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git"

    if [ -d "$DEPLOY_DIR/MaiBot" ]; then # 如果目录已存在
        warn "检测到MaiBot 文件夹已存在。是否删除重新克隆？(y/n)" # 提示用户是否删除
        read -p "请输入选择 (y/n, 默认n): " del_choice # 询问用户是否删除
        del_choice=${del_choice:-n} # 默认选择不删除
        if [ "$del_choice" = "y" ] || [ "$del_choice" = "Y" ]; then # 如果用户选择删除
            rm -rf "$DEPLOY_DIR/MaiBot" # 删除MaiBot目录
            ok "已删除MaiBot 文件夹。" # 提示用户已删除
        else # 如果用户选择不删除
            warn "跳过MaiBot仓库克隆。" # 提示用户跳过克隆
            return # 结束函数
        fi # 结束删除选择
    fi # 如果目录不存在则继续克隆
    info "克隆 MaiBot 仓库" # 提示用户开始克隆
    git clone --depth 1 "$CLONE_URL" # 克隆仓库
    
    if [ -d "$DEPLOY_DIR/MaiBot-Napcat-Adapter" ]; then # 如果目录已存在
        warn "检测到MaiBot-Napcat-Adapter文件夹已存在。是否删除重新克隆？(y/n)" # 提示用户是否删除
        read -p "请输入选择 (y/n, 默认n): " del_choice # 询问用户是否删除
        del_choice=${del_choice:-n} # 默认选择不删除
        if [ "$del_choice" = "y" ] || [ "$del_choice" = "Y" ]; then # 如果用户选择删除
            rm -rf "$DEPLOY_DIR/MaiBot-Napcat-Adapter" # 删除目录
            ok "已删除MaiBot-Napcat-Adapter文件夹。" # 提示用户已删除
        else # 如果用户选择不删除
            warn "跳过MaiBot-Napcat-Adapter仓库克隆。" # 提示用户跳过克隆
            return # 结束函数
        fi # 结束删除选择
    fi # 如果目录不存在则继续克隆
     git clone --depth 1 "$CLONE_URL1" # 克隆仓库
}  # 克隆 仓库结束

# 安装 Python 依赖
install_python_dependencies() {
    print_title "安装 Python 依赖"

    VENV_DIR="$DEPLOY_DIR/MaiBot-Napcat-Adapter/.MaiBot-Napcat-Adapter"

    # 创建虚拟环境
    if [[ ! -d "$VENV_DIR" ]]; then
        uv venv "$VENV_DIR"
        ok "uv 虚拟环境创建完成: $VENV_DIR"
    else
        warn "检测到已有虚拟环境，跳过创建"
    fi

    # 激活虚拟环境
    
    cd "$DEPLOY_DIR/MaiBot" || exit 1
    # 安装 uv 依赖
    export UV_INDEX_URL="https://mirrors.ustc.edu.cn/pypi/simple/"
    mkdir -p ~/.cache/uv
    chown -R "$(whoami):$(whoami)" ~/.cache/uv

    attempt=1
    while [[ $attempt -le 3 ]]; do
        if uv sync --index-url "$UV_INDEX_URL"; then
            ok "uv sync 成功"
            break
        else
            warn "uv sync 失败，重试 $attempt/3"
            ((attempt++))
            sleep 5
        fi
    done
    [[ $attempt -gt 3 ]] && err "uv sync 多次失败"
    source "$VENV_DIR/bin/activate"
    # 安装 Napcat Adapter 依赖
    cd "$DEPLOY_DIR/MaiBot-Napcat-Adapter"
    pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
    ok "Python 依赖已安装"

    # 复制配置文件
    mkdir -p config
    cp template/bot_config_template.toml config/bot_config.toml
    cp template/template.env .env
    cp template/template_config.toml config.toml

    deactivate
}


update_shell_config() {
    local path_export='export PATH="$HOME/.local/bin:$PATH"'
    local fish_path_set='set -gx PATH "$HOME/.local/bin" $PATH'

    [[ -f "$HOME/.bashrc" ]] && grep -qF "$path_export" "$HOME/.bashrc" || echo "$path_export" >> "$HOME/.bashrc"
    [[ -f "$HOME/.zshrc" ]] && grep -qF "$path_export" "$HOME/.zshrc" || echo "$path_export" >> "$HOME/.zshrc"
    
    local fish_config="$HOME/.config/fish/config.fish"
    mkdir -p "$(dirname "$fish_config")"
    [[ -f "$fish_config" ]] && grep -qF "$fish_path_set" "$fish_config" || echo "$fish_path_set" >> "$fish_config"
}


download-script() {
    local DOWNLOAD_URL="${GITHUB_PROXY}https://github.com/Astriora/Antlia/raw/refs/heads/main/Script/MaiBot/maibot"
    local TARGET_DIR="$LOCAL_BIN/maibot"        # 目录
    local TARGET_FILE="$TARGET_DIR/maibot"      # 文件路径

    mkdir -p "$TARGET_DIR"

    # 下载 maibot 文件到 TARGET_FILE
    download_with_retry "$DOWNLOAD_URL" "$TARGET_FILE"
    chmod +x "$TARGET_FILE"
    ok "maibot 脚本已下载到 $TARGET_FILE"

    # 调用 maibot 初始化
    if [[ -f "$TARGET_FILE" ]]; then
        "$TARGET_FILE" --init="$SCRIPT_DIR"
        ok "maibot 已初始化到 $SCRIPT_DIR"
    else
        err "maibot 脚本下载失败，初始化中止"
    fi

    # 生成第二个辅助文件（示例：记录下载时间）
    echo "Downloaded at $(date)" > "$TARGET_DIR/download.log"
    ok "辅助文件 download.log 已生成"
}






main() {
    print_title "MaiBot 自动部署脚本"
    detect_system

    # 选择 GitHub 代理
    select_github_proxy

    # 安装系统依赖
    install_system_dependencies

    # 安装 uv
    install_uv_environment

    # 克隆仓库
    clone_maibot

    # 安装 Python 依赖
    install_python_dependencies

    # 更新 shell 配置
    update_shell_config

    # 下载 maibot 脚本
    TARGET_PATH="$LOCAL_BIN/maibot"
    download-script

    ok "MaiBot 部署完成！ 执行: 
    source  ~/.bashrc
    maibot
    来启动"
}

# 执行主函数
main
