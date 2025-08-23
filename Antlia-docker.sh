#!/bin/bash
set -eux

# =============================================================================
# 配置
# =============================================================================
IMAGE="zhende1113/eridanus-docker-unofficial:latest"
CONTAINER="eridanus-docker"
DATA_DIR="$PWD/Eridanus-Docker"
PYENV_DIR="$HOME/antlia-venv"
LOG_DIR="$DATA_DIR/logs"

mkdir -p "$DATA_DIR" "$LOG_DIR"

# =============================================================================
# 包管理器检测
# =============================================================================
PKG_MANAGER="none"
for mgr in apt yum dnf pacman apk emerge zypper xbps-install brew; do
    command -v $mgr &>/dev/null && PKG_MANAGER=$mgr && break
done
echo "检测到包管理器: $PKG_MANAGER"

# =============================================================================
# 安装核心系统依赖
# =============================================================================
install_package() {
    local pkg="$1"
    case $PKG_MANAGER in
        apt) sudo apt update && sudo apt install -y "$pkg" ;;
        yum) sudo yum install -y "$pkg" ;;
        dnf) sudo dnf install -y "$pkg" ;;
        pacman) sudo pacman -S --noconfirm "$pkg" ;;
        apk) sudo apk add "$pkg" ;;
        emerge) sudo emerge --ask=n "$pkg" ;;
        zypper) sudo zypper install -y "$pkg" ;;
        xbps-install) sudo xbps-install -y "$pkg" ;;
        brew) brew install "$pkg" ;;
        *) echo "未知包管理器，建议手动安装 $pkg";;
    esac
}

for pkg in python3 python3-pip git docker; do
    command -v "$pkg" >/dev/null || install_package "$pkg"
done

# 启动 Docker 服务
if command -v systemctl &>/dev/null; then
    sudo systemctl enable docker || true
    sudo systemctl start docker || true
else
    sudo service docker start || true
fi

# 配置 Docker 国内镜像
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn/"]
}
EOF
if command -v systemctl &>/dev/null; then
    sudo systemctl restart docker || true
else
    sudo service docker restart || true
fi

# =============================================================================
# 拉取 Docker 镜像
# =============================================================================
docker pull "$IMAGE"

# =============================================================================
# 创建 Python 虚拟环境
# =============================================================================
python3 -m venv "$PYENV_DIR"
source "$PYENV_DIR/bin/activate"
pip install --upgrade pip
pip install ruamel.yaml colorlog

# =============================================================================
# 创建交互式启动脚本 antlia-start.sh
# =============================================================================
cat > antlia-start.sh <<'EOF'
#!/bin/bash
set -eux

IMAGE="zhende1113/eridanus-docker-unofficial:latest"
CONTAINER="eridanus-docker"
DATA_DIR="$PWD/Eridanus-Docker"
LOG_DIR="$DATA_DIR/logs"

mkdir -p "$DATA_DIR" "$LOG_DIR"

start() {
    if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER\$"; then
        echo "$CONTAINER 已存在，使用 restart"
        return
    fi
    docker run -d \
        --name "$CONTAINER" \
        -v "$DATA_DIR":/app/data \
        -p 5007:5007 \
        -p 6379:6379 \
        "$IMAGE"
    echo "$CONTAINER 已启动"
}

stop() {
    if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER\$"; then
        docker stop "$CONTAINER" && docker rm "$CONTAINER"
        echo "$CONTAINER 已停止"
    else
        echo "$CONTAINER 不存在"
    fi
}

restart() {
    stop
    start
}

logs() {
    local logfile="$LOG_DIR/$(date +%F).log"
    docker logs -f "$CONTAINER" | tee -a "$logfile"
}

update() {
    #echo "拉取最新镜像..."
    #docker pull "$IMAGE"
    #echo "重启容器..."
    #restart
    echo "执行 tool.py 更新..."
    docker exec "$CONTAINER" python /app/tool.py update
}

status() {
    docker ps -a --filter "name=$CONTAINER"
}

menu() {
    while true; do
        echo -e "\n================= Antlia Docker ================="
        echo "1) 启动容器"
        echo "2) 停止容器"
        echo "3) 重启容器"
        echo "4) 查看日志"
        echo "5) 更新容器"
        echo "6) 查看容器状态"
        echo "0) 退出"
        echo "================================================="
        read -rp "请选择操作: " choice
        case $choice in
            1) start ;;
            2) stop ;;
            3) restart ;;
            4) logs ;;
            5) update ;;
            6) status ;;
            0) echo "退出"; exit 0 ;;
            *) echo "无效选项";;
        esac
    done
}

menu
EOF

chmod +x antlia-start.sh

echo "部署完成，运行 ./antlia-start.sh 进入交互式菜单"
echo "数据目录: $DATA_DIR"