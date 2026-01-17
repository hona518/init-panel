#!/bin/bash

set -e

# ================================
# init-panel 一键初始化脚本（最终版）
# ================================

# -------- 基础变量 --------
PANEL_DIR="/etc/init-panel"
CERT_DIR="$PANEL_DIR/cert"
WEB_DIR="$PANEL_DIR/web"
BIN_PATH="$PANEL_DIR/panel"
SERVICE_FILE="/etc/systemd/system/init-panel.service"

# -------- 用户配置（已替换为你提供的 EAB） --------
EMAIL="admin@example.com"
ZEROSSL_EAB_KID="LNySi-BXwKx1B_fOUpq-Ag"
ZEROSSL_EAB_HMAC="sn8twIvLZ9Xdd2MY379wd9E4XQTEtTx4Blwpgbd__WvePyYRDTNr4HPGd5NWzENyDRQfyRXxL5EF_KmstMahMg"

# -------- 自动检测服务器 IP --------
SERVER_IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me)

# -------- 输出函数 --------
info() { echo -e "\033[32m[INFO]\033[0m $1"; }
error() { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }

# ================================
# 1. 环境准备
# ================================
info "更新系统并安装依赖"

apt update -y
apt install -y curl wget tar socat unzip

mkdir -p "$PANEL_DIR" "$CERT_DIR" "$WEB_DIR"

# ================================
# 2. 安装 acme.sh
# ================================
if [ ! -d ~/.acme.sh ]; then
    info "安装 acme.sh"
    curl https://get.acme.sh | sh
else
    info "acme.sh 已存在，跳过安装"
fi

# ================================
# 3. 注册 ZeroSSL ACME 账户（EAB）
# ================================
info "注册 ZeroSSL ACME 账户"

~/.acme.sh/acme.sh --register-account \
  --server zerossl \
  --eab-kid "$ZEROSSL_EAB_KID" \
  --eab-hmac-key "$ZEROSSL_EAB_HMAC" \
  --accountemail "$EMAIL" \
  --force

# ================================
# 4. 申请 IP 证书
# ================================
info "申请 ZeroSSL IP 证书（IP: $SERVER_IP）"

~/.acme.sh/acme.sh --issue \
  --server zerossl \
  --ip "$SERVER_IP" \
  --standalone \
  --keylength ec-256 \
  --force

# ================================
# 5. 安装证书
# ================================
info "安装证书到 $CERT_DIR"

~/.acme.sh/acme.sh --install-cert \
  --server zerossl \
  --ip "$SERVER_IP" \
  --fullchain-file "$CERT_DIR/fullchain.cer" \
  --key-file "$CERT_DIR/private.key" \
  --reloadcmd "systemctl restart init-panel"

# ================================
# 6. 下载 panel 后端
# ================================
info "下载 panel 后端"

wget -O "$BIN_PATH" \
  "https://raw.githubusercontent.com/hona518/init-panel/main/panel"

chmod +x "$BIN_PATH"

# ================================
# 7. 下载 web 前端
# ================================
info "下载 web 前端"

wget -O /tmp/web.tar.gz \
  "https://raw.githubusercontent.com/hona518/init-panel/main/web.tar.gz"

tar -xzf /tmp/web.tar.gz -C "$WEB_DIR"

# ================================
# 8. 创建 systemd 服务
# ================================
info "创建 systemd 服务"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Init Panel Service
After=network.target

[Service]
Type=simple
ExecStart=$BIN_PATH --web-dir $WEB_DIR --cert $CERT_DIR/fullchain.cer --key $CERT_DIR/private.key
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
# 9. 完成
# ================================
info "Init Panel 部署完成！"
info "访问地址：https://$SERVER_IP"
info "证书路径：$CERT_DIR"
info "前端路径：$WEB_DIR"
info "后端路径：$BIN_PATH"
