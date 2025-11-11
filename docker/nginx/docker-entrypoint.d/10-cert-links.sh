#!/bin/sh
set -euo pipefail

DOMAIN=${DOMAIN:-example.com}
WORKDIR=/etc/nginx/tls
LIVE_DIR=/etc/letsencrypt/live/${DOMAIN}

mkdir -p "$WORKDIR"

if [ -f "${LIVE_DIR}/fullchain.pem" ] && [ -f "${LIVE_DIR}/privkey.pem" ]; then
  echo "[nginx] using Let's Encrypt certificates for ${DOMAIN}" >&2
  ln -sf "${LIVE_DIR}/fullchain.pem" "${WORKDIR}/server.crt"
  ln -sf "${LIVE_DIR}/privkey.pem" "${WORKDIR}/server.key"
else
  echo "[nginx] generating temporary self-signed certificate for ${DOMAIN}" >&2
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "${WORKDIR}/selfsigned.key" \
    -out "${WORKDIR}/selfsigned.crt" \
    -days 365 \
    -subj "/CN=${DOMAIN}"
  ln -sf "${WORKDIR}/selfsigned.crt" "${WORKDIR}/server.crt"
  ln -sf "${WORKDIR}/selfsigned.key" "${WORKDIR}/server.key"
fi

