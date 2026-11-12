#!/usr/bin/env bash
# Despliegue de PrioMed en una instancia EC2 Amazon Linux 2023 (se ejecuta EN la instancia).
# Requisitos previos: los tres repos copiados en ~/priomed/ como carpetas hermanas.
#   ~/priomed/priomed-classification-service  ~/priomed/priomed-infra  ~/priomed/priomed-docs
# Idempotente: se puede volver a correr para redesplegar.
set -euo pipefail

ROOT="${PRIOMED_ROOT:-$HOME/priomed}"
INFRA="$ROOT/priomed-infra"
WEB=/var/www/priomed

TOKEN=$(curl -s -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token)
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
echo ">> IP pública: $PUBLIC_IP"

# 1. Swap: t3.micro tiene ~1 GB de RAM; el build y el entrenamiento de scikit-learn lo necesitan.
if ! swapon --show | grep -q /swapfile; then
  echo ">> Creando swap de 1 GB"
  sudo dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
  sudo chmod 600 /swapfile && sudo mkswap /swapfile >/dev/null && sudo swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

# 2. Docker + plugins compose/buildx
sudo dnf install -y -q docker httpd mod_ssl >/dev/null
sudo systemctl enable --now docker
PLUGINS=/usr/local/lib/docker/cli-plugins
if ! docker compose version >/dev/null 2>&1; then
  echo ">> Instalando docker compose v2"
  sudo mkdir -p "$PLUGINS"
  sudo curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64" -o "$PLUGINS/docker-compose"
  sudo chmod +x "$PLUGINS/docker-compose"
fi
if ! docker buildx version >/dev/null 2>&1; then
  echo ">> Instalando docker buildx"
  sudo mkdir -p "$PLUGINS"
  sudo curl -fsSL "https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-amd64" -o "$PLUGINS/docker-buildx"
  sudo chmod +x "$PLUGINS/docker-buildx"
fi

# 3. Variables de entorno (.env no versionado; se genera una contraseña aleatoria la primera vez)
cd "$INFRA"
if [ ! -f .env ]; then
  echo ">> Generando .env"
  (
    umask 077  # solo en este subshell: .env legible solo por el dueño
    cat > .env <<ENV
POSTGRES_PASSWORD=$(openssl rand -hex 24)
PRIOMED_CORS_ORIGINS=http://priomed.$PUBLIC_IP.nip.io,http://priomed.$PUBLIC_IP.sslip.io,http://localhost:5173
ENV
  )
fi

# 4. Contenedores
echo ">> Construyendo y levantando contenedores"
sudo docker compose up -d --build
echo ">> Esperando /health"
for i in $(seq 1 60); do
  curl -fs http://127.0.0.1:8000/health >/dev/null && break
  sleep 3
done
curl -fs http://127.0.0.1:8000/health && echo

# 5. Portal estático + documentación
sudo mkdir -p "$WEB/docs-proyecto"
sudo cp "$INFRA/deploy/web/index.html" "$WEB/index.html"
sudo cp -r "$ROOT/priomed-docs/figures/"*.png "$WEB/docs-proyecto/"
sudo cp "$ROOT/priomed-docs/paper/"*.docx "$ROOT/priomed-docs/presentation/"*.pptx "$WEB/docs-proyecto/"
sudo cp "$ROOT/priomed-classification-service/reports/evaluation_report.md" "$WEB/docs-proyecto/" 2>/dev/null || true
sudo chmod -R u=rwX,go=rX "$WEB"

# 6. Reverse proxy (VirtualHost propio; no toca los demás sitios del servidor)
sed "s/__PUBLIC_IP__/$PUBLIC_IP/g" "$INFRA/deploy/priomed-httpd.conf" | sudo tee /etc/httpd/conf.d/priomed.conf >/dev/null
sudo apachectl configtest
sudo systemctl enable httpd >/dev/null
sudo systemctl reload httpd

echo ">> Listo: http://priomed.$PUBLIC_IP.nip.io/  ·  Swagger: http://priomed.$PUBLIC_IP.nip.io/docs"
