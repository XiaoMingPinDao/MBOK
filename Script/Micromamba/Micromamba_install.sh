#!/bin/sh
set -eu

# ----------------------
# 默认参数
# ----------------------
GITHUB_PROXY=""
BIN_FOLDER="$HOME/.local/bin"
INIT_YES="yes"
CONDA_FORGE_YES="yes"
PREFIX_LOCATION="$HOME/micromamba"

# ----------------------
# 解析命令行参数
# ----------------------
for arg in "$@"; do
  case $arg in
    --GITHUBPROXYURL=*) GITHUB_PROXY="${arg#*=}"; shift ;;
    --BIN_FOLDER=*) BIN_FOLDER="${arg#*=}"; shift ;;
    --INIT_YES=*) INIT_YES="${arg#*=}"; shift ;;
    --CONDA_FORGE_YES=*) CONDA_FORGE_YES="${arg#*=}"; shift ;;
    --PREFIX_LOCATION=*) PREFIX_LOCATION="${arg#*=}"; shift ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ----------------------
# 交互选择 GitHub 代理（如果没传参数且是交互终端）
# ----------------------
if [ -z "$GITHUB_PROXY" ] && [ -t 0 ]; then
  echo "请选择 GitHub 下载代理："
  echo "1) ghfast.top"
  echo "2) ghproxy.net"
  echo "3) 不使用代理"
  read -p "#? " choice
  case "$choice" in
    1) GITHUB_PROXY="https://ghfast.top/" ;;
    2) GITHUB_PROXY="https://ghproxy.net/" ;;
    3) GITHUB_PROXY="" ;;
    *) GITHUB_PROXY="" ;;
  esac
fi

# ----------------------
# 检测父 shell
# ----------------------
parent=$(ps -o comm $PPID | tail -1)
parent=${parent#-}
case "$parent" in
  bash|fish|xonsh|zsh) shell=$parent ;;
  *) shell=${SHELL##*/} ;;
esac

# ----------------------
# 检测平台与架构
# ----------------------
PLATFORM=$(uname)
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="64" ;;
  aarch64|arm64|ppc64le) ;;  # 保持原样
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$PLATFORM" in
  Linux) PLATFORM="linux" ;;
  Darwin) PLATFORM="osx" ;;
  *NT*) PLATFORM="win" ;;
esac

# ----------------------
# 下载 URL
# ----------------------
RELEASE_URL="${GITHUB_PROXY}https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-${PLATFORM}-${ARCH}"

# ----------------------
# 下载并安装 micromamba
# ----------------------
mkdir -p "$BIN_FOLDER"
if hash curl >/dev/null 2>&1; then
  curl -# -fSL "$RELEASE_URL" -o "$BIN_FOLDER/micromamba"
elif hash wget >/dev/null 2>&1; then
  wget --progress=bar:force:noscroll -O "$BIN_FOLDER/micromamba" "$RELEASE_URL"
else
  echo "Neither curl nor wget was found" >&2
  exit 1
fi
chmod +x "$BIN_FOLDER/micromamba"

# ----------------------
# 初始化 shell
# ----------------------
if [ "$INIT_YES" = "yes" ]; then
  "$BIN_FOLDER/micromamba" shell init --shell "$shell" --root-prefix "$PREFIX_LOCATION"
  echo "请重启 shell 或运行 source ~/.bashrc (或对应 shell 配置文件)"
fi

# ----------------------
# 配置 conda-forge
# ----------------------
if [ "$CONDA_FORGE_YES" = "yes" ]; then
  "$BIN_FOLDER/micromamba" config append channels conda-forge
  "$BIN_FOLDER/micromamba" config append channels nodefaults
  "$BIN_FOLDER/micromamba" config set channel_priority strict
fi

echo "Micromamba 安装完成 "
