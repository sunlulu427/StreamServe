FROM registry.aliyuncs.com/library/alpine:3.20

LABEL maintainer="StreamServe Ops"

RUN set -eux; \
    apk add --no-cache nginx nginx-mod-rtmp tzdata bash curl; \
    mkdir -p /var/www/hls /var/www/stat /run/nginx; \
    chown -R nginx:nginx /var/www/hls /var/www/stat

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 1935

STOPSIGNAL SIGTERM

CMD ["/entrypoint.sh"]
