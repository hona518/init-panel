#!/bin/bash

set -e

# ================================
# init-panel 一键初始化脚本（最终可运行版）
# ================================

# -------- 基础变量 --------
PANEL_DIR="/etc/init-panel"
CERT_DIR="$PANEL_DIR/cert"
WEB_DIR="$PANEL_DIR/web"
BIN_PATH="$PANEL_DIR/panel"
SERVICE_FILE="/etc/systemd/system/init-panel.service"

# -------- ZeroSSL API Key --------
ZEROSSL_API_KEY="b1ff7e16f47a369d19cfb928e48c21f2"

# -------- 自动检测服务器 IP --------
SERVER_IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me)

# -------- 输出函数 --------
info() { echo -e "\033[32m[INFO]\033[0m $1"; }
error() { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }

mkdir -p "$PANEL_DIR" "$CERT_DIR" "$WEB_DIR"

# ================================
# 1. 环境准备
# ================================
info "更新系统并安装依赖"

apt update -y
apt install -y curl wget tar unzip openssl

# ================================
# 2. 申请 ZeroSSL IP 证书（API 方式）
# ================================
info "开始申请 ZeroSSL IP 证书（API 模式）"

TMP_DIR="/tmp/zerossl-ip"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# 生成私钥和 CSR
info "生成私钥和 CSR（包含 IP SAN）"

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

# 创建证书订单
info "创建 ZeroSSL 证书订单"

ORDER_RESPONSE=$(curl -s -X POST "https://api.zerossl.com/certificates?access_key=$ZEROSSL_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"certificate_domains\": \"$SERVER_IP\",
    \"certificate_validity_days\": 90,
    \"certificate_csr\": \"$CSR_CONTENT\"
  }")

CERT_ID=$(echo "$ORDER_RESPONSE" | grep -o '"id":"[^"]*' | cut -d'"' -f4)

if [ -z "$CERT_ID" ]; then
  error "证书订单创建失败：$ORDER_RESPONSE"
fi

info "证书订单创建成功：$CERT_ID"

# 获取验证文件
info "获取验证文件"

VALIDATION=$(curl -s "https://api.zerossl.com/certificates/$CERT_ID?access_key=$ZEROSSL_API_KEY")

# 提取验证文件内容（数组 → 多行文本）
FILE_CONTENT=$(echo "$VALIDATION" \
  | grep -o '"file_validation_content":[^}]*' \
  | sed 's/"file_validation_content":

\[//' \
  | sed 's/\]

//' \
  | tr -d '"' \
  | tr ',' '\n')

# 提取验证文件路径（从 URL 中提取路径部分）
FILE_URL=$(echo "$VALIDATION" \
  | grep -o '"file_validation_url_http":"[^"]*' \
  | cut -d'"' -f4)

FILE_PATH=$(echo "$FILE_URL" | sed 's#http://[^/]*##')

if [ -z "$FILE_PATH" ] || [ -z "$FILE_CONTENT" ]; then
  error "无法解析验证文件信息：$VALIDATION"
fi

info "写入验证文件：$FILE_PATH"

mkdir -p "$(dirname "$FILE_PATH")"
echo "$FILE_CONTENT" > "$FILE_PATH"

# 通知 ZeroSSL 开始验证
info "通知 ZeroSSL 开始验证"

curl -s -X POST "https://api.zerossl.com/certificates/$CERT_ID/challenges?access_key=$ZEROSSL_API_KEY" >/dev/null

# 轮询验证状态
info "等待 ZeroSSL 验证..."

while true; do
  STATUS=$(curl -s "https://api.zerossl.com/certificates/$CERT_ID?access_key=$ZEROSSL_API_KEY" \
    | grep -o '"status":"[^"]*' | cut -d'"' -f4)

  if [ "$STATUS" = "issued" ]; then
    info "证书已签发"
    break
  fi

  if [ "$STATUS" = "cancelled" ] || [ "$STATUS" = "revoked" ]; then
    error "证书验证失败，状态：$STATUS"
  fi

  sleep 3
done

# 下载证书
info "下载证书"

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

# ================================
# 6. 完成
# ================================
info "Init Panel 部署完成！"
info "访问地址：https://$SERVER_IP"
info "证书路径：$CERT_DIR"
info "前端路径：$WEB_DIR"
info "后端路径：$BIN_PATH"
