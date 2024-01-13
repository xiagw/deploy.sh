#!/usr/bin/env bash

# set -x
## hostname
# read -rp "set-hostname (pve1.test.com): " host_name
# hostnamectl set-hostname "${host_name:-pve1.test.com}"
# echo "$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)    ${host_name}" >>/etc/hosts

## set mirror
sed -i 's|^deb http://ftp.debian.org|deb https://mirrors.ustc.edu.cn|g' /etc/apt/sources.list
sed -i 's|^deb http://security.debian.org|deb https://mirrors.ustc.edu.cn/debian-security|g' /etc/apt/sources.list

# 修改 Proxmox 的源文件，可以使用如下命令：
source /etc/os-release
echo "deb https://mirrors.ustc.edu.cn/proxmox/debian/pve $VERSION_CODENAME pve-no-subscription" >/etc/apt/sources.list.d/pve-no-subscription.list
# 对于 Proxmox Backup Server 和 Proxmox Mail Gateway，请将以上命令中的 pve 分别替换为 pbs 和 pmg。
# PVE 8 之后默认安装 ceph 仓库源文件 /etc/apt/sources.list.d/ceph.list，可以使用如下命令更换源：
if [ -f /etc/apt/sources.list.d/ceph.list ]; then
    CEPH_CODENAME=$(ceph -v | grep ceph | awk '{print $(NF-1)}')
    source /etc/os-release
    echo "deb https://mirrors.ustc.edu.cn/proxmox/debian/ceph-$CEPH_CODENAME $VERSION_CODENAME no-subscription" >/etc/apt/sources.list.d/ceph.list
fi
# 更改完 sources.list 文件后请运行 apt update 更新索引以生效。
# CT Templates
# 另外，如果你需要使用 Proxmox 网页端下载 CT Templates，可以替换 CT Templates 的源为 http://mirrors.ustc.edu.cn。
# 具体方法：将 /usr/share/perl5/PVE/APLInfo.pm 文件中默认的源地址 http://download.proxmox.com 替换为 https://mirrors.ustc.edu.cn/proxmox 即可。可以使用如下命令：
cp /usr/share/perl5/PVE/APLInfo.pm /usr/share/perl5/PVE/APLInfo.pm.bak
sed -i 's|http://download.proxmox.com|https://mirrors.ustc.edu.cn/proxmox|g' /usr/share/perl5/PVE/APLInfo.pm
# 针对 /usr/share/perl5/PVE/APLInfo.pm 文件的修改，执行`systemctl restart pvedaemon`后生效。
systemctl restart pvedaemon

## ssl cert
# scp ~/Downloads/test.com.key /etc/pve/nodes/pve1/pveproxy-ssl.key
# scp ~/Downloads/test.com.pem /etc/pve/nodes/pve1/pveproxy-ssl.pem
# pvecm updatecerts -f
# systemctl restart pvedaemon.service pveproxy.service
# journalctl -b -u pveproxy.service

## disable subscription 禁止注册提示信息
sed -i -e "s/data.status.*ctive'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
sed -i 's/^/#/g' /etc/apt/sources.list.d/pve-enterprise.list

## byobu and upgrade
apt update -yq
apt install -y byobu
apt upgrade -y

# ssh-key
grep -q cen8UtnI13y $HOME/.ssh/authorized_keys ||
    curl -fsSL 'https://github.com/xiagw.keys' >>$HOME/.ssh/authorized_keys

# https://forum.proxmox.com/threads/installing-ceph-in-pve8-nosub-repo.131348/
## install ceph 17
# yes | pveceph install --repository no-subscription
## install ceph 18
yes | pveceph install --repository no-subscription --version reef

## iso dir
# /var/lib/pve/local-btrfs/template/iso/

# $Installer = "qemu-ga-x86_64.msi"
# if ([Environment]::Is64BitOperatingSystem -eq $false)
# {
#     $Installer = "qemu-ga-i386.msi"
# }
# Start-Process msiexec -ArgumentList "/I e:\GUEST-AGENT\$Installer /qn /norestart" -Wait -NoNewWindow

# windows - Unattend Installation with virtio drivers doesn't activate network drivers - Stack Overflow
# https://stackoverflow.com/questions/70234047/unattend-installation-with-virtio-drivers-doesnt-activate-network-drivers

# https://pve.proxmox.com/pve-docs/pve-admin-guide.html#storage_lvmthin
# https://pve-doc-cn.readthedocs.io/zh-cn/latest/chapter_storage/lvmthinstorage.html

## import from ESXi
# qm set 130 --bios ovmf
# sed -i 's/scsi0:/sata0:/' /etc/pve/qemu-server/130.conf
# qm set 215 --bios ovmf --boot cdn --ostype win10 --agent 1 --cpu host --sata0 local-btrfs:215/vm-215-disk-0.raw --net0 virtio,bridge=vmbr0 --ide0 local-btrfs:iso/virtio-win-0.1.225.iso,media=cdrom

# Checking Virtio Drivers in Linux | Tencent Cloud
# https://www.tencentcloud.com/document/product/213/9929

# ceph auth get client.bootstrap-osd >/etc/pve/priv/ceph.client.bootstrap-osd.keyring

# ceph daemon mon.$(hostname -s) config set auth_allow_insecure_global_id_reclaim true
# ceph daemon mon.$(hostname -s) config set auth_allow_insecure_global_id_reclaim false
# ceph daemon mon.$(hostname -s) config get auth_allow_insecure_global_id_reclaim

# scp /var/lib/ceph/bootstrap-osd/ceph.keyring pve2:/var/lib/ceph/bootstrap-osd/ceph.keyring
# scp /var/lib/ceph/bootstrap-osd/ceph.keyring pve3:/var/lib/ceph/bootstrap-osd/ceph.keyring
# sgdisk -t 4:0FC63DAF-8483-4772-8E79-3D69D8477DE4 /dev/sda

## 重置 ceph
# pveceph stop; pveceph purge

# for id in $(qm list | awk '/running/ {print $1}'); do qm shutdown $id; done
# for h in zd-pve1 zd-pve2 zd-pve3; do ssh $h "reboot"; done
