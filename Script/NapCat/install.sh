#!/bin/bash
set -euo pipefail
USER="${USER:-$(whoami)}"

# ================================
# 颜色定义
# ================================
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'

# ================================
# 全局变量
# ================================
DEFAULT_INSTALL_DIR="$HOME/NapCat"
INSTALL_BASE_DIR=""
QQ_BASE_PATH=""
TARGET_FOLDER=""
QQ_EXECUTABLE=""
QQ_PACKAGE_JSON_PATH=""
NAPCAT_CONFIG=""

SUDO=""
FORCE_INSTALL="n"
PKG_MANAGER=""
DISTRO=""
SYSTEM_ARCH=""
GITHUB_PROXY=""

# ================================
# 日志函数
# ================================
info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
ok() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
err() { echo -e "${RED}[ERROR]${RESET} $1"; }
print_title() { echo -e "\n${BOLD}${CYAN}=== $1 ===${RESET}\n"; }

err_exit() {
    err "$1"
    cleanup
    exit 1
}

cleanup() {
    [[ -f ./package.json.tmp ]] && rm -f ./package.json.tmp
    [[ -f ./NapCat.Shell.zip ]] && rm -f ./NapCat.Shell.zip
    # 不删除用户安装目录，避免误删
    [[ -d /tmp/napcat_temp_* ]] && rm -rf /tmp/napcat_temp_*
}

# ================================
# 工具函数
# ================================
command_exists() { command -v "$1" >/dev/null 2>&1; }

confirm() {
    local prompt="$1"
    local response
    read -rp "$prompt [y/N]: " response
    [[ "$response" =~ ^[Yy]$ ]]
}

download_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        info "下载尝试 $attempt/$max_attempts: $url"
        if command_exists wget && wget -q --show-progress -O "$output" "$url"; then
            ok "下载成功: $output"
            return 0
        elif command_exists curl && curl -fL --progress-bar -o "$output" "$url"; then
            ok "下载成功: $output"
            return 0
        fi
        warn "第 $attempt 次下载失败"
        ((attempt++))
        [[ $attempt -le $max_attempts ]] && sleep 3
    done
    return 1
}

# ================================
# 权限检查
# ================================
check_root_or_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then
        warn "您当前以 root 身份运行脚本"
        SUDO=""
    else
        if command_exists sudo; then
            SUDO="sudo"
            [[ -n "${SUDO_USER:-}" ]] && warn "您当前在使用 sudo 运行脚本"
        else
           info "普通用户权限，"
        fi
    fi
}


prepare_dnf_repos() {
    info "准备 dnf 仓库..."

    # 安装 dnf-plugins-core 确保 config-manager 可用
    if ! rpm -q dnf-plugins-core >/dev/null 2>&1; then
        info "安装 dnf-plugins-core"
        $SUDO dnf install -y dnf-plugins-core
    fi

    # 检测系统类型并安装 epol/epel
    if [ -f "/etc/opencloudos-release" ]; then
        os_version=$(grep -oE '[0-9]+' /etc/opencloudos-release | head -n1)
        if [[ -n "$os_version" && "$os_version" -ge 9 ]]; then
            info "检测到 OpenCloudOS 9+, 安装 epol-release..."
            $SUDO dnf install -y epol-release
        else
            info "OpenCloudOS <9 或无法检测版本, 安装 epel-release..."
            $SUDO dnf install -y epel-release
        fi
    elif [ -f "/etc/fedora-release" ]; then
        info "检测到 Fedora 系统, 默认使用 Fedora 仓库"
    else
        info "非 OpenCloudOS/Fedora 的 EL 系统, 安装 epel-release..."
        $SUDO dnf install -y epel-release
    fi

    # 启用 AppStream 仓库
    if dnf repolist all | grep -q '^appstream\s'; then
        if dnf repolist disabled | grep -q '^appstream\s'; then
            info "启用 AppStream 仓库"
            $SUDO dnf config-manager --set-enabled appstream
        else
            info "AppStream 仓库已启用"
        fi
    else
        info "未检测到 AppStream 仓库，依赖可能不完整"
    fi

    # 刷新缓存
    info "刷新 dnf 缓存"
    $SUDO dnf makecache --refresh
}





