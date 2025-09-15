#!/bin/bash

# AstrBot Shell部署脚本
# 版本: 2025/09/14

#set -o pipefail

# =============================================================================
# 路径与常量定义
# =============================================================================

SCRIPT_DIR="$(pwd)"
DEPLOY_DIR="$SCRIPT_DIR"                                 #部署目录
DEPLOY_STATUS_FILE="$SCRIPT_DIR/deploy.status"              #部署状态文件路径
GITHUB_PROXY=""                                             # GitHub 代理URL
PKG_MANAGER=""                                              # 包管理器
DISTRO=""                                                   # 发行版
ENV_TYPE=""                                                 # Python 环境类型
echo "您当前的目录是: $SCRIPT_DIR" 2>/dev/null
echo "DEPLOY_DIR is: $DEPLOY_DIR" 2>/dev/null # 鬼知道这是为什么 

#------------------------------------------------------------------------------


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

astrbot_art() {
    echo -e "${CYAN}"
    echo "               _        ____        _   "
    echo "     /\       | |      |  _ \      | |  "
    echo "    /  \   ___| |_ _ __| |_) | ___ | |_ "
    echo "   / /\ \ / __| __| '__|  _ < / _ \| __|"
    echo "  / ____ \\__ \ |_| |  | |_) | (_) | |_ "
    echo " /_/    \_\___/\__|_|  |____/ \___/ \__|"
    echo -e "${RESET}"
}

#------------------------------------------------------------------------------


# =============================================================================
# 工具函数
# =============================================================================
command_exists() {                                        #定义函数
    command -v "$1" >/dev/null 2>&1                       #检查命令是否存在
}                                                         #结束函数定义

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

#------------------------------------------------------------------------------

check_root_or_sudo() {
    # 检查当前是否为 root 用户或使用 sudo 运行
    if [[ "$(id -u)" -eq 0 ]]; then
        # 如果是 root 用户
        echo -e "\e[31m警告：您当前以 root 用户身份运行此脚本！\e[0m"
    elif [[ $EUID -ne 0 && $(sudo -v > /dev/null 2>&1; echo $?) -eq 0 ]]; then
        # 如果是使用 sudo 运行
        echo -e "\e[31m警告：您当前以 sudo 权限运行此脚本！\e[0m"
    else
        # 用户既不是 root 也没有使用 sudo
        return 0
    fi

    # 提示用户确认是否继续
    read -p "您是否确认以管理员权限运行此脚本？请输入 'yes' 继续： " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "操作已取消。"
        exit 1
    fi
}


# =============================================================================
# GitHub 代理选择
# =============================================================================

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
} #结束函数定义                                                            #结束函数定义

#------------------------------------------------------------------------------

# =============================================================================
# 一次性检查sudo可用性
# =============================================================================
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
        #"apk:Alpine Linux"
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

#------------------------------------------------------------------------------


# =============================================================================
# 系统检测
# =============================================================================
detect_system() {                               #定义函数
    print_title "检测系统环境"                     #打印标题
    
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

#------------------------------------------------------------------------------


# =============================================================================
# 通用包安装函数
# =============================================================================
install_package() { #定义函数
    local package="$1"                           #获取参数
    
    info "安装 $package..."                  #打印信息日志
    case $PKG_MANAGER in                   #根据包管理器选择安装命令
        pacman)
            $SUDO pacman -S --noconfirm "$package" #安装包
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
    
    local packages=("git" "python3" "tmux")  #定义必需包数组
    
    # 检查下载工具
    if ! command_exists curl && ! command_exists wget; then  #如果 curl 和 wget 都不存在
        packages+=("curl")   #添加 curl 到数组
    fi                                  #结束条件判断
    
    # 检查 pip
    if ! command_exists pip3 && ! command_exists pip; then   #如果 pip3 和 pip 都不存在
        case $PKG_MANAGER in                                 #根据包管理器选择 pip 包名称
            apt) packages+=("python3-pip") ;;                # apt
            pacman) packages+=("python-pip") ;;              # pacman
            dnf|yum) packages+=("python3-pip") ;;            # dnf 和 yum
            zypper) packages+=("python3-pip") ;;             # zypper
            apk) packages+=("py3-pip") ;;                    # apk
            brew) packages+=("pip3") ;;                      # brew
            *) packages+=("python3-pip") ;;                  #默认
        esac                                                 #结束条件判断
    fi                                                       #结束条件判断
    
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


