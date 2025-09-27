#!/bin/bash

# --- 全局设置 ---
set -o pipefail

# --- 路径与常量定义 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/bot"
LOG_DIR="$DEPLOY_DIR/logs"
CONDA_DIR="$HOME/mambaforge"
DEPLOY_STATUS_FILE="$DEPLOY_DIR/deploy.status"

# --- 日志文件路径 ---
LAGRANGE_LOG_FILE="$LOG_DIR/lagrange.log"

# --- 后台会话名 ---
TMUX_SESSION_ERIDANUS="Eridanus"
SCREEN_SESSION_LAGRANGE="lagrange"
# --- 全局变量 ---
PACKAGE_MANAGER=""

CURRENT_USER=$(whoami)

# --- 日志与颜色 ---
info() { echo "[INFO] $1"; }
ok() { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
err() { echo "[ERROR] $1" >&2; }
print_title() { echo -e "\n--- $1 ---"; }
hr() { echo "-------------------------------------------------"; }

# =============================================================================
# 工具函数 (Helper Functions)
# =============================================================================

check_command() {
  for cmd in "$@"; do
    if ! command -v "$cmd" &>/dev/null; then err "关键命令 '$cmd' 未找到。"; fi
  done
}
activate_environment() {
  if [[ ! -d "$CONDA_DIR" ]]; then err "Conda 目录 '$CONDA_DIR' 未找到。"; fi
  source "$CONDA_DIR/etc/profile.d/conda.sh"
  if ! conda activate Eridanus 2>/dev/null; then err "无法激活 Conda 环境 'Eridanus'。"; fi
}
# 停止服务，按名猎杀进程，然后清理会话
stop_service() {
  local service_name="$1"
  info "正在强制终结所有 '$service_name' 相关进程和会话..."

  case "$service_name" in
  Eridanus)
    tmux kill-session -t "$TMUX_SESSION_ERIDANUS" 2>/dev/null
    ;;
  Lagrange)
    pkill -f "Lagrange.OneBot" 2>/dev/null
    sleep 0.5
    screen -wipe 2>/dev/null
    ;;
  NapCat)
    sudo pkill -f "qq" 2>/dev/null
    sudo pkill -f "linuxqq" 2>/dev/null
    sleep 0.5
    sudo screen -wipe 2>/dev/null
    ;;
  esac

  ok "'$service_name' 清理完成。"
}

refresh_sudo() {
  info "正在检查并刷新 sudo 权限，可能需要您输入密码..."
  if sudo -v; then
    ok "Sudo 权限已确认。"
    return 0
  else
    err "Sudo 权限获取失败。"
    return 1
  fi
}

# (重构) "仅后台运行" 选项，采用先停后启模式
start_service_background() {
  local type="$1"
  local service_name="$2"
  local session_name="$3"
  local work_dir="$4"
  local start_cmd="$5"

  stop_service "$service_name" # 先彻底清理旧进程和会话
  info "正在后台启动 $service_name..."
  if [[ ! -d "$work_dir" ]]; then
    err "$service_name 的工作目录不存在。"
    return 1
  fi

  local log_file=""
  if [[ "$service_name" == "Lagrange" ]]; then log_file="$LAGRANGE_LOG_FILE"; elif [[ "$service_name" == "NapCat" ]]; then log_file="$NAPCAT_LOG_FILE"; fi
  if [[ -n "$log_file" ]]; then >"$log_file"; fi

  if [[ "$type" == "tmux" ]]; then
    tmux new-session -d -s "$session_name" "source '$CONDA_DIR/etc/profile.d/conda.sh' && conda activate Eridanus && cd '$work_dir' && python main.py"
  elif [[ "$type" == "screen" ]]; then
    local executable_cmd
    if [[ "$service_name" == "NapCat" ]]; then executable_cmd="bash $start_cmd"; else executable_cmd="./$start_cmd"; fi
    local cmd_for_screen="cd '$work_dir' && $executable_cmd > '$log_file' 2>&1"

    if [[ "$service_name" == "NapCat" ]]; then
      sudo screen -dmS "$session_name" bash -c "$cmd_for_screen"
    else
      screen -dmS "$session_name" bash -c "$cmd_for_screen"
    fi
  fi

  sleep 1
  ok "$service_name 已在后台启动。"
}

# (重构) 交互式启动，采用先停后启模式
start_service_interactive() {
  local service_name="$1"
  local session_name="$2"
  local work_dir="$3"
  local start_cmd="$4"

  stop_service "$service_name" # 先彻底清理旧进程和会话
  info "正在启动 $service_name..."

  hr
  echo "您即将进入 $service_name 的实时会话。"
  echo "【重要】分离方式: 按住 Ctrl+a, 然后按 d 键。"
  hr
  sleep 3
  clear

  local executable_cmd
  if [[ "$service_name" == "NapCat" ]]; then executable_cmd="bash $start_cmd"; else executable_cmd="./$start_cmd"; fi
  local cmd_for_screen="cd '$work_dir' && $executable_cmd"

  if [[ "$service_name" == "NapCat" ]]; then
    sudo screen -S "$session_name" bash -c "$cmd_for_screen"
  else # Lagrange
    screen -S "$session_name" bash -c "$cmd_for_screen"
  fi

  clear
  ok "已从 $service_name 会话分离。服务仍在后台运行。"
}

