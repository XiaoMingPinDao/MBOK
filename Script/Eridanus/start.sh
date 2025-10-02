#!/bin/bash

# --- 全局设置 ---
set -o pipefail

# --- 路径与常量定义 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/bot"
LOG_DIR="$DEPLOY_DIR/logs"
DEPLOY_STATUS_FILE="$DEPLOY_DIR/deploy.status"

# --- 日志文件路径 ---
ERIDANUS_LOG_FILE="$LOG_DIR/eridanus.log"
LAGRANGE_LOG_FILE="$LOG_DIR/lagrange.log"

# --- 后台会话名 ---
TMUX_SESSION_ERIDANUS="Eridanus"
SCREEN_SESSION_LAGRANGE="lagrange"

# --- 全局变量 ---
CURRENT_USER=$(whoami)

# --- 日志 ---
info() { echo "[INFO] $1"; }
ok() { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
err() { echo "[ERROR] $1" >&2; }
print_title() { echo -e "\n--- $1 ---"; }
hr() { echo "-------------------------------------------------"; }

# =============================================================================
# 工具函数
# =============================================================================

check_command() {
  for cmd in "$@"; do
    if ! command -v "$cmd" &>/dev/null; then err "关键命令 '$cmd' 未找到。"; fi
  done
}

stop_service() {
  local service_name="$1"
  info "正在清理 '$service_name' 相关进程和会话..."

  case "$service_name" in
  Eridanus)
    tmux kill-session -t "$TMUX_SESSION_ERIDANUS" 2>/dev/null
    ;;
  Lagrange)
    pkill -f "Lagrange.OneBot" 2>/dev/null
    sleep 0.5
    screen -wipe 2>/dev/null
    ;;
  esac

  ok "'$service_name' 已清理。"
}

start_service_background() {
  local type="$1"
  local service_name="$2"
  local session_name="$3"
  local work_dir="$4"
  local start_cmd="$5"

  stop_service "$service_name"
  info "正在后台启动 $service_name..."

  [[ ! -d "$work_dir" ]] && err "$service_name 工作目录不存在。"

  local log_file=""
  [[ "$service_name" == "Eridanus" ]] && log_file="$ERIDANUS_LOG_FILE"
  [[ "$service_name" == "Lagrange" ]] && log_file="$LAGRANGE_LOG_FILE"
  [[ -n "$log_file" ]] && >"$log_file"

  if [[ "$type" == "tmux" ]]; then
    tmux new-session -d -s "$session_name" "cd '$work_dir' && micromamba run -n Eridanus python main.py > '$log_file' 2>&1"
  elif [[ "$type" == "screen" ]]; then
    local cmd_for_screen="cd '$work_dir' && ./$start_cmd > '$log_file' 2>&1"
    screen -dmS "$session_name" bash -c "$cmd_for_screen"
  fi

  sleep 1
  ok "$service_name 已在后台启动。"
}

start_service_interactive() {
  local service_name="$1"
  local session_name="$2"
  local work_dir="$3"
  local start_cmd="$4"

  stop_service "$service_name"
  info "正在启动 $service_name (前台)..."
  hr
  echo "分离方式: Ctrl+a, 然后按 d"
  hr
  sleep 2
  clear

  local cmd_for_screen
  if [[ "$service_name" == "Lagrange" ]]; then
    cmd_for_screen="cd '$work_dir' && ./$start_cmd"
    screen -S "$session_name" bash -c "$cmd_for_screen"
  fi

  clear
  ok "$service_name 会话已分离，仍在后台运行。"
}

switch_compatibility_auto() {
  local target_mode="$1"
  local config_file="$DEPLOY_DIR/Eridanus/run/common_config/basic_config.yaml"
  [[ ! -f "$config_file" ]] && config_file="$DEPLOY_DIR/Eridanus/config/common_config/basic_config.yaml"
  [[ ! -f "$config_file" ]] && { warn "未找到配置文件"; return; }

  [[ "$target_mode" == "Lagrange" ]] && sed -i 's/name:[[:space:]]*"any"/name: "Lagrange"/' "$config_file"
  ok "已自动切换到 [Lagrange] 兼容模式。"
}

