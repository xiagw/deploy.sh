#!/usr/bin/env bash
# shellcheck disable=SC2029
# set -xe

_msg() {
    local color_on
    local color_off='\033[0m' # Text Reset
    duration=$SECONDS
    h_m_s="$((duration / 3600))h$(((duration / 60) % 60))m$((duration % 60))s"
    time_now="$(date +%Y%m%d-%u-%T.%3N)"

    case "${1:-none}" in
    red | error | erro) color_on='\033[0;31m' ;;       # Red
    green | info) color_on='\033[0;32m' ;;             # Green
    yellow | warning | warn) color_on='\033[0;33m' ;;  # Yellow
    blue) color_on='\033[0;34m' ;;                     # Blue
    purple | question | ques) color_on='\033[0;35m' ;; # Purple
    cyan) color_on='\033[0;36m' ;;                     # Cyan
    orange) color_on='\033[1;33m' ;;                   # Orange
    step)
        ((++STEP))
        color_on="\033[0;36m[${STEP}] $time_now \033[0m"
        color_off=" $h_m_s"
        ;;
    time)
        color_on="[${STEP}] $time_now "
        color_off=" $h_m_s"
        ;;
    log)
        shift
        echo "$time_now $*" >>"$me_log"
        return
        ;;
    *)
        unset color_on color_off
        ;;
    esac
    [ "$#" -gt 1 ] && shift
    echo -e "${color_on}$*${color_off}"
}

_set_peer2peer() {
    ## 新建的client，直接选择 服务器端
    if [[ "$new_key_flag" -eq 1 ]]; then
        _msg green "### is new key..."
    ## 不是新建的client，需要选择已存在的client
    else
        _msg green "### Select exist conf..."
        select client_conf in $me_data/wg*.conf quit; do
            [[ "$client_conf" == 'quit' ]] && exit
            break
        done
        client_key_pub="$(awk '/^### public_key:/ {print $3}' "$client_conf" | head -n 1)"
        client_key_pre="$(awk '/PresharedKey/ {print $4}' "$client_conf" | head -n 1)"
        client_ip_public="$(awk '/^### public_ip:/ {print $3}' "$client_conf" | head -n 1)"
        client_ip_pri="$(awk '/^Address/ {print $3}' "$client_conf" | head -n 1)"
        client_ip_pri="${client_ip_pri%/24*}"
        client_ip6_pri="$(awk '/^Address/ {print $4}' "$client_conf" | head -n 1)"
        client_ip6_pri="${client_ip6_pri%/64*}"
        client_ip_port="$(awk '/^ListenPort/ {print $3}' "$client_conf" | head -n 1)"
    fi
    ## select server
    _msg red "### Select >>>>>> SERVER >>>>>> side conf"
    # select svr_conf in $me_data/wg{1,2,5,17,20,27,36,37,38}.conf quit; do
    select svr_conf in $me_data/wg*.conf quit; do
        [[ "$svr_conf" == 'quit' ]] && break
        svr_key_pub="$(awk '/^### public_key:/ {print $3}' "$svr_conf" | head -n 1)"
        svr_ip_pub="$(awk '/^### public_ip:/ {print $3}' "$svr_conf" | head -n 1)"
        svr_ip_pri="$(awk '/^Address/ {print $3}' "$svr_conf" | head -n 1)"
        svr_ip_pri=${svr_ip_pri%/24*}
        svr_ip6_pri="$(awk '/^Address/ {print $4}' "$svr_conf" | head -n 1)"
        svr_ip6_pri=${svr_ip6_pri%/64*}
        svr_ip_port="$(awk '/^ListenPort/ {print $3}' "$svr_conf" | head -n 1)"
        read -rp "Set route(client-to-server): [192.168.1.0/24, 172.16.0.0/16] " read_ip_route
        _msg red "From: $svr_conf to $client_conf "
        if ! grep -q "### ${svr_conf##*/} begin" "$client_conf"; then
            (
                echo ""
                echo "### ${svr_conf##*/} begin"
                echo "[Peer]"
                echo "PublicKey = $svr_key_pub"
                echo "# PresharedKey = $client_key_pre"
                echo "endpoint = $svr_ip_pub:$svr_ip_port"
                if [[ -z ${read_ip_route} ]]; then
                    echo "AllowedIPs = ${svr_ip_pri}/32, ${svr_ip6_pri}/128"
                else
                    echo "AllowedIPs = ${svr_ip_pri}/32, ${svr_ip6_pri}/128, ${read_ip_route}"
                fi
                echo "PersistentKeepalive = 60"
                echo "### ${svr_conf##*/} end"
                echo ""
            ) >>"$client_conf"
        fi
        _msg green "From $client_conf to $svr_conf"
        if ! grep -q "### ${client_conf##*/} begin" "$svr_conf"; then
            (
                echo ""
                echo "### ${client_conf##*/} begin  $client_comment"
                echo "[Peer]"
                echo "PublicKey = $client_key_pub"
                echo "# PresharedKey = $client_key_pre"
                echo "AllowedIPs = ${client_ip_pri}/32, ${svr_ip6_pri}/128"
                echo "### ${client_conf##*/} end"
                echo ""
            ) >>"$svr_conf"
        fi
    done
}

