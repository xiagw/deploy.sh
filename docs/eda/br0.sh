#!/usr/bin/env bash

## CentOS 7.9
nmcli connection add type bridge autoconnect yes con-name br0 ifname br0
nmcli connection modify br0 ipv4.method auto
#curl -L http://10.9.0.27:8000/before
nmcli connection delete em3
nmcli connection add type bridge-slave autoconnect yes con-name em3 ifname em3 master br0
# curl -L http://10.9.0.27:8000/after
sleep 10

reboot

exit

virsh net-define br0.xml
virsh net-start br0
virsh net-autostart br0
virsh net-list --all

virt-install \
--name centos7 \
--ram 4096 \
--disk path=/var/lib/libvirt/images/centos7.img,size=30 \
--vcpus 2 \
--os-type linux \
--os-variant rhel7 \
--network bridge=br0 \
--graphics none \
--console pty,target_type=serial \
--location 'http://mirrors.ustc.edu.cn/centos/7.9.2009/os/x86_64/' \
--extra-args 'console=ttyS0,115200n8 serial'