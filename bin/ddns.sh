#!/bin/sh
# shellcheck disable=SC2016,SC1090
# DynV6 DDNS Update Script
# Version: 1.0.0
# Description: This script updates DynV6 DNS records with the current IP address.
#  support ipv4 and ipv6
#  support macos/openwrt/linux
#
# Usage: ./ddns.sh [OPTIONS]
# See --help for more information.

_get_config() {
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    ddns_conf_path="${XDG_CONFIG_HOME}/ddns"
    [ -d "$ddns_conf_path" ] || ddns_conf_path="$g_me_data_path"

    g_me_env="${ddns_conf_path}/${g_me_name}.env"
    g_me_log="${ddns_conf_path}/${g_me_name}.log"

    echo "config file: $g_me_env"
    echo "log file: $g_me_log"
    . "$g_me_env"

    dynv6_host="${dynv6_host:-$ddns_host}"
    dynv6_token="${dynv6_token:-$ddns_token}"

    if [ -z "$dynv6_host" ] || [ -z "$dynv6_token" ]; then
        echo "Usage: $0 <your-name>.dynv6.net <token> [device]"
        return 1
    fi
    echo "ddns dynv6 host: $dynv6_host"
}

## get last ip from log
_get_saved_ip() {
    ip4_last=$(awk 'END {print $4}' "$g_me_log")
    ip6_last=$(awk 'END {print $6}' "$g_me_log")
    _msg yellow "get old IPv4 from log file: $ip4_last"
    _msg yellow "get old IPv6 from log file: $ip6_last"
}

# address with netmask
# ip6_current=$ip6_current/${netmask:-128}

_update_dynv6() {
    if [ "$ip6_last" = "${ip6_current-}" ] && [ "$ip4_last" = "${ip4_current-}" ] && [ "${force_update:-0}" -ne 1 ]; then
        echo "old == current, skip update"
        return
    fi

    base_url="http://dynv6.com/api/update?hostname=${dynv6_host}&token=${dynv6_token}"
    if curl -fssL "${base_url}&ipv4=${ip4_current}" -fsSL "${base_url}&ipv6=${ip6_current}"; then
        echo
        _msg log "$g_me_log" "IPV4: ${ip4_current:-none} IPV6: ${ip6_current:-none}"
    else
        _msg error "Failed to update DynV6"
        return 1
    fi
}

_print_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]
Update DynV6 DNS records.

Options:
  -f, --force           Force update even if IP hasn't changed
  -h, --host HOST       Set the DynV6 hostname
  -t, --token TOKEN     Set the DynV6 token
  -d, --device DEVICE   Set the network device (default: pppoe-wan)
  -s, --silent         Run in silent mode
  --help               Display this help message

Environment variables:
  ddns_host            DynV6 hostname (can be set in config file)
  ddns_token           DynV6 token (can be set in config file)
EOF
}

_parse_args() {
    ## disable proxy
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY

    wan_device=pppoe-wan
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -a | --auto | --silent) silent_mode=1 ;;
        -f | --force) force_update=1 ;;
        -o | --host) ddns_host=$2 && shift ;;
        -t | --token) ddns_token=$2 && shift ;;
        -d | --device) wan_device=$2 && shift ;;
        -h | --help) _print_usage && exit 0 ;;
        *) echo "Unknown option: $1" && _print_usage && exit 1 ;;
        esac
        shift
    done
    echo "$wan_device $silent_mode" >/dev/null
}

_common_lib() {
    common_lib="$g_me_lib_path/common.sh"
    if [ ! -f "$common_lib" ]; then
        common_lib='/tmp/common.sh'
        include_url="https://gitee.com/xiagw/deploy.sh/raw/main/lib/common.sh"
        [ -f "$common_lib" ] || curl -fsSL "$include_url" >"$common_lib"
    fi
    . "$common_lib"
}

_setup_environment() {
    g_me_name="$(basename "$0")"
    g_me_path="$(dirname "$($(command -v greadlink || command -v readlink) -f "$0")")"
    g_me_path_parent="$(dirname "$g_me_path")"
    g_me_lib_path="$g_me_path_parent/lib"
    g_me_data_path="$g_me_path_parent/data"
    g_me_env="$g_me_path/${g_me_name}.env"
    g_me_log="$g_me_path/${g_me_name}.log"
}

main() {
    _setup_environment
    _common_lib || return
    _parse_args "$@" || return
    _get_config || return
    _get_saved_ip
    _get_current_ip
    _update_dynv6
}

main "$@"
