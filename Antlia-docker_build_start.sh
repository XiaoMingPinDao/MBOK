#!/bin/bash

# Eridanus 启动脚本 - VENV 环境优化版
# 版本: 2025/08/24 (新增 tool.py 选项)

set -o pipefail

# =============================================================================
# 路径与常量定义
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/bot"
LOG_DIR="$DEPLOY_DIR/logs"
VENV_DIR="$DEPLOY_DIR/venv" # VENV 路径
PYTHON_EXEC="$VENV_DIR/bin/python" # VENV 中的 Python 解释器
DEPLOY_STATUS_FILE="$DEPLOY_DIR/deploy.status"

# 日志文件路径
LAGRANGE_LOG_FILE="$LOG_DIR/lagrange.log"

# 会话名称
TMUX_SESSION_ERIDANUS="eridanus-main"
SCREEN_SESSION_LAGRANGE="eridanus-lagrange"

# 全局变量
CURRENT_USER=$(whoami)
LAGRANGE_DEPLOYED=0

# =============================================================================
# 日志函数
# =============================================================================
info() { echo "[INFO] $1"; }
ok() { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
err() { echo "[ERROR] $1" >&2; }
print_title() { echo -e "\n=== $1 ==="; }
hr() { echo "================================================"; }

# =============================================================================
# 工具函数
# =============================================================================
check_command() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            err "关键命令 '$cmd' 未找到，请确保已安装。"
            exit 1
        fi
    done
}

# =============================================================================
# 服务管理
# =============================================================================
stop_service() {
    local service_name="$1"
    info "正在停止 '$service_name'..."
    case "$service_name" in
        Eridanus) tmux kill-session -t "$TMUX_SESSION_ERIDANUS" 2>/dev/null ;;
        Lagrange) pkill -f "Lagrange.OneBot" 2>/dev/null; sleep 0.5; screen -wipe 2>/dev/null ;;
    esac
    ok "'$service_name' 已停止"
}

start_service_background() {
    local type="$1"; local service_name="$2"; local session_name="$3"; local work_dir="$4"; local start_cmd="$5"
    stop_service "$service_name"
    info "正在后台启动 $service_name..."
    if [[ ! -d "$work_dir" ]]; then err "$service_name 工作目录不存在"; return 1; fi

    if [[ "$type" == "tmux" ]]; then
        # 直接使用 venv 中的 python，无需激活
        tmux new-session -d -s "$session_name" "cd '$work_dir' && '$PYTHON_EXEC' main.py"
    elif [[ "$type" == "screen" ]]; then
        # 创建日志文件
        >"$LAGRANGE_LOG_FILE"
        screen -dmS "$session_name" bash -c "cd '$work_dir' && ./$start_cmd > '$LAGRANGE_LOG_FILE' 2>&1"
    fi
    sleep 1
    ok "$service_name 已在后台启动"
}

start_service_interactive() {
    local service_name="$1"; local session_name="$2"; local work_dir="$3"; local start_cmd="$4"
    stop_service "$service_name"
    info "正在启动 $service_name..."
    hr; echo "您即将进入 $service_name 的实时会话 (用于扫码)"; echo "【重要】分离会话: 按住 Ctrl+a, 然后按 d 键"; hr
    sleep 3; clear
    screen -S "$session_name" bash -c "cd '$work_dir' && ./$start_cmd"
    clear; ok "已从 $service_name 会话分离。服务仍在后台运行"
}

# =============================================================================
# 配置管理
# =============================================================================
switch_compatibility_to_lagrange() {
    local config_file="$DEPLOY_DIR/Eridanus/run/common_config/basic_config.yaml"
    [[ ! -f "$config_file" ]] && config_file="$DEPLOY_DIR/Eridanus/config/common_config/basic_config.yaml"
    if [[ ! -f "$config_file" ]]; then warn "未找到 Eridanus 配置文件"; return; fi
    # 假设用户有免密sudo权限
    sudo sed -i 's/name:[[:space:]]*"any"/name: "Lagrange"/' "$config_file" 2>/dev/null || warn "切换 Lagrange 模式失败，可能需要 sudo 权限"
    ok "已自动尝试切换到 [Lagrange] 兼容模式"
}

# =============================================================================
# 综合启动流程
# =============================================================================
start_all_interactive() {
    print_title "启动所有服务"
    hr
    info "自动配置 Eridanus 以兼容 Lagrange..."
    switch_compatibility_to_lagrange
    hr
    start_service_background "tmux" "Eridanus" "$TMUX_SESSION_ERIDANUS" "$DEPLOY_DIR/Eridanus" "main.py"
    hr
    start_service_interactive "Lagrange" "$SCREEN_SESSION_LAGRANGE" "$DEPLOY_DIR/Lagrange" "Lagrange.OneBot"
    hr
    ok "启动流程已完成！"
}

