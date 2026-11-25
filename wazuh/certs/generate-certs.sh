#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="/certificates"
TMP_DIR="/tmp/wazuh-certs"

if [ -f "${CERT_DIR}/indexer.pem" ] && [ -f "${CERT_DIR}/admin.pem" ] && [ -f "${CERT_DIR}/server.pem" ] && [ -f "${CERT_DIR}/dashboard.pem" ]; then
  echo "Certificados já existem em ${CERT_DIR}. Pulando geração."
  exit 0
fi

mkdir -p "${TMP_DIR}" "${CERT_DIR}"
cd "${TMP_DIR}"

# 1. Root CA
openssl genrsa -out root-ca-key.pem 2048
openssl req -x509 -new -nodes -key root-ca-key.pem -sha256 -days 3650 \
  -subj "/C=BR/ST=MG/L=BeloHorizonte/O=Wazuh/OU=Security/CN=root-ca" \
  -out root-ca.pem

generate_signed_cert() {
  local prefix="$1"
  local cn_name="$2"

  openssl genrsa -out "${prefix}-key.pem" 2048
  openssl req -new -key "${prefix}-key.pem" \
    -subj "/C=BR/ST=MG/L=BeloHorizonte/O=Wazuh/OU=Security/CN=${cn_name}" \
    -out "${prefix}.csr"

  cat <<EOF > "${TMP_DIR}/ext.cnf"
subjectAltName=DNS:${cn_name},DNS:localhost,IP:127.0.0.1
EOF

  openssl x509 -req -in "${prefix}.csr" -CA root-ca.pem -CAkey root-ca-key.pem \
    -CAcreateserial -out "${prefix}.pem" -days 3650 -sha256 -extfile "${TMP_DIR}/ext.cnf"

  rm -f "${prefix}.csr" "${TMP_DIR}/ext.cnf"
}

generate_signed_cert "indexer" "wazuh-indexer"
generate_signed_cert "admin" "admin"
generate_signed_cert "server" "wazuh-server"
generate_signed_cert "dashboard" "wazuh-dashboard"

cp "${TMP_DIR}"/*.pem "${CERT_DIR}/"
chmod 644 "${CERT_DIR}"/*.pem
chmod 600 "${CERT_DIR}"/*-key.pem
chown -R 1000:1000 "${CERT_DIR}"

echo "Certificados gerados com sucesso em ${CERT_DIR}."