_new_key() {
    # ip_prefix="10.10.10."
    # port_prefix="40000"
    ip_prefix="10.9.0."
    ip6_prefix="fd00:9::"
    port_prefix="39000"
    client_num="${1:-20}"
    client_conf="$me_data/wg${client_num}.conf"
    until [[ "${client_num}" -lt 254 ]]; do
        read -rp "Error! enter ip again [1-254]: " client_num
        client_conf="$me_data/wg${client_num}.conf"
    done
    while [ -f "$client_conf" ]; do
        client_num=$((client_num + 1))
        client_conf="$me_data/wg${client_num}.conf"
    done
    _msg green "Generate: $client_conf , client IP: $ip_prefix${client_num}, $ip6_prefix${client_num}"
    read -rp "Comment? (Options: username or hostname): " -e -i "host${client_num}" client_comment
    read -rp 'Public IP (Options: as wg server): ' -e -i "wg${client_num}.vpn.lan" client_ip_public

    client_ip_pri="$ip_prefix${client_num}"
    client_ip6_pri="$ip6_prefix${client_num}"
    client_ip_port="$((client_num + port_prefix))"
    client_key_pri="$(wg genkey)"
    client_key_pub="$(echo "$client_key_pri" | wg pubkey)"
    client_key_pre="$(wg genpsk)"

    cat >"$client_conf" <<EOF

### ${client_conf##*/} $client_comment
[Interface]
PrivateKey = $client_key_pri
Address = $client_ip_pri/24, $client_ip6_pri/64
ListenPort = $client_ip_port
### PresharedKey = $client_key_pre
### public_key: $client_key_pub
### public_ip: $client_ip_public
## DNS = 192.168.1.1, 8.8.8.8, 8.8.4.4, 1.0.0.1, 1.1.1.1, 114.114.114.114
## MTU = 1420
## PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
## PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

EOF
    ## set peer 2 peer
    new_key_flag=1
    _set_peer2peer
}

_get_qrcode() {
    if ! command -v qrencode; then
        if uname -s | grep -q Linux; then
            sudo apt install qrencode
        elif uname -s | grep -q Darwin; then
            brew install qrencode
        else
            _msg yellow "qrencode not exists"
        fi
    fi
    local conf
    select conf in $me_data/wg*.conf quit; do
        [[ "${conf}" == 'quit' || ! -f "${conf}" ]] && break
        _msg green "${conf}.png"
        qrencode -o "${conf}.png" -t PNG <"$conf"
    done
}

