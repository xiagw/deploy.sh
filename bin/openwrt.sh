#!/bin/sh

os_release=/etc/os-release
etc_hosts=/etc/hosts
openwrt_ip=$(uci get network.lan.ipaddr)
proxy_port=1080
wpad_file=/www/wpad.dat

if [ -f $os_release ] && grep -i -q openwrt $os_release; then
    echo "setup $etc_hosts"
    grep -q wpad $etc_hosts || echo "$openwrt_ip wpad" >>$etc_hosts
    /etc/init.d/dnsmasq restart

    echo "generate $wpad_file"
    cat >$wpad_file <<EOF
function FindProxyForURL(url, host) {
    return "PROXY $openwrt_ip:$proxy_port";
}
EOF
else
    echo "not found openwrt in $os_release, skip"
    exit 1
fi

# wget https://github.com/XTLS/Xray-core/releases/download/v1.8.10/Xray-linux-64.zip