#!/bin/bash

# Eridanus 启动脚本 - 安全 VENV 版
# 版本: 2025/08/25

set -o pipefail

# =============================================================================
# 环境初始化
# =============================================================================
: "${TERM:=xterm-256color}"
export TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/bot"
LOG_DIR="$DEPLOY_DIR/logs"
VENV_DIR="$DEPLOY_DIR/venv"
PYTHON_EXEC="$VENV_DIR/bin/python"
DEPLOY_STATUS_FILE="$DEPLOY_DIR/deploy.status"

LAGRANGE_LOG_FILE="$LOG_DIR/lagrange.log"
TMUX_SESSION_ERIDANUS="eridanus-main"
SCREEN_SESSION_LAGRANGE="eridanus-lagrange"
CURRENT_USER=$(whoami)
LAGRANGE_DEPLOYED=1

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
# 安全读取（兼容非交互环境）
# =============================================================================
safe_read() {
    if [ -t 0 ]; then
        read -rp "$1" REPLY
    else
        echo "[INFO] 非交互环境，自动跳过输入: $1"
        REPLY=""
    fi
}

# =============================================================================
# 命令检查
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
# 服务管理函数
# =============================================================================
stop_service() {
    local service="$1"
    info "正在停止 $service..."
    case "$service" in
        Eridanus) tmux kill-session -t "$TMUX_SESSION_ERIDANUS" 2>/dev/null ;;
        Lagrange) pkill -f "Lagrange.OneBot" 2>/dev/null; sleep 0.5; screen -wipe 2>/dev/null ;;
    esac
    ok "$service 已停止"
}

start_service_background() {
    local type="$1" local service="$2" local session="$3" local work_dir="$4" local cmd="$5"
    stop_service "$service"
    info "正在后台启动 $service..."
    [[ ! -d "$work_dir" ]] && { err "$service 工作目录不存在"; return 1; }

    if [[ "$type" == "tmux" ]]; then
        tmux new-session -d -s "$session" "cd '$work_dir' && '$PYTHON_EXEC' main.py"
    elif [[ "$type" == "screen" ]]; then
        >"$LAGRANGE_LOG_FILE"
        screen -dmS "$session" bash -c "cd '$work_dir' && ./$cmd > '$LAGRANGE_LOG_FILE' 2>&1"
    fi
    sleep 1
    ok "$service 已在后台启动"
}

start_service_interactive() {
    local service="$1" local session="$2" local work_dir="$3" local cmd="$4"
    stop_service "$service"
    info "正在启动 $service..."
    hr; echo "您即将进入 $service 的实时会话"; hr
    sleep 2; clear
    screen -S "$session" bash -c "cd '$work_dir' && ./$cmd"
    clear; ok "已从 $service 会话分离，服务仍在后台运行"
}

attach_eridanus_session() {
    if tmux has-session -t "$TMUX_SESSION_ERIDANUS" 2>/dev/null; then
        info "附加到 Eridanus tmux 会话..."
        echo "分离会话: Ctrl+b, 然后 d 键"
        sleep 1; clear
        tmux attach-session -t "$TMUX_SESSION_ERIDANUS"
        clear; ok "已分离 Eridanus 会话"
    else
        warn "Eridanus 会话不存在"
    fi
}

attach_lagrange_session() {
    if screen -list | grep -q "$SCREEN_SESSION_LAGRANGE"; then
        info "附加到 Lagrange.OneBot screen 会话..."
        echo "分离会话: Ctrl+a, 然后 d 键"
        sleep 1; clear
        screen -r "$SCREEN_SESSION_LAGRANGE"
        clear; ok "已分离 Lagrange 会话"
    else
        warn "Lagrange.OneBot 会话不存在"
    fi
}

# =============================================================================
# 配置管理
# =============================================================================
switch_compatibility_to_lagrange() {
    local cfg="$DEPLOY_DIR/Eridanus/run/common_config/basic_config.yaml"
    [[ ! -f "$cfg" ]] && cfg="$DEPLOY_DIR/Eridanus/config/common_config/basic_config.yaml"
    [[ ! -f "$cfg" ]] && { warn "未找到 Eridanus 配置文件"; return; }
    sudo sed -i 's/name:[[:space:]]*"any"/name: "Lagrange"/' "$cfg" 2>/dev/null || warn "切换 Lagrange 模式失败"
    ok "已尝试切换到 Lagrange 模式"
}

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
    ok "启动完成！"
}

