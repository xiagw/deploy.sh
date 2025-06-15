#!/usr/bin/env bash
# shellcheck disable=SC2029
# set -xe

set_peer() {
    local file="$1"
    ## 新建的client，直接选择对端配置文件
    if [[ "$NEW_FLAG" -eq 1 ]]; then
        _msg green "is new key/是新建的密钥"
    ## 不是新建的client，需要选择已存在的client
    else
        _msg green "select exist conf/选择已存在的配置"
        cd "$G_DATA" || exit 1
        select file in wg*.conf quit; do
            [[ "$file" == 'quit' ]] && exit
            break
        done
        client_key_pub=$(awk '/^### public_key:/ {print $3; exit}' "$file")
        client_key_pre=$(awk '/PresharedKey/ {print $4; exit}' "$file")
        client_ip_public=$(awk '/^### public_ip:/ {print $3; exit}' "$file")
        client_ip_pri=$(awk '/^Address/ {print $3}' "$file" | grep '[0-9]\.' | head -n1 | cut -d'/' -f1)
        client_ip6_pri=$(awk '/^Address/ {print $3}' "$file" | grep '[A-Za-z0-9]:' | tail -n1 | cut -d'/' -f1)
        client_ip_port=$(awk '/^ListenPort/ {print $3; exit}' "$file")
    fi
    ## 选择对端配置文件
    _msg red "select peer conf/选择对端配置文件"
    cd "$G_DATA" || exit 1
    # select peer_conf in $G_DATA/wg{1,2,5,17,20,27,36,37,38}.conf quit; do
    select peer_conf in wg*.conf quit; do
        [[ "$peer_conf" == 'quit' ]] && break
        peer_key_pub=$(awk '/^### public_key:/ {print $3; exit}' "$peer_conf")
        peer_ip_pub=$(awk '/^### public_ip:/ {print $3; exit}' "$peer_conf")
        peer_ip_pri=$(awk '/^Address/ {print $3}' "$file" | grep '[0-9]\.' | head -n1 | cut -d'/' -f1)
        peer_ip6_pri=$(awk '/^Address/ {print $3}' "$file" | grep '[A-Za-z0-9]:' | tail -n1 | cut -d'/' -f1)
        peer_ip_port=$(awk '/^ListenPort/ {print $3; exit}' "$peer_conf")
        peer_lan_cidr=$(awk '/^### add_route:/ {print $3; exit}' "$peer_conf")

        _msg red "From $peer_conf to ${file##*/}"
        if ! grep -q "### ${peer_conf##*/} begin" "$file"; then
            {
                echo ""
                echo "### ${peer_conf##*/} begin"
                echo "[Peer]"
                echo "PublicKey = $peer_key_pub"
                echo "# PresharedKey = $client_key_pre"
                echo "Endpoint = $peer_ip_pub:$peer_ip_port"
                if [[ -z "$peer_lan_cidr" ]]; then
                    if [ -z "${peer_ip6_pri}" ]; then
                        echo "AllowedIPs = ${peer_ip_pri}/32"
                    else
                        echo "AllowedIPs = ${peer_ip_pri}/32,${peer_ip6_pri}/128"
                    fi
                else
                    if [ -z "${peer_ip6_pri}" ]; then
                        echo "AllowedIPs = ${peer_ip_pri}/32,${peer_lan_cidr}"
                    else
                        echo "AllowedIPs = ${peer_ip_pri}/32,${peer_ip6_pri}/128,${peer_lan_cidr}"
                    fi
                fi
                echo "PersistentKeepalive = 60"
                echo "### ${peer_conf##*/} end"
                echo ""
            } >>"$file"
        fi

        _msg green "From ${file##*/} to $peer_conf"
        if ! grep -q "### ${file##*/} begin" "$peer_conf"; then
            {
                echo ""
                echo "### ${file##*/} begin $client_comment"
                echo "[Peer]"
                echo "PublicKey = $client_key_pub"
                echo "# PresharedKey = $client_key_pre"
                echo "AllowedIPs = ${client_ip_pri}/32,${client_ip6_pri}/128"
                echo "### ${file##*/} end"
                echo ""
            } >>"$peer_conf"
        fi
    done
}

