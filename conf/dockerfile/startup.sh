#!/usr/bin/env bash

## run schedule.sh
[ -f '/var/www/schedule.sh' ] && source '/var/www/schedule.sh'

## start php-fpm
php-fpm
