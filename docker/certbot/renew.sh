#!/bin/sh
set -euo pipefail

DOMAINS=${DOMAINS:-example.com}
SSL_EMAIL=${SSL_EMAIL:-}
WEBROOT_PATH=${WEBROOT_PATH:-/var/www/certbot}
STAGING=${STAGING:-false}
RENEW_INTERVAL_HOURS=${RENEW_INTERVAL_HOURS:-12}

if [ -z "$SSL_EMAIL" ]; then
  echo "[certbot] SSL_EMAIL environment variable is required" >&2
  exit 1
fi

DOMAIN_ARGS=""
for domain in $(echo "$DOMAINS" | tr ',' ' '); do
  DOMAIN_ARGS="$DOMAIN_ARGS -d $domain"
done

STAGING_ARG=""
if [ "$STAGING" = "true" ]; then
  STAGING_ARG="--staging"
fi

case "${1:-renew}" in
  issue)
    exec certbot certonly \
      --webroot -w "$WEBROOT_PATH" \
      $STAGING_ARG \
      --non-interactive \
      --agree-tos \
      --email "$SSL_EMAIL" \
      --keep-until-expiring \
      $DOMAIN_ARGS
    ;;
  renew)
    while true; do
      echo "[certbot] running renewal check";
      certbot renew \
        --webroot -w "$WEBROOT_PATH" \
        $STAGING_ARG \
        --non-interactive \
        --quiet;
      sleep "$((RENEW_INTERVAL_HOURS * 3600))";
    done
    ;;
  *)
    exec "$@"
    ;;
esac

