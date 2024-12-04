#!/bin/sh

os_release=/etc/os-release
etc_hosts=/etc/hosts
dnsmasq_conf=/etc/dnsmasq.conf
wpad_file=/www/wpad.dat

openwrt_ip=$(uci get network.lan.ipaddr)
if ! grep -i -q openwrt "$os_release"; then
    echo "not found openwrt in $os_release, skip"
    exit 1
fi

echo "setup $etc_hosts"
grep -q wpad "$etc_hosts" || echo "$openwrt_ip wpad" >>"$etc_hosts"

echo "setup $dnsmasq_conf"
grep -q "dhcp-option=252" "$dnsmasq_conf" ||
    echo "dhcp-option=252,\"http://$openwrt_ip/wpad.dat\"" >>"$dnsmasq_conf"

echo "generate $wpad_file"
cat >"$wpad_file" <<EOF
function FindProxyForURL(url, host) {
    return "PROXY $openwrt_ip:1080; SOCKS5 $openwrt_ip:1081; DIRECT";
}
EOF

echo "restart dnsmasq service"
/etc/init.d/dnsmasq restart

## https://openwrt.org/docs/guide-user/advanced/expand_root
opkg update
opkg install wireguard-tools xray-core
opkg install parted losetup resize2fs

wget -U "" -O expand-root.sh "https://openwrt.org/_export/code/docs/guide-user/advanced/expand_root?codeblock=0"
. ./expand-root.sh

# Expand root partition/filesystem
sh /etc/uci-defaults/70-rootpt-resize