# =============================================================================
# 核心功能实现
# =============================================================================

switch_compatibility_auto() {
  local target_mode="$1"
  local config_file="$DEPLOY_DIR/Eridanus/run/common_config/basic_config.yaml"
  [[ ! -f "$config_file" ]] && config_file="$DEPLOY_DIR/Eridanus/config/common_config/basic_config.yaml"
  if [[ ! -f "$config_file" ]]; then
    warn "未找到 Eridanus 配置文件。"
    return
  fi
  if [[ "$target_mode" == "Lagrange" || "$target_mode" == "NapCat" ]]; then
    if ! sudo -v; then
      info "需要sudo权限修改配置文件。"
      return
    fi
    if [[ "$target_mode" == "Lagrange" ]]; then
      sudo sed -i 's/name:[[:space:]]*"any"/name: "Lagrange"/' "$config_file"
      ok "已自动切换到 [Lagrange] 兼容模式。"
    else
      sudo sed -i 's/name:[[:space:]]*"Lagrange"/name: "any"/' "$config_file"
      ok "已自动切换到 [NapCat] 兼容模式。"
    fi
  fi
}

start_all_interactive() {
  print_title "启动所有服务 (推荐流程)"
  hr

  selected_protocol_name="Lagrange"

  hr
  info "自动配置 Eridanus 以兼容 $selected_protocol_name..."
  switch_compatibility_auto "$selected_protocol_name"
  hr

  start_service_background "tmux" "Eridanus" "$TMUX_SESSION_ERIDANUS" "$DEPLOY_DIR/Eridanus" "python main.py"
  hr

  start_service_interactive "Lagrange" "$SCREEN_SESSION_LAGRANGE" "$DEPLOY_DIR/Lagrange" "Lagrange.OneBot"

  hr
  ok "智能启动流程已完成！"
}

# =============================================================================
# 菜单界面 (Menus)
# =============================================================================

main_menu() {
  while true; do
    clear
    echo "================================================="
    echo "       Eridanus & Antlia 管理面板 2025/08/05"
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
    read -rp "请输入您的选择: " choice

    case $choice in
    1)
      start_all_interactive
      read -rp "按 Enter 键返回主菜单..."
      ;;
    2)
      stop_service "Eridanus"
      stop_service "Lagrange"
      read -rp "按 Enter 键返回..."
      ;;
    3) eridanus_menu ;;
    4) lagrange_menu ;;
    q | Q) exit 0 ;;
    *)
      warn "无效输入，请重试。"
      sleep 1
      ;;
    esac
  done
}

eridanus_menu() {
  while true; do
    clear
    print_title "管理 Eridanus"
    hr
    echo "  1. 启动 (后台模式)"
    echo "  2. 启动 (前台调试)"
    echo "  3. 停止服务"
    echo "  4. 查看原生日志"
    echo "  q. 返回主菜单"
    read -rp "请选择: " choice
    case $choice in
    1)
      start_service_background "tmux" "Eridanus" "$TMUX_SESSION_ERIDANUS" "$DEPLOY_DIR/Eridanus" "python main.py"
      read -rp "按 Enter 键返回..."
      ;;
    2)
      info "即将前台启动 Eridanus..."
      sleep 2
      clear
      (cd "$DEPLOY_DIR/Eridanus" && source "$CONDA_DIR/etc/profile.d/conda.sh" && conda activate Eridanus && python main.py)
      read -rp "Eridanus 已停止，按 Enter 键返回..."
      ;;
    3)
      stop_service "Eridanus"
      read -rp "按 Enter 键返回..."
      ;;
    4)
      ERIDANUS_NATIVE_LOG_FILE="$DEPLOY_DIR/Eridanus/log/$(date '+%Y-%m-%d').log"
      less "$ERIDANUS_NATIVE_LOG_FILE"
      ;;
    q | Q) break ;; *) warn "无效输入。" ;;
    esac
  done
}

lagrange_menu() {
  while true; do
    clear
    print_title "管理 Lagrange"
    hr
    echo "  1. 启动并进入交互会话 (扫码)"
    echo "  2. 启动 (仅后台运行)"
    echo "  3. 停止"
    echo "  4. 查看后台日志"
    echo "  q. 返回主菜单"
    read -rp "请选择: " choice
    case $choice in
    1) start_service_interactive "Lagrange" "$SCREEN_SESSION_LAGRANGE" "$DEPLOY_DIR/Lagrange" "Lagrange.OneBot" ;;
    2)
      start_service_background "screen" "Lagrange" "$SCREEN_SESSION_LAGRANGE" "$DEPLOY_DIR/Lagrange" "Lagrange.OneBot"
      read -rp "按 Enter 键返回..."
      ;;
    3)
      stop_service "Lagrange"
      read -rp "按 Enter 键返回..."
      ;;
    4) less "$LAGRANGE_LOG_FILE" ;;
    q | Q) break ;; *) warn "无效输入。" ;;
    esac
  done
}

# =============================================================================
# 脚本入口 (Main Entry)
# =============================================================================
main() {

  mkdir -p "$LOG_DIR"
  check_command tmux screen conda sudo xvfb-run pkill
  activate_environment
  main_menu

}

main
