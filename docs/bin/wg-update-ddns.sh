#!/usr/bin/env bash

_update_ddns() {
    if [ "$(id -u)" -eq 0 ]; then
        : # return 0
    else
        use_sudo=sudo
    fi

    wg_interface=$($use_sudo wg show | awk '/interface:/ {print $2}')

    for i in /etc/wireguard/*.conf /usr/local/etc/wireguard/*.conf /etc/config/network; do
        [ -f "$i" ] || continue
        wg_conf=$i
        break
    done

    while read -r line; do
        read -r -a array <<<"$line"
        public_key=${array[0]}
        handshake_time=${array[1]}
        wg_endpoint=$(
            grep -A 10 "${public_key}" "$wg_conf" |
                awk -F= 'BEGIN{IGNORECASE=1} /[E|e]ndpoint/ {print $NF}' | head -n1
        )
        wg_endpoint=${wg_endpoint// /}

        time_now=$(($(date +%s) - handshake_time))
        if ((time_now > 300)); then
            echo "wg set $wg_interface peer $public_key endpoint $wg_endpoint"
            sudo wg set "$wg_interface" peer "$public_key" endpoint "$wg_endpoint"
        fi
    done < <(
        $use_sudo wg show "$wg_interface" latest-handshakes
    )

}

# set -xe
_update_ddns