# ================================
# 系统检测
# ================================
get_system_arch() {
    SYSTEM_ARCH=$(uname -m)
    case "$SYSTEM_ARCH" in
        x86_64) SYSTEM_ARCH="amd64" ;;
        aarch64) SYSTEM_ARCH="arm64" ;;
        *) err_exit "不支持的架构: $SYSTEM_ARCH" ;;
    esac
    info "系统架构: $SYSTEM_ARCH"
}

detect_package_manager() {
    info "检测包管理器..."
    local managers=("apt:Debian/Ubuntu" "pacman:Arch Linux" "dnf:Fedora/RHEL9+" "yum:RHEL/CentOS" "zypper:openSUSE")
    
    for manager_info in "${managers[@]}"; do
        local manager="${manager_info%%:*}"
        local distro="${manager_info##*:}"
        if command_exists "$manager"; then
            PKG_MANAGER="$manager"
            DISTRO="$distro"
            ok "检测到包管理器: $PKG_MANAGER ($DISTRO)"
            return 0
        fi
    done
    err_exit "未检测到支持的包管理器"
}

# ================================
# 系统依赖安装
# ================================
install_system_dependencies() {
    print_title "安装系统依赖"

    local has_desktop=false
    # 检测桌面环境
    if [[ -n "${DISPLAY:-}" ]]; then
        has_desktop=true
    else
        for proc in gnome-shell plasmashell xfce4-session mate-session; do
            if pgrep -x "$proc" >/dev/null 2>&1; then
                has_desktop=true
                break
            fi
        done
    fi

    if $has_desktop; then
        warn "检测到桌面环境，某些库将使用标准版本"
    fi

    case $PKG_MANAGER in
        apt)
            $SUDO apt update -qq
            local base_pkgs=(zip unzip jq curl xvfb xauth procps screen)
            local dyn_pkgs=(libglib2.0-0 libatk1.0-0 libatspi2.0-0 libgtk-3-0 libasound2)
            local resolved_pkgs=()

            for pkg_base in "${dyn_pkgs[@]}"; do
                local t64_variant="${pkg_base}t64"
                if ! $has_desktop && apt-cache show "$t64_variant" >/dev/null 2>&1; then
                    resolved_pkgs+=("$t64_variant")
                else
                    resolved_pkgs+=("$pkg_base")
                fi
            done

            $SUDO apt install -y "${base_pkgs[@]}" "${resolved_pkgs[@]}"
            ;;

        pacman)
            if confirm "要更新整个系统吗？(pacman -Syu)"; then
                $SUDO pacman -Syu --noconfirm
            fi
            $SUDO pacman -S --needed --noconfirm tmux tar gzip unzip zip jq \
                xorg-server-xvfb xorg-xauth procps-ng curl \
                nss alsa-lib gtk3 gjs at-spi2-core libvips openjpeg2 openslide dpkg
            ;;

        zypper)
            $SUDO zypper refresh
            $SUDO zypper install -y tmux tar gzip unzip zip jq \
                xorg-x11-server-Xvfb xauth procps curl \
                mozilla-nss libasound2 libgtk-3-0 gjs at-spi2-core cpio
            ;;

        dnf|yum)
            [[ "$PKG_MANAGER" == "dnf" ]] && prepare_dnf_repos
            $SUDO $PKG_MANAGER install -y tmux tar gzip unzip zip jq \
                xorg-x11-server-Xvfb xorg-x11-xauth procps-ng curl \
                nss mesa-libgbm atk at-spi2-atk gtk3 alsa-lib pango cairo \
                libdrm libXcursor libXrandr libXdamage libXcomposite libXfixes \
                libXrender libXi libXtst libXScrnSaver cups-libs libxkbcommon
            ;;

        *)
            err_exit "未知包管理器: $PKG_MANAGER"
            ;;
    esac

    ok "系统依赖安装完成"
}


