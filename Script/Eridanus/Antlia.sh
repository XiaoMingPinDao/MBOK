#!/bin/bash

# --- 全局设置 ---
set -o pipefail

# --- 路径与常量定义 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/bot"
DEPLOY_STATUS_FILE="$SCRIPT_DIR/bot/deploy.status"

# --- 全局变量 ---
GITHUB_PROXY=""
MINICONDA_ARCH=""

# =============================================================================
# 日志函数
# =============================================================================
# 定义颜色
RESET='\033[0m'   # 重置颜色
BOLD='\033[1m'    # 加粗
RED='\033[31m'    # 红色
GREEN='\033[32m'  # 绿色
YELLOW='\033[33m' # 黄色
BLUE='\033[34m'   # 蓝色
CYAN='\033[36m'   # 青色

# 信息日志
info() { echo -e "${BLUE}[INFO]${RESET} $1"; }

# 成功日志
ok() { echo -e "${GREEN}[OK]${RESET} $1"; }

# 警告日志
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }

# 错误日志
err() {
  echo -e "${RED}[ERROR]${RESET} $1"
  exit 1
}

# 打印标题
print_title() { echo -e "${BOLD}${CYAN}=== $1 ===${RESET}"; }

select_github_proxy() {        #定义函数
  print_title "选择 GitHub 代理"   #打印标题
  echo "请根据您的网络环境选择一个合适的下载代理：" #打印提示
  echo                         #打印空行

  # 使用 select 提供选项
  select proxy_choice in "ghfast.top 镜像 (推荐)" "ghproxy.net 镜像" "不使用代理" "自定义代理"; do
    case $proxy_choice in
    "ghfast.top 镜像 (推荐)")
      GITHUB_PROXY="https://ghfast.top/"
      ok "已选择: ghfast.top 镜像"
      break
      ;;
    "ghproxy.net 镜像")
      GITHUB_PROXY="https://ghproxy.net/"
      ok "已选择: ghproxy.net 镜像"
      break
      ;;
    "不使用代理")
      GITHUB_PROXY=""
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

download_with_retry() {
  local url="$1"
  local output="$2"
  local max_attempts=3
  local attempt=1
  while [[ $attempt -le $max_attempts ]]; do
    info "尝试下载 (第 $attempt 次): $url"
    if wget -O "$output" "$url"; then
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

# =============================================================================
# 系统检测与环境准备 (已修改 install_conda_environment)
# =============================================================================

detect_architecture() {
  print_title "检测系统架构"
  ARCH=$(uname -m)
  case $ARCH in
  x86_64)
    MINICONDA_ARCH="x86_64"
    ok "检测到系统架构: $ARCH "
    ;;
  aarch64 | arm64)
    MINICONDA_ARCH="aarch64"
    ok "检测到系统架构: $ARCH "
    ;;
  *)
    err "不支持的架构: $ARCH。本脚本仅支持 x86_64 和 aarch64/arm64 架构。"
    ;;
  esac
}

detect_package_manager() {
  print_title "检测系统包管理器"
  if command_exists apt; then
    PACKAGE_MANAGER="apt"
    ok "检测到 Debian/Ubuntu (apt)"
  elif command_exists yum; then
    PACKAGE_MANAGER="yum"
    ok "检测到 Red Hat/CentOS (yum)"
  elif command_exists dnf; then
    PACKAGE_MANAGER="dnf"
    ok "检测到 Fedora (dnf)"
  elif command_exists pacman; then
    PACKAGE_MANAGER="pacman"
    ok "检测到 Arch Linux (pacman)"
  elif command_exists zypper; then
    PACKAGE_MANAGER="zypper"
    ok "检测到 openSUSE (zypper)"
  else err "无法检测到支持的包管理器"; fi
}

install_system_dependencies() {
  print_title "安装系统依赖"
  local pkgs="redis tmux zip git curl wget tar jq screen"
  case $PACKAGE_MANAGER in
  apt) sudo apt update && sudo apt install -y $pkgs || err "依赖安装失败" ;;
  yum | dnf) sudo $PACKAGE_MANAGER install -y $pkgs || err "依赖安装失败" ;;
  pacman) sudo pacman -S --noconfirm && sudo pacman -S --noconfirm $pkgs || err "依赖安装失败" ;;
  zypper) sudo zypper --non-interactive install $pkgs || err "依赖安装失败" ;;
  esac
  #info "启动并设置 Redis 开机自启..."
  #if command_exists systemctl; then
  # sudo systemctl enable redis-server 2>/dev/null || sudo systemctl enable redis 2>/dev/null || true
  # sudo systemctl start redis-server 2>/dev/null || sudo systemctl start redis 2>/dev/null || true
  #fi
  ok "系统依赖安装完成"
}

