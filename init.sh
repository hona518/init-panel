#!/bin/bash

set -e

echo "==========================================="
echo " Reality Panel 一键安装脚本（Let’s Encrypt 版本）"
echo "==========================================="

# -----------------------------
# 1. 基础变量
# -----------------------------
SERVER_IP=$(curl -s ipv4.ip.sb)
INSTALL_DIR="/opt/reality-panel"
CERT_DIR="$INSTALL_DIR/certs"
WEB_DIR="$INSTALL_DIR/web"
PANEL_BIN="$INSTALL_DIR/panel"

PANEL_DOWNLOAD_URL="https://raw.githubusercontent.com/hona518/init-panel/main/panel"
WEB_DOWNLOAD_URL="https://raw.githubusercontent.com/hona518/init-panel/main/web.tar.gz"

echo "[1/10] 检查系统环境..."

apt update -y
apt install -y curl wget tar socat

# -----------------------------
# 2. 创建目录
# -----------------------------
echo "[2/10] 创建目录..."
mkdir -p $INSTALL_DIR
mkdir -p $CERT_DIR
mkdir -p $WEB_DIR

# -----------------------------
# 3. 安装 sing-box（Reality）
# -----------------------------
echo "[3/10] 安装 Reality（sing-box）..."

bash <(curl -fsSL https://sing-box.app/install.sh)

# 写 Reality 默认配置
echo "[4/10] 写 Reality 默认配置..."

cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": 52368,
      "users": [
        {
          "uuid": "11111111-2222-3333-4444-555555555555",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.amd.com",
        "reality": {
          "enabled": true,
          "private_key": "",
          "short_id": ["1234abcd"]
        }
      }
    }
  ]
}
EOF

# 写 systemd
echo "[5/10] 写 sing-box systemd..."

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-Box Service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# -----------------------------
# 6. 安装 acme.sh
# -----------------------------
echo "[6/10] 安装 acme.sh..."

curl https://get.acme.sh | sh

# -----------------------------
# 7. 使用 Let’s Encrypt 申请 IP 证书
# -----------------------------
echo "[7/10] 申请 Let’s Encrypt IP 证书..."

~/.acme.sh/acme.sh --register-account -m admin@$SERVER_IP --server letsencrypt

~/.acme.sh/acme.sh --issue --insecure --standalone -d $SERVER_IP --keylength ec-256 --server letsencrypt

~/.acme.sh/acme.sh --install-cert -d $SERVER_IP \
  --key-file       $CERT_DIR/panel.key \
  --fullchain-file $CERT_DIR/panel.crt \
  --reloadcmd     "systemctl restart reality-panel"

# -----------------------------
# 8. 安装 panel 后端
# -----------------------------
echo "[8/10] 安装 panel 后端..."

wget -O $PANEL_BIN $PANEL_DOWNLOAD_URL
chmod +x $PANEL_BIN

# 写 panel systemd
cat > /etc/systemd/system/reality-panel.service <<EOF
[Unit]
Description=Reality Panel
After=network.target

[Service]
ExecStart=$PANEL_BIN --cert $CERT_DIR/panel.crt --key $CERT_DIR/panel.key --web $WEB_DIR --addr :8443
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable reality-panel

# -----------------------------
# 9. 安装 web 前端
# -----------------------------
echo "[9/10] 安装 web 前端..."

wget -O /tmp/web.tar.gz $WEB_DOWNLOAD_URL
tar -xzf /tmp/web.tar.gz -C $INSTALL_DIR

# -----------------------------
# 10. 启动服务
# -----------------------------
echo "[10/10] 启动服务..."

systemctl restart reality-panel

echo "==========================================="
echo " Reality Panel 安装完成！"
echo " 面板地址：https://$SERVER_IP:8443"
echo "==========================================="