# =============================================================================
# uv 环境安装
# =============================================================================
install_uv_environment() {
    print_title "安装和配置 uv 环境"
    
    if command_exists uv; then
        ok "uv 已安装"
    else
        info "安装 uv..."
        pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/ 2>/dev/null || true
        # 方法1: pip 安装
        if command_exists pip3; then
            if python3 -m pip install --upgrade pip && pip3 install --user --break-system-packages uv; then
                export PATH="$HOME/.local/bin:$PATH"
                ok "uv 安装成功"
            else
                err "pip3 安装失败，尝试使用官方脚本安装..."
            fi
        elif command_exists pip; then
            if python -m pip install --upgrade pip && pip install --user --break-system-packages uv; then
                export PATH="$HOME/.local/bin:$PATH"
                ok "uv 安装成功"
            else
                err "pip 安装失败，尝试使用官方脚本安装..."
            fi
        else
            err "没有找到 pip3 或 pip，无法安装 uv，使用官方安装脚本..."
        fi
        
        # 方法2: 官方脚本安装 (备选)
        if ! command_exists uv; then
            info "pip 安装失败，使用官方安装脚本..."
            if command_exists curl; then
                curl -LsSf https://astral.sh/uv/install.sh | sh
                export PATH="$HOME/.cargo/bin:$PATH"
                if command_exists uv; then
                    ok "uv 安装成功"
                else
                    err "官方安装脚本也失败，请手动安装 uv"
                fi
            else
                err "无法安装 uv，请手动安装 pip 或 curl"
            fi
        fi
        
    fi
    
    # 配置镜像
    info "配置 uv 使用清华大学镜像..."
    uv pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/ 2>/dev/null || true
    
    ok "uv 环境配置完成"
}



#------------------------------------------------------------------------------




# =============================================================================
# 项目克隆
# =============================================================================
clone_astrbot() { #定义函数
    print_title "克隆 AstrBot 项目" #打印标题
    
    echo "SCRIPT_DIR is: $SCRIPT_DIR" 2>/dev/null 
    echo "DEPLOY_DIR is: $DEPLOY_DIR" 2>/dev/null 
    cd "$DEPLOY_DIR" #进入部署目录
     # 如果目录已存在，提示用户选择是否删除
    
    if [[ -d "AstrBot" ]]; then #如果目录存在
        warn "检测到 AstrBot 文件夹已存在" #打印警告
        read -p "是否删除并重新克隆? (y/n, 默认n): " del_choice #读取用户输入
        if [[ "$del_choice" =~ ^[Yy]$ ]]; then #如果用户选择删除
            rm -rf "AstrBot" #删除目录
            ok "已删除旧的 AstrBot 文件夹" #打印信息
        else #否则
           warn "跳过 AstrBot 仓库克隆" #打印警告
            #跳过克隆
            return
        fi #结束条件判断
    fi #结束条件判断

     # 克隆项目
    
    local repo_url="${GITHUB_PROXY}https://github.com/AstrBotDevs/AstrBot.git" #设置仓库URL
    #克隆项目
    info "开始克隆 AstrBot 仓库..." #打印信息日志
    
    if ! git clone --depth 1 "$repo_url" AstrBot; then #尝试克隆仓库
        err "项目克隆失败，请检查网络或代理设置" #打印错误日志并退出
    fi #结束条件判断
    
    ok "AstrBot 项目克隆完成" #打印成功日志
} #结束函数定义

#------------------------------------------------------------------------------


