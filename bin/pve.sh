#!/usr/bin/env bash

# set -x
## hostname
# read -rp "set-hostname (pve1.test.com): " host_name
# hostnamectl set-hostname "${host_name:-pve1.test.com}"
# echo "$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)    ${host_name}" >>/etc/hosts

## set mirror
sed -i 's|^deb http://ftp.debian.org|deb https://mirrors.ustc.edu.cn|g' /etc/apt/sources.list
sed -i 's|^deb http://security.debian.org|deb https://mirrors.ustc.edu.cn/debian-security|g' /etc/apt/sources.list

## 修改 Proxmox 的源文件，可以使用如下命令：
source /etc/os-release
echo "deb https://mirrors.ustc.edu.cn/proxmox/debian/pve $VERSION_CODENAME pve-no-subscription" | tee /etc/apt/sources.list.d/pve-no-subscription.list
## 对于 Proxmox Backup Server 和 Proxmox Mail Gateway，请将以上命令中的 pve 分别替换为 pbs 和 pmg。
# echo "deb https://mirrors.ustc.edu.cn/proxmox/debian/pbs $VERSION_CODENAME pbs-no-subscription" >/etc/apt/sources.list.d/pbs-no-subscription.list
# echo "deb https://mirrors.ustc.edu.cn/proxmox/debian/pmg $VERSION_CODENAME pmg-no-subscription" >/etc/apt/sources.list.d/pmg-no-subscription.list
## PVE 8 之后默认安装 ceph 仓库源文件 /etc/apt/sources.list.d/ceph.list，可以使用如下命令更换源：
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

# https://dannyda.com/2020/05/17/how-to-remove-you-do-not-have-a-valid-subscription-for-this-server-from-proxmox-virtual-environment-6-1-2-proxmox-ve-6-1-2-pve-6-1-2/
## disable subscription 禁止注册提示信息
# sed -i.backup -z "s/res === null || res === undefined || \!res || res\n\t\t\t.data.status.toLowerCase() \!== 'active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js && systemctl restart pveproxy.service
sed -i -e "s/data.status.*ctive'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
sed -i -e 's/^/#/g' /etc/apt/sources.list.d/pve-enterprise.list
systemctl restart pveproxy.service

## byobu and upgrade
apt update -yq
apt install -y byobu
apt upgrade -y

# ssh-key
if ! grep -q cen8UtnI13y "$HOME"/.ssh/authorized_keys; then
    curl -fsSL 'https://github.com/xiagw.keys' >>"$HOME"/.ssh/authorized_keys
fi

# export http_proxy=http://192.168.41.252:1080
# https://forum.proxmox.com/threads/installing-ceph-in-pve8-nosub-repo.131348/
## install ceph 17
# yes | pveceph install --repository no-subscription
## install ceph 18
if dpkg -l | grep -q ceph; then
    echo "Ceph already install"
else
    yes | pveceph install --repository no-subscription --version reef
fi
## ssl cert
if [ -f $HOME/ssl.key ] && [ -f $HOME/ssl.pem ]; then
    echo "Found $HOME/ssl.key and $HOME/ssl.pem ..."
    cp -vf $HOME/ssl.key /etc/pve/nodes/*/pve-ssl.key
    cp -vf $HOME/ssl.pem /etc/pve/nodes/*/pve-ssl.pem
    # pvecm updatecerts -f
    systemctl restart pvedaemon.service pveproxy.service
    # journalctl -b -u pveproxy.service
fi

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

# qemu-img resize --shrink /var/lib/pve/local-btrfs/images/209/vm-209-disk-0/disk.raw -100G && echo ok

# a=2G; for i in {1..3}; do truncate -s $a /vdisk/$a.$i; done
# zpool create tank /vdisk/2G.1
# zpool attach tank /vdisk/2G.1 /vdisk/2G.2  # mirror

# sysctl -w vm.swappiness=10
# /etc/sysctl.conf
# vm.swappiness = 10
# echo 3 > /proc/sys/vm/drop_caches
# Create the file /etc/modprobe.d/zfs.conf and write memory limits in it : (for example, this is for 4G max and 1G min)
# echo "$[1 * 1024*1024*1024 - 1]" >/sys/module/zfs/parameters/zfs_arc_min
# echo "$[1 * 1024*1024*1024]" >/sys/module/zfs/parameters/zfs_arc_max
# echo "options zfs zfs_arc_min=$[1 * 1024*1024*1024 - 1]" >/etc/modprobe.d/zfs.conf
# echo "options zfs zfs_arc_max=$[1 * 1024*1024*1024]" >>/etc/modprobe.d/zfs.conf
# update-initramfs -u -k all
#
# Workload Tuning — OpenZFS documentation
# https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Workload%20Tuning.html#basic-concepts

# zfs set dedup=on atime=off compression=lz4 zfs01
# apt install nfs-kernel-server

# zfs get compression,dedup,atime,casesensitivity
# zfs create -o compression=lz4 -o dedup=on -o atime=off -o casesensitivity=insensitive -o normalization=none
# zfs create -o compression=lz4 -o dedup=on -o atime=off -o casesensitivity=insensitive tank/share
# zfs create -o compression=on -o atime=off -o casesensitivity=insensitive zfs03/share
# net usershare add fly /zfs01/share /zfs01/share Everyone:F
# zfs set sharenfs='rw' tank/home

## 修改cluster IP
# https://gist.github.com/matissime/ee7b5d1e937e751a97b0013caab24915
# systemctl stop corosync pve-cluster

# pmxcfs -l

# Edit your corosync on a newly created file:
# vi /etc/pve/corosync.conf

# killall pmxcfs

# systemctl start pve-cluster corosync

# reboot

# zfs snapshot -r tank@nas_backup
# zfs send -Rv tank@nas_backup | zfs receive -Fv sonne