_revoke_client() {
    _msg green "Select client conf (revoke it)."
    select conf in $me_data/wg*.conf quit; do
        [[ "$conf" == 'quit' ]] && break
        _msg green "Selected: $conf"
        _msg yellow "revoke ${conf##*/} from all conf."
        sed -i "/^### ${conf##*/} begin/,/^### ${conf##*/} end/d" "$me_data"/wg*.conf
        _msg yellow "remove $conf."
        rm -f "$conf"
        _msg red "!!! DONT forget update conf to Server/Client and reload"
        break
    done
}

_restart_host() {
    _msg yellow "scp $conf to root@$host:/etc/wireguard/wg0.conf"
    if scp "${conf}" root@"$host":/etc/wireguard/wg0.conf; then
        _msg yellow "wg syncconf wg0 <(wg-quick strip wg0); wg show"
        if ssh root@"$host" "wg syncconf wg0 <(wg-quick strip wg0); echo sleep 2; sleep 2; wg show"; then
            _msg green "Wireguard restarted on $host"
        else
            _msg red "Error restarting Wireguard on $host"
        fi
    else
        _msg red "Error copying $conf to $host"
    fi
}

_reload_conf() {
    _msg red "Please select wg conf."
    select conf in $me_data/wg*.conf quit; do
        [[ "${conf}" == 'quit' ]] && break
        _msg red "(Have selected $conf)"
        if [ -f "$HOME/.ssh/config" ]; then
            select host in $(awk 'NR>1' "$HOME/.ssh/config"* | awk '/^Host/ {print $2}') quit; do
                [[ "${host}" == 'quit' ]] && break
                _restart_host
                break
            done
        else
            _msg yellow "not found $HOME/.ssh/config"
            read -rp "Enter host IP: " host
            _restart_host
        fi
        break
    done
}
# ssh root@"$host" "systemctl restart wg-quick@wg0"
# wg genkey | tee privatekey | wg pubkey > publickey; cat privatekey publickey; rm privatekey publickey

_update_ddns() {
    if [ "$(id -u)" -eq 0 ]; then
        unset use_sudo
    else
        use_sudo=sudo
    fi

    for wg_interface in $($use_sudo wg show interfaces); do
        while read -r line; do
            read -r -a array <<<"$line"
            wg_peer=${array[0]}
            wg_endpoint=$(
                $use_sudo wg-quick strip wg0 | grep -A5 "$wg_peer" |
                    grep -v '^#' | awk '/[Ee]ndpoint/ {print $3}'
            )
            # wg_endpoint=${array[1]}
            sudo wg set "$wg_interface" peer "${wg_peer}" endpoint "${wg_endpoint}"
        done < <($use_sudo wg show "$wg_interface" endpoints)
    done
    $use_sudo wg show all dump
    # $use_sudo wg show all latest-handshakes
}

main() {
    me_path="$(dirname "$(readlink -f "$0")")"
    me_name="$(basename "$0")"
    me_data="${me_path}/../data/wireguard"
    # me_data="${me_path}/wireguard"
    me_log="${me_data}/${me_name}.log"
    [ -d "$me_data" ] || mkdir -p "$me_data"

    if [[ "$1" = u ]]; then
        _update_ddns
        return
    fi

    echo "
What do you want to do?
    1) New key (key for client/server)
    2) Set peer to peer (exists conf)
    3) Upload conf and reload (client/server)
    4) Convert conf to qrcode
    5) Revoke client/server conf
    6) Update DDNS
    7) Quit
"
    until [[ ${MENU_OPTION} =~ ^[1-6]$ ]]; do
        read -rp "Select an option [1-6]: " MENU_OPTION
    done
    case "${MENU_OPTION}" in
    1) _new_key "$@" ;;
    2) _set_peer2peer ;;
    3) _reload_conf ;;
    4) _get_qrcode ;;
    5) _revoke_client ;;
    6) _update_ddns ;;
    *)
        echo "Invalid option: $MENU_OPTION"
        exit 0
        ;;
    esac
}

main "$@"
