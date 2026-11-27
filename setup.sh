#!/usr/bin/env bash
# Prepara o host. Pode ser executado mais de uma vez.
set -euo pipefail
cd "$(dirname "$0")"

WAZUH_TAG="v4.10.0"
CERTS="wazuh/config/wazuh_indexer_ssl_certs"

[ "$(id -u)" -eq 0 ] || { echo "Execute como root."; exit 1; }
command -v git >/dev/null || { echo "Instale o git: apt install -y git"; exit 1; }
command -v openssl >/dev/null || { echo "Instale o openssl: apt install -y openssl"; exit 1; }

echo "[1/4] Ajustando vm.max_map_count"
echo "vm.max_map_count=262144" > /etc/sysctl.d/99-opensearch.conf
sysctl -w vm.max_map_count=262144 >/dev/null

echo "[2/4] Preparando .env"
if ! grep -q '^SHUFFLE_ENCRYPTION_MODIFIER=.' .env 2>/dev/null; then
  [ -f .env ] && cp .env ".env.bak.$(date +%s)"
  # Senhas padrão oficiais do Wazuh: só para o primeiro boot. Ver README.
  cat > .env <<ENV
INDEXER_PASSWORD='SecretPassword'
DASHBOARD_PASSWORD='kibanaserver'
API_PASSWORD='MyS3cr37P450r.*-'
SHUFFLE_ENCRYPTION_MODIFIER='$(openssl rand -hex 32)'
ENV
  chmod 600 .env
fi

echo "[3/4] Baixando configurações oficiais do Wazuh ${WAZUH_TAG}"
if [ ! -f wazuh/config/wazuh_indexer/internal_users.yml ]; then
  tmp="$(mktemp -d)"
  git clone --quiet --depth 1 -b "$WAZUH_TAG" https://github.com/wazuh/wazuh-docker.git "$tmp/repo"
  mkdir -p wazuh/config
  cp -r "$tmp/repo/single-node/config/." wazuh/config/
  rm -rf "$tmp"
fi

echo "[4/4] Gerando certificados"
mkdir -p "$CERTS" shuffle-apps shuffle-files
if [ ! -f "$CERTS/wazuh.indexer.pem" ]; then
  docker compose run --rm wazuh-certs-gen
fi

for f in root-ca.pem root-ca-manager.pem admin.pem admin-key.pem \
         wazuh.indexer.pem wazuh.indexer-key.pem \
         wazuh.manager.pem wazuh.manager-key.pem \
         wazuh.dashboard.pem wazuh.dashboard-key.pem; do
  [ -f "$CERTS/$f" ] || { echo "ERRO: certificado ausente: $CERTS/$f"; exit 1; }
done

echo "Pronto. Agora execute: docker compose up -d --remove-orphans"
