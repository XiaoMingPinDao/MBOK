#!/bin/bash

# Eridanus ArchLinux启动器脚本
clear
echo "===== Eridanus 启动器 ====="
echo "请选择操作："
echo "1. 启动 Eridanu"
echo "2. 更新 Eridanu"
read -p "输入选项（1/2）: " choice

case $choice in
    1)
        echo "正在进入虚拟环境并启动 Eridanus..."
        source activate qqbot
            echo "成功进入虚拟环境"
            echo "正在启动 Eridanus..."
            cd Eridanus
            python launch.py

        ;;

    2)
        echo "正在进入虚拟环境并更新 Eridanus..."
        source activate qqbot
            echo "成功进入虚拟环境"
            echo "正在启动 Eridanus..."
            cd Eridanus
            python tool.py
        ;;

    *)
        echo "错误：无效选项（仅支持1/2）"
        exit 1
        ;;
esac

# 保持终端窗口不退出，直到手动终止
echo -e "\nEridanus 已启动，按 Ctrl+C 终止进程..."
wait  # 等待子进程结束（可选，根据实际需求保留）
