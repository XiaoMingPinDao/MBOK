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
# Antlia Docker 管理面板 - 增强版
# 版本: 2025/08/25
set -o pipefail

# =============================================================================
# 常量与变量
# =============================================================================
CONTAINER_NAME="antlia-prod"
ERIDANUS_PATH="/app"
BOT_PATH="/app/bot"
CURRENT_USER=$(whoami)
# 宿主机挂载目录
HOST_DATA_DIR="$(pwd)/Antlia-Docker-DATA"

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
    echo " Antlia Docker 管理面板 2025/08/25"
    echo " 用户: $CURRENT_USER | $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================"
}

hr() { echo "================================================"; }
info() { echo "[INFO] $1"; }
ok() { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
err() { echo "[ERROR] $1"; }
pause() { read -rp "按 Enter 键返回菜单..."; }

# 检查容器是否存在
check_container_exists() {
    if ! $DOCKER_CMD ps -a --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
        err "容器 $CONTAINER_NAME 不存在"
        return 1
    fi
    return 0
}

# 检查容器是否运行
check_container_running() {
    if ! $DOCKER_CMD ps --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
        err "容器 $CONTAINER_NAME 未运行"
        return 1
    fi
    return 0
}

# =============================================================================
# 文件挂载管理函数
# =============================================================================
setup_host_directory() {
    if [[ ! -d "$HOST_DATA_DIR" ]]; then
        info "创建宿主机数据目录: $HOST_DATA_DIR"
        mkdir -p "$HOST_DATA_DIR"
        ok "目录创建成功"
    else
        info "宿主机数据目录已存在: $HOST_DATA_DIR"
    fi
}

mount_bot_files() {
    check_container_exists || return 1
    check_container_running || return 1
    
    setup_host_directory
    
    info "正在同步容器内 $BOT_PATH 到宿主机 $HOST_DATA_DIR ..."
    
    # 首先清空宿主机目录（可选）
    read -rp "是否清空宿主机目录后同步? [y/N]: " clear_host
    if [[ "$clear_host" == [yY] ]]; then
        sudo rm -rf "${HOST_DATA_DIR:?}"/*
        # 危险不要乱改
        info "已清空宿主机目录"
    fi
    
    # 从容器复制文件到宿主机
    $DOCKER_CMD cp "$CONTAINER_NAME:$BOT_PATH/." "$HOST_DATA_DIR/"
    
    if [[ $? -eq 0 ]]; then
        ok "文件同步完成"
        ok "宿主机路径: $HOST_DATA_DIR"
        ok "容器路径: $BOT_PATH"
        echo
        info "现在您可以直接编辑 $HOST_DATA_DIR 中的文件"
        info "编辑完成后使用选项 '8' 将文件同步回容器"
    else
        err "文件同步失败"
    fi
}

sync_to_container() {
    check_container_exists || return 1
    check_container_running || return 1
    
    if [[ ! -d "$HOST_DATA_DIR" ]]; then
        err "宿主机数据目录不存在: $HOST_DATA_DIR"
        err "请先使用选项 '9' 挂载文件"
        return 1
    fi
    
    info "正在将宿主机 $HOST_DATA_DIR 同步到容器 $BOT_PATH ..."
    
    # 备份容器内原始文件（可选）
    read -rp "是否先备份容器内原始文件? [Y/n]: " backup_original
    if [[ "$backup_original" != [nN] ]]; then
        timestamp=$(date +"%Y%m%d_%H%M%S")
        backup_name="bot_backup_$timestamp.tar.gz"
        $DOCKER_CMD exec "$CONTAINER_NAME" tar czf "/tmp/$backup_name" -C "$BOT_PATH" . 2>/dev/null
        if [[ $? -eq 0 ]]; then
            ok "已创建容器内备份: /tmp/$backup_name"
        fi
    fi
    
    # 将宿主机文件同步到容器
    $DOCKER_CMD cp "$HOST_DATA_DIR/." "$CONTAINER_NAME:$BOT_PATH/"
    
    if [[ $? -eq 0 ]]; then
        ok "文件同步到容器完成"
        
        # 询问是否重启容器以应用更改
        read -rp "是否重启容器以应用更改? [Y/n]: " restart_confirm
        if [[ "$restart_confirm" != [nN] ]]; then
            restart_container
        fi
    else
        err "文件同步到容器失败"
    fi
}


show_mount_status() {
    info "文件挂载状态信息:"
    echo "  容器名称: $CONTAINER_NAME"
    echo "  容器路径: $BOT_PATH"
    echo "  宿主机路径: $HOST_DATA_DIR"
    echo
    
    if [[ -d "$HOST_DATA_DIR" ]]; then
        ok "宿主机目录存在"
        echo "  文件数量: $(find "$HOST_DATA_DIR" -type f 2>/dev/null | wc -l)"
        echo "  目录大小: $(du -sh "$HOST_DATA_DIR" 2>/dev/null | cut -f1)"
    else
        warn "宿主机目录不存在"
    fi
    
    if check_container_running; then
        info "容器运行状态: 运行中"
        container_files=$($DOCKER_CMD exec "$CONTAINER_NAME" find "$BOT_PATH" -type f 2>/dev/null | wc -l)
        echo "  容器内文件数量: $container_files"
    else
        warn "容器运行状态: 未运行"
    fi
}





# =============================================================================
# 原有容器管理函数
# =============================================================================
start_container() {
    info "正在启动容器 $CONTAINER_NAME ..."
    
    # 尝试启动容器
    if $DOCKER_CMD start "$CONTAINER_NAME" 2>/dev/null; then
        ok "容器 $CONTAINER_NAME 已启动"
        return 0
    fi
    
    # 启动失败，获取详细错误信息
    local error_output
    error_output=$($DOCKER_CMD start "$CONTAINER_NAME" 2>&1)
    err "容器启动失败"
    
    # 检查是否是端口占用问题
    if [[ "$error_output" =~ "address already in use" ]]; then
        # 提取端口号
        local port
        port=$(echo "$error_output" | grep -o ":[0-9]\+:" | head -1 | tr -d ':')
        
        if [[ -n "$port" ]]; then
            warn "检测到端口 $port 被占用"
            echo
            check_port_usage "$port"
            echo
            
            read -rp "是否尝试自动释放端口 $port? [Y/n]: " auto_kill
            if [[ "$auto_kill" != [nN] ]]; then
                if kill_port_process "$port"; then
                    info "重新尝试启动容器..."
                    if $DOCKER_CMD start "$CONTAINER_NAME" 2>/dev/null; then
                        ok "容器 $CONTAINER_NAME 已启动"
                        return 0
                    fi
                fi
            fi
        fi
        
        echo
        err "端口冲突解决方案："
        echo "  1. 手动停止占用端口的进程"
        echo "  2. 或运行: sudo fuser -k $port/tcp"
        echo "  3. 然后重新启动容器"
    else
        echo
        err "启动错误详情:"
        echo "$error_output"
    fi
    
    return 1
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
    check_container_running || return 1
    info "进入容器 $CONTAINER_NAME shell ..."
    info "提示: 使用 exit 命令退出容器 shell"
    info "提示: 脚本启动命令 bash /app/start.sh 或者 ./start.sh"
    $DOCKER_CMD exec -it "$CONTAINER_NAME" bash
}

backup_volume() {
    check_container_running || return 1
    
    read -rp "请输入备份文件名 (例如 backup.tar.gz): " BACKUP_FILE
    
    # 检查文件是否已存在
    if [[ -f "$BACKUP_FILE" ]]; then
        read -rp "文件已存在，是否覆盖? [y/N]: " overwrite
        [[ "$overwrite" != [yY] ]] && return
    fi
    
    info "备份数据卷..."
    $DOCKER_CMD exec "$CONTAINER_NAME" tar czf "/tmp/$BACKUP_FILE" -C "$ERIDANUS_PATH" .
    $DOCKER_CMD cp "$CONTAINER_NAME:/tmp/$BACKUP_FILE" .
    $DOCKER_CMD exec "$CONTAINER_NAME" rm "/tmp/$BACKUP_FILE"  # 清理临时文件
    ok "已备份至本地文件 $BACKUP_FILE"
}

restore_volume() {
    check_container_running || return 1
    
    read -rp "请输入要恢复的备份文件名: " BACKUP_FILE
    if [[ ! -f "$BACKUP_FILE" ]]; then
        err "文件不存在: $BACKUP_FILE"
        return
    fi
    
    warn "恢复操作将覆盖容器内现有数据！"
    read -rp "确认继续? [y/N]: " confirm
    [[ "$confirm" != [yY] ]] && return
    
    $DOCKER_CMD cp "$BACKUP_FILE" "$CONTAINER_NAME:/tmp/$BACKUP_FILE"
    info "正在恢复数据卷..."
    $DOCKER_CMD exec "$CONTAINER_NAME" tar xzf "/tmp/$BACKUP_FILE" -C "$ERIDANUS_PATH"
    $DOCKER_CMD exec "$CONTAINER_NAME" rm "/tmp/$BACKUP_FILE"  # 清理临时文件
    ok "数据恢复完成"
}

# =============================================================================
# 主菜单
# =============================================================================
main_menu() {
    while true; do
        print_header
        echo "容器: $CONTAINER_NAME"
        if check_container_running; then
            echo "状态: 运行中"
        else
            echo "状态: 未运行"
        fi
        echo "=== 容器管理 ==="
        echo "1. 启动容器"
        echo "2. 停止容器"
        echo "3. 重启容器"
        echo "4. ⭐进入容器手动执行启动脚本⭐"
        echo "5. 备份数据卷"
        echo "6. 恢复数据卷"
        echo
        echo "=== 文件挂载管理 ==="
        echo "7. 挂载 /app/bot 到宿主机"
        echo "8. 同步宿主机文件到容器"
        echo "9. 查看挂载状态"
        echo
        echo "=== 容器管理 ==="
        echo "10. 创建容器第一次必用"
        echo "11. 删除容器 危险会丢数据"

        echo
        echo "q. 退出脚本"
        hr
        read -rp "请选择操作 [1-11/q]: " choice
        
        case $choice in
            1) start_container; pause ;;
            2) stop_container; pause ;;
            3) restart_container; pause ;;
            4) enter_shell ;;
            5) backup_volume; pause ;;
            6) restore_volume; pause ;;
            7) mount_bot_files; pause ;;
            8) sync_to_container; pause ;;
            9) show_mount_status; pause ;;
            10) 
                sudo docker run -d \
  --name antlia-prod \
  -p 5007:5007 \
  --restart unless-stopped \
  zhende1113/antlia:latest

                ok "容器已创建"
                pause
                ;;
            11)
                #show_container_ports
                check_container_exists && $DOCKER_CMD stop antlia-prod
                sudo docker rm -v antlia-prod
                ok "容器已删除"
                pause
                ;;
            114514)
                echo "人机"
                pause
                ;;
            q|0) exit 0 ;;
            *) warn "无效输入"; sleep 1 ;;
        esac
    done
}

# =============================================================================
# 脚本入口
# =============================================================================
main_menu

EOF

chmod +x Antlia-docker.sh
echo "[完成] 部署成功，使用 ./Antlia-docker.sh 管理容器"
