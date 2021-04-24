#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091

## program type
if [ -f artisan ]; then
    prog_type=laraval
    prog_file=artisan
elif [ -f think ]; then
    prog_type=ThinkPHP
    prog_file=think
fi

# echo "SwooleTask start" >task.swoole.1
# echo "RefundCheck" >task.cron.1
# echo "PushTask" >task.cron.2
# echo "OrderCheck" >task.cron.3
# echo "Fix" >task.cron.4
# echo "TsOrderCheck" >task.cron.5
# echo "schedule:run" >task.cron.6
# echo "base:socket start --d" >task.cron.7
# echo "queue:work --queue=sms" >task.cron.8

task_swoole() {
    for i in task.swoole.*; do
        echo "[$prog_type] starting $i..."
        php "${prog_file}" $(cat "$i") &
    done
}

task_cron() {
    while true; do
        for j in task.cron.*; do
            echo "[$prog_type] starting $j..."
            php "${prog_file}" $(cat "$j") &
        done
        sleep 60
    done
}

main() {
    for f in /var/www/*/"${prog_file}"; do
        cd "${f%/*}" || exit 1
        task_swoole &
        task_cron &
    done
}

main "$@"
