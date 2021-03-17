#!/usr/bin/env bash

swoole_task() {
    echo "[ThinkPHP] Starting swoole..."
    while IFS= read -r line; do
        php think "$line" start
    done < <(cat autostart.swoole.task)

}
cron_task() {
    echo "[ThinkPHP] Starting cron..."
    while true; do
        while IFS= read -r line; do
            php think "$line" &
        done < <(cat autostart.cron.task)
        sleep 60
    done
}

main() {
    ## if used ThinkPHP
    ## if you want run crontab or swoole task
    for f in /var/www/*/think; do
        path_app=${f%/*}
        cd "${path_app}" || exit 1
        if [[ -f "${path_app}/autostart.swoole" && -f "${path_app}/autostart.swoole.task" ]]; then
            swoole_task
        elif [[ -f "${path_app}/autostart.cron" && -f "${path_app}/autostart.cron.task" ]]; then
            cron_task &
        else
            echo '[ThinkPHP] Nothing to do.'
        fi
    done

    ## start php-fpm
    php-fpm
}

main "$@"
