#!/bin/bash
set -e

IMAGE="zhende1113/antlia"
CONTAINER_NAME="antlia"
HOST_DIR="$(pwd)/Antlia-Docker"
CONTAINER_DIR="/app/bot"

echo "=== Antlia Docker 部署脚本 ==="

# 检查 docker
if ! command -v docker &> /dev/null; then
    echo "[提示] 未检测到 Docker，是否安装？ (y/n)"
    read -r choice
    if [[ "$choice" == "y" ]]; then
        if [[ -f /etc/debian_version ]]; then
            sudo apt update && sudo apt install -y docker.io
        elif [[ -f /etc/redhat-release ]]; then
            sudo yum install -y docker
        elif [[ -f /etc/arch-release ]]; then
            sudo pacman -S --noconfirm docker
        else
            echo "[错误] 未知发行版，请手动安装 Docker"
            exit 1
        fi
        sudo systemctl enable --now docker
    else
        echo "[退出] 请先安装 Docker"
        exit 1
    fi
fi

# 是否配置国内源
echo "[提示] 是否配置国内 Docker Hub 镜像加速？ (y/n)"
read -r accelerate
if [[ "$accelerate" == "y" ]]; then
    sudo mkdir -p /etc/docker
    cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://mirror.ccs.tencentyun.com",
    "https://hub-mirror.c.163.com",
    "https://registry.docker-cn.com"
  ]
}
EOF
    sudo systemctl restart docker
    echo "[OK] 已配置国内源"
fi

# 创建数据目录
mkdir -p "$HOST_DIR"

# 拉取镜像
echo "[信息] 拉取镜像 $IMAGE..."
sudo docker pull "$IMAGE"

# 生成启动脚本
cat > Antlia-docker.sh <<'EOF'
#!/bin/bash
# Antlia Docker 管理面板 - 精简版
# 版本: 2025/08/25

set -o pipefail

# =============================================================================
# 常量与变量
# =============================================================================
CONTAINER_NAME="antlia-prod"
ERIDANUS_PATH="/app"
CURRENT_USER=$(whoami)

# 自动检测 docker 命令权限
DOCKER_CMD="docker"
if ! docker info &>/dev/null; then
    if command -v sudo &>/dev/null; then
        echo "[INFO] 当前用户无法直接访问 Docker，已切换为 sudo 执行"
        DOCKER_CMD="sudo docker"
    else
        echo "[ERROR] 当前用户无法访问 Docker，也无法使用 sudo"
        exit 1
    fi
fi

# =============================================================================
# 工具函数
# =============================================================================
print_header() {
    clear
    echo "================================================"
    echo "               Antlia Docker 管理面板"
    echo "       用户: $CURRENT_USER | $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================"
}

hr() { echo "================================================"; }

info() { echo "[INFO] $1"; }
ok() { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
err() { echo "[ERROR] $1"; }

pause() { read -rp "按 Enter 键返回菜单..."; }

# =============================================================================
# 容器管理函数
# =============================================================================
start_container() {
    info "正在启动容器 $CONTAINER_NAME ..."
    $DOCKER_CMD start "$CONTAINER_NAME"
    ok "容器 $CONTAINER_NAME 已启动"
}

stop_container() {
    info "正在停止容器 $CONTAINER_NAME ..."
    $DOCKER_CMD stop "$CONTAINER_NAME"
    ok "容器 $CONTAINER_NAME 已停止"
}

restart_container() {
    info "正在重启容器 $CONTAINER_NAME ..."
    $DOCKER_CMD restart "$CONTAINER_NAME"
    ok "容器 $CONTAINER_NAME 已重启"
}

enter_shell() {
    info "进入容器 $CONTAINER_NAME shell ..."
    $DOCKER_CMD exec -it "$CONTAINER_NAME" bash
}

view_logs() {
    info "查看容器 $CONTAINER_NAME 日志 ..."
    $DOCKER_CMD logs -f "$CONTAINER_NAME"
}

backup_volume() {
    read -rp "请输入备份文件名 (例如 backup.tar.gz): " BACKUP_FILE
    info "备份数据卷..."
    $DOCKER_CMD exec "$CONTAINER_NAME" tar czf "/tmp/$BACKUP_FILE" -C "$ERIDANUS_PATH" .
    $DOCKER_CMD cp "$CONTAINER_NAME:/tmp/$BACKUP_FILE" .
    ok "已备份至本地文件 $BACKUP_FILE"
}

restore_volume() {
    read -rp "请输入要恢复的备份文件名: " BACKUP_FILE
    if [[ ! -f "$BACKUP_FILE" ]]; then
        err "文件不存在"
        return
    fi
    $DOCKER_CMD cp "$BACKUP_FILE" "$CONTAINER_NAME:/tmp/$BACKUP_FILE"
    info "正在恢复数据卷..."
    $DOCKER_CMD exec "$CONTAINER_NAME" tar xzf "/tmp/$BACKUP_FILE" -C "$ERIDANUS_PATH"
    ok "数据恢复完成"
}

# =============================================================================
# 主菜单
# =============================================================================
main_menu() {
    while true; do
        print_header
        echo "  1. 启动容器"
        echo "  2. 停止容器"
        echo "  3. 重启容器"
        echo "  4. 执行 /app/eridanus-start.sh"
        echo "  5. 进入容器 Shell"
        echo "  6. 查看日志"
        echo "  7. 备份数据卷"
        echo "  8. 恢复数据卷"
        echo "  q. 退出脚本"
        hr
        read -rp "请选择操作 [1-8/q]: " choice
        case $choice in
            1) start_container; pause ;;
            2) stop_container; pause ;;
            3) restart_container; pause ;;
            4) $DOCKER_CMD exec -d "$CONTAINER_NAME" bash -c "cd $ERIDANUS_PATH && ./eridanus-start.sh"; ok "执行完成"; pause ;;
            5) enter_shell ;;
            6) view_logs ;;
            7) backup_volume ;;
            8) restore_volume ;;
            q|Q) exit 0 ;;
            *) warn "无效输入"; sleep 1 ;;
        esac
    done
}

# =============================================================================
# 脚本入口
# =============================================================================
main() {
    main_menu
}

main

EOF

chmod +x Antlia-docker.sh
echo "[完成] 部署成功，使用 ./Antlia-docker.sh 管理容器"
