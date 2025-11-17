#!/bin/bash
# ==============================================
# Script: Auto Install Chatwoot + Nginx Proxy Manager
# Phiên bản: 1.0
# Tác giả: Michel Tran
# Website: https://phonuiit.com
# Liên hệ: support@phonuiit.com
# Mục đích: Tự động cài Chatwoot instance riêng biệt
#           với Rails + Sidekiq, Proxy Host + SSL trên Nginx Proxy Manager
# Tính năng:
#   - Tạo container Chatwoot riêng cho mỗi instance
#   - Tạo thư mục data riêng
#   - Tự động tạo SECRET_KEY
#   - Chuẩn bị database và chạy Rails + Sidekiq
#   - Cài đặt Nginx Proxy Manager nếu chưa có
#   - Tạo Proxy Host + SSL tự động
#   - Kiểm tra port trùng và tên container trùng
# ==============================================

set -e

echo "==============================================="
echo "INSTALL CHATWOOT INSTANCE + NGINX PROXY MANAGER"
echo "==============================================="

# 1. Cài jq nếu chưa có
if ! command -v jq &> /dev/null
then
    echo "📦 Cài đặt jq..."
    sudo apt update && sudo apt install -y jq
else
    echo "✔ jq đã có sẵn, bỏ qua"
fi

# 2. Kiểm tra Docker
if ! command -v docker &> /dev/null
then
    echo "🐳 Cài đặt Docker..."
    sudo apt update
    sudo apt install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
else
    echo "✔ Docker đã có sẵn, bỏ qua"
fi

# 3. Kiểm tra Docker Compose
if ! docker compose version &> /dev/null
then
    echo "📦 Cài đặt Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
else
    echo "✔ Docker Compose đã có sẵn, bỏ qua"
fi

# 4. Nhập domain
read -p "Nhập domain (vd: chat.example.com): " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    echo "❌ Chưa nhập domain. Thoát!"
    exit 1
fi

# 5. Nhập port và check trùng
while true; do
    read -p "Nhập port Chatwoot forward (vd: 3000): " CHAT_PORT
    if [ -z "$CHAT_PORT" ]; then
        echo "❌ Chưa nhập port."
        continue
    fi
    if ss -tln | grep ":$CHAT_PORT " > /dev/null; then
        echo "❌ Port $CHAT_PORT đang dùng. Vui lòng nhập port khác."
    else
        break
    fi
done

# 6. Nhập tên container và check trùng
while true; do
    read -p "Nhập tên container (vd: chatwoot1): " CONTAINER_NAME
    if [ -z "$CONTAINER_NAME" ]; then
        echo "❌ Chưa nhập tên container."
        continue
    fi
    if docker ps -a --format '{{.Names}}' | grep -w "$CONTAINER_NAME" > /dev/null; then
        echo "❌ Container $CONTAINER_NAME đã tồn tại. Nhập tên khác."
    else
        break
    fi
done

# 7. Thiết lập thư mục
DOMAIN_DIR="/home/$DOMAIN_NAME"
CHATWOOT_DIR="$DOMAIN_DIR/$CONTAINER_NAME"
PROXY_DIR="$DOMAIN_DIR/nginx-proxy"
ENV_CHAT="$CHATWOOT_DIR/.env"

echo "===== TẠO THƯ MỤC ====="
mkdir -p $CHATWOOT_DIR/data/storage $CHATWOOT_DIR/data/postgres $CHATWOOT_DIR/data/redis
mkdir -p $PROXY_DIR

# 8. Kiểm tra .env
if [ ! -f "$ENV_CHAT" ]; then
    echo "⚠ File .env chưa tồn tại. Vui lòng upload file vào $CHATWOOT_DIR"
    exit 1
fi

# 9. Tạo SECRET_KEY
SECRET_KEY=$(openssl rand -hex 64)
sed -i "s|SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$SECRET_KEY|" $ENV_CHAT
echo "✔ SECRET_KEY đã tạo: $SECRET_KEY"

# 10. Chuẩn bị DB
cd $CHATWOOT_DIR
docker compose run --rm rails bundle exec rails db:chatwoot_prepare

# 11. Chạy Rails + Sidekiq với tên container riêng
docker compose -p $CONTAINER_NAME up -d rails sidekiq
echo "✔ Chatwoot container $CONTAINER_NAME đang chạy"

# 12. Cài Nginx Proxy Manager nếu chưa có
if [ ! -f "$PROXY_DIR/docker-compose.yml" ]; then
cat > $PROXY_DIR/docker-compose.yml <<EOF
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF
fi

cd $PROXY_DIR
docker compose up -d

# 13. Đợi NPM khởi động
echo "⏳ Đợi 15s cho Nginx Proxy Manager khởi động..."
sleep 15

NPM_URL="http://localhost:81"
NPM_EMAIL="admin@example.com"
NPM_PASS="changeme"

# 14. Lấy token API
TOKEN=$(curl -s -X POST "$NPM_URL/api/tokens" \
  -H "Content-Type: application/json" \
  -d "{\"identity\":\"$NPM_EMAIL\",\"secret\":\"$NPM_PASS\"}" | jq -r '.token')

if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ Lấy token NPM thất bại. Kiểm tra NPM đã chạy chưa."
    exit 1
fi

echo "✔ Lấy token NPM thành công"

# 15. Lấy IP container Rails
RAILS_CONTAINER=$(docker ps --format '{{.Names}}' | grep $CONTAINER_NAME)
RAILS_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $RAILS_CONTAINER)
echo "✔ Rails container IP: $RAILS_IP"

# 16. Tạo Proxy Host trong NPM
curl -s -X POST "$NPM_URL/api/nginx/proxy-hosts" \
-H "Authorization: Bearer $TOKEN" \
-H "Content-Type: application/json" \
-d "{
  \"domain_names\": [\"$DOMAIN_NAME\"],
  \"forward_scheme\": \"http\",
  \"forward_host\": \"$RAILS_IP\",
  \"forward_port\": $CHAT_PORT,
  \"block_exploits\": true,
  \"caching_enabled\": false,
  \"ssl\": {
    \"enabled\": true,
    \"force_ssl\": true,
    \"http2\": true,
    \"hsts_enabled\": true,
    \"hsts_subdomains\": true,
    \"hsts_include_subdomains\": true,
    \"letsencrypt_email\": \"$NPM_EMAIL\",
    \"letsencrypt_agree\": true
  }
}"

echo "==============================================="
echo "HOÀN TẤT CÀI ĐẶT CHATWOOT INSTANCE RIÊNG BIỆT!"
echo "-----------------------------------------------"
echo "📌 Domain: $DOMAIN_NAME"
echo "📌 Container: $CONTAINER_NAME"
echo "📌 Port forward: $CHAT_PORT"
echo "📌 Nginx Proxy Manager: http://IP-SERVER:81"
echo "📌 Email NPM: $NPM_EMAIL / Password: $NPM_PASS"
echo "📌 Tác giả: Michel Tran"
echo "📌 Website: https://phonuiit.com"
echo "📌 Liên hệ: support@phonuiit.com"
echo "==============================================="
