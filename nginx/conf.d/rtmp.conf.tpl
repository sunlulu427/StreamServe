server {
  listen 1935;
  chunk_size 4096;

  application live {
    live on;
    record off;
    sync 3ms;
    max_connections 1024;
    include /etc/nginx/conf.d/rtmp-allow.conf;

    allow play all;

    hls on;
    hls_path /var/www/hls;
    hls_fragment 3s;
    hls_playlist_length 30s;
    hls_continuous on;
    hls_nested on;
  }
}
