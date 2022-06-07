#!/usr/bin/env bash

## catch the TERM signal and exit cleanly
trap "exit 0" HUP INT PIPE QUIT TERM

## schedule task
[ -f /var/www/schedule.sh ] && bash /var/www/schedule.sh &
[ -f /app/schedule.sh ] && bash /app/schedule.sh &

## start php-fpm
if [ -f easyswoole ]; then
    exec php easyswoole server start -mode=config
elif command -v php-fpm >/dev/null 2>&1; then
    exec php-fpm -F
else
    echo "No easyswoole/php-fpm found, exit 1."
    exit 1
fi
