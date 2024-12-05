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

# wget -U "" -O expand-root.sh "https://openwrt.org/_export/code/docs/guide-user/advanced/expand_root?codeblock=0"
# . ./expand-root.sh

# Configure startup scripts
cat <<"EOF" >/etc/uci-defaults/70-rootpt-resize
if [ ! -e /etc/rootpt-resize ] \
&& type parted > /dev/null \
&& lock -n /var/lock/root-resize
then
ROOT_BLK="$(readlink -f /sys/dev/block/"$(awk -e \
'$9=="/dev/root"{print $3}' /proc/self/mountinfo)")"
ROOT_DISK="/dev/$(basename "${ROOT_BLK%/*}")"
ROOT_PART="${ROOT_BLK##*[^0-9]}"
parted -f -s "${ROOT_DISK}" \
resizepart "${ROOT_PART}" 100%
mount_root done
touch /etc/rootpt-resize
reboot
fi
exit 1
EOF

cat <<"EOF" >/etc/uci-defaults/80-rootfs-resize
if [ ! -e /etc/rootfs-resize ] \
&& [ -e /etc/rootpt-resize ] \
&& type losetup > /dev/null \
&& type resize2fs > /dev/null \
&& lock -n /var/lock/root-resize
then
ROOT_BLK="$(readlink -f /sys/dev/block/"$(awk -e \
'$9=="/dev/root"{print $3}' /proc/self/mountinfo)")"
ROOT_DEV="/dev/${ROOT_BLK##*/}"
LOOP_DEV="$(awk -e '$5=="/overlay"{print $9}' \
/proc/self/mountinfo)"
if [ -z "${LOOP_DEV}" ]
then
LOOP_DEV="$(losetup -f)"
losetup "${LOOP_DEV}" "${ROOT_DEV}"
fi
resize2fs -f "${LOOP_DEV}"
mount_root done
touch /etc/rootfs-resize
reboot
fi
exit 1
EOF

if ! grep -qE "70-rootpt-resize" /etc/sysupgrade.conf; then
    echo '/etc/uci-defaults/70-rootpt-resize' >>/etc/sysupgrade.conf
fi
if ! grep -qE "80-rootfs-resize" /etc/sysupgrade.conf; then
    echo '/etc/uci-defaults/80-rootfs-resize' >>/etc/sysupgrade.conf
fi

# Expand root partition/filesystem
sh /etc/uci-defaults/70-rootpt-resize