# =============================================================================
# Python 依赖安装
# =============================================================================
install_python_dependencies() {  # 定义函数
    print_title "安装 Python 依赖" # 打印标题
    
    # 进入项目目录
    cd "$DEPLOY_DIR/AstrBot" || err "无法进入 AstrBot 目录" # 进入目录

    # 使用 uv 同步依赖
    if [[ -f "pyproject.toml" ]]; then
        # 设置环境变量使 uv 使用 pip 镜像配置
        export UV_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple/"

        # 使用 uv sync 安装依赖
        attempt=1
        while [[ $attempt -le 3 ]]; do
            if uv sync --index-url https://pypi.tuna.tsinghua.edu.cn/simple/; then
                ok "uv sync 成功"
                break
            else
                warn "uv sync 失败，重试 $attempt/3"
                ((attempt++))
                sleep 5
            fi
        done

        # 如果 uv sync 仍然失败，改用 pip
        if [[ $attempt -gt 3 ]]; then
            warn "uv sync 失败，尝试使用 pip 安装"
            uv pip install -r requirements.txt || err "pip 安装失败"
        fi
    elif [[ -f "requirements.txt" ]]; then
        # 设置环境变量使 uv 使用 pip 镜像配置
        export UV_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple/"

        # 使用 uv pip 安装依赖
        attempt=1
        while [[ $attempt -le 3 ]]; do
            if uv pip install -r requirements.txt; then
                ok "uv pip 安装成功"
                break
            else
                warn "uv pip 安装失败，重试 $attempt/3"
                ((attempt++))
                sleep 5
            fi
        done

        # 如果 uv pip 仍然失败，改用 pip
        if [[ $attempt -gt 3 ]]; then
            warn "uv pip 安装失败，尝试使用 pip 安装"
            pip install -r requirements.txt || err "pip 安装失败"
        fi
    else
        warn "未找到 pyproject.toml 或 requirements.txt 文件"
    fi

    ok "Python 依赖安装完成" # 打印成功日志
}  # 结束函数定义



#------------------------------------------------------------------------------


generate_start_script(){ #定义函数
local start_script_url="${GITHUB_PROXY}https://github.com/zhende1113/Antlia/raw/refs/heads/main/Script/AstrBot/start.sh" #下载链接
         #下载启动脚本
        cd "$DEPLOY_DIR" || err "无法进入部署目录" #进入部署目录
        download_with_retry "$start_script_url" "astrbot.sh"

        info "下载astrbot.sh ing..." #打印信息日志
        chmod +x astrbot.sh #赋予执行权限

}                    #结束函数定义

#------------------------------------------------------------------------------


# =============================================================================
# 保存部署状态
# =============================================================================
#save_deploy_status() {  #定义函数
#    print_title "保存部署状态" #打印标题
#    mkdir -p "$(dirname "$DEPLOY_STATUS_FILE")" #创建目录
#    {
#        echo "ENV_TYPE=$ENV_TYPE"
#        #echo "PKG_MANAGER=$PKG_MANAGER"
#        #echo "GITHUB_PROXY=$GITHUB_PROXY"
#    } > "$DEPLOY_STATUS_FILE" #保存状态到文件
#    #打印信息日志
#    ok "部署状态已保存到 $DEPLOY_STATUS_FILE"
#}                        #结束函数定义

#------------------------------------------------------------------------------


# =============================================================================
# 主函数
# =============================================================================
main() { #定义主函数
    # 调用检查函数
    check_root_or_sudo
    astrbot_art
    print_title "AstrBot Shell部署脚本" #打印标题
    #echo "欢迎使用 AstrBot 简化部署脚本" #打印欢迎信息
    echo "脚本版本: 2025/09/14" #打印版本信息
    
    # 执行部署步骤
    select_github_proxy #选择 GitHub 代理
    detect_system #检测系统
    install_system_dependencies #安装系统依赖
    # 安装uv
    install_uv_environment
    
    clone_astrbot #克隆项目
    install_python_dependencies #安装 Python 依赖
    generate_start_script #生成启动脚本
     #保存部署状态 
    #save_deploy_status
    
    print_title "🎉 部署完成! 🎉"
    echo "系统信息: $DISTRO ($PKG_MANAGER)"
    echo
    echo "下一步: 运行 './astrbot.sh' 来启动和管理 AstrBot"

}

# 检查是否以 root 用户运行
#if [[ $EUID -eq 0 ]]; then 
#    err "请不要使用 root 用户运行此脚本"
#fi

# 执行主函数
main