check_dependencies() {
    local deps=(jq unzip curl  xauth tmux)
    command_exists dpkg && deps+=(dpkg)
    command_exists rpm2cpio && deps+=(cpio rpm2cpio)
    
    for cmd in "${deps[@]}"; do
        command_exists "$cmd" || err_exit "$cmd 未安装，请先安装系统依赖"
    done
}


# ================================
# 安装目录配置
# ================================
setup_install_paths() {
    print_title "配置安装目录"

    local real_user="${SUDO_USER:-$USER}"
    local home_dir
    home_dir=$(eval echo "~$real_user")

    # 直接使用默认安装目录，无需交互
    INSTALL_BASE_DIR="$home_dir/NapCat"
    QQ_BASE_PATH="$INSTALL_BASE_DIR/opt/QQ"
    TARGET_FOLDER="$QQ_BASE_PATH/resources/app/app_launcher"
    QQ_EXECUTABLE="$QQ_BASE_PATH/qq"
    QQ_PACKAGE_JSON_PATH="$QQ_BASE_PATH/resources/app/package.json"
    NAPCAT_CONFIG="$TARGET_FOLDER/napcat/config"

    info "安装目录: $INSTALL_BASE_DIR"

    # 如果强制安装模式，删除旧目录
    [[ -d "$INSTALL_BASE_DIR" && "$FORCE_INSTALL" == "y" ]] && rm -rf "$INSTALL_BASE_DIR"
    mkdir -p "$INSTALL_BASE_DIR"
}


# ================================
# LinuxQQ 安装
# ================================
install_linuxqq() {
    print_title "安装 LinuxQQ"
    
    local qq_version="3.2.19-39038"
    local base_url="https://dldir1.qq.com/qqfile/qq/QQNT/c773cdf7"
    local url file_name
    local use_rpm=false

    mkdir -p "$INSTALL_BASE_DIR"

    if command_exists rpm2cpio && command_exists cpio; then
        use_rpm=true
        info "检测到 rpm2cpio 和 cpio，将使用 RPM 包"
    elif command_exists dpkg; then
        info "检测到 dpkg，将使用 DEB 包"
    else
        err_exit "未找到 dpkg 或 rpm2cpio+cpio，无法解压 QQ 安装包"
    fi
    
    if $use_rpm; then
        case "$SYSTEM_ARCH" in
            amd64) url="$base_url/linuxqq_${qq_version}_x86_64.rpm" ;;
            arm64) url="$base_url/linuxqq_${qq_version}_aarch64.rpm" ;;
        esac
    else
        case "$SYSTEM_ARCH" in
            amd64) url="$base_url/linuxqq_${qq_version}_amd64.deb" ;;
            arm64) url="$base_url/linuxqq_${qq_version}_arm64.deb" ;;
        esac
    fi
    
    file_name=$(basename "$url")
    info "下载 LinuxQQ: $file_name"
    info "下载地址: $url"

    if [[ -f "$INSTALL_BASE_DIR/$file_name" ]]; then
        info "使用安装目录已有包: $INSTALL_BASE_DIR/$file_name"
    elif [[ -f "$file_name" ]]; then
        info "复制本地文件到安装目录"
        cp "$file_name" "$INSTALL_BASE_DIR/"
    else
        download_with_retry "$url" "$INSTALL_BASE_DIR/$file_name" || err_exit "LinuxQQ 下载失败"
    fi

    info "文件大小: $(( $(stat -c%s "$INSTALL_BASE_DIR/$file_name") / 1024 / 1024 )) MB"

    info "解压到: $INSTALL_BASE_DIR"
    if $use_rpm; then
        info "使用 rpm2cpio 解压 RPM 包..."
        (cd "$INSTALL_BASE_DIR" && rpm2cpio "$INSTALL_BASE_DIR/$file_name" | cpio -idmv) || err_exit "解压 RPM 失败"
    else
        info "使用 dpkg 解压 DEB 包..."
        dpkg -x "$INSTALL_BASE_DIR/$file_name" "$INSTALL_BASE_DIR" || err_exit "解压 DEB 失败"
    fi

    [[ -f "$QQ_EXECUTABLE" ]] || err_exit "LinuxQQ 安装失败: $QQ_EXECUTABLE 不存在"
    ok "LinuxQQ 安装完成"
    info "QQ 可执行文件: $QQ_EXECUTABLE"
}

