#!/bin/sh

_msg() {
    if command -v gdate >/dev/null; then
        time_now="$(gdate +%Y%m%d-%u-%T.%3N)"
    else
        time_now="$(date +%Y%m%d-%u-%T.%3N)"
    fi
    if [ "${1:-none}" = log ]; then
        shift
        echo "${time_now} $*" >>"$me_log"
    else
        if [ "${msg_disable:-0}" -eq 1 ]; then
            return
        fi
        echo "${time_now} $*"
    fi
}

_get_config() {
    ## get config from file
    XDG_CONFIG_HOME="$HOME/.config"
    if [ -d "$XDG_CONFIG_HOME/ddns" ]; then
        me_conf="$XDG_CONFIG_HOME/ddns/${me_name}.conf"
        me_log="$XDG_CONFIG_HOME/ddns/${me_name}.log"
    else
        [ -d "$me_path_data" ] || mkdir -p "$me_path_data"
        me_conf="$me_path_data/${me_name}.conf"
        me_log="$me_path_data/${me_name}.log"
    fi
    _msg "config file: $me_conf"
    _msg "log file: $me_log"

    . "$me_conf"

    ## get config from args
    if [ -z "$dynv6_host" ] || [ -z "$dynv6_token" ]; then
        dynv6_host=${ddns_host}
        dynv6_token=${ddns_token}
    fi
    if [ -z "$dynv6_host" ] || [ -z "$dynv6_token" ]; then
        echo "Usage: $0 <your-name>.dynv6.net <token> [device]"
        return 1
    fi
    _msg "dynv6_host: $dynv6_host"
}

## get last ip from log
_get_ip_last() {
    ip4_last=$(awk 'END {print $3}' "$me_log")
    _msg "ip4_last: $ip4_last"
    ip6_last=$(awk 'END {print $5}' "$me_log")
    _msg "ip6_last: $ip6_last"
}

## curl or wget
_get_ip_current() {
    ## get current ip from Internet or Interface
    # if [ -n "$wan_device" ]; then
    #   wan_device="dev $wan_device"
    # fi
    if [ "$(uname -o)" = Darwin ]; then
        # ip4_current=$($cmd cip.cc | awk '/^IP.*:/ {print $3}')
        ip4_current=$($cmd 4.ipw.cn)
        ip6_current=$(ifconfig en0 | awk '/inet6.*temporary/ {print $2}' | head -n 1)
    # ip6_current=$($cmd 6.ipw.cn | tail -n 1)
    # elif grep -q 'ID="openwrt"' /etc/os-release; then
    #     . /lib/functions/network.sh
    #     network_flush_cache
    #     IPV=4
    #     eval network_find_wan${IPV%4} NET_IF
    #     eval network_get_ipaddr${IPV%4} NET_ADDR "${NET_IF}"
    #     ip4_current="${NET_ADDR}"
    #     IPV=6
    #     eval network_find_wan${IPV%4} NET_IF
    #     eval network_get_ipaddr${IPV%4} NET_ADDR "${NET_IF}"
    #     ip6_current="${NET_ADDR}"
    else
        ip4_current=$(ip -4 addr list scope global "$wan_device" | awk '/inet/ {print $2}' | head -n 1)
        ip6_current=$(ip -6 addr list scope global "$wan_device" | awk '/inet6/ {print $2}' | head -n 1)
        # ip6_current=${ip6_current%%/*}
    fi
    _msg "ip4_current: $ip4_current"
    _msg "ip6_current: $ip6_current"
}

# address with netmask
# ip6_current=$ip6_current/${netmask:-128}
_compare_ip() {
    if [ "$ip6_last" = "$ip6_current" ] && [ "$ip4_last" = "$ip4_current" ]; then
        _msg "not changed"
        if [ "${force_update:-0}" -eq 1 ]; then
            _msg "force update"
            return 1
        else
            return 0
        fi
    else
        return 1
    fi
}

_update_dynv6() {
    if [ -z "$ip4_current" ]; then
        _msg "Not found IPv4 address"
    else
        $cmd "http://ipv4.dynv6.com/api/update?ipv4=auto&zone=${dynv6_host}&token=${dynv6_token}"
        # $cmd "http://ipv4.dynv6.com/api/update?ipv4=${ip4_current}&zone=${dynv6_host}&token=${dynv6_token}"
        echo
        _msg log "IPV4:  ${ip4_current:-none}  IPV6:  ${ip6_current:-none}"
    fi
    if [ -z "$ip6_current" ]; then
        _msg "Not found IPv6 address"
    else
        # $cmd "http://ipv6.dynv6.com/api/update?ipv6=auto&zone=${dynv6_host}&token=${dynv6_token}"
        $cmd "http://ipv6.dynv6.com/api/update?ipv6=${ip6_current}&zone=${dynv6_host}&token=${dynv6_token}"
        echo
        _msg log "IPV4:  ${ip4_current:-none}  IPV6:  ${ip6_current:-none}"
    fi
}

_set_args() {
    ## disable proxy
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
    if [ -x /usr/local/opt/curl/bin/curl ]; then
        cmd="/usr/local/opt/curl/bin/curl -fsSL"
    elif [ -x /usr/bin/curl ]; then
        cmd="/usr/bin/curl -fsSL"
    elif [ -x /usr/bin/wget ]; then
        cmd="wget --quiet -O-"
    else
        echo "neither curl nor wget found"
        echo "try to install curl"
        echo "opkg update && opkg install curl"
        exit 1
    fi
    wan_device=pppoe-wan
    case "$1" in
    -f | --force)
        force_update=1
        shift
        ;;
    -h | --host)
        ddns_host=$2
        shift 2
        ;;
    -t | --token)
        ddns_token=$2
        shitf 2
        ;;
    -d | --device)
        wan_device=$2
        shitf 2
        ;;
    --auto)
        msg_disable=1
        ;;
    # *)
    #     _msg "Usage: $me_name [force] <config>"
    #     ;;
    esac
}

main() {
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_path_data="$me_path/../data"

    ## interface name in openwrt
    _set_args "$@"
    _get_config || return
    _get_ip_last
    _get_ip_current
    _compare_ip && return
    _update_dynv6
    # _update_aliyun
}

main "$@"
