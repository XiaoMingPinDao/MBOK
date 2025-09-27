#!/bin/bash

# --- 全局设置 ---
set -o pipefail

# --- 路径与常量定义 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/bot"
DEPLOY_STATUS_FILE="$SCRIPT_DIR/bot/deploy.status"
echo "SCRIPT_DIR: $SCRIPT_DIR" 
echo "DEPLOY_DIR: $DEPLOY_DIR" # 鬼知道这是为什么 
# --- 全局变量 ---
GITHUB_PROXY=""
MINICONDA_ARCH=""
SUDO=""



# =============================================================================
# 日志函数
# =============================================================================
RESET='\033[0m'   # 重置颜色
BOLD='\033[1m'    # 加粗
RED='\033[31m'    # 红色
GREEN='\033[32m'  # 绿色
YELLOW='\033[33m' # 黄色
BLUE='\033[34m'   # 蓝色
CYAN='\033[36m'   # 青色

info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
ok() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
err() { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

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
        exit 1
    fi
}
print_title() { echo -e "${BOLD}${CYAN}=== $1 ===${RESET}"; }

select_github_proxy() {
  print_title "选择 GitHub 代理"
  echo "请根据您的网络环境选择一个合适的下载代理："
  echo
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
        read -p "请输入自定义 GitHub 代理 URL (必须以斜杠 / 结尾): " custom_proxy
        [[ -n "$custom_proxy" && "$custom_proxy" != */ ]] && custom_proxy="${custom_proxy}/" && warn "已自动添加斜杠"
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
}

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
    [[ $attempt -lt $max_attempts ]] && info "5秒后重试..." && sleep 5
    ((attempt++))
  done
  err "所有下载尝试都失败了"
}

# =============================================================================
# 系统检测与环境准备
# =============================================================================

detect_architecture() {
  print_title "检测系统架构"
  ARCH=$(uname -m)
  case $ARCH in
    x86_64) MINICONDA_ARCH="x86_64"; ok "检测到系统架构: $ARCH" ;;
    aarch64|arm64) MINICONDA_ARCH="aarch64"; ok "检测到系统架构: $ARCH" ;;
    *) err "不支持的架构: $ARCH" ;;
  esac
}

detect_package_manager() {
  print_title "检测系统包管理器"
  if command_exists apt; then PACKAGE_MANAGER="apt"; ok "检测到 Debian/Ubuntu (apt)"
  elif command_exists yum; then PACKAGE_MANAGER="yum"; ok "检测到 Red Hat/CentOS (yum)"
  elif command_exists dnf; then PACKAGE_MANAGER="dnf"; ok "检测到 Fedora (dnf)"
  elif command_exists pacman; then PACKAGE_MANAGER="pacman"; ok "检测到 Arch Linux (pacman)"
  elif command_exists zypper; then PACKAGE_MANAGER="zypper"; ok "检测到 openSUSE (zypper)"
  else err "无法检测到支持的包管理器"; fi
}

install_system_dependencies() {
  print_title "安装系统依赖"
  local pkgs="redis tmux zip git curl wget tar jq screen"
  case $PACKAGE_MANAGER in
    apt) $SUDO apt update && $SUDO apt install -y $pkgs || err "依赖安装失败" ;;
    yum | dnf) $SUDO $PACKAGE_MANAGER install -y $pkgs || err "依赖安装失败" ;;
    pacman) $SUDO pacman -S --noconfirm $pkgs || err "依赖安装失败" ;;
    zypper) $SUDO zypper --non-interactive install $pkgs || err "依赖安装失败" ;;
  esac
  ok "系统依赖安装完成"
}

