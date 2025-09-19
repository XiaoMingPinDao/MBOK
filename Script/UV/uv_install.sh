#!/bin/bash
set -o pipefail

# 定义颜色
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'

info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
ok() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
err() { echo -e "${RED}[ERROR]${RESET} $1"; }

print_title() { echo -e "${BOLD}${CYAN}=== $1 ===${RESET}"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

download_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts=3
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        info "下载尝试 $attempt/$max_attempts: $url"
        if command_exists wget && wget -O "$output" "$url"; then
            ok "下载成功: $output"
            return 0
        elif command_exists curl && curl -L -o "$output" "$url" 2>/dev/null; then
            ok "下载成功: $output"
            return 0
        fi
        warn "第 $attempt 次下载失败"
        ((attempt++))
        sleep 5
    done
    return 1
}

parse_github_url() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --GITHUB-URL)
                if [[ -n "$2" && "$2" != --* ]]; then
                    GITHUB_PROXY="$2"
                    info "使用的代理地址: $GITHUB_PROXY"
                    shift 2
                else
                    GITHUB_PROXY=""
                    info "你没有定义代理地址，无代理"
                    shift 2
                fi
                ;;
            *)
                err "未知参数: $1"
                return 1
                ;;
        esac
    done
}

get_latest_version() {
    local api_url="${GITHUB_PROXY}https://api.github.com/repos/astral-sh/uv/releases/latest"
    local version

    info "获取 uv 最新版本信息..."
    if command_exists curl; then
        version=$(curl -s "$api_url" | grep '"tag_name"' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
    elif command_exists wget; then
        version=$(wget -qO- "$api_url" | grep '"tag_name"' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
    else
        warn "无法获取最新版本，使用默认版本 0.8.18"
        version="0.8.18"
    fi

    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        warn "获取的版本格式异常: $version，使用默认版本 0.8.18"
        version="0.8.18"
    fi
    info "获取到的最新版本: $version"
    echo "$version"
}

detect_system() {
    local arch os
    case "$(uname -m)" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        armv7*) arch="armv7" ;;
        armv6*) arch="arm" ;;
        i686) arch="i686" ;;
        powerpc64) arch="powerpc64" ;;
        powerpc64le) arch="powerpc64le" ;;
        riscv64) arch="riscv64gc" ;;
        s390x) arch="s390x" ;;
        *) err "不支持的架构: $(uname -m)"; return 1 ;;
    esac

    case "$(uname -s)" in
        Linux)
            if [ -f "/lib/ld-musl-x86_64.so.1" ] || [ -f "/lib/ld-musl-aarch64.so.1" ] || command -v musl-gcc >/dev/null 2>&1; then
                case "$arch" in
                    armv7|arm) os="unknown-linux-musleabihf" ;;
                    *) os="unknown-linux-musl" ;;
                esac
            else
                case "$arch" in
                    armv7) os="unknown-linux-gnueabihf" ;;
                    arm) os="unknown-linux-gnueabihf" ;;
                    *) os="unknown-linux-gnu" ;;
                esac
            fi
            ;;
        Darwin) os="apple-darwin" ;;
        *) err "不支持的操作系统: $(uname -s)"; return 1 ;;
    esac

    echo "${arch}-${os}"
}

build_download_url() {
    local version="$1"
    local target="$2"
    local filename="uv-${target}.tar.gz"
    echo "${GITHUB_PROXY}https://github.com/astral-sh/uv/releases/download/${version}/${filename}"
}

install_uv_binary() {
    local temp_dir="$1"
    local uv_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "uv-*" | head -n1)
    if [[ -z "$uv_dir" ]]; then
        warn "未找到 uv 目录"
        ls -la "$temp_dir"
        return 1
    fi

    cd "$uv_dir" || return 1
    if [ -f "uv" ]; then
        mkdir -p "$HOME/.local/bin"
        cp "uv" "$HOME/.local/bin/uv" && chmod +x "$HOME/.local/bin/uv"
        export PATH="$HOME/.local/bin:$PATH"
        "$HOME/.local/bin/uv" --version >/dev/null 2>&1 || return 1
        ok "uv 安装成功"
    else
        warn "uv 可执行文件不存在"
        ls -la
        return 1
    fi
}

download_and_install_uv() {
    local version=$(get_latest_version)
    local target=$(detect_system)
    local url=$(build_download_url "$version" "$target")
    local temp_dir="/tmp/uv_install_$$"
    mkdir -p "$temp_dir"
    trap 'rm -rf "$temp_dir"' EXIT

    info "系统架构: $target"
    info "下载地址: $url"

    cd "$temp_dir" || return 1
    if download_with_retry "$url" "uv.tar.gz"; then
        tar -xzf "uv.tar.gz" && install_uv_binary "$temp_dir"
    else
        warn "下载预编译包失败"
        return 1
    fi
}

install_uv_official_script() {
    info "使用官方安装脚本..."
    if command_exists curl; then
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
        command_exists uv || return 1
        ok "uv 通过官方脚本安装成功"
    else
        warn "无法安装 uv，请安装 curl 或手动安装"
        return 1
    fi
}

configure_uv_mirror() {
    uv pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/ 2>/dev/null || true
}

update_shell_config() {
    local path_export='export PATH="$HOME/.local/bin:$PATH"'
    local fish_path_set='set -gx PATH "$HOME/.local/bin" $PATH'

    [[ -f "$HOME/.bashrc" ]] && grep -qF "$path_export" "$HOME/.bashrc" || echo "$path_export" >> "$HOME/.bashrc"
    [[ -f "$HOME/.zshrc" ]] && grep -qF "$path_export" "$HOME/.zshrc" || echo "$path_export" >> "$HOME/.zshrc"
    
    local fish_config="$HOME/.config/fish/config.fish"
    mkdir -p "$(dirname "$fish_config")"
    [[ -f "$fish_config" ]] && grep -qF "$fish_path_set" "$fish_config" || echo "$fish_path_set" >> "$fish_config"
}

install_uv_environment() {
    print_title "安装和配置 uv 环境"

    if command_exists uv; then
        ok "uv 已安装"
    else
        info "开始安装 uv..."
        download_and_install_uv || install_uv_official_script || err "uv 安装失败"
    fi

    configure_uv_mirror
    update_shell_config
    ok "uv 环境配置完成"
}

main() {
    parse_github_url "$@"
    install_uv_environment
}

main "$@"
