#!/usr/bin/env bash

## catch the TERM signal and exit cleanly
trap "exit 0" HUP INT PIPE QUIT TERM

## start task
[ -f /var/www/schedule.sh ] && bash /var/www/schedule.sh &

## start php-fpm
exec php-fpm