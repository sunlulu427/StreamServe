worker_processes auto;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
  worker_connections 1024;
}

rtmp {
  include /etc/nginx/conf.d/rtmp.conf;
}

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  sendfile        on;
  keepalive_timeout 65;

  server {
    listen 80;
    listen [::]:80;
    server_name ${STREAMSERVE_DOMAIN};

    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";

    location / {
      return 200 'StreamServe 控制面已运行';
      add_header Content-Type text/plain;
    }

    location /hls/ {
      types {
        application/vnd.apple.mpegurl m3u8;
        video/mp2t ts;
      }
      root /var/www;
      add_header Cache-Control no-cache;
      add_header Access-Control-Allow-Origin *;
      add_header Access-Control-Allow-Headers *;
      add_header Access-Control-Allow-Methods 'GET, HEAD, OPTIONS';
      expires -1;
    }

    location /stat {
      rtmp_stat all;
      rtmp_stat_stylesheet stat.xsl;
    }

    location /stat.xsl {
      root /var/www/stat/;
    }
  }

  server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${STREAMSERVE_DOMAIN};

    ssl_certificate ${SSL_CERT_PATH};
    ssl_certificate_key ${SSL_CERT_PATH};
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
      return 200 'StreamServe HTTPS 监听正常';
      add_header Content-Type text/plain;
    }

    location /hls/ {
      types {
        application/vnd.apple.mpegurl m3u8;
        video/mp2t ts;
      }
      root /var/www;
      add_header Cache-Control no-cache;
      add_header Access-Control-Allow-Origin *;
      add_header Access-Control-Allow-Headers *;
      add_header Access-Control-Allow-Methods 'GET, HEAD, OPTIONS';
      expires -1;
    }
  }
}
