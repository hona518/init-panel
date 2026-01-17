#!/bin/bash
set -e

echo "=== Reality Panel 初始化开始 ==="

# -------------------------------
# 0. 基础变量
# -------------------------------
INSTALL_DIR="/opt/reality-panel"
PANEL_DIR="$INSTALL_DIR/panel"
WEB_DIR="$INSTALL_DIR/web"
CERT_DIR="$INSTALL_DIR/certs"
CONFIG_FILE="$INSTALL_DIR/config.json"
TRAFFIC_FILE="$INSTALL_DIR/traffic.json"

# ⚠️ 请替换为你自己的 GitHub Raw 地址
PANEL_DOWNLOAD_URL="https://raw.githubusercontent.com/hona518/init-panel/main/panel"
WEB_DOWNLOAD_URL="https://raw.githubusercontent.com/hona518/init-panel/main/web.tar.gz"

# -------------------------------
# 1. 安装基础依赖
# -------------------------------
echo "[1/10] 安装基础依赖..."
apt update -y
apt install -y curl wget tar openssl socat cron

# -------------------------------
# 2. 创建目录
# -------------------------------
echo "[2/10] 创建目录..."
mkdir -p $PANEL_DIR $WEB_DIR $CERT_DIR

# -------------------------------
# 3. 安装 sing-box
# -------------------------------
echo "[3/10] 安装 sing-box..."

ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac

LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep browser_download_url | grep linux-$ARCH | cut -d '"' -f 4)
wget -O /tmp/singbox.tar.gz "$LATEST"
tar -xf /tmp/singbox.tar.gz -C /tmp
mv /tmp/sing-box*/sing-box /usr/local/bin/sing-box
chmod +x /usr/local/bin/sing-box

# -------------------------------
# 4. 写 Reality 默认配置
# -------------------------------
echo "[4/10] 写 Reality 默认配置..."

UUID=$(cat /proc/sys/kernel/random/uuid)
KEYPAIR=$(sing-box generate reality-keypair)
PRIV=$(echo "$KEYPAIR" | grep PrivateKey | awk '{print $2}')
PUB=$(echo "$KEYPAIR" | grep PublicKey | awk '{print $2}')
SHORT=$(openssl rand -hex 8)

cat > $CONFIG_FILE <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": 52368,
      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision",
          "name": "Reality_Default"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.amd.com",
        "reality": {
          "enabled": true,
          "private_key": "$PRIV",
          "public_key": "$PUB",
          "short_id": ["$SHORT"]
        }
      }
    }
  ]
}
EOF

# -------------------------------
# 5. 写 sing-box systemd
# -------------------------------
echo "[5/10] 写 sing-box systemd..."

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-Box Service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c $CONFIG_FILE
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now sing-box

# -------------------------------
# 6. 安装 acme.sh + ZeroSSL
# -------------------------------
echo "[6/10] 安装 acme.sh..."

curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --register-account -m "admin@local"

SERVER_IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me)

echo "[6.1] 申请 IP 证书..."

~/.acme.sh/acme.sh --issue \
  --server zerossl \
  --insecure \
  --ip "$SERVER_IP" \
  --keylength 2048 \
  --force

~/.acme.sh/acme.sh --install-cert \
  --ip "$SERVER_IP" \
  --cert-file "$CERT_DIR/panel.crt" \
  --key-file "$CERT_DIR/panel.key" \
  --fullchain-file "$CERT_DIR/fullchain.crt"

# -------------------------------
# 7. 下载 panel 后端
# -------------------------------
echo "[7/10] 安装 Reality Panel 后端..."

wget -O $PANEL_DIR/panel "$PANEL_DOWNLOAD_URL"
chmod +x $PANEL_DIR/panel

# -------------------------------
# 8. 下载前端
# -------------------------------
echo "[8/10] 安装前端..."

wget -O /tmp/web.tar.gz "$WEB_DOWNLOAD_URL"
tar -xf /tmp/web.tar.gz -C $WEB_DIR

# -------------------------------
# 9. 写 renew-cert.sh
# -------------------------------
echo "[9/10] 写证书续期脚本..."

cat > $PANEL_DIR/renew-cert.sh <<EOF
#!/bin/bash
set -e

CERT_DIR="$CERT_DIR"
CERT_FILE="\$CERT_DIR/panel.crt"
KEY_FILE="\$CERT_DIR/panel.key"
ACME_HOME="/root/.acme.sh"

SERVER_IP=\$(curl -s ipv4.ip.sb || curl -s ifconfig.me)

if [ -f "\$CERT_FILE" ]; then
  END_DATE=\$(openssl x509 -enddate -noout -in "\$CERT_FILE" | cut -d= -f2)
  END_TS=\$(date -d "\$END_DATE" +%s)
  NOW_TS=\$(date +%s)
  REMAIN_DAYS=\$(( (END_TS - NOW_TS) / 86400 ))
else
  REMAIN_DAYS=0
fi

if [ "\$REMAIN_DAYS" -gt 60 ]; then
  exit 0
fi

\$ACME_HOME/acme.sh --issue \
  --server zerossl \
  --insecure \
  --ip "\$SERVER_IP" \
  --keylength 2048 \
  --force

\$ACME_HOME/acme.sh --install-cert \
  --ip "\$SERVER_IP" \
  --cert-file "\$CERT_FILE" \
  --key-file "\$KEY_FILE" \
  --fullchain-file "\$CERT_DIR/fullchain.crt" \
  --reloadcmd "systemctl restart reality-panel"
EOF

chmod +x $PANEL_DIR/renew-cert.sh

# -------------------------------
# 10. 写 reality-panel.service
# -------------------------------
echo "[10/10] 写 reality-panel systemd..."

cat > /etc/systemd/system/reality-panel.service <<EOF
[Unit]
Description=Reality Panel Web Service
After=network.target

[Service]
ExecStart=$PANEL_DIR/panel \
  --cert=$CERT_DIR/panel.crt \
  --key=$CERT_DIR/panel.key \
  --web=$WEB_DIR \
  --addr=:8443
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# -------------------------------
# 11. 写证书续期 timer
# -------------------------------
cat > /etc/systemd/system/panel-cert-renew.service <<EOF
[Unit]
Description=Renew Reality Panel SSL Certificate

[Service]
Type=oneshot
ExecStart=$PANEL_DIR/renew-cert.sh
EOF

cat > /etc/systemd/system/panel-cert-renew.timer <<EOF
[Unit]
Description=Run Reality Panel SSL Certificate Renew Task

[Timer]
OnBootSec=5min
OnUnitActiveSec=30d
Unit=panel-cert-renew.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now reality-panel
systemctl enable --now panel-cert-renew.timer

echo "=== Reality Panel 安装完成 ==="
echo "访问地址: https://$SERVER_IP:8443"
