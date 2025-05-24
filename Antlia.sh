#!/bin/bash

# ======================
# 系统检测与变量定义
# ======================
IS_ARCH=$(grep -q "Arch Linux" /etc/os-release || grep -q "arch" /etc/os-release)
PACKAGE_MANAGER=$(awk -F'=' '/^ID=/' /etc/os-release | tr -d '"')

# ======================
# 交互式选择
# ======================
clear
echo "检测到系统：$(if $IS_ARCH; then echo "Arch Linux"; else echo "其他系统"; fi)"
echo "---------------------------"
echo "如果您是Arch Linux用户，请输入y（默认）"
echo "如果您是其他系统（apt/yum），请输入n"

#默认值为y
read -p "请输入选择(y/n)[y]: " choice
choice=${choice:-y}  # 默认选择y

if [[ $choice =~ ^[Yy]$ ]]; then
    # Arch Linux 流程
    if ! $IS_ARCH; then
        echo "错误：当前系统不是Arch Linux，无法执行y选项"
        exit 1
    fi
# 日志文件路径
LOG_FILE="Eridanus-install_log.txt"
if ! grep -q "Arch Linux" /etc/os-release && ! grep -q "arch" /etc/os-release; then
  echo "错误：当前系统不是 Arch Linux"
  exit 1
fi
echo "
ArchLinux Eridanus部署脚本😋😋😋
"
echo "请回车进行下一步"
read -r
# 更新和安装
sudo pacman -Syu --noconfirm
sudo pacman -S git gcc base-devel whiptail --noconfirm



# 配置区
LL_PATH="$HOME/.local/share/LiteLoaderQQNT"  # LiteLoader安装路径
PLUGIN_DIR="$LL_PATH/plugins"                # 插件目录
NAPCAT_FRAMEWORK_URL="https://ghfast.top/https://github.com/NapNeko/NapCatQQ/releases/download/v4.7.68/NapCat.Framework.zip"
NAPCAT_ZIP="NapCat.Framework.zip"

# 函数定义
# 检查Yay
check_yay_installed() {
    command -v yay >/dev/null 2>&1
    return $?
}

# 安装Yay
install_yay() {
    echo "正在安装Yay依赖..."
    sudo pacman -S git base-devel --noconfirm || {
        echo "错误：安装依赖失败"
        return 1
    }
    git clone https://aur.archlinux.org/yay-bin.git || {
        echo "错误：克隆Yay仓库失败"
        return 1
    }
    cd yay-bin || {
        echo "错误：进入Yay目录失败"
        return 1
    }
    makepkg -si --noconfirm || {
        echo "错误：安装Yay失败"
        return 1
    }
    cd .. && rm -rf yay-bin
    echo "Yay安装完成！"
}

# Yay安装linuxqq
install_linuxqq_with_yay() {
    if check_yay_installed; then
        echo "正在通过Yay安装linuxqq..."
        yay -S linuxqq
    else
        echo "检测到未安装Yay，是否需要安装？(y/n)"
        read -r choice
        if [[ $choice =~ ^[Yy]$ ]]; then
            install_yay || return 1
            yay -S linuxqq --noconfirm
        else
            echo "将通过手动方式安装linuxqq..."
            git clone https://aur.archlinux.org/linuxqq.git || {
                echo "错误：克隆linuxqq仓库失败"
                return 1
            }
            cd linuxqq || {
                echo "错误：进入linuxqq目录失败"
                return 1
            }
            makepkg -si --noconfirm || {
                echo "错误：安装linuxqq失败"
                return 1
            }
            cd .. && rm -rf linuxqq
        fi
    fi
}

#安装LiteLoaderQQNT
run_liteloader_script() {
    echo "下载并运行LiteLoaderQQNT安装脚本..."
    wget -qO install.sh https://ghfast.top/https://github.com/Mzdyl/LiteLoaderQQNT_Install/raw/main/install.sh || {
        echo "错误：下载安装脚本失败"
        return 1
    }
    chmod +x install.sh
    echo "自动配置LiteLoaderQQNT..."
    ./install.sh <<< "q"  # 自动输入q
}