install_mamba_environment() {
  print_title "安装和配置 Mamba 环境 (Mambaforge)"
  [[ -d "$HOME/mambaforge/envs/Eridanus" ]] && ok "检测到 Mamba 环境 'Eridanus' 已存在" && return
  LATEST=$(curl -s "https://api.github.com/repos/conda-forge/miniforge/releases/latest" \
         | grep -oP '"tag_name":\s*"\K[^"]+')
  if [[ -z "$LATEST" ]]; then
    warn "未能获取最新 Mambaforge 版本号，使用固定版本"
    LATEST=25.3.1-0
  fi

  info "当前mamba版本号是 $LATEST"

  info "下载 Mambaforge 安装脚本..."
  local Micromamba_url="${GITHUB_PROXY}https://raw.githubusercontent.com/Astriora/Antlia/refs/heads/main/Script/Micromamba/Micromamba_install.sh"
  download_with_retry "$Micromamba_url" "Micromamba_install.sh"
  chmod +x Micromamba_install.sh
  ./Micromamba_install.sh --GITHUBPROXYURL="${GITHUB_PROXY}" --BIN_FOLDER="$HOME/bin" --INIT_YES=yes
  export PATH="$HOME/.local/bin:$PATH"

  info "运行 Mambaforge 安装脚本..."
  bash mambaforge.sh -b -p "$HOME/mambaforge" || err "Mambaforge 安装失败"
  rm -f mambaforge.sh

  info "初始化 Mamba..."
  source "$HOME/mambaforge/etc/profile.d/conda.sh"
  conda init --all || err "conda init 失败"
  source ~/.bashrc 2>/dev/null || true
  ok "Mamba 安装成功！"

  info "配置镜像源..."
  conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/ --prepend
  conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/ --prepend


  info "创建 Python 3.11 虚拟环境 (Eridanus)..."
  mamba create -n Eridanus python=3.11 -y || err "虚拟环境创建失败"
  source "$HOME/mambaforge/etc/profile.d/conda.sh"
  (conda activate Eridanus) || (source "$HOME/.bashrc" && conda activate Eridanus)

  info "安装图形库依赖 pycairo..."
  mamba install pycairo -y || warn "pycairo 安装失败，可能需要手动安装"
  ok "Mamba 环境配置完成"
}

# =============================================================================
# 项目安装
# =============================================================================

clone_eridanus() {
  print_title "克隆 Eridanus 项目"
  cd "$DEPLOY_DIR"
  [[ -d "Eridanus" ]] && read -p "是否删除并重新克隆? (y/n, 默认n): " del_choice && [[ "$del_choice" =~ ^[Yy]$ ]] && rm -rf "Eridanus" && ok "已删除旧的 Eridanus 文件夹"

  local repo_url="${GITHUB_PROXY}https://github.com/avilliai/Eridanus.git"
  info "开始克隆 Eridanus 仓库..."
  git clone --depth 1 "$repo_url" Eridanus || err "项目克隆失败"
  ok "Eridanus 项目克隆完成"
}

install_python_dependencies() {
  print_title "安装 Python 依赖"
  cd "$DEPLOY_DIR/Eridanus" || err "无法进入 Eridanus 目录"
  source "$HOME/mambaforge/etc/profile.d/conda.sh"
  conda activate Eridanus || source "$HOME/.bashrc" && conda activate Eridanus
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
  local pattern="linux-x64.*.tar.gz"
  [[ "$MINICONDA_ARCH" == "aarch64" ]] && pattern="linux-aarch64.*.tar.gz"

  local github_url
  github_url=$(curl -s "https://api.github.com/repos/LagrangeDev/Lagrange.Core/releases/tags/nightly" \
    | jq -r ".assets[] | select(.name | test(\"$pattern\")) | .browser_download_url")

  [[ -z "$github_url" ]] && err "无法动态获取 Lagrange 最新版本链接。"
  local download_url="${GITHUB_PROXY}${github_url}"
  download_with_retry "$download_url" "Lagrange.tar.gz"

  info "解压 Lagrange..."
  tar -xzf "Lagrange.tar.gz" || err "解压失败"

  local executable_path
  executable_path=$(find . -name "Lagrange.OneBot" -type f 2>/dev/null | head -1)
  [[ -z "$executable_path" ]] && err "未找到 Lagrange.OneBot 可执行文件"

  info "复制到目标目录..."
  cp "$executable_path" "$DEPLOY_DIR/Lagrange/Lagrange.OneBot" || err "复制失败"
  chmod +x "$DEPLOY_DIR/Lagrange/Lagrange.OneBot"

  cd "$DEPLOY_DIR/Lagrange"
  wget -O appsettings.json https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/appsettings/appsettings-Eridanus.json

  info "清理临时文件..."
  rm -rf "$TMP_DIR"
  ok "Lagrange 安装完成"
}

download_start_script() {
  local start_script_url="${GITHUB_PROXY}https://raw.githubusercontent.com/Astriora/Antlia/refs/heads/main/Script/Eridanus/start.sh"
  download_with_retry "$start_script_url" "start.sh"
  chmod +x start.sh
  ok "start.sh 下载并设置可执行权限完成"
}

# =============================================================================
# 主函数
# =============================================================================

main() {
  check_sudo
  print_title "Eridanus & Antlia 部署脚本 20250927"
  mkdir -p "$DEPLOY_DIR"
  cd "$SCRIPT_DIR" || exit
  select_github_proxy
  detect_architecture
  detect_package_manager
  install_system_dependencies
  install_lagrange
  install_mamba_environment
  clone_eridanus
  install_python_dependencies
  download_start_script
  print_title "🎉 部署完成! 🎉"
  echo "下一步: 请运行 './start.sh' 来启动和管理您的机器人服务。"
}

main