# =============================================================================
# 菜单界面
# =============================================================================
main_menu() {
    while true; do
        clear
        echo "================================================"
        echo "               Antlia 管理面板"
        echo "       用户: $CURRENT_USER | $(date '+%Y-%m-%d %H:%M:%S')"
        echo "================================================"
        echo "  1. 启动所有服务 (推荐)"
        echo "  2. 停止所有服务"
        hr
        echo "  3. 管理 Eridanus (主程序)"
        if [[ "$LAGRANGE_DEPLOYED" -eq 1 ]]; then
            echo "  4. 管理 Lagrange.OneBot (QQ客户端)"
        fi
        hr
        echo "  q. 退出脚本"
        read -rp "请输入您的选择: " choice

        case $choice in
            1) start_all_interactive; read -rp "按 Enter 键返回主菜单..." ;;
            2) stop_service "Eridanus"; stop_service "Lagrange"; read -rp "按 Enter 键返回..." ;;
            3) eridanus_menu ;;
            4) [[ "$LAGRANGE_DEPLOYED" -eq 1 ]] && lagrange_menu ;;
            q|Q) exit 0 ;;
            *) warn "无效输入，请重试"; sleep 1 ;;
        esac
    done
}

eridanus_menu() {
    while true; do
        clear; print_title "管理 Eridanus"; hr
        echo "  1. 启动 (后台)"
        echo "  2. 启动 (前台调试)"
        echo "  3. 停止"
        echo "  4. 执行 tool.py (更新/工具)" # <-- 新增选项
        echo "  5. 查看日志"                 # <-- 序号顺延
        echo "  q. 返回主菜单"
        
        read -rp "请选择: " choice
        case $choice in
            1) 
                start_service_background "tmux" "Eridanus" "$TMUX_SESSION_ERIDANUS" "$DEPLOY_DIR/Eridanus" "main.py"
                read -rp "按 Enter 返回..."
                ;;
            2) 
                info "即将前台启动 Eridanus... 按 Ctrl+C 停止"
                sleep 2; clear
                (cd "$DEPLOY_DIR/Eridanus" && source "$VENV_DIR/bin/activate" && python main.py)
                read -rp "Eridanus 已停止，按 Enter 返回..."
                ;;
            3) 
                stop_service "Eridanus"
                read -rp "按 Enter 返回..."
                ;;
            4) # <-- 新增处理逻辑
                info "即将前台执行 tool.py 更新脚本..."
                sleep 1; clear
                (
                    cd "$DEPLOY_DIR/Eridanus" && \
                    source "$VENV_DIR/bin/activate" && \
                    python tool.py
                )
                read -rp "tool.py 执行完毕，按 Enter 键返回..."
                ;;
            5) # <-- 序号顺延
                less "$DEPLOY_DIR/Eridanus/log/$(date '+%Y-%m-%d').log"
                ;;
            q|Q) 
                break
                ;;
            *) 
                warn "无效输入"
                ;;
        esac
    done
}

lagrange_menu() {
    while true; do
        clear; print_title "管理 Lagrange.OneBot"; hr
        echo "  1. 启动并进入会话 (扫码)"; echo "  2. 启动 (仅后台)"; echo "  3. 停止"; echo "  4. 查看日志"; echo "  q. 返回主菜单"
        read -rp "请选择: " choice
        case $choice in
            1) start_service_interactive "Lagrange" "$SCREEN_SESSION_LAGRANGE" "$DEPLOY_DIR/Lagrange" "Lagrange.OneBot" ;;
            2) start_service_background "screen" "Lagrange" "$SCREEN_SESSION_LAGRANGE" "$DEPLOY_DIR/Lagrange" "Lagrange.OneBot"; read -rp "按 Enter 返回..." ;;
            3) stop_service "Lagrange"; read -rp "按 Enter 返回..." ;;
            4) less "$LAGRANGE_LOG_FILE" ;;
            q|Q) break ;;
            *) warn "无效输入" ;;
        esac
    done
}

# =============================================================================
# 脚本入口
# =============================================================================
main() {
    export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
    export DOTNET_BUNDLE_EXTRACT_BASE_DIR=/app/temp
    if [[ $EUID -eq 0 ]]; then err "请不要使用 root 用户或 'sudo' 直接运行此脚本"; exit 1; fi
    if [[ ! -f "$DEPLOY_STATUS_FILE" ]]; then err "部署状态文件 '$DEPLOY_STATUS_FILE' 未找到，请先运行部署脚本"; exit 1; fi
    if [[ ! -f "$PYTHON_EXEC" ]]; then err "Python 虚拟环境未找到于 '$VENV_DIR'，请重新部署"; exit 1; fi
    
    source "$DEPLOY_STATUS_FILE"
    mkdir -p "$LOG_DIR"
    check_command tmux screen pkill
    main_menu
}

# 执行主函数
main