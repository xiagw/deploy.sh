#!/bin/sh

_get_config() {
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    ddns_conf_path="${XDG_CONFIG_HOME}/ddns"
    [ -d "$ddns_conf_path" ] || ddns_conf_path="$g_me_data_path"

    g_me_env="${ddns_conf_path}/${g_me_name}.env"
    g_me_log="${ddns_conf_path}/${g_me_name}.log"

    _msg "config file: $g_me_env"
    _msg "log file: $g_me_log"
    # shellcheck disable=SC1090
    . "$g_me_env"

    dynv6_host="${dynv6_host:-$ddns_host}"
    dynv6_token="${dynv6_token:-$ddns_token}"

    if [ -z "$dynv6_host" ] || [ -z "$dynv6_token" ]; then
        echo "Usage: $0 <your-name>.dynv6.net <token> [device]"
        return 1
    fi
    _msg "ddns dynv6 host: $dynv6_host"
}

## get last ip from log
_get_saved_ip() {
    ip4_last=$(tail -n1 "$g_me_log" | awk '{print $4}')
    ip6_last=$(tail -n1 "$g_me_log" | awk '{print $6}')
    _msg "get old IPv4 from log file: $ip4_last"
    _msg "get old IPv6 from log file: $ip6_last"
}

# address with netmask
# ip6_current=$ip6_current/${netmask:-128}

_update_dynv6() {
    [ "$ip6_last" = "${ip6_current-}" ] && [ "$ip4_last" = "${ip4_current-}" ] && [ "${force_update:-0}" -ne 1 ] && return

    base_url="http://dynv6.com/api/update?hostname=${dynv6_host}&token=${dynv6_token}"
    $cmd "${base_url}&ipv4=${ip4_current}" \
        -fsSL "${base_url}&ipv6=${ip6_current}" && echo
    _msg log "$g_me_log" "IPV4: ${ip4_current:-none} IPV6: ${ip6_current:-none}"
}

_parse_args() {
    ## disable proxy
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
    if [ -x /usr/local/opt/curl/bin/curl ]; then
        cmd="/usr/local/opt/curl/bin/curl -fsSL"
    elif [ -x /usr/bin/curl ]; then
        cmd="/usr/bin/curl -fsSL"
    elif [ -x /usr/bin/wget ]; then
        cmd="wget --quiet -O-"
    else
        echo "Neither curl nor wget found. Please install curl."
        echo "opkg update && opkg install curl"
        return 1
    fi

    wan_device=pppoe-wan
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -f | --force) force_update=1 ;;
        -h | --host) ddns_host=$2 && shift ;;
        -t | --token) ddns_token=$2 && shift ;;
        -d | --device) wan_device=$2 && shift ;;
        -s | --auto | --silent) silent_mode=1 ;;
        *) echo "Unknown option: $1" ;;
        esac
        shift
    done
    echo "$wan_device $silent_mode" >/dev/null
}

_include_sh() {
    include_sh="$g_me_path/include.sh"
    if [ ! -f "$include_sh" ]; then
        include_sh='/tmp/include.sh'
        if [ ! -f "$include_sh" ]; then
            include_url='https://gitee.com/xiagw/deploy.sh/raw/main/bin/include.sh'
            curl -fsSL "$include_url" >"$include_sh"
        fi
    fi
    # shellcheck disable=SC1090
    . "$include_sh"
}

main() {
    g_me_name="$(basename "$0")"
    g_me_path="$(dirname "$($(command -v greadlink || command -v readlink) -f "$0")")"
    g_me_env="$g_me_path/${g_me_name}.env"
    g_me_log="$g_me_path/${g_me_name}.log"
    g_me_data_path="$g_me_path/../data"

    ## interface name in openwrt
    _parse_args "$@" || return
    _include_sh || return
    _get_config || return
    _get_saved_ip
    _get_current_ip
    _update_dynv6
}

main "$@"