start_all_interactive() {
  print_title "启动所有服务"
  hr
  selected_protocol_name="Lagrange"
  info "配置 Eridanus 兼容 $selected_protocol_name..."
  switch_compatibility_auto "$selected_protocol_name"
  hr

  start_service_background "tmux" "Eridanus" "$TMUX_SESSION_ERIDANUS" "$DEPLOY_DIR/Eridanus" "python main.py"
  hr

  start_service_interactive "Lagrange" "$SCREEN_SESSION_LAGRANGE" "$DEPLOY_DIR/Lagrange" "Lagrange.OneBot"
  hr

  ok "启动完成"
}

# =============================================================================
# 菜单
# =============================================================================

main_menu() {
  while true; do
    clear
    echo "================================================="
    echo "       Eridanus & Antlia 管理面板"
    echo "    用户: $CURRENT_USER | 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================="
    echo "主菜单:"
    echo "  1. 启动所有服务 (推荐流程)"
    echo "  2. 停止所有服务"
    hr
    echo "  3. 管理 Eridanus"
    echo "  4. 管理 Lagrange"
    hr
    echo "  q. 退出脚本"
    read -rp "选择: " choice

    case $choice in
    1) start_all_interactive; read -rp "Enter 返回..." ;;
    2)
      stop_service "Eridanus"
      stop_service "Lagrange"
      read -rp "Enter 返回..." ;;
    3) eridanus_menu ;;
    4) lagrange_menu ;;
    q|Q) exit 0 ;;
    *) warn "无效输入"; sleep 1 ;;
    esac
  done
}

eridanus_menu() {
  while true; do
    clear
    print_title "管理 Eridanus"
    hr
    echo "  1. 启动 (后台)"
    echo "  2. 启动 (前台调试)"
    echo "  3. 停止服务"
    echo "  4. 附加后台会话"
    echo "  5. 前台执行 tool.py 更新"
    echo "  q. 返回主菜单"
    read -rp "选择: " choice

    case $choice in
    1) start_service_background "tmux" "Eridanus" "$TMUX_SESSION_ERIDANUS" "$DEPLOY_DIR/Eridanus" "python main.py"; read -rp "Enter 返回..." ;;
    2) (cd "$DEPLOY_DIR/Eridanus" && micromamba run -n Eridanus python main.py); read -rp "Enter 返回..." ;;
    3) stop_service "Eridanus"; read -rp "Enter 返回..." ;;
    4) tmux attach -t "$TMUX_SESSION_ERIDANUS"; read -rp "Enter 返回..." ;;
    5) (cd "$DEPLOY_DIR/Eridanus" && micromamba run -n Eridanus python tool.py); read -rp "Enter 返回..." ;;
    q|Q) break ;;
    *) warn "无效输入" ;;
    esac
  done
}

lagrange_menu() {
  while true; do
    clear
    print_title "管理 Lagrange"
    hr
    echo "  1. 启动并进入交互会话 (扫码)"
    echo "  2. 启动 (后台)"
    echo "  3. 停止"
    echo "  4. 附加后台会话"
    echo "  q. 返回主菜单"
    read -rp "选择: " choice

    case $choice in
    1) start_service_interactive "Lagrange" "$SCREEN_SESSION_LAGRANGE" "$DEPLOY_DIR/Lagrange" "Lagrange.OneBot" ;;
    2) start_service_background "screen" "Lagrange" "$SCREEN_SESSION_LAGRANGE" "$DEPLOY_DIR/Lagrange" "Lagrange.OneBot"; read -rp "Enter 返回..." ;;
    3) stop_service "Lagrange"; read -rp "Enter 返回..." ;;
    4) screen -r "$SCREEN_SESSION_LAGRANGE"; read -rp "Enter 返回..." ;;
    q|Q) break ;;
    *) warn "无效输入" ;;
    esac
  done
}

# =============================================================================
# 入口
# =============================================================================

main() {
  export PATH="$HOME/.local/bin:$PATH"

  mkdir -p "$LOG_DIR"
  check_command tmux screen pkill micromamba
  main_menu
}

main
