# 构建阶段：安装依赖和源码（仅用于第一次复制）
FROM python:3.11-slim AS builder

# 安装依赖工具
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential redis-server curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

# 安装 Python 依赖
COPY requirements.txt /tmp/requirements.txt
RUN pip install --upgrade pip && pip install --no-cache-dir -r /tmp/requirements.txt

# 克隆源码到 /app/Eridanus（仅第一次复制用）
RUN git clone https://github.com/AOrbitron/Eridanus.git /app/Eridanus

# 运行阶段：仅保留依赖
FROM python:3.11-slim

# 安装运行所需依赖（Redis + 系统库）
RUN apt-get update && apt-get install -y --no-install-recommends \
    redis-server curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 复制 Python 包和第一次复制用的源码
COPY --from=builder /usr/local /usr/local
COPY --from=builder /app/Eridanus /app/Eridanus

WORKDIR /app
ENV PYTHONPATH=/usr/local/lib/python3.11/site-packages
ENV TZ=Asia/Shanghai

EXPOSE 5007
CMD ["python", "/app/main.py"]
