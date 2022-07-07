#!/usr/bin/env bash

# set -x
if command -v nc &>/dev/null; then
    echo >&2 "I require nc but it's not installed.  Aborting."
    return 1
fi
ssh_opt='ssh -qfg -o ExitOnForwardFailure=yes'
ssh_host='ip.host.mysql.server'
ssh_forward_port="${1:-3306}"
## create ssh tunnel
$ssh_opt -L "$ssh_forward_port":localhost:3306 $ssh_host "sleep 300" || true
## kill ssh tunnel timeout
while nc -vz localhost "$ssh_forward_port"; do
    # echo "ssh forward port $ssh_forward_port exist."
    count=$((count + 1))
    if [ $count -gt 30 ]; then
        echo "ssh forward port $ssh_forward_port exist too long, break."
        pkill -f "$ssh_opt -L $ssh_forward_port:localhost:3306" || true
        break
    fi
    sleep 10
done &
