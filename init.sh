#!/bin/bash

set -e

# ================================
# init-panel 一键初始化脚本（无证书版）
# ================================

PANEL_DIR="/etc/init-panel"
WEB_DIR="$PANEL_DIR/web"
BIN_PATH="$PANEL_DIR/panel"
SERVICE_FILE="/etc/systemd/system/init-panel.service"

SERVER_IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me)

info() { echo -e "\033[32m[INFO]\033[0m $1"; }
error() { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }

mkdir -p "$PANEL_DIR" "$WEB_DIR"

# ================================
# 1. 环境准备
# ================================
info "更新系统并安装依赖"

apt update -y
apt install -y curl wget tar unzip

# ================================
# 2. 下载 panel 后端
# ================================
info "下载 panel 后端"

wget -O "$BIN_PATH" \
  "https://raw.githubusercontent.com/hona518/init-panel/main/panel"

chmod +x "$BIN_PATH"

# ================================
# 3. 下载 web 前端
# ================================
info "下载 web 前端"

wget -O /tmp/web.tar.gz \
  "https://raw.githubusercontent.com/hona518/init-panel/main/web.tar.gz"

tar -xzf /tmp/web.tar.gz -C "$WEB_DIR"

# ================================
# 4. 创建 systemd 服务（HTTP，无证书）
# ================================
info "创建 systemd 服务"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Init Panel Service
After=network.target

[Service]
Type=simple
ExecStart=$BIN_PATH --web-dir $WEB_DIR
Restart=always
User=root
WorkingDirectory=$PANEL_DIR

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable init-panel
systemctl restart init-panel

# ================================
# 5. 完成
# ================================
info "Init Panel 部署完成！"
info "访问地址：http://$SERVER_IP"
info "前端路径：$WEB_DIR"
info "后端路径：$BIN_PATH"
