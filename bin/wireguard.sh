#!/usr/bin/env bash
# shellcheck disable=SC2029
# set -xe

_set_peer2peer() {
    ## 新建的client，直接选择 服务器端
    if [[ "$new_key_flag" -eq 1 ]]; then
        _msg green "is new key..."
    ## 不是新建的client，需要选择已存在的client
    else
        _msg green "select exist conf..."
        cd "$g_me_data_path" || exit 1
        select client_conf in wg*.conf quit; do
            [[ "$client_conf" == 'quit' ]] && exit
            break
        done
        client_key_pub=$(awk '/^### public_key:/ {print $3; exit}' "$client_conf")
        client_key_pre=$(awk '/PresharedKey/ {print $4; exit}' "$client_conf")
        client_ip_public=$(awk '/^### public_ip:/ {print $3; exit}' "$client_conf")
        client_ip_pri=$(awk '/^Address/ {print $3}' "$client_conf" | grep '[0-9]\.' | head -n1 | cut -d'/' -f1)
        client_ip6_pri=$(awk '/^Address/ {print $3}' "$client_conf" | grep '[A-Za-z0-9]:' | tail -n1 | cut -d'/' -f1)
        client_ip_port=$(awk '/^ListenPort/ {print $3; exit}' "$client_conf")
    fi
    ## 选择对端配置文件
    _msg red "select peer conf..."
    cd "$g_me_data_path" || exit 1
    # select svr_conf in $g_me_data_path/wg{1,2,5,17,20,27,36,37,38}.conf quit; do
    select svr_conf in wg*.conf quit; do
        [[ "$svr_conf" == 'quit' ]] && break
        svr_key_pub=$(awk '/^### public_key:/ {print $3; exit}' "$svr_conf")
        svr_ip_pub=$(awk '/^### public_ip:/ {print $3; exit}' "$svr_conf")
        svr_ip_pri=$(awk '/^Address/ {print $3}' "$client_conf" | grep '[0-9]\.' | head -n1 | cut -d'/' -f1)
        svr_ip6_pri=$(awk '/^Address/ {print $3}' "$client_conf" | grep '[A-Za-z0-9]:' | tail -n1 | cut -d'/' -f1)
        svr_ip_port=$(awk '/^ListenPort/ {print $3; exit}' "$svr_conf")
        svr_lan_cidr=$(awk '/^### site2site_lan_cidr:/ {print $3; exit}' "$svr_conf")

        _msg red "Setup peer, from: $svr_conf to ${client_conf##*/}"
        if ! grep -q "### ${svr_conf##*/} begin" "$client_conf"; then
            {
                echo ""
                echo "### ${svr_conf##*/} begin"
                echo "[Peer]"
                echo "PublicKey = $svr_key_pub"
                echo "# PresharedKey = $client_key_pre"
                echo "Endpoint = $svr_ip_pub:$svr_ip_port"
                if [[ -z "$svr_lan_cidr" ]]; then
                    if [ -z "${svr_ip6_pri}" ]; then
                        echo "AllowedIPs = ${svr_ip_pri}/32"
                    else
                        echo "AllowedIPs = ${svr_ip_pri}/32,${svr_ip6_pri}/128"
                    fi
                else
                    if [ -z "${svr_ip6_pri}" ]; then
                        echo "AllowedIPs = ${svr_ip_pri}/32,${svr_lan_cidr}"
                    else
                        echo "AllowedIPs = ${svr_ip_pri}/32,${svr_ip6_pri}/128,${svr_lan_cidr}"
                    fi
                fi
                echo "PersistentKeepalive = 60"
                echo "### ${svr_conf##*/} end"
                echo ""
            } >>"$client_conf"
        fi

        _msg green "Setup peer, from ${client_conf##*/} to $svr_conf"
        if ! grep -q "### ${client_conf##*/} begin" "$svr_conf"; then
            {
                echo ""
                echo "### ${client_conf##*/} begin  $client_comment"
                echo "[Peer]"
                echo "PublicKey = $client_key_pub"
                echo "# PresharedKey = $client_key_pre"
                echo "AllowedIPs = ${client_ip_pri}/32,${client_ip6_pri}/128"
                echo "### ${client_conf##*/} end"
                echo ""
            } >>"$svr_conf"
        fi
    done
}

