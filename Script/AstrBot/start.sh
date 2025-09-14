#!/bin/bash

set -o pipefail #启用管道失败检测

# =============================================================================
# 环境检查和路径设置
# =============================================================================
setup_uv_environment() {
    # 确保 uv 在 PATH 中
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    
    # 检查 uv 是否可用
    if ! command -v uv >/dev/null 2>&1; then
        err "uv 未找到，请检查安装或重新运行部署脚本"
        return 1
    fi
    return 0
}

# =============================================================================

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
print_warning() { echo "[WARNING] $1"; }                          #警告信息函数
hr() { echo "================================================"; } #分割线

#------------------------------------------------------------------------------

# =============================================================================
# 工具函数
# =============================================================================

#检查tmux会话是否存在
tmux_session_exists() {
    tmux has-session -t "$1" 2>/dev/null
}

#用于检查关键命令是否存在
check_command() {
    for cmd in "$@"; do                            #遍历所有传入的命令    
        if ! command -v "$cmd" &>/dev/null; then   #如果命令不存在
            err "关键命令 '$cmd' 未找到"             #打印错误信息
            return 1                               #返回错误状态
        fi                                         #结束条件判断
    done                                           #结束循环
}                                                  #结束函数定义


# =============================================================================
# 停止AstrBot
# =============================================================================
stop_service() {                                                     #定义函数
    info "正在停止 '$TMUX_SESSION_ASTRBOT' 相关进程和会话..."            #打印信息日志
    tmux kill-session -t "$TMUX_SESSION_ASTRBOT" 2>/dev/null         #杀掉 tmux 会话
    ok "'$TMUX_SESSION_ASTRBOT' 清理完成"                             #打印成功日志
}                                                                    #结束函数定义

#------------------------------------------------------------------------------

# =============================================================================
# 后台启动AstrBot
# =============================================================================
start_service_background() {       #定义函数
    tmux new-session -d -s "$TMUX_SESSION_ASTRBOT" \
            "cd '$DEPLOY_DIR/AstrBot' && uv run python main.py"
    sleep 1                               #等待 1 秒确保服务启动
    ok "AstrBot 已在后台启动"              #打印成功日志 (修复变量名)
}
#------------------------------------------------------------------------------

# =============================================================================
# 前台启动AstrBot
# =============================================================================
start_astrbot_interactive() {             #定义函数
    cd "$DEPLOY_DIR/AstrBot"              #进入 AstrBot 目录
    uv run python "$DEPLOY_DIR/AstrBot/main.py"  #使用 uv 运行 AstrBot 主程序
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
                if tmux_session_exists "$TMUX_SESSION_ASTRBOT"; then
                    stop_service
                fi
                start_service_background
                read -rp "按 Enter 键返回..."
                ;;
            2) 
                clear
                if tmux_session_exists "$TMUX_SESSION_ASTRBOT"; then
                    stop_service
                fi
                start_astrbot_interactive
                read -rp "按 Enter 键返回..."
                ;;
            3) 
                if tmux_session_exists "$TMUX_SESSION_ASTRBOT"; then
                    tmux attach -t "$TMUX_SESSION_ASTRBOT"
                else
                    print_warning "AstrBot 会话不存在"  #修复会话名称
                fi
                read -rp "按 Enter 键返回..."
                ;;
            4) 
                stop_service
                read -rp "按 Enter 键返回..."
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
    setup_uv_environment
    # 检查必需命令
    if ! check_command tmux; then
        exit 1
    fi
    
    # 启动主菜单
    main_menu
}

#------------------------------------------------------------------------------

# 执行主函数
main
