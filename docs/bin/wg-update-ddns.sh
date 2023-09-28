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

    $use_sudo wg show utun3 latest-handshakes |
        while read -r line; do
            pub_key=$(echo "$line" | awk '{print $1}')
            handshake_time=$(echo "$line" | awk '{print $2}')

            wg_endpoint=$(grep -A 10 "${pub_key}" "$wg_conf" | awk -F= 'BEGIN{IGNORECASE=1} /[E|e]ndpoint/ {print $NF}' | head -n1)
            wg_endpoint=${wg_endpoint// /}
            if (($(($(date +%s) - handshake_time)) > 300)); then
                sudo wg set "$wg_interface" peer "$pub_key" endpoint "$wg_endpoint"
            fi
        done

}

# set -xe
_update_ddns
