FROM certbot/certbot:latest

COPY renew.sh /opt/certbot/renew.sh

RUN chmod +x /opt/certbot/renew.sh

ENTRYPOINT ["/opt/certbot/renew.sh"]

CMD ["renew"]

