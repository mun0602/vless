#!/bin/bash

# Cài đặt các gói cần thiết
apt update
apt install -y unzip curl uuid-runtime qrencode

# Biến
XRAY_URL="https://dtdp.bio/wp-content/apk/Xray-linux-64.zip"
INSTALL_DIR="/usr/local/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/xray.service"
LOG_FILE="${INSTALL_DIR}/access.log"
ERR_FILE="${INSTALL_DIR}/error.log"

# Tải và cài đặt Xray nếu chưa có
if [[ ! -f "${INSTALL_DIR}/xray" ]]; then
  mkdir -p ${INSTALL_DIR}
  curl -L ${XRAY_URL} -o xray.zip
  unzip xray.zip -d ${INSTALL_DIR}
  chmod +x ${INSTALL_DIR}/xray
  rm xray.zip
fi

# Sinh UUID và port
UUID=$(uuidgen)
PORT=10086

# Nhập tên hiển thị (ps) cho cấu hình VLESS
read -p "Nhập tên hiển thị cho cấu hình (ps): " PS_NAME
PS_NAME=${PS_NAME:-"VLESS-TCP-Test"}

# Tạo file cấu hình Xray (VLESS TCP đơn giản, có log)
cat > ${CONFIG_FILE} <<EOF
{
  "log": {
    "loglevel": "info",
    "access": "${LOG_FILE}",
    "error": "${ERR_FILE}"
  },
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

# Tạo systemd service
cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=Xray VLESS Simple Service
After=network.target nss-lookup.target

[Service]
ExecStart=${INSTALL_DIR}/xray run -config ${CONFIG_FILE}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray
sleep 2

# Kiểm tra trạng thái Xray
if systemctl is-active --quiet xray; then
  echo "Xray đã khởi động thành công!"
else
  echo "Xray không khởi động được. Kiểm tra logs: journalctl -u xray -f"
  systemctl status xray
  exit 1
fi

# Lấy IP server
SERVER_IP=$(curl -s ifconfig.me)

# Mở port firewall (ufw và iptables)
if command -v ufw >/dev/null 2>&1; then
  ufw allow ${PORT}/tcp
  ufw allow 22/tcp
  ufw --force enable
fi
iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT

# In thông tin cấu hình cho client
echo "==== VLESS TCP Đơn giản ===="
echo "Address: $SERVER_IP"
echo "Port: $PORT"
echo "UUID: $UUID"
echo "Network: tcp"
echo "Encryption: none (decryption: none)"
echo "============================"

# Tạo cấu hình VLESS URL cho client
tls=""
VLESS_URL="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&security=${tls}&type=tcp#${PS_NAME}"
echo "VLESS URL: $VLESS_URL"

# Tạo mã QR code cho VLESS URL
QR_FILE="/root/vless_tcp_simple_qr.png"
qrencode -o ${QR_FILE} -s 5 -m 2 "${VLESS_URL}"
echo "Mã QR đã lưu tại: ${QR_FILE}"
echo "Quét mã QR dưới đây để nhập nhanh vào app:"
qrencode -t ANSIUTF8 "${VLESS_URL}"

echo "==== HƯỚNG DẪN SỬ DỤNG ===="
echo "1. Dùng v2rayN, v2rayNG, Shadowrocket (network: tcp, không TLS, không WebSocket, VLESS)."
echo "2. Quét mã QR hoặc nhập VLESS URL."
echo "3. Nếu không kết nối được, kiểm tra firewall, log Xray, và outbound server."
echo "4. Xem log truy cập: tail -f ${LOG_FILE}"
echo "============================="
