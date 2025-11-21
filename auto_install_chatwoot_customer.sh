#!/bin/bash
set -e
echo "=============================================="
echo " Script Auto Install N8n + Chatwoot + Proxy Manager"
echo " Version: 2.0"
echo " Author: Michel Tran"
echo " Website: https://phonuiit.com"
echo "=============================================="
# ================= Kiểm tra root =================
if [[ $EUID -ne 0 ]]; then
   echo "❌ Script cần chạy với quyền root"
   exit 1
fi

echo "================ CHATWOOT + N8N + NPM INSTALLER ================"

# ----------------- Hàm kiểm tra domain -----------------
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain 2>/dev/null | head -1)
    
    if [ -z "$domain_ip" ]; then
        echo "❌ Không thể resolve domain $domain"
        return 1
    fi
    
    if [ "$domain_ip" = "$server_ip" ]; then
        return 0
    else
        echo "❌ Domain $domain chưa trỏ đúng IP server"
        return 1
    fi
}

# ----------------- Nhập thông tin -----------------
read -p "Nhập domain Chatwoot: " CW_DOMAIN
read -p "Nhập domain N8n: " N8N_DOMAIN

for domain in $CW_DOMAIN $N8N_DOMAIN; do
    check_domain $domain || exit 1
done

read -p "Nhập tiền tố container (mặc định: services): " CONTAINER_PREFIX
CONTAINER_PREFIX=${CONTAINER_PREFIX:-services}

read -p "Nhập port Chatwoot Rails (mặc định 3000): " CHATWOOT_PORT
CHATWOOT_PORT=${CHATWOOT_PORT:-3000}

read -p "Nhập port N8n (mặc định 5678): " N8N_PORT
N8N_PORT=${N8N_PORT:-5678}

read -p "Nhập port Postgres (mặc định 5432): " POSTGRES_PORT
POSTGRES_PORT=${POSTGRES_PORT:-5432}

read -p "Nhập port Redis (mặc định 6379): " REDIS_PORT
REDIS_PORT=${REDIS_PORT:-6379}

BASE_DIR="/home/${CONTAINER_PREFIX}"
mkdir -p $BASE_DIR
cd $BASE_DIR
mkdir -p chatwoot/data/{postgres,redis,storage}
mkdir -p n8n/data

# ----------------- Tạo key bảo mật -----------------
SECRET_KEY=$(openssl rand -hex 64)
POSTGRES_PASSWORD=$(openssl rand -hex 16)
REDIS_PASSWORD=$(openssl rand -hex 16)

# ----------------- Tạo .env Chatwoot -----------------
cat > $BASE_DIR/chatwoot/.env <<EOF
FRONTEND_URL=https://${CW_DOMAIN}
RAILS_ENV=production
SECRET_KEY_BASE=${SECRET_KEY}
LOG_LEVEL=info
LOG_SIZE=1024
DEFAULT_LOCALE=vi
ACTIVE_STORAGE_SERVICE=local
INSTALLATION_ENV=docker
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DATABASE=chatwoot
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379
ENABLE_ACCOUNT_SIGNUP=true
EOF

# ----------------- Docker Compose Chatwoot -----------------
cat > $BASE_DIR/chatwoot/docker-compose.yml <<EOF
services:
  postgres:
    image: ankane/pgvector:latest
    container_name: ${CONTAINER_PREFIX}_chatwoot_postgres
    restart: always
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: chatwoot
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    ports:
      - "${POSTGRES_PORT}:5432"

  redis:
    image: redis:7-alpine
    container_name: ${CONTAINER_PREFIX}_chatwoot_redis
    restart: always
    command: redis-server --requirepass \${REDIS_PASSWORD}
    volumes:
      - ./data/redis:/data
    ports:
      - "${REDIS_PORT}:6379"

  rails:
    image: chatwoot/chatwoot:latest
    container_name: ${CONTAINER_PREFIX}_chatwoot_rails
    env_file: .env
    depends_on:
      - postgres
      - redis
    ports:
      - "${CHATWOOT_PORT}:3000"
    volumes:
      - ./data/storage:/app/storage
    restart: always
    command: bundle exec rails s -b 0.0.0.0 -p 3000

  sidekiq:
    image: chatwoot/chatwoot:latest
    container_name: ${CONTAINER_PREFIX}_chatwoot_sidekiq
    env_file: .env
    depends_on:
      - postgres
      - redis
    volumes:
      - ./data/storage:/app/storage
    restart: always
    command: bundle exec sidekiq
EOF

# ----------------- Docker Compose N8n -----------------
cat > $BASE_DIR/n8n/docker-compose.yml <<EOF
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: ${CONTAINER_PREFIX}_n8n
    restart: always
    environment:
      - N8N_HOST=${N8N_DOMAIN}
      - N8N_PORT=${N8N_PORT}
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${N8N_DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - N8N_DIAGNOSTICS_ENABLED=false
    volumes:
      - ./data:/home/node/.n8n
    ports:
      - "${N8N_PORT}:5678"
EOF

# ----------------- Cài Docker nếu chưa có -----------------
if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
    echo ">>> Cài Docker + Docker Compose ..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common dnsutils
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose
else
    echo "✅ Docker + Docker Compose đã cài, bỏ qua bước cài"
fi

# ----------------- Khởi động Chatwoot -----------------
echo ">>> Khởi động Chatwoot ..."
cd $BASE_DIR/chatwoot
docker compose up -d postgres redis

echo ">>> Chờ Postgres + Redis khởi động (sleep 20s) ..."
sleep 20

docker compose run --rm rails bundle exec rails db:chatwoot_prepare
docker compose up -d rails sidekiq

# ----------------- Khởi động N8n -----------------
echo ">>> Khởi động N8n ..."
cd $BASE_DIR/n8n
docker compose up -d
cd $BASE_DIR/n8n
sudo chown -R 1000:1000 data
# ----------------- Cài Nginx Proxy Manager -----------------
if [ ! "$(docker ps -q -f name=npm)" ]; then
    echo ">>> Cài Nginx Proxy Manager ..."
    docker volume create npm_data
    docker volume create npm_letsencrypt

    docker run -d \
      --name npm \
      -p 81:81 \
      -p 80:80 \
      -p 443:443 \
      -v npm_data:/data \
      -v npm_letsencrypt:/etc/letsencrypt \
      jc21/nginx-proxy-manager:latest
else
    echo "✅ Nginx Proxy Manager đã chạy, bỏ qua bước cài"
fi

echo "============================================"
echo "✅ INSTALLATION COMPLETED!"
echo "✅Author: Michel Tran"
echo "🔹 Chatwoot: http://${CW_DOMAIN}:${CHATWOOT_PORT} (NPM quản lý domain & SSL)"
echo "🔹 N8n: http://${N8N_DOMAIN}:${N8N_PORT} (NPM quản lý domain & SSL)"
echo "🔹 Nginx Proxy Manager: http://<server-ip>:81 (admin/changeme)"
echo "🔹 Thư mục dự án: $BASE_DIR"
echo "============================================"

