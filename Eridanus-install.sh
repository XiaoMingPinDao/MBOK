#!/bin/bash
#选择
echo "选择克隆源10秒后自动选择镜像源"
echo "1. 官方源 (github.com)"
echo "2. 镜像源1 (ghproxy.com)"
echo "3. 镜像源2 (github.moeyy.xyz)"
echo "4. 镜像源3 (ghfast.top) [默认]"
echo "5. 镜像源4 (gh.llkk.cc)"

read -t 10 -p "请输入数字（1-5）: " reply
reply=${reply:-4}  # 默认4
case $reply in
  1) CLONE_URL="https://github.com/avilliai/Eridanus.git" ;;
  2) CLONE_URL="https://mirror.ghproxy.com/https://github.com/avilliai/Eridanus.git" ;;
  3) CLONE_URL="https://github.moeyy.xyz/https://github.com/avilliai/Eridanus.git" ;;
  4) CLONE_URL="https://ghfast.top/https://github.com/avilliai/Eridanus.git" ;;
  5) CLONE_URL="https://gh.llkk.cc/https://github.com/avilliai/Eridanus.git" ;;
  *) echo "无效输入，使用默认源"; CLONE_URL="https://ghfast.top/https://github.com/avilliai/Eridanus.git" ;;
esac
conda init
conda activate qqbot
  echo "克隆项目"
cd $(pwd)
git clone --depth 1 "$CLONE_URL" Eridanus && cd Eridanus

# 安装依赖
pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/
pip install --user --upgrade pip && pip install -r requirements.txt
