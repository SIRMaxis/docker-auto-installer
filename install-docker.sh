#!/bin/bash
set -e

echo "=== Updating system ==="
sudo apt update

echo "=== Installing required packages ==="
sudo apt install -y ca-certificates curl

echo "=== Creating keyrings directory ==="
sudo install -m 0755 -d /etc/apt/keyrings

echo "=== Downloading Docker GPG key ==="
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "=== Adding Docker APT repository ==="
sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

echo "=== Updating package index ==="
sudo apt update

echo "=== Installing Docker Engine + plugins ==="
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== Creating /etc/docker/daemon.json ==="
sudo mkdir -p /etc/docker

sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "insecure-registries": ["https://docker.iw5.ir"],
  "registry-mirrors": ["https://docker.iw5.ir"]
}
EOF

echo "=== Restarting Docker service ==="
sudo systemctl daemon-reload
sudo systemctl restart docker

echo "=== Done! Docker installed and configured successfully. ==="
docker --version
