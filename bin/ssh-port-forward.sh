#!/usr/bin/env bash

# set -x

path0_script="$(cd "$(dirname "$0")" && pwd)"
echo "$path0_script" >/dev/null

command -v nc >/dev/null 2>&1 || {
    echo >&2 "I require nc but it's not installed.  Aborting."
    return 1
}

ssh_opt='ssh -qfg -o ExitOnForwardFailure=yes'
ssh_host='ip.host.mysql.server'
ssh_forward_port='3306'
$ssh_opt -L $ssh_forward_port:localhost:3306 $ssh_host "sleep 120" || true

while nc -vz localhost $ssh_forward_port; do
    # echo "ssh forward port $ssh_forward_port exist."
    count=$((count + 1))
    if [ $count -gt 60 ]; then
        echo "ssh forward port $ssh_forward_port exist too long, break."
        pkill -f "$ssh_opt -L $ssh_forward_port:localhost:3306" || true
        break
    fi
    sleep 2
done &
