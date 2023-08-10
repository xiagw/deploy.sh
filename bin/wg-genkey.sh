#!/usr/bin/env bash
# shellcheck disable=SC2029
# set -xe

_msg() {
    local color_on
    local color_off='\033[0m' # Text Reset
    case "${1:-none}" in
    red | error | erro) color_on='\033[0;31m' ;;       # Red
    green | info) color_on='\033[0;32m' ;;             # Green
    yellow | warning | warn) color_on='\033[0;33m' ;;  # Yellow
    blue) color_on='\033[0;34m' ;;                     # Blue
    purple | question | ques) color_on='\033[0;35m' ;; # Purple
    cyan) color_on='\033[0;36m' ;;                     # Cyan
    time)
        color_on="[+] $(date +%Y%m%d-%T-%u), "
        color_off=''
        ;;
    step | timestep)
        color_on="\033[0;36m[$((${STEP:-0} + 1))] $(date +%Y%m%d-%T-%u), \033[0m"
        STEP=$((${STEP:-0} + 1))
        color_off=' ... start'
        ;;
    stepend | end)
        color_on="[+] $(date +%Y%m%d-%T-%u), "
        color_off=' ... end'
        ;;
    *)
        color_on=
        color_off=
        ;;
    esac
    if [ "$#" -gt 1 ]; then
        shift
    fi
    echo -e "${color_on}$*${color_off}"
}

_set_peer2peer() {
    if [[ "$new_key_flag" -ne 1 ]]; then
        _msg green "### Please select << client >> side conf..."
        select c_conf in $me_data/wg*.conf quit; do
            [[ "$c_conf" == 'quit' ]] && exit
            break
        done
        c_key_pub="$(awk '/^### pubkey:/ {print $3}' "$c_conf" | head -n 1)"
        c_key_pre="$(awk '/PresharedKey/ {print $4}' "$c_conf" | head -n 1)"
        c_ip_pub="$(awk '/^### pubip:/ {print $3}' "$c_conf" | head -n 1)"
        c_ip_pri="$(awk '/^Address/ {print $3}' "$c_conf" | head -n 1)"
        c_ip_pri="${c_ip_pri%/24}"
        c_port="$(awk '/^ListenPort/ {print $3}' "$c_conf" | head -n 1)"
    fi
    ## select server
    _msg red "### Please select ====< server >==== side conf"
    select s_conf in $me_data/wg*.conf quit; do
        [[ "$s_conf" == 'quit' ]] && break
        _msg red "(Have selected $s_conf)"
        s_key_pub="$(awk '/^### pubkey:/ {print $3}' "$s_conf" | head -n 1)"
        s_ip_pub="$(awk '/^### pubip:/ {print $3}' "$s_conf" | head -n 1)"
        s_ip_pri="$(awk '/^Address/ {print $3}' "$s_conf" | head -n 1)"
        s_ip_pri=${s_ip_pri%/24}
        s_port="$(awk '/^ListenPort/ {print $3}' "$s_conf" | head -n 1)"
        _msg red "From: $s_conf"
        _msg green "To: $c_conf"
        read -rp "Set route: [IP/MASK,IP/MASK] " read_ip_route
        if ! grep -q "### ${s_conf##*/} begin" "$c_conf"; then
            (
                echo ""
                echo "### ${s_conf##*/} begin"
                echo "[Peer]"
                echo "PublicKey = $s_key_pub"
                echo "# PresharedKey = $c_key_pre"
                echo "endpoint = $s_ip_pub:$s_port"
                if [[ -z ${read_ip_route} ]]; then
                    echo "AllowedIPs = ${s_ip_pri}/32"
                else
                    echo "AllowedIPs = ${s_ip_pri}/32, ${read_ip_route}"
                fi
                echo "PersistentKeepalive = 60"
                echo "### ${s_conf##*/} end"
                echo ""
            ) >>"$c_conf"
        fi
        echo "set from $c_conf to $s_conf..."
        if ! grep -q "### ${c_conf##*/} begin" "$s_conf"; then
            (
                echo ""
                echo "### ${c_conf##*/} begin  $c_comment"
                echo "[Peer]"
                echo "PublicKey = $c_key_pub"
                echo "# PresharedKey = $c_key_pre"
                echo "AllowedIPs = ${c_ip_pri}/32"
                echo "### ${c_conf##*/} end"
                echo ""
            ) >>"$s_conf"
        fi
    done
}

_new_key() {
    c_num="${1:-20}"
    c_conf="$me_data/wg${c_num}.conf"
    until [[ "${c_num}" -lt 254 ]]; do
        read -rp "Error! enter ip again [1-254]: " c_num
        c_conf="$me_data/wg${c_num}.conf"
    done
    while [ -f "$c_conf" ]; do
        c_num=$((c_num + 1))
        c_conf="$me_data/wg${c_num}.conf"
    done
    _msg green "IP: 10.9.0.$c_num, filename: $c_conf"
    read -rp "Who use this file? (username or hostname): " -e -i "client$c_num" c_comment
    read -rp 'Enter public ip (empty for client behind NAT): ' -e -i "wg${c_num}.vpn.com" c_ip_pub
    c_ip_pri="10.9.0.${c_num}"
    c_port="$((c_num + 39000))"
    c_key_pri="$(wg genkey)"
    c_key_pub="$(echo "$c_key_pri" | wg pubkey)"
    c_key_pre="$(wg genpsk)"
    cat >"$c_conf" <<EOF

### ${c_conf##*/} $c_comment
[Interface]
PrivateKey = $c_key_pri
### PresharedKey = $c_key_pre
### pubkey: $c_key_pub
### pubip: $c_ip_pub
Address = $c_ip_pri/24
ListenPort = $c_port
## DNS = 192.168.1.1, 8.8.8.8, 8.8.4.4, 114.114.114.114
## MTU = 1420
## PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
## PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

EOF
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
    _msg green "Please select client conf (revoke it)."
    select conf in $me_data/wg*.conf quit; do
        [[ "$conf" == 'quit' ]] && break
        _msg green "(Have selected $conf)"
        sed -i "/^### ${conf##*/} begin/,/^### ${conf##*/} end/d" "$me_data"/wg*.conf
        rm -f "$conf"
        _msg yellow "revoke $conf done."
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

main() {
    me_path="$(dirname "$(readlink -f "$0")")"
    me_name="$(basename "$0")"
    me_data="${me_path}/../data/wireguard"
    me_log="${me_data}/${me_name}.log"
    [ -d "$me_data" ] || mkdir -p "$me_data"
    exec &> >(tee -a "$me_log")

    echo "
What do you want to do?
    1) New key (client or server)
    2) Set peer to peer (exists conf)
    3) Upload conf and reload (client/server)
    4) Convert conf to qrcode
    5) Revoke server/client conf
    6) Quit
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
    *)
        echo "Invalid option: $MENU_OPTION"
        exit 0
        ;;
    esac
}

main "$@"
