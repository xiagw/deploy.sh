#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091

cron_task() {
    echo "[ThinkPHP] Starting cron..."
    while true; do
        for j in ${task_cron}; do
            php think "$j" &
        done
        sleep 60
    done
}

main() {
    ## if you want run crontab or swoole task in ThinkPHP
    for f in /var/www/*/think; do
        path_app=${f%/*}
        cd "${path_app}" || exit 1

        if [[ -f 'autostart.env' ]]; then
            source 'autostart.env'
            if [[ ${autostart_swoole:-0} == 'true' ]]; then
                echo "[ThinkPHP] Starting swoole..."
                php think "${task_swoole:-SwooleTask}" start
            fi
            if [[ ${autostart_cron:-0} == 'true' ]]; then
                cron_task &
            fi
        else
            echo '[ThinkPHP] Nothing to do.'
        fi
    done

    ## start php-fpm
    php-fpm
}

main "$@"
