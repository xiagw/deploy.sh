#!/bin/bash

## laradock nginx 启动初始化

## generate cert
ssl_dir="/etc/nginx/ssl"
mkdir -p "$ssl_dir"
if [ ! -f "$ssl_dir/default.pem" ]; then
    openssl genrsa -out "$ssl_dir/default.key" 2048
    openssl req -new -key "$ssl_dir/default.key" -out "$ssl_dir/default.csr" -subj "/CN=default/O=default/C=CN"
    openssl x509 -req -days 3650 -in "$ssl_dir/default.csr" -signkey "$ssl_dir/default.key" -out "$ssl_dir/default.pem"
fi
if [ ! -f "$ssl_dir/dhparams.pem" ]; then
    openssl dhparam -dsaparam -out "$ssl_dir/dhparams.pem" 4096
fi
# chown 1000:1000 $html_path
chmod 600 "$ssl_dir"/*.key
chown -R nginx "$ssl_dir"/*.key "$log_path"

html_path=/var/www/html
log_path=/var/log/nginx
mkdir -p "$html_path"/{s,tp,.well-known/acme-challenge}
if [ ! -f "$html_path/.well-known/security.txt" ]; then
    (
      echo "Contact: mailto:root@website.com"
      echo "Expires: 2050-12-31T00:00:00Z"
    ) >"$html_path/.well-known/security.txt"
fi
[ -f "$html_path/index.html" ] || echo "INDEX Page: $(date)" >>"$html_path/index.html"
[ -f "$html_path/favicon.ico" ] || touch "$html_path/favicon.ico"

## nginx 4xx 5xx
if [ ! -f "$html_path/4xx.html" ]; then
    echo 'Client error page: 4xx' >>"$html_path/4xx.html"
fi
if [ ! -f "$html_path/5xx.html" ]; then
    echo 'Server error page: 5xx' >>"$html_path/5xx.html"
fi

## php upstream
if ping -c 2 php-fpm >/dev/null 2>&1; then
    server_name=php-fpm
fi
echo "upstream upstream-php { server ${server_name:-127.0.0.1}:9000; }" >/etc/nginx/conf.d/upstream-php.conf

## remove log files / 自动清理超过15天的旧日志文件
while [ -d "$log_path" ] && [ ! -f "$log_path/.keep_all_log" ]; do
    find "$log_path" -type f -iname "*.log" -ctime +15 -delete
    sleep 1d
done &

# Start crond in background
# crond -l 2 -b

# Start nginx in foreground
# exec nginx
