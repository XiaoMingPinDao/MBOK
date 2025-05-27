#!/bin/bash
clear
echo "===== Eridanus 启动器 ====="
echo "请选择操作："
echo "1. 启动 Eridanu (默认)"
echo "2. 更新 Eridanu"
read -p "输入选项（1/2）: " choice

case $choice in
    1)
        echo "正在进入虚拟环境并启动 Eridanus..."
        conda activate qqbot
            echo "成功进入虚拟环境"
            echo "正在启动 Eridanus..."
            cd Eridanus
            python launch.py

        ;;

    2)
        echo "正在进入虚拟环境并更新 Eridanus..."
        conda activate qqbot
            echo "成功进入虚拟环境"
            echo "正在启动 Eridanus..."
            cd Eridanus
            python tool.py
        ;;

    *)
        conda activate qqbot
            echo "成功进入虚拟环境"
            echo "正在启动 Eridanus..."
            cd Eridanus
            python launch.py
        ;;
esac

echo -e "\n按 Ctrl+C 终止进程..."
