FROM python:3.11-slim AS builder

ARG REQUIREMENTS_FILE

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 安装 Python 依赖
COPY ${REQUIREMENTS_FILE} /tmp/requirements.txt
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r /tmp/requirements.txt

# 生产镜像
FROM python:3.11-slim

COPY --from=builder /usr/local /usr/local

# 可选：复制 Eridanus 源码到镜像（如果需要）
COPY . /app/Eridanus

WORKDIR /app/Eridanus
EXPOSE 5007

CMD ["python", "launch.py"]
