#!/bin/sh

_get_config() {
    ## get config from file
    XDG_CONFIG_HOME="$HOME/.config"
    if [ -d "$XDG_CONFIG_HOME/ddns" ]; then
        me_env="$XDG_CONFIG_HOME/ddns/${me_name}.env"
        me_log="$XDG_CONFIG_HOME/ddns/${me_name}.log"
    else
        [ -d "$me_path_data" ] || mkdir -p "$me_path_data"
        me_env="$me_path_data/${me_name}.env"
        me_log="$me_path_data/${me_name}.log"
    fi
    _msg "config file: $me_env"
    _msg "log file: $me_log"

    . "$me_env"

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
        _msg log "$me_log" "IPV4:  ${ip4_current:-none}  IPV6:  ${ip6_current:-none}"
    fi
    if [ -z "$ip6_current" ]; then
        _msg "Not found IPv6 address"
    else
        # $cmd "http://ipv6.dynv6.com/api/update?ipv6=auto&zone=${dynv6_host}&token=${dynv6_token}"
        $cmd "http://ipv6.dynv6.com/api/update?ipv6=${ip6_current}&zone=${dynv6_host}&token=${dynv6_token}"
        echo
        _msg log "$me_log" "IPV4:  ${ip4_current:-none}  IPV6:  ${ip6_current:-none}"
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
    -s | --auto | --silent)
        silent_mode=1
        ;;
    # *)
    #     _msg "Usage: $me_name [force] <config>"
    #     ;;
    esac
}

main() {
    cmd_readlink="$(command -v greadlink)"
    me_path="$(dirname "$(${cmd_readlink:-readlink} -f "$0")")"
    me_path_data="$me_path/../data"
    me_name="$(basename "$0")"

    . "$me_path"/include.sh

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
