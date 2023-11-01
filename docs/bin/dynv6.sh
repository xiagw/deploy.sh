#!/bin/sh

# set -x

unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY

me_name="$(basename "$0")"
me_path="$(dirname "$(readlink -f "$0")")"
me_log=$me_path/.${me_name}.log
[ -f "$me_log" ] || touch "$me_log"
## openwrt interface name
device=${3:-pppoe-wan}

## get config from file
export XDG_CONFIG_HOME="$HOME/.config"
if [ -f "$me_path/dynv6.conf" ]; then
    . "$me_path/dynv6.conf"
elif [ -f "$XDG_CONFIG_HOME/dynv6.conf" ]; then
    . "$XDG_CONFIG_HOME/dynv6.conf"
fi
## get config from args
if [ -z "$dynv6_host" ] || [ -z "$dynv6_token" ]; then
    if [ "${#1}" -gt 0 ]; then
        dynv6_host=${1}
        dynv6_token=${2}
        device=${3:-pppoe-wan}
    else
        echo "Usage: $0 <your-name>.dynv6.net <token> [device]"
        exit 1
    fi
fi

## get last ip from log
ip4_last=$(awk 'END {print $3}' "$me_log")
ip6_last=$(awk 'END {print $5}' "$me_log")

## curl or wget
if [ -e /usr/local/opt/curl/bin/curl ]; then
    cmd="/usr/local/opt/curl/bin/curl -fsSL"
elif [ -e /usr/bin/curl ]; then
    cmd="/usr/bin/curl -fsSL"
elif [ -e /usr/bin/wget ]; then
    cmd="wget --quiet -O-"
else
    echo "neither curl nor wget found"
    echo "try to install curl"
    echo "opkg update && opkg install curl"
    exit 1
fi
## get current ip from Internet or Interface
# if [ -n "$device" ]; then
#   device="dev $device"
# fi
if [ "$(uname -o)" = Darwin ]; then
    ip4_current=$($cmd cip.cc | awk '/^IP.*:/ {print $3}')
    ip6_current=$(ifconfig en0 | awk '/inet6.*temporary/ {print $2}' | head -n 1)
else
    ip4_current=$(ip -4 addr list scope global "$device" | awk '/inet/ {print $2}' | head -n 1)
    ip6_current=$(ip -6 addr list scope global "$device" | awk '/inet6/ {print $2}' | head -n 1)
    # ip6_current=${ip6_current%%/*}
fi

# address with netmask
# ip6_current=$ip6_current/${netmask:-128}
if [ "$ip6_last" = "$ip6_current" ] && [ "$ip4_last" = "$ip4_current" ]; then
    echo "IPv4/IPv6 address unchanged"
    if [ "$1" = force ]; then
        echo "force update"
    else
        exit
    fi
fi

if [ -z "$ip4_current" ]; then
    echo "Not found IPc4 address"
else
    $cmd "http://ipv4.dynv6.com/api/update?ipv4=auto&zone=${dynv6_host}&token=${dynv6_token}"
    # $cmd "http://ipv4.dynv6.com/api/update?ipv4=${ip4_current}&zone=${dynv6_host}&token=${dynv6_token}"
    log_ip=1
    echo
fi
if [ -z "$ip6_current" ]; then
    echo "Not found IPv6 address"
else
    # $cmd "http://ipv6.dynv6.com/api/update?ipv6=auto&zone=${dynv6_host}&token=${dynv6_token}"
    $cmd "http://ipv6.dynv6.com/api/update?ipv6=${ip6_current}&zone=${dynv6_host}&token=${dynv6_token}"
    log_ip=1
    echo
fi

## history log
if [ "$log_ip" = 1 ]; then
    echo "$(date +%F_%T)  IPV4:  ${ip4_current:-none}  IPV6:  ${ip6_current:-none}" >>"$me_log"
fi
