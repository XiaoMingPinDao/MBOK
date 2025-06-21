#!/bin/bash
LOG_FILE="Eridanus-install_log.txt"

# 检测
echo "
Eridanus部署脚本
"
echo "请回车进行下一步"
read -r
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


sudo apt update
echo "克隆项目"



git clone --depth 1 "$CLONE_URL" Eridanus && echo "克隆项目"



# 安装Redis
echo "安装Redis"
# 克隆Redis
sudo apt install redis

# 启动Redis服务（使用系统默认配置）
sudo redis-server &  #前台
sudo systemctl enable --now redis  # 设置开机自启并启动

# 检查服务状态

if ! pgrep -f "redis-server" >/dev/null; then
  echo -e "${COLOR_RED}[警告] Redis服务未正常启动，建议手动启动：redis-server${COLOR_RESET}🤔🤔🤔"
fi

mkdir -p ~/miniconda3
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh
bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3
rm ~/miniconda3/miniconda.sh
source ~/miniconda3/bin/activate
conda init --all
conda create --name qqbot
conda activate qqbot
conda install pip


wget https://mirror.ghproxy.com/https://github.com/zhende1113/Antlia/blob/main/start.sh
chmod +x start.sh
cd Eridanus

# 安装依赖
pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/
pip install --user --upgrade pip && pip install -r requirements.txt
pip3 install audioop-lts
echo "安装完成😋"
echo "1. WebUI配置: http://127.0.0.1:6099/webui?token=napcat
2. 启动环境: source ~/miniconda3/envs/qqbot/bin/activate
3. 运行项目: 
cd Eridanus
python main.py
更新
source activate qqbot
cd Eridanus
python launch.py
如果启动的时候报错请执行 指的是第一次启动
pip3 install audioop-lts

项目地址 https://github.com/avilliai/Eridanus/releases
官方文档 https://eridanus-doc.netlify.app
官方群聊 913122269
"
echo "安装完成，日志已保存至 $LOG_FILE"





#更新日志
#v1.04 替换原有的检查逻辑 改为检查软件包管理器