#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091

cron_task() {
    echo "[${prog_type:?empty var}] Starting ${schedule_type:-0}..."
    while true; do
        for j in ${task_cron:?empty var}; do
            php "${prog_file:?empty var}" "$j" &
        done
        sleep 60
    done
}

main() {
    ## if you want run crontab or swoole task in $prog_type
    for f in /var/www/*/"${prog_file}"; do
        path_app=${f%/*}
        cd "${path_app}" || exit 1

        if [[ -f 'schedule.env' ]]; then
            source 'schedule.env'
            case ${schedule_type:-0} in
            'swoole')
                echo "[$prog_type] Starting ${schedule_type:-0}..."
                php "${prog_file}" "${task_swoole:-SwooleTask}" start
                ;;
            'cron')
                cron_task &
                ;;
            esac
        else
            echo "[${prog_type:-null}] Nothing to do."
        fi
    done

    ## start php-fpm
    php-fpm
}

main "$@"