install_mamba_environment() {
  print_title "安装和配置 Mamba 环境 (Mambaforge)"

  if [[ -d "$HOME/mambaforge/envs/Eridanus" ]]; then
    ok "检测到 Mamba 环境 'Eridanus' 已存在，跳过安装。"
    return
  fi

  info "下载 Mambaforge 安装脚本..."
  local url="${GITHUB_PROXY}https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Linux-$MINICONDA_ARCH.sh"
  download_with_retry "$url" "mambaforge.sh"

  info "运行 Mambaforge 安装脚本..."
  bash mambaforge.sh -b -p "$HOME/mambaforge" || err "Mambaforge 安装失败"
  rm -f mambaforge.sh

  info "初始化 Mamba..."
  source "$HOME/mambaforge/etc/profile.d/conda.sh"
  conda init --all || err "conda init 失败"
  source ~/.bashrc 2>/dev/null || true
  ok "Mamba 安装成功！"

  info "配置镜像源..."
  conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/ >/dev/null 2>&1
  conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/ >/dev/null 2>&1

  info "创建 Python 3.11 虚拟环境 (Eridanus)..."
  mamba create -n Eridanus python=3.11 -y || err "虚拟环境创建失败"
  conda activate Eridanus

  info "安装图形库依赖 pycairo..."
  mamba install pycairo -y || warn "pycairo 安装失败，可能需要手动安装"

  ok "Mamba 环境配置完成"
}

# =============================================================================
# 项目与协议端安装 (保持不变)
# =============================================================================

clone_eridanus() {
  print_title "克隆 Eridanus 项目"
  cd "$DEPLOY_DIR"
  if [[ -d "Eridanus" ]]; then
    warn "检测到 Eridanus 文件夹已存在。"
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
    err "项目克隆失败，请检查网络或代理设置。"
  fi
  ok "Eridanus 项目克隆完成"
}

install_python_dependencies() {
  print_title "安装 Python 依赖"
  cd "$DEPLOY_DIR/Eridanus" || err "无法进入 Eridanus 目录"
  source "$HOME/miniconda3/etc/profile.d/conda.sh"
  conda activate Eridanus
  info "配置 pip 镜像源并安装依赖..."
  pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple >/dev/null 2>&1
  python -m pip install --upgrade pip || warn "pip 升级失败"
  pip install -r requirements.txt || err "依赖安装失败"
  ok "Python 依赖已安装"
}

install_lagrange() {
  print_title "安装 Lagrange"

  cd "$DEPLOY_DIR"
  mkdir -p Lagrange tmp || err "无法创建目录"

  local TMP_DIR="$DEPLOY_DIR/tmp"
  cd "$TMP_DIR" || err "进入临时目录失败"

  info "正在动态获取 Lagrange 最新版本..."
  local github_url
  github_url=$(curl -s "https://api.github.com/repos/LagrangeDev/Lagrange.Core/releases/tags/nightly" | jq -r '.assets[] | select(.name | test("linux-x64.*.tar.gz")) | .browser_download_url')
  [[ -z "$github_url" ]] && err "无法动态获取 Lagrange 最新版本链接。"

  local download_url="${GITHUB_PROXY}${github_url}"
  download_with_retry "$download_url" "Lagrange.tar.gz"

  info "解压 Lagrange..."
  tar -xzf "Lagrange.tar.gz" || err "解压失败"

  # 查找可执行文件
  info "正在查找 Lagrange.OneBot 可执行文件..."
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
  wget -O appsettings.json https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/appsettings/appsettings-Eridanus.json

  # 清理临时目录
  info "清理临时文件..."
  rm -rf "$TMP_DIR"

  info "当前 Lagrange 目录内容:"
  ls -la

  ok "Lagrange 安装完成"
}

# =============================================================================
# 主函数
# =============================================================================

main() {
  print_title "Eridanus & Antlia 部署脚本 20250927"
  mkdir -p "$DEPLOY_DIR"
  cd "$SCRIPT_DIR" || exit
  select_github_proxy
  detect_architecture
  detect_package_manager
  install_system_dependencies

  install_lagrange

  install_conda_environment

  clone_eridanus
  install_python_dependencies
  generate_napcat_launcher

  print_title "🎉 部署完成! 🎉"
  echo "所有操作已成功完成。"
  echo "下一步: 请运行 './start.sh' 来启动和管理您的机器人服务。"
}

# 执行主函数
main
