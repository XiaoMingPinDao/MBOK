<<<<<<< HEAD
# Antlia 轻量化 Dockerfile
# 使用 Alpine Linux 和一个 独立的部署脚本

# 1. 基础镜像
# 使用官方的 Python 3.11 Alpine 镜像，非常轻量
FROM python:3.11-alpine

# 2. 设置工作目录
WORKDIR /app

# 3. 复制部署脚本
# 脚本将负责克隆源码和安装所有依赖
COPY docker-deploy.sh .

# 4. 执行部署脚本
# 赋予脚本执行权限，然后运行它
RUN chmod +x docker-deploy.sh && \
    ./docker-deploy.sh

# 5. 设置环境变量和端口
ENV TZ=Asia/Shanghai
EXPOSE 5007

# 6. 设置启动命令
# 注意：这里的 python 来自于脚本创建的 venv 虚拟环境
CMD ["/app/venv/bin/python", "Eridanus/main.py"]
=======
FROM python:3.11-slim AS builder

# 安装系统依赖（包括 cairo 依赖）
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libcairo2-dev \
        libpango1.0-dev \
        libglib2.0-dev \
        git \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 下载并安装 Python 依赖
COPY requirements.txt /tmp/requirements.txt
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r /tmp/requirements.txt

# 生产镜像
FROM python:3.11-slim

# 拷贝安装好的依赖
COPY --from=builder /usr/local /usr/local

WORKDIR /app/Eridanus
EXPOSE 5007

# 默认启动 main.py
CMD ["python", "main.py"]
>>>>>>> d0b7d369ea0940a79c462b0b105af4d50a8b398c
