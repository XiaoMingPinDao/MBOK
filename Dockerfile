# Antlia 轻量化 Dockerfile
# 使用 Debian-slim 和一个独立的部署脚本

# 1. 基础镜像
# 更换为兼容性更好的 slim 版本以支持 playwright
FROM python:3.11-slim-bookworm

# 2. 设置工作目录
WORKDIR /app

# 3. 复制部署脚本
# 脚本将负责克隆源码和安装所有依赖
COPY Eridanus-docker_build-Antlia.sh .

# 4. 执行部署脚本
# 赋予脚本执行权限，然后运行它
RUN chmod +x Eridanus-docker_build-Antlia.sh && \
    ./Eridanus-docker_build-Antlia.sh

# 5. 设置环境变量和端口
ENV TZ=Asia/Shanghai
EXPOSE 5007

# 6. 设置启动命令
# 注意：这里的 python 来自于脚本创建的 venv 虚拟环境
CMD ["/app/venv/bin/python", "Eridanus/main.py"]
