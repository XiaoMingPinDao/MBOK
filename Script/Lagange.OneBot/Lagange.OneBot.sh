#!/bin/bash




select_github_proxy() {
  print_title "选择 GitHub 代理"
  echo "请根据您的网络环境选择一个合适的下载代理："
  echo
  select proxy_choice in "ghfast.top 镜像 (推荐)" "ghproxy.net 镜像" "不使用代理" "自定义代理"; do
    case $proxy_choice in
      "ghfast.top 镜像 (推荐)")
        GITHUB_PROXY="https://ghfast.top/"
        ok "已选择: ghfast.top 镜像"
        break
        ;;
      "ghproxy.net 镜像")
        GITHUB_PROXY="https://ghproxy.net/"
        ok "已选择: ghproxy.net 镜像"
        break
        ;;
      "不使用代理")
        GITHUB_PROXY=""
        ok "已选择: 不使用代理"
        break
        ;;
      "自定义代理")
        read -p "请输入自定义 GitHub 代理 URL (必须以斜杠 / 结尾): " custom_proxy
        [[ -n "$custom_proxy" && "$custom_proxy" != */ ]] && custom_proxy="${custom_proxy}/" && warn "已自动添加斜杠"
        GITHUB_PROXY="$custom_proxy"
        ok "已选择: 自定义代理 - $GITHUB_PROXY"
        break
        ;;
      *)
        warn "无效输入，使用默认代理"
        GITHUB_PROXY="https://ghfast.top/"
        ok "已选择: ghfast.top 镜像 (默认)"
        break
        ;;
    esac
  done
}


install_lagrange() {
  print_title "安装 Lagrange"
  cd "$DEPLOY_DIR"
  mkdir -p Lagrange tmp || err "无法创建目录"
  local TMP_DIR="$DEPLOY_DIR/tmp"
  cd "$TMP_DIR" || err "进入临时目录失败"

  info "正在动态获取 Lagrange 最新版本..."
  local pattern="linux-x64.*.tar.gz"
  [[ "$MINICONDA_ARCH" == "aarch64" ]] && pattern="linux-aarch64.*.tar.gz"

  local github_url
  github_url=$(curl -s "https://api.github.com/repos/LagrangeDev/Lagrange.Core/releases/tags/nightly" \
    | jq -r ".assets[] | select(.name | test(\"$pattern\")) | .browser_download_url")

  [[ -z "$github_url" ]] && err "无法动态获取 Lagrange 最新版本链接。"
  local download_url="${GITHUB_PROXY}${github_url}"
  download_with_retry "$download_url" "Lagrange.tar.gz"

  info "解压 Lagrange..."
  tar -xzf "Lagrange.tar.gz" || err "解压失败"

  local executable_path
  executable_path=$(find . -name "Lagrange.OneBot" -type f 2>/dev/null | head -1)
  [[ -z "$executable_path" ]] && err "未找到 Lagrange.OneBot 可执行文件"

  info "复制到目标目录..."
  cp "$executable_path" "$DEPLOY_DIR/Lagrange/Lagrange.OneBot" || err "复制失败"
  chmod +x "$DEPLOY_DIR/Lagrange/Lagrange.OneBot"

  cd "$DEPLOY_DIR/Lagrange"
  wget -O appsettings.json https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/appsettings/appsettings-Eridanus.json

  info "清理临时文件..."
  rm -rf "$TMP_DIR"
  ok "Lagrange 安装完成"
}