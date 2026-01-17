#!/bin/bash

set -e

# ================================
# init-panel 一键初始化脚本（最终可运行版）
# ================================

PANEL_DIR="/etc/init-panel"
CERT_DIR="$PANEL_DIR/cert"
WEB_DIR="$PANEL_DIR/web"
BIN_PATH="$PANEL_DIR/panel"
SERVICE_FILE="/etc/systemd/system/init-panel.service"

ZEROSSL_API_KEY="b1ff7e16f47a369d19cfb928e48c21f2"

SERVER_IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me)

info() { echo -e "\033[32m[INFO]\033[0m $1"; }
error() { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }

mkdir -p "$PANEL_DIR" "$CERT_DIR" "$WEB_DIR"

# ================================
# 1. 环境准备
# ================================
info "安装依赖"

apt update -y
apt install -y curl wget tar unzip openssl jq

# ================================
# 2. ZeroSSL API 证书申请
# ================================
info "开始申请 ZeroSSL IP 证书"

TMP_DIR="/tmp/zerossl-ip"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# 生成私钥和 CSR
openssl genrsa -out "$TMP_DIR/private.key" 2048

cat > "$TMP_DIR/csr.conf" <<EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
req_extensions     = req_ext
distinguished_name = dn

[ dn ]
CN = $SERVER_IP

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
IP.1 = $SERVER_IP
EOF

openssl req -new -key "$TMP_DIR/private.key" \
  -out "$TMP_DIR/csr.csr" \
  -config "$TMP_DIR/csr.conf"

CSR_CONTENT=$(sed ':a;N;$!ba;s/\n/\\n/g' "$TMP_DIR/csr.csr")

# 创建订单
ORDER_RESPONSE=$(curl -s -X POST "https://api.zerossl.com/certificates?access_key=$ZEROSSL_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"certificate_domains\": \"$SERVER_IP\",
    \"certificate_validity_days\": 90,
    \"certificate_csr\": \"$CSR_CONTENT\"
  }")

CERT_ID=$(echo "$ORDER_RESPONSE" | jq -r '.id')

if [ "$CERT_ID" = "null" ] || [ -z "$CERT_ID" ]; then
  error "证书订单创建失败：$ORDER_RESPONSE"
fi

info "证书订单创建成功：$CERT_ID"

# 获取验证信息
VALIDATION=$(curl -s "https://api.zerossl.com/certificates/$CERT_ID?access_key=$ZEROSSL_API_KEY")

FILE_URL=$(echo "$VALIDATION" | jq -r ".validation.other_methods.\"$SERVER_IP\".file_validation_url_http")
FILE_CONTENT=$(echo "$VALIDATION" | jq -r ".validation.other_methods.\"$SERVER_IP\".file_validation_content[]")

if [ "$FILE_URL" = "null" ] || [ -z "$FILE_URL" ]; then
  error "无法解析验证文件 URL：$VALIDATION"
fi

FILE_PATH=$(echo "$FILE_URL" | sed 's#http://[^/]*##')

info "写入验证文件：$FILE_PATH"

mkdir -p "$(dirname "$FILE_PATH")"
echo "$FILE_CONTENT" > "$FILE_PATH"

# 通知 ZeroSSL 开始验证
curl -s -X POST "https://api.zerossl.com/certificates/$CERT_ID/challenges?access_key=$ZEROSSL_API_KEY" >/dev/null

info "等待 ZeroSSL 验证..."

while true; do
  STATUS=$(curl -s "https://api.zerossl.com/certificates/$CERT_ID?access_key=$ZEROSSL_API_KEY" | jq -r '.status')

  if [ "$STATUS" = "issued" ]; then
    info "证书已签发"
    break
  fi

  if [ "$STATUS" = "cancelled" ] || [ "$STATUS" = "revoked" ]; then
    error "证书验证失败：$STATUS"
  fi

  sleep 3
done

# 下载证书
curl -s "https://api.zerossl.com/certificates/$CERT_ID/download/return?access_key=$ZEROSSL_API_KEY" \
  -o "$TMP_DIR/cert.zip"

unzip -o "$TMP_DIR/cert.zip" -d "$TMP_DIR" >/dev/null

cp "$TMP_DIR/certificate.crt" "$CERT_DIR/fullchain.cer"
cp "$TMP_DIR/ca_bundle.crt" "$CERT_DIR/ca_bundle.cer"
cp "$TMP_DIR/private.key" "$CERT_DIR/private.key"

info "证书已安装到：$CERT_DIR"

rm -rf "$TMP_DIR"

# ================================
# 3. 下载 panel 后端
# ================================
info "下载 panel 后端"

wget -O "$BIN_PATH" \
  "https://raw.githubusercontent.com/hona518/init-panel/main/panel"

chmod +x "$BIN_PATH"

# ================================
# 4. 下载 web 前端
# ================================
info "下载 web 前端"

wget -O /tmp/web.tar.gz \
  "https://raw.githubusercontent.com/hona518/init-panel/main/web.tar.gz"

tar -xzf /tmp/web.tar.gz -C "$WEB_DIR"

# ================================
# 5. 创建 systemd 服务
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

info "部署完成，访问：https://$SERVER_IP"