_new_key() {
    if [ "${wireguard_network:-1}" -eq 1 ]; then
        ip_prefix="10.9.0."
        ip6_prefix="fd00:9::"
        port_prefix="39000"
    else
        ip_prefix="10.10.10."
        ip6_prefix="fd00:10::"
        port_prefix="40000"
    fi
    client_num="${1:-21}"
    client_conf="$g_me_data_path/wg${client_num}.conf"
    until [[ "${client_num}" -lt 254 ]]; do
        read -rp "Error! enter ip again [1-254]: " client_num
        client_conf="$g_me_data_path/wg${client_num}.conf"
    done
    while [ -f "$client_conf" ]; do
        _msg warn "File exists: $client_conf"
        ((client_num++))
        client_conf="$g_me_data_path/wg${client_num}.conf"
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
Address = $client_ip_pri/24
# Address = $client_ip6_pri/64
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
    cd "$g_me_data_path" || exit 1
    select conf in wg*.conf quit; do
        [[ "${conf}" == 'quit' || ! -f "${conf}" ]] && break
        _msg green "${conf}.png"
        qrencode -o "${conf}.png" -t PNG <"$conf"
    done
}

_revoke_client() {
    _msg green "Select conf to revoke..."
    cd "$g_me_data_path" || exit 1
    select conf in wg*.conf quit; do
        [[ "$conf" == 'quit' ]] && break
        _msg green "Selected: $conf"
        _msg yellow "revoke ${conf##*/} from all conf."
        grep --color "^### ${conf##*/} begin" "$g_me_data_path"/wg*.conf
        sed -i "/^### ${conf##*/} begin/,/^### ${conf##*/} end/d" "$g_me_data_path"/wg*.conf
        _msg yellow "remove $conf."
        rm -f "$conf"
        _msg red "!!! DONT forget update conf to Server/Client and restart wireguard !!!"
        break
    done
}

_restart_host() {
    _msg yellow "scp $conf to root@$host:/etc/wireguard/wg0.conf"
    if scp "${conf}" root@"$host":/etc/wireguard/wg0.conf; then
        _msg yellow "Setting up WireGuard with infinite DNS retries..."
        if ssh root@"$host" "export WG_ENDPOINT_RESOLUTION_RETRIES=infinity && \
            wg syncconf wg0 <(wg-quick strip wg0); \
            echo sleep 2; sleep 2; wg show"; then
            _msg green "Wireguard restarted on $host with infinite DNS retries"
        else
            _msg red "Error restarting Wireguard on $host"
        fi
    else
        _msg red "Error copying $conf to $host"
    fi
}

_reload_conf() {
    _msg red "Please select conf."
    cd "$g_me_data_path" || exit 1
    select conf in wg*.conf quit; do
        [[ "${conf}" == 'quit' ]] && break
        _msg red "selected $conf"
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
    _get_root

    for wg_interface in $(${use_sudo-} wg show interfaces); do
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
    date +%s
    $use_sudo wg show all dump | awk 'NR>1 {print $4"\t"$5"\t"$6}'
}

get_lib_common() {
    local lib url
    lib="$(dirname "$g_me_path")/lib/common.sh"
    if [ ! -f "$lib" ]; then
        lib='/tmp/common.sh'
        url="https://gitee.com/xiagw/deploy.sh/raw/main/lib/common.sh"
        curl -fsSLo "$lib" "$url"
    fi
    # shellcheck source=/dev/null
    . "$lib"
}

main() {
    g_me_name="$(basename "$0")"
    g_me_path="$(dirname "$($(command -v greadlink || command -v readlink) -f "$0")")"
    g_me_data_path="$(dirname "${g_me_path}")/data/wireguard"
    g_me_log="${g_me_data_path}/${g_me_name}.log"

    get_lib_common

    _msg "log file: $g_me_log"

    [ -d "$g_me_data_path" ] || mkdir -p "$g_me_data_path"

    if [[ "$1" = u ]]; then
        _update_ddns
        return
    fi

    echo "
What do you want to do?
    1) Add a new conf (server/client)
    2) Set peer to peer (existing conf)
    3) Upload conf and reload wireguard (server/client)
    4) Convert conf to qrcode (iPhone scan with camera)
    5) Revoke existing conf
    6) Update DDNS
    7) Quit
"
    until [[ ${MENU_OPTION} =~ ^[1-7]$ ]]; do
        read -rp "Select an option [1-7]: " MENU_OPTION
    done
    [[ ${MENU_OPTION} == 7 ]] && return

    until [[ ${wireguard_network} =~ ^[1-3]$ ]]; do
        read -rp "Select wireguard network [gitlab|jump|demo]: [1-3]: " -e -i1 wireguard_network
    done
    if [ "${wireguard_network:-1}" -gt 1 ]; then
        g_me_data_path="$(dirname "${g_me_path}")/data/wireguard${wireguard_network}"
        mkdir -p "$g_me_data_path"
    fi
    _msg green "wireguard data path: $g_me_data_path"

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

# wg syncconf wg0 <(wg-quick strip wg0)