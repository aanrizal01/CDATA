#!/bin/bash
# Auto-install CMS C-DATA + Docker + SSL + Auto-renew (Ubuntu 24.04)
# Domain default: acsc.gogiga.id
# CMS version default: 3.6.9

CMS_VERSION="3.6.9"
CMS_DIR="/opt/cms"
DOMAIN="acsc.gogiga.id"
EMAIL="admin@gogiga.id"
SSL_DIR="/opt/cms-ssl"

echo "=== Auto Install CMS C-DATA + SSL + Auto-Renew for $DOMAIN ==="

# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Install prerequisites
sudo apt install -y curl ca-certificates gnupg lsb-release cron

# 3. Install Docker jika belum ada
if ! command -v docker &> /dev/null; then
    echo "=== Installing Docker ==="
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
else
    echo "[INFO] Docker sudah terpasang"
fi

# 4. Pastikan Docker Compose tersedia
if ! docker compose version &> /dev/null; then
    echo "[ERROR] Docker Compose plugin tidak ditemukan."
    exit 1
fi

# 5. Download CMS installer
sudo curl -fsSL -o cms_install.sh https://cms.s.cdatayun.com/cms_linux/cms_install.sh
sudo chmod +x cms_install.sh

# 6. Install CMS
sudo ./cms_install.sh install --version "$CMS_VERSION"

# 7. Masuk folder CMS
if [ -d "$CMS_DIR" ]; then
    cd "$CMS_DIR"
elif [ -d "./CMS" ]; then
    cd "./CMS"
else
    echo "[WARNING] Direktori CMS tidak ditemukan, menggunakan current folder"
fi

# 8. Start CMS
sudo docker compose up -d

# 9. Setup folder SSL
mkdir -p $SSL_DIR
cd $SSL_DIR

# 10. Stop CMS nginx sementara (untuk port 80)
docker stop cms-nginx 2>/dev/null || true

# 11. Request SSL dengan Certbot standalone
docker run --rm -p 80:80 \
    -v "$SSL_DIR/certs:/etc/letsencrypt" \
    certbot/certbot certonly --standalone \
    --email $EMAIL --agree-tos --no-eff-email \
    -d $DOMAIN

# 12. Buat docker-compose untuk Nginx SSL
cat > docker-compose.yml <<'EOF'
version: '3.8'
services:
  nginx-proxy:
    image: nginx:latest
    container_name: cms-ssl-proxy
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certs:/etc/letsencrypt
    networks:
      - cms-network

networks:
  cms-network:
    external: true
EOF

# 13. Buat nginx.conf
cat > nginx.conf <<EOF
events {}

http {
    server {
        listen 80;
        server_name $DOMAIN;
        return 301 https://\$host\$request_uri;
    }

    server {
        listen 443 ssl;
        server_name $DOMAIN;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

        location / {
            proxy_pass http://cms-nginx:80;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }
}
EOF

# 14. Pastikan network CMS ada
docker network inspect cms-network >/dev/null 2>&1 || docker network create cms-network

# 15. Hubungkan cms-nginx ke network
docker network connect cms-network cms-nginx || echo "[INFO] cms-nginx sudah terhubung ke cms-network"

# 16. Jalankan Nginx proxy
docker compose up -d

# 17. Setup auto-renew cron job
CRON_CMD="0 3 * * * docker run --rm -p 80:80 -v $SSL_DIR/certs:/etc/letsencrypt certbot/certbot renew --standalone && docker compose -f $SSL_DIR/docker-compose.yml exec nginx-proxy nginx -s reload"
(crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -

echo "=== Instalasi CMS + SSL + Auto-Renew selesai! ==="
echo "Akses CMS di: https://$DOMAIN"
echo "SSL akan diperbarui otomatis setiap 3 bulan"
