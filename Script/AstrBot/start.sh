#!/bin/bash

set -o pipefail #启用管道失败检测

# =============================================================================
# 路径与常量定义
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  #获取脚本所在目录
DEPLOY_DIR="$SCRIPT_DIR"                                    #部署目录这里偷了一个懒 不想改太多东西
CONDA_DIR="$HOME/miniconda3"                                #Conda 安装目录如果你部署的时候选的其他环境不管
DEPLOY_STATUS_FILE="$DEPLOY_DIR/deploy.status"              #部署状态文件路径
TMUX_SESSION_ASTRBOT="Astrbot"                              #tmux 会话名称
CURRENT_USER=$(whoami)                                      #当前用户

# =============================================================================
# 日志函数
# =============================================================================

info() { echo "[INFO] $1"; }                                      #信息日志
ok() { echo "[OK] $1"; }                                          #成功日志
warn() { echo "[WARN] $1"; }                                      #警告日志
err() { echo "[ERROR] $1" >&2; }                                  #错误日志
print_title() { echo -e "\n=== $1 ==="; }                         #打印标题
hr() { echo "================================================"; } #分割线

#------------------------------------------------------------------------------



# =============================================================================
# 工具函数
# =============================================================================
#用于检查关键命令是否存在
check_command() {
    for cmd in "$@"; do                            #遍历所有传入的命令    
        if ! command -v "$cmd" &>/dev/null; then   #如果命令不存在
            err "关键命令 '$cmd' 未找到"             #打印错误信息
        fi                                         #结束条件判断
    done                                           #结束循环
}                                                  #结束函数定义

#------------------------------------------------------------------------------
#激活 Conda 环境
activate_environment() {                             #定义函数
    if [[ ! -d "$CONDA_DIR" ]]; then                 #检查 Conda 目录是否存在
        err "Conda 目录 '$CONDA_DIR' 未找到"           #如果不存在打印错误信息
    fi                                               #结束条件判断
                                                     
    source "$CONDA_DIR/etc/profile.d/conda.sh"       #加载 conda 脚本
    if ! conda activate Eridanus 2>/dev/null; then   #尝试激活环境
        err "无法激活 Conda 环境 'Eridanus'"           #如果失败打印错误信息
    fi                                               #结束条件判断
}

#------------------------------------------------------------------------------
#激活 venv 环境
activate_environment_venv() {                         #定义函数
    if [[ ! -d "$DEPLOY_DIR/.astrbot" ]]; then        #检查 venv 目录是否存在
        err "虚拟环境目录 '$DEPLOY_DIR/.astrbot' 未找到" #如果不存在打印错误信息
    fi                                                #结束条件判断
    
    source "$DEPLOY_DIR/.astrbot/bin/activate"        #激活 venv 环境
}                                                     #结束函数定义

#------------------------------------------------------------------------------





# =============================================================================
# 停止AstrBot
# =============================================================================
stop_service() {                                                     #定义函数
    local service_name="$1"                                          #获取服务名称参数
    info "正在停止 '$TMUX_SESSION_ASTRBOT' 相关进程和会话..."            #打印信息日志
            tmux kill-session -t "$TMUX_SESSION_ASTRBOT" 2>/dev/null #杀掉 tmux 会话
    ok "'$TMUX_SESSION_ASTRBOT' 清理完成"                             #打印成功日志
}                                                                    #结束函数定义

#------------------------------------------------------------------------------



