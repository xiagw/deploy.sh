#!/bin/sh

os_release=/etc/os-release
etc_hosts=/etc/hosts
dnsmasq_conf=/etc/dnsmasq.conf
proxy_port=1080
wpad_file=/www/wpad.dat

openwrt_ip=$(uci get network.lan.ipaddr)
if [ -f "$os_release" ] && grep -i -q openwrt "$os_release"; then
    echo "setup $etc_hosts"
    grep -q wpad "$etc_hosts" || echo "$openwrt_ip wpad" >>"$etc_hosts"

    echo "setup $dnsmasq_conf"
    grep -q "dhcp-option=252" "$dnsmasq_conf" ||
        echo "dhcp-option=252,\"http://$openwrt_ip/wpad.dat\"" >>"$dnsmasq_conf"

    echo "generate $wpad_file"
    cat >"$wpad_file" <<EOF
function FindProxyForURL(url, host) {
    return "PROXY $openwrt_ip:$proxy_port";
}
EOF

    echo "restart dnsmasq service"
    /etc/init.d/dnsmasq restart
else
    echo "not found openwrt in $os_release, skip"
    exit 1
fi

# wget https://github.com/XTLS/Xray-core/releases/download/v1.8.10/Xray-linux-64.zip

# vim /etc/dnsmasq.conf
# dhcp-option=252,"http://router_ip/wpad.dat"
# $ vim /www/wpad.dat # put pac here
# $ service dnsmasq restart