#!/bin/bash

# Eridanus Docker 管理脚本
# 支持生产模式和开发模式 (首次运行自动复制源码)

set -e

# =============================================================================
# 配置
# =============================================================================
# 容器和镜像名称
CONTAINER_NAME="eridanus-service"
IMAGE_NAME="zhende1113/eridanus-docker-unofficial:latest"

# 本地 Eridanus 源码路径 (脚本所在目录下的 Eridanus 文件夹)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_ERIDANUS_PATH="$SCRIPT_DIR/Eridanus"

# =============================================================================
# 日志函数
# =============================================================================
info() { echo "[INFO] $1"; }
ok() { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
err() { echo "[ERROR] $1"; exit 1; }

# =============================================================================
# 脚本功能
# =============================================================================

# 启动容器
start_container() {
    local dev_mode=false
    if [ "$1" == "--dev" ]; then
        dev_mode=true
    fi

    info "准备启动容器..."

    # 检查容器是否已在运行
    if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$\)" ]; then
        warn "容器 '$CONTAINER_NAME' 已经在运行中。"
        return
    fi

    # 检查是否存在已停止的同名容器，如果存在则删除
    if [ "$(docker ps -aq -f status=exited -f name=^/${CONTAINER_NAME}$\)" ]; then
        info "发现已停止的同名容器，正在删除..."
        docker rm "$CONTAINER_NAME" > /dev/null
    fi

    info "正在拉取最新镜像: $IMAGE_NAME..."
    docker pull "$IMAGE_NAME"

    local docker_run_cmd="docker run -d \
        --name \"$CONTAINER_NAME\" \
        --restart unless-stopped \
        -p 5007:5007"

    if [ "$dev_mode" = true ]; then
        info "以开发模式启动..."
        
        # 检查本地源码文件夹是否存在，如果不存在，则从镜像中复制
        if [ ! -d "$LOCAL_ERIDANUS_PATH" ]; then
            warn "本地源码目录 '$LOCAL_ERIDANUS_PATH' 不存在。"
            info "首次运行，正在从镜像中为您复制初始版本..."
            
            local temp_container_name="eridanus-temp-copy-$(date +%s)"
            # 创建一个临时容器
            docker create --name "$temp_container_name" "$IMAGE_NAME" > /dev/null
            # 从临时容器中复制文件到本地
            docker cp "$temp_container_name:/app/Eridanus" "$LOCAL_ERIDANUS_PATH"
            # 删除临时容器
            docker rm "$temp_container_name" > /dev/null
            
            ok "初始文件已成功复制到 '$LOCAL_ERIDANUS_PATH'"
            info "现在您可以修改文件夹内的配置文件，然后通过此脚本启动。"
        fi
        
        info "挂载本地路径: $LOCAL_ERIDANUS_PATH"
        docker_run_cmd="$docker_run_cmd -v \"$LOCAL_ERIDANUS_PATH:/app/Eridanus\""
    else
        info "以生产模式启动 (使用镜像内置代码)..."
    fi

    docker_run_cmd="$docker_run_cmd \"$IMAGE_NAME\""

    eval "$docker_run_cmd"

    ok "容器启动成功！使用 './$0 logs' 查看日志。"
}

# 停止容器
stop_container() {
    info "正在停止容器 '$CONTAINER_NAME' בו..."
    if [ ! "$(docker ps -q -f name=^/${CONTAINER_NAME}$\)" ]; then
        warn "容器 '$CONTAINER_NAME' 未在运行中。"
        # 如果需要，也可以删除已停止的容器
        if [ "$(docker ps -aq -f status=exited -f name=^/${CONTAINER_NAME}$\)" ]; then
            info "正在删除已停止的容器 בו..."
            docker rm "$CONTAINER_NAME" > /dev/null
            ok "已停止的容器已被删除 בו."
        fi
        return
    fi
    docker stop "$CONTAINER_NAME" > /dev/null
    docker rm "$CONTAINER_NAME" > /dev/null
    ok "容器已成功停止并移除 בו."
}

# 查看日志
view_logs() {
    info "正在查看容器 '$CONTAINER_NAME' 的日志... (按 Ctrl+C 退出)"
    docker logs -f "$CONTAINER_NAME"
}

# 进入容器
enter_container() {
    info "正在进入容器 '$CONTAINER_NAME' בו..."
    # Alpine 基础镜像是 sh，不是 bash
    docker exec -it "$CONTAINER_NAME" /bin/sh
}

# 执行更新工具
run_update() {
    info "在容器内执行 tool.py 更新 בו..."
    # 使用 venv 内的 python
    docker exec "$CONTAINER_NAME" /app/venv/bin/python /app/Eridanus/tool.py update
    ok "更新命令执行完毕 בו."
}

# 显示帮助信息
show_usage() {
    echo "Eridanus Docker 管理脚本"
    echo "---------------------------------"
    echo "用法: $0 [command]"
    echo
    echo "可用命令 בו:
    echo "  start         - 启动容器 (生产模式，使用镜像内置代码)"
    echo "  start --dev   - 启动容器 (开发模式，挂载本地 Eridanus 文件夹)"
    echo "                (如果本地文件夹不存在，会自动从镜像复制一份)"
    echo "  stop          - 停止并移除容器"
    echo "  logs          - 实时查看容器日志"
    echo "  shell         - 进入容器的交互式 Shell"
    echo "  update        - 在容器内执行 Eridanus 的 tool.py 更新脚本"
    echo
}

# =============================================================================
# 主逻辑
# =============================================================================

COMMAND="$1"
START_ARG="$2"

if [ -z "$COMMAND" ]; then
    show_usage
    exit 1
fi

case "$COMMAND" in
    start)
        start_container "$START_ARG"
        ;;
    stop)
        stop_container
        ;;
    logs)
        view_logs
        ;;
    shell)
        enter_container
        ;;
    update)
        run_update
        ;;
    *)
        err "无效命令: $COMMAND"
        show_usage
        ;;
esac
