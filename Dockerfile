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