new_key() {
    local ip_net="10.9.0."
    local ip6_net="fd00:9::"
    local port="39000"
    local num="${1:-21}"
    local file="$G_DATA/wg${num}.conf"
    until [[ "${num}" -lt 254 ]]; do
        read -rp "Error! enter ip again [1-254]: " num
        file="$G_DATA/wg${num}.conf"
    done
    while [ -f "$file" ]; do
        _msg warn "File exists/文件已存在: $file"
        ((num++))
        file="$G_DATA/wg${num}.conf"
    done
    _msg green "info/信息: ${file} ${ip_net}${num} ${ip6_net}${num}"
    read -rp "Enter comment/输入可选项备注: username or hostname: " -e -i "host${num}" client_comment
    read -rp 'Enter Public IP/输入可选项公网IP，如果作为服务器: ' -e -i "wg${num}.vpn.lan" client_ip_public

    client_ip_pri="${ip_net}${num}"
    client_ip6_pri="${ip6_net}${num}"
    client_ip_port="$((num + port))"
    local client_key_pri
    client_key_pri="$(wg genkey)"
    client_key_pub="$(echo "$client_key_pri" | wg pubkey)"
    client_key_pre="$(wg genpsk)"

    cat >"$file" <<EOF

### ${file##*/} $client_comment
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

    NEW_FLAG=1
    set_peer "${file}"
}

get_qrcode() {
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
    cd "$G_DATA" || exit 1
    select conf in wg*.conf quit; do
        [[ "${conf}" == 'quit' || ! -f "${conf}" ]] && break
        _msg green "${conf}.png"
        qrencode -o "${conf}.png" -t PNG <"$conf"
    done
}

revoke_client() {
    _msg green "Select conf to revoke/选择要撤销的配置文件"
    cd "$G_DATA" || exit 1
    local conf
    select conf in wg*.conf quit; do
        [[ "$conf" == 'quit' ]] && break
        _msg green "Selected/已选择: $conf"
        _msg yellow "revoke from all conf/撤销在所有配置文件中的引用: ${conf##*/}"
        grep --color "^### ${conf##*/} begin" "$G_DATA"/wg*.conf
        sed -i "/^### ${conf##*/} begin/,/^### ${conf##*/} end/d" "$G_DATA"/wg*.conf
        _msg yellow "remove/删除: $conf"
        rm -f "$conf"
        _msg red "!!! DONT forget update conf to Server/Client and restart wireguard/不要忘记更新配置到服务器/客户端并重启 WireGuard !!!"
        break
    done
}

restart_host() {
    local conf="$1" host="$2"
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

reload_conf() {
    _msg red "Please select conf/请选择配置文件"
    cd "$G_DATA" || exit 1
    select conf in wg*.conf quit; do
        [[ "${conf}" == 'quit' ]] && break
        _msg red "selected/已选择配置文件: $conf"
        if [ -f "$HOME/.ssh/config" ]; then
            select host in $(awk 'NR>1' "$HOME/.ssh/config"* | awk '/^Host/ {print $2}') quit; do
                [[ "${host}" == 'quit' ]] && break
                restart_host "$conf" "$host"
                break
            done
        else
            _msg yellow "not found/未找到: $HOME/.ssh/config"
            read -rp "Enter host IP/输入主机IP: " host
            restart_host "$conf" "$host"
        fi
        break
    done
}
# ssh root@"$host" "systemctl restart wg-quick@wg0"
# wg genkey | tee privatekey | wg pubkey > publickey; cat privatekey publickey; rm privatekey publickey

import_common() {
    local lib url
    lib="$(dirname "$G_PATH")/lib/common.sh"
    if [ ! -f "$lib" ]; then
        lib='/tmp/common.sh'
        url="https://gitee.com/xiagw/deploy.sh/raw/main/lib/common.sh"
        curl -fsSLo "$lib" "$url"
    fi
    # shellcheck source=/dev/null
    . "$lib"
}

main() {
    G_NAME="$(basename "$0")"
    G_PATH="$(dirname "$($(command -v greadlink || command -v readlink) -f "$0")")"
    G_DATA="$(dirname "${G_PATH}")/data/wireguard"
    G_LOG="${G_DATA}/${G_NAME}.log"

    import_common

    _msg "log file: $G_LOG"

    mkdir -p "$G_DATA"

    echo "
What do you want to do?
    1) New key / 新建客户/服务端配置文件
    2) Set peer to peer / 设置对端配置文件
    3) Upload conf and reload / 上传配置并重载（客户端/服务端）
    4) Convert conf to qrcode / 转换配置为二维码
    5) Revoke client/server conf / 撤销客户端/服务端配置
    6) Quit / 退出
"
    until [[ ${MENU_OPTION} =~ ^[1-6]$ ]]; do
        read -rp "Select an option [1-6]: " MENU_OPTION
    done
    [[ ${MENU_OPTION} == 6 ]] && return

    _msg green "wireguard data path: $G_DATA"

    case "${MENU_OPTION}" in
    1) new_key "$@" ;;
    2) set_peer "$@" ;;
    3) reload_conf "$@" ;;
    4) get_qrcode "$@" ;;
    5) revoke_client "$@" ;;
    *)
        echo "Invalid option: $MENU_OPTION"
        exit 0
        ;;
    esac
}

main "$@"

# wg syncconf wg0 <(wg-quick strip wg0)
