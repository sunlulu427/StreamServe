#!/bin/sh
set -e

mkdir -p /var/www/hls /var/www/stat /run/nginx
chown -R nginx:nginx /var/www/hls /var/www/stat

exec nginx -g "daemon off;"
