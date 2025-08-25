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
IMAGE="zhende1113/antlia:latest"
CONTAINER_NAME="antlia-prod"
VOLUME_NAME="antlia-bot-data"

case "$1" in
    start)
        echo "[启动] 容器 $CONTAINER_NAME"
        docker run -d \
            --name $CONTAINER_NAME \
            -v $VOLUME_NAME:/app/bot \
            -p 5007:5007 \
            --restart always \
            $IMAGE
        ;;
    stop)
        echo "[停止] 容器 $CONTAINER_NAME"
        docker stop $CONTAINER_NAME
        docker rm $CONTAINER_NAME
        ;;
    exec)
        echo "[进入容器] $CONTAINER_NAME"
        docker exec -it $CONTAINER_NAME /bin/bash
        ;;
    run)
        echo "[执行] start.sh"
        docker exec -it $CONTAINER_NAME bash /app/start.sh
        ;;
    logs)
        echo "[日志] $CONTAINER_NAME"
        docker logs -f $CONTAINER_NAME
        ;;
    *)
        echo "用法: sudo ./Antlia-docker.sh {start|stop|exec|run|logs}"
        ;;
esac
EOF

chmod +x Antlia-docker.sh
echo "[完成] 部署成功，使用 ./Antlia-docker.sh 管理容器"