view_eridanus_log() {
    local log_file="$DEPLOY_DIR/Eridanus/log/$(date '+%Y-%m-%d').log"
    if [[ -f "$log_file" ]]; then
        less "$log_file"
    else
        warn "日志文件未找到: $log_file"
    fi
}

# =============================================================================
# 菜单
# =============================================================================
eridanus_menu() {
    while true; do
        clear; print_title "管理 Eridanus"; hr
        echo "  1. 启动 (后台)"
        echo "  2. 启动 (前台调试)"
        echo "  3. 停止"
        echo "  4. 附加 tmux 会话"
        echo "  5. 执行 tool.py 更新"
        echo "  q. 返回主菜单"
        safe_read "请选择: "
        case "$REPLY" in
            1) start_service_background "tmux" "Eridanus" "$TMUX_SESSION_ERIDANUS" "$DEPLOY_DIR/Eridanus" "main.py"; safe_read "按 Enter 返回..." ;;
            2) info "前台启动 Eridanus"; sleep 1; clear; (cd "$DEPLOY_DIR/Eridanus" && "$PYTHON_EXEC" main.py); safe_read "按 Enter 返回..." ;;
            3) stop_service "Eridanus"; safe_read "按 Enter 返回..." ;;
            4) attach_eridanus_session; safe_read "按 Enter 返回..." ;;
            5)
                info "执行 tool.py..."
                sleep 1; clear
                (export HOME=/app; mkdir -p /app/.config/pip /app/.cache/pip; cd "$DEPLOY_DIR/Eridanus"; source "$VENV_DIR/bin/activate"; python tool.py)
                safe_read "tool.py 执行完毕, 按 Enter 返回..."
                ;;
            q|Q) break ;;
            *) warn "无效输入"; sleep 1 ;;
        esac
    done
}

lagrange_menu() {
    while true; do
        clear; print_title "管理 Lagrange.OneBot"; hr
        echo "  1. 启动并进入会话"
        echo "  2. 启动 (后台)"
        echo "  3. 停止"
        echo "  4. 附加 screen 会话"
        echo "  5. 查看日志"
        echo "  q. 返回主菜单"
        safe_read "请选择: "
        case "$REPLY" in
            1) start_service_interactive "Lagrange" "$SCREEN_SESSION_LAGRANGE" "$DEPLOY_DIR/Lagrange" "Lagrange.OneBot"; safe_read "按 Enter 返回..." ;;
            2) start_service_background "screen" "Lagrange" "$SCREEN_SESSION_LAGRANGE" "$DEPLOY_DIR/Lagrange" "Lagrange.OneBot"; safe_read "按 Enter 返回..." ;;
            3) stop_service "Lagrange"; safe_read "按 Enter 返回..." ;;
            4) attach_lagrange_session; safe_read "按 Enter 返回..." ;;
            5) [[ -f "$LAGRANGE_LOG_FILE" ]] && less "$LAGRANGE_LOG_FILE" || warn "日志文件未找到"; safe_read "按 Enter 返回..." ;;
            q|Q) break ;;
            *) warn "无效输入"; sleep 1 ;;
        esac
    done
}

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
        [[ "$LAGRANGE_DEPLOYED" -eq 1 ]] && echo "  4. 管理 Lagrange.OneBot (QQ客户端)"
        hr
        echo "  q. 退出脚本"

        safe_read "请选择: "

        case "$REPLY" in
            1) start_all_interactive; safe_read "按 Enter 返回..." ;;
            2) stop_service "Eridanus"; stop_service "Lagrange"; safe_read "按 Enter 返回..." ;;
            3) eridanus_menu ;;
            4) [[ "$LAGRANGE_DEPLOYED" -eq 1 ]] && lagrange_menu ;;
            q|Q) exit 0 ;;
            *) warn "无效输入"; sleep 1 ;;
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
    [[ ! -f "$DEPLOY_STATUS_FILE" ]] && { err "部署状态文件未找到"; exit 1; }
    [[ ! -f "$PYTHON_EXEC" ]] && { err "Python 虚拟环境未找到"; exit 1; }

    source "$DEPLOY_STATUS_FILE"
    mkdir -p "$LOG_DIR"
    check_command tmux screen pkill
    main_menu
}

main
