FROM nginx:1.27-alpine

RUN apk add --no-cache openssl

COPY nginx.conf /etc/nginx/nginx.conf
COPY options-ssl-nginx.conf /etc/letsencrypt/options-ssl-nginx.conf
COPY docker-entrypoint.d/ /docker-entrypoint.d/

RUN chmod +x /docker-entrypoint.d/*.sh && \
    mkdir -p /var/www/certbot /var/cache/nginx /etc/nginx/tls && \
    chown -R nginx:nginx /var/www/certbot /var/cache/nginx /var/run /etc/nginx/tls

EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1

