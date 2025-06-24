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

get_config() {
    if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/ddns/${G_NAME}.env" ]; then
        ddns_conf_path="${XDG_CONFIG_HOME:-$HOME/.config}/ddns"
    elif [ -f "$G_PATH_DATA/${G_NAME}.env" ]; then
        ddns_conf_path="$G_PATH_DATA"
    elif [ -f "${G_PATH}/${G_NAME}.env" ]; then
        ddns_conf_path="${G_PATH}"
    else
        echo "Not found ${G_NAME}.env"
        return 1
    fi

    G_ENV="${ddns_conf_path}/${G_NAME}.env"
    G_LOG="${ddns_conf_path}/${G_NAME}.log"

    echo "config file: $G_ENV"
    echo "log file: $G_LOG"
    if [ -z "$DDNS_HOST" ] || [ -z "$DDNS_TOKEN" ]; then
        . "$G_ENV"
    fi

    if [ -z "$DDNS_HOST" ] || [ -z "$DDNS_TOKEN" ]; then
        echo "Usage: $0 <your-name>.dynv6.net <token> [device]"
        return 1
    fi
    echo "ddns dynv6 host: $DDNS_HOST"
}

## get last ip from log
get_saved_ip() {
    ip4_last=$(awk 'END {print $4}' "$G_LOG")
    ip6_last=$(awk 'END {print $6}' "$G_LOG")
    _msg yellow "get old IPv4 from log file: $ip4_last"
    _msg yellow "get old IPv6 from log file: $ip6_last"
}

# address with netmask
# ip6_current=$ip6_current/${netmask:-128}

update_dynv6() {
    if [ "$ip6_last" = "${ip6_current-}" ] && [ "$ip4_last" = "${ip4_current-}" ] && [ "${force_update:-0}" -ne 1 ]; then
        echo "old == current, skip update"
        return
    fi

    base_url="http://dynv6.com/api/update?hostname=${DDNS_HOST}&token=${DDNS_TOKEN}"
    if curl -fssL "${base_url}&ipv4=${ip4_current}" -fsSL "${base_url}&ipv6=${ip6_current}"; then
        echo
        _msg log "$G_LOG" "IPV4: ${ip4_current:-none} IPV6: ${ip6_current:-none}"
    else
        _msg error "Failed to update DynV6"
        return 1
    fi
}

print_usage() {
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
  DDNS_HOST            DynV6 hostname (can be set in config file)
  DDNS_TOKEN           DynV6 token (can be set in config file)
EOF
}

parse_args() {
    ## disable proxy
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY

    wan_device=pppoe-wan
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -a | --auto | --silent) silent_mode=1 ;;
        -f | --force) force_update=1 ;;
        -o | --host) DDNS_HOST=$2 && shift ;;
        -t | --token) DDNS_TOKEN=$2 && shift ;;
        -d | --device) wan_device=$2 && shift ;;
        -h | --help) print_usage && exit 0 ;;
        *) echo "Unknown option: $1" && print_usage && exit 1 ;;
        esac
        shift
    done
    echo "$wan_device $silent_mode" >/dev/null
}

import_common() {
    common_lib="$G_PATH_LIB/common.sh"
    if [ ! -f "$common_lib" ]; then
        common_lib='/tmp/common.sh'
        include_url="https://gitee.com/xiagw/deploy.sh/raw/main/lib/common.sh"
        [ -f "$common_lib" ] || curl -fsSL "$include_url" >"$common_lib"
    fi
    . "$common_lib"
}

setup_environment() {
    G_NAME="$(basename "$0")"
    G_PATH="$(dirname "$($(command -v greadlink || command -v readlink) -f "$0")")"
    G_PATH_UP="$(dirname "$G_PATH")"
    G_PATH_LIB="$G_PATH_UP/lib"
    G_PATH_DATA="$G_PATH_UP/data"
    G_ENV="$G_PATH/${G_NAME}.env"
    G_LOG="$G_PATH/${G_NAME}.log"
}

main() {
    setup_environment
    import_common || return
    parse_args "$@" || return
    get_config || return
    get_saved_ip
    _get_current_ip
    update_dynv6
}

main "$@"
