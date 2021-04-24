#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091

# echo "SwooleTask start" >task.swoole.1
# echo "RefundCheck" >task.cron.1
# echo "PushTask" >task.cron.2
# echo "OrderCheck" >task.cron.3
# echo "Fix" >task.cron.4
# echo "TsOrderCheck" >task.cron.5
# echo "schedule:run" >task.cron.6
# echo "base:socket start --d" >task.cron.7
# echo "queue:work --queue=sms" >task.cron.8

main() {
    for d in /var/www/*; do
        if [ -d "$d" ]; then
            cd "${d}" || exit 1
            ## program type
            if [ -f artisan ]; then
                prog_type=laraval
                prog_file=artisan
            elif [ -f think ]; then
                prog_type=ThinkPHP
                prog_file=think
            else
                continue
            fi
            for i in task.*; do
                if [ -f "$i" ]; then
                    echo "[$prog_type] starting $i..."
                    if [[ "$i" =~ task.swoole.* ]]; then
                        php "${prog_file}" $(cat "$i") &
                    elif [[ "$i" =~ task.cron.* ]]; then
                        while true; do
                            php "${prog_file}" $(cat "$i") &
                            sleep 60
                        done &
                    fi
                fi
            done

        fi
    done
}

main "$@"
