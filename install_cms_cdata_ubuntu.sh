#!/bin/bash
# Auto-install Docker + C-DATA CMS on Ubuntu 24.04 (Noble)
# CMS version default: 3.6.9

CMS_VERSION="3.6.9"
CMS_DIR="/opt/cms"

echo "=== C-DATA CMS Auto Installer for Ubuntu 24.04 ==="
echo "Versi CMS yang akan diinstall: $CMS_VERSION"

# 1. Update system
echo "=== Updating system packages ==="
sudo apt update && sudo apt upgrade -y

# 2. Install prerequisites
echo "=== Installing required packages (curl, ca-certificates, gnupg) ==="
sudo apt install -y curl ca-certificates gnupg lsb-release

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

# 5. Download CMS installer script
echo "=== Downloading CMS installer script ==="
sudo curl -fsSL -o cms_install.sh https://cms.s.cdatayun.com/cms_linux/cms_install.sh
if [ $? -ne 0 ]; then
    echo "[ERROR] Gagal download cms_install.sh"
    exit 1
fi
sudo chmod +x cms_install.sh

# 6. Install CMS
echo "=== Installing CMS version $CMS_VERSION ==="
sudo ./cms_install.sh install --version "$CMS_VERSION"
if [ $? -ne 0 ]; then
    echo "[ERROR] Gagal menginstall CMS"
    exit 1
fi

# 7. Masuk ke folder CMS
if [ -d "$CMS_DIR" ]; then
    cd "$CMS_DIR"
elif [ -d "./CMS" ]; then
    cd "./CMS"
else
    echo "[WARNING] Direktori CMS tidak ditemukan secara default, menggunakan current folder"
fi

# 8. Start CMS dengan Docker Compose
echo "=== Starting CMS containers ==="
sudo docker compose up -d

# 9. Cek status container
echo "=== Checking running containers ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 10. Tampilkan URL akses
IP=$(hostname -I | awk '{print $1}')
echo "=== Instalasi selesai ==="
echo "Akses CMS di: http://$IP:8080"
echo "Default login biasanya: admin / admin123 (cek dokumentasi resmi)"