# 安装NapCatQQ
install_napcatqq() {
    echo -e "\n======================="
    echo "开始安装 NapCatQQ 插件..."

    # 检查依赖
    if ! command -v unzip >/dev/null; then
        echo "错误：未安装unzip，请先执行：sudo pacman -S unzip"
        exit 1
    fi

    # 下载
    echo "正在下载 NapCatFramework..."
    if ! wget -q "$NAPCAT_FRAMEWORK_URL" -O "$NAPCAT_ZIP"; then
        echo "警告：下载失败！请手动下载：$NAPCAT_FRAMEWORK_URL"
        return 1
    fi

    # 解压
    echo "正在解压文件..."
    unzip -q "$NAPCAT_ZIP" -d napcat_temp || {
        echo "错误：解压失败，请检查ZIP文件完整性"
        return 1
    }

    # 复制
    echo "正在复制插件到 LiteLoader 目录..."
    mkdir -p "$PLUGIN_DIR"
    cp -rf napcat_temp/* "$PLUGIN_DIR"/ || {
        echo "错误：复制文件失败，请检查路径权限"
        return 1
    }
    rm -rf napcat_temp  # 清理临时目录
    echo "NapCatQQ 安装完成！"
}

clear
echo "===== Napcat安装向导 ====="
echo "请选择安装方式："
echo "1. 使用LiteLoaderQQNT（全自动安装，推荐）"
echo "2. 暂不使用（仅安装QQ，即将更新）"
read -p "请输入选项（1/2）： " choice

case $choice in
    1)
        echo "正在执行完整安装流程（LiteLoader+NapCatQQ）..."

        # 1. 安装linuxqq
        install_linuxqq_with_yay || exit 1

        # 2. 安装LiteLoaderQQNT
        run_liteloader_script || exit 1

        # 3. 安装NapCatQQ插件
        install_napcatqq || exit 1

        # 4. 最终提示
        echo -e "\n======================="
        echo "所有组件安装完成！请进行以下操作："
        echo "1. 打开QQ并登录机器人账号"
        echo "2. 在LiteLoaderQQNT设置中启用NapCatQQ插件"
        echo "3. 若插件未显示："
        echo "   - 检查数据目录：$LL_PATH"
        echo "   - 手动复制插件到：$PLUGIN_DIR"
        echo "4. 重启QQ使配置生效"
        echo "======================="
        ;;

    2)
        echo "仅安装linuxqq（选项2功能待更新）..."
        install_linuxqq_with_yay || exit 1
        echo "请后续手动安装LiteLoader和NapCatQQ插件"
        ;;

    *)
        echo "错误：无效选项"
        exit 1
        ;;
esac


# 安装Redis
echo "安装Redis"
# 克隆Redis
git clone --depth 1 https://ghfast.top/https://github.com/redis/redis.git
cd redis

# 编译安装
make -j$(nproc)  # 使用多核编译加快速度
sudo make install  # 安装
cd ..
rm -rf redis-src  # 清理源码目录

# 启动Redis服务（使用系统默认配置）
sudo redis-server &  #前台
sudo systemctl enable --now redis  # 设置开机自启并启动

# 检查服务状态

if ! pgrep -f "redis-server" >/dev/null; then
  echo -e "${COLOR_RED}[警告] Redis服务未正常启动，建议手动启动：redis-server${COLOR_RESET}🤔🤔🤔"
fi

# 安装Miniconda3
SOFTWARE_NAME="miniconda3"
# Miniconda3官方下载地址（包含架构变量）
BASE_DOWNLOAD_URL="https://repo.anaconda.com/miniconda"
# 安装路径
INSTALL_PATH="$HOME/miniconda3"
# 初始化
POST_INSTALL_INIT="source $HOME/.bashrc"


# 系统检测
if ! grep -q "Arch Linux" /etc/os-release && ! grep -q "arch" /etc/os-release; then
  echo "错误：当前系统不是 Arch Linux"
  exit 1
fi

# 检测架构
ARCH=$(uname -m)
case "$ARCH" in
  "x86_64")
    DOWNLOAD_FILE="Miniconda3-latest-Linux-x86_64.sh"
    ;;
  "aarch64"|"arm64")
    DOWNLOAD_FILE="Miniconda3-latest-Linux-aarch64.sh"
    ;;
  *)
    echo "错误：不支持的架构 $ARCH"
    exit 1
    ;;
esac

DOWNLOAD_URL="${BASE_DOWNLOAD_URL}/${DOWNLOAD_FILE}"

#安装
install_miniconda() {
  local TEMP_DIR=$(mktemp -d)
  cd "$TEMP_DIR" || exit 1

  # 下载Miniconda3
  echo "正在下载 Miniconda3 for $ARCH..."
  if ! curl -fsSL "$DOWNLOAD_URL" -o miniconda.sh; then
    echo "错误：下载失败"
    exit 1
  fi

  # 安装脚本
  echo "正在安装 Miniconda3 到 $INSTALL_PATH..."
  bash miniconda.sh -b -p "$INSTALL_PATH"
  echo "Miniconda3 安装完成！"
}

echo "检测到系统：Arch Linux ($ARCH)"
install_miniconda
source ~/miniconda3/bin/activate
conda init --all
conda create -n qqbot python=3.13 --yes
wget https://github.com/zhende1113/Antlia/blob/main/Eridanus-install.sh
chmod +x Eridanus-install.sh
./Eridanus-install.sh
wget https://github.com/zhende1113/Antlia/blob/main/SetUP.sh
chmod +x SetUP.sh

echo "安装完成😋"
echo "1. WebUI配置: http://127.0.0.1:6099/webui?token=napcat
2. 启动环境: source ~/miniconda3/envs/qqbot/bin/activate
3. 运行项目:
cd Eridanus
python main.py
更新
source activate qqbot
cd Eridanus
python tool.py
如果启动的时候报错请执行 指的是第一次启动
pip3 install audioop-lts
启动脚本 ./SetUP.sh
项目地址 https://github.com/avilliai/Eridanus/releases
官方文档 https://eridanus-doc.netlify.app
官方群聊 913122269
"
elif [[ $choice =~ ^[Nn]$ ]]; then
    # 非Arch Linux流程
    if $IS_ARCH; then
        echo "警告：当前系统是Arch Linux，建议选择y选项"
    fi

    echo "该脚本的项目地址为：https://gitee.com/laixi_lingdun/eridanus_deploy"
    echo "正在下载安装脚本..."

    wget install.sh https://gitee.com/laixi_lingdun/eridanus_deploy/raw/master/install.sh

    echo "正在赋予脚本权限..."
    chmod +x install.sh

    echo "正在运行脚本..."
    ./install.sh

else
    echo "错误：无效输入"
    exit 1
fi