# ================================
# NapCat 安装
# ================================
install_napcat() {
    print_title "安装 NapCat"

    local napcat_zip="NapCat.Shell.zip"
    local download_url="${GITHUB_PROXY}https://github.com/NapNeko/NapCatQQ/releases/latest/download/$napcat_zip"
    local temp_dir="/tmp/napcat_temp_$$"

    [[ -f "$napcat_zip" ]] || download_with_retry "$download_url" "$napcat_zip" || err_exit "NapCat 下载失败"

    mkdir -p "$temp_dir"
    unzip -q -o "$napcat_zip" -d "$temp_dir" || err_exit "NapCat 解压失败"

    local napcat_source=""
    if [[ -d "$temp_dir/opt/QQ/resources/app/app_launcher/napcat" ]]; then
        napcat_source="$temp_dir/opt/QQ/resources/app/app_launcher/napcat"
    elif [[ -d "$temp_dir/napcat" ]]; then
        napcat_source="$temp_dir/napcat"
    elif [[ -f "$temp_dir/napcat.mjs" ]]; then
        napcat_source="$temp_dir"
    else
        err_exit "未找到 NapCat 文件，解压结构异常"
    fi

    mkdir -p "${TARGET_FOLDER}/napcat"
    cp -r "$napcat_source"/* "${TARGET_FOLDER}/napcat/" || err_exit "NapCat 文件复制失败"
    chmod -R +x "${TARGET_FOLDER}/napcat/"

    rm -rf "$temp_dir"

    cat > "${QQ_BASE_PATH}/resources/app/loadNapCat.js" <<'EOF'
(async () => {
    await import('file:///' + __dirname + '/app_launcher/napcat/napcat.mjs');
})();
EOF

    jq '.main="./loadNapCat.js"' "$QQ_PACKAGE_JSON_PATH" > ./package.json.tmp && \
        mv ./package.json.tmp "$QQ_PACKAGE_JSON_PATH" || err_exit "package.json 修改失败"

    ok "NapCat 安装完成"
}

# ================================
# 使用说明
# ================================
show_usage() {
    print_title "安装完成"
    cat <<EOF
${GREEN}所有组件安装完成！${RESET}

${BOLD}启动方式：${RESET}
1. 直接运行: $HOME/start_napcat.sh
2. 或者: cd $QQ_BASE_PATH && ./qq

${BOLD}配置文件位置：${RESET}
- NapCat 配置: $NAPCAT_CONFIG
- QQ 数据目录: $HOME/.config/QQ

${BOLD}日志查看：${RESET}
- NapCat 日志会输出到终端

${YELLOW}注意事项：${RESET}
- 首次启动需要扫码登录
- 建议在配置文件中设置你的机器人参数
- 如需卸载，删除 $INSTALL_BASE_DIR 即可
EOF
}

# ================================
# 主程序
# ================================
main() {
    print_title "LinuxQQ + NapCat 自动安装脚本"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                FORCE_INSTALL="y"
                info "强制安装模式"
                shift
                ;;
            --github-proxy)
                GITHUB_PROXY="$2"
                info "使用 GitHub 代理: $GITHUB_PROXY"
                shift 2
                ;;
            --help|-h)
                echo "用法: $0 [选项]"
                echo "选项:"
                echo "  --force, -f              强制覆盖安装"
                echo "  --github-proxy <URL>     使用 GitHub 代理"
                echo "  --help, -h               显示此帮助信息"
                exit 0
                ;;
            *)
                err "未知参数: $1"
                exit 1
                ;;
        esac
    done

    check_root_or_sudo
    detect_package_manager
    get_system_arch
    install_system_dependencies
    check_dependencies
    setup_install_paths
    install_linuxqq
    install_napcat

    cleanup
    show_usage
}

main "$@"