# =============================================================================
# 后台启动AstrBot
# =============================================================================
start_service_background() {       #定义函数                                                                                                  

if [[ "$ENV_TYPE" == "conda" ]]; then     #如果是conda  激活 Conda 环境并运行 AstrBot 主程序                                                                                              
    tmux new-session -d -s "$TMUX_SESSION_ASTRBOT" \
            "source '$CONDA_DIR/etc/profile.d/conda.sh' && conda activate astrbot && cd '$DEPLOY_DIR/AstrBot' && python main.py"     
elif [[ "$ENV_TYPE" == "venv" ]]; then    #如果是 venv  激活 venv 环境并运行 AstrBot 主程序                                                                                             
    tmux new-session -d -s "$TMUX_SESSION_ASTRBOT" \
            "source "$DEPLOY_DIR/.astrbot/bin/activate" && cd '$DEPLOY_DIR/AstrBot' && python main.py"
elif [[ "$ENV_TYPE" == "uv" ]]; then      #如果是 uv  使用 uv 运行 AstrBot 主程序
   tmux new-session -d -s "$TMUX_SESSION_ASTRBOT" \
            "source '$CONDA_DIR/etc/profile.d/conda.sh' && conda activate Eridanus && cd '$DEPLOY_DIR/AstrBot' && python main.py"
else
    err "你部署的时候有问题 请查看部署状态文件" #打印报错
    exit 1                                #退出脚本
fi                                        #结束条件判断
    sleep 1                               #等待 1 秒确保服务启动
    ok "$service_name 已在后台启动"         #打印成功日志
}
#------------------------------------------------------------------------------


# =============================================================================
# 前台启动AstrBot
# =============================================================================
start_astrbot_interactive() {             #定义函数
    cd "$DEPLOY_DIR/AstrBot"              #进入 AstrBot 目录
if [[ "$ENV_TYPE" == "conda" ]]; then     #根据环境类型选择启动方式
    activate_environment_conda            #激活 Conda 环境 
    python "$DEPLOY_DIR/AstrBot/main.py"  #运行 AstrBot 主程序
elif [[ "$ENV_TYPE" == "venv" ]]; then    #如果是 venv 环境
    activate_environment_venv             #激活 venv 环境
    python "$DEPLOY_DIR/AstrBot/main.py"  #运行 AstrBot 主程序
elif [[ "$ENV_TYPE" == "uv" ]]; then      #如果是 uv 环境
    uv run "$DEPLOY_DIR/AstrBot/main.py"  #使用 uv 运行 AstrBot 主程序
    
else                                      #如果都不是
    err "你部署的时候有问题 请查看部署状态文件" #打印报错
    exit 1                                #退出脚本
fi                                        #结束条件判断
}                                         #结束函数定义
#------------------------------------------------------------------------------




# =============================================================================
# 菜单界面
# =============================================================================
main_menu() {
    while true; do
        clear
        echo "================================================"
        echo "       Astrbot & Antlia 管理面板"
        echo "    用户: $CURRENT_USER | 时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "================================================"
        echo "主菜单:"
        echo "  1. 启动Astrbot (后台运行)"
        echo "  2. 启动Astrbot (前台运行)"
        echo "  3. 附加Astrbot会话"
        hr
        echo "  4. 停止所有服务"
        hr
        echo "  q. 退出脚本"
        read -rp "请输入您的选择: " choice

        case $choice in
            1) 
                stop_service
                start_service_background
                read -rp "按 Enter 键返回主菜单..."
                ;;
            2) 
                stop_service
                start_astrbot_interactive
                read -rp "按 Enter 键返回..."
                ;;
            3) 
                if tmux_session_exists "$TMUX_SESSION_ASTRBOT"; then
                    tmux attach -t "$TMUX_SESSION_ASTRBOT"
                else
                    print_warning "Eridanus 会话不存在"
                fi
                read -rp "按 Enter 键返回..."
                ;;
            4) 
                stop_service
                ;;
            q|0) 
                exit 0
                ;;
            *) 
                warn "无效输入，请重试"
                sleep 1
                ;;
        esac
    done
}

#------------------------------------------------------------------------------


# =============================================================================
# 脚本入口
# =============================================================================
main() {
    # 设置异常处理
    
    # 检查是否以 root 用户运行
    if [[ $EUID -eq 0 ]]; then
        err "请不要使用 root 用户或 'sudo' 直接运行此脚本"
        exit 1
    fi
    
    # 检查部署状态文件
    if [[ ! -f "$DEPLOY_STATUS_FILE" ]]; then
        err "部署状态文件 '$DEPLOY_STATUS_FILE' 未找到"
        exit 1
    fi
    
    # 加载部署状态
    source "$DEPLOY_STATUS_FILE"
    
    
    # 检查必需命令
    check_command tmux 
    
    # 激活 Conda 环境
    
    # 启动主菜单
    main_menu
    
    # 清理异常处理
    trap - INT TERM EXIT
}

#------------------------------------------------------------------------------

# 执行主函数
main
