#!/bin/sh
set -euo pipefail

DOMAIN=${DOMAIN:-example.com}
WORKDIR=/etc/nginx/tls
LIVE_DIR=/etc/letsencrypt/live/${DOMAIN}

mkdir -p "$WORKDIR"

if [ -f "${LIVE_DIR}/fullchain.pem" ] && [ -f "${LIVE_DIR}/privkey.pem" ]; then
  ln -sf "${LIVE_DIR}/fullchain.pem" "${WORKDIR}/server.crt"
  ln -sf "${LIVE_DIR}/privkey.pem" "${WORKDIR}/server.key"
else
  if [ ! -f "${WORKDIR}/selfsigned.crt" ] || [ ! -f "${WORKDIR}/selfsigned.key" ]; then
    echo "[nginx] generating temporary self-signed certificate for ${DOMAIN}" >&2
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout "${WORKDIR}/selfsigned.key" \
      -out "${WORKDIR}/selfsigned.crt" \
      -days 1 \
      -subj "/CN=${DOMAIN}"
  fi
  ln -sf "${WORKDIR}/selfsigned.crt" "${WORKDIR}/server.crt"
  ln -sf "${WORKDIR}/selfsigned.key" "${WORKDIR}/server.key"
fi

