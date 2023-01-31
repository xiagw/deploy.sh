#!/usr/bin/env bash

mkwinpeimg --iso \
    --windows-dir=/net/nas/mnt/nas/data/win10 \
    -s $HOME/src/deploy.sh/docs/pxe/startnet.cmd \
    -a amd64 $HOME/winpe.iso

for host in zmvm nas; do
    rsync -avzP $HOME/winpe.iso $host:/tftpboot/
    rsync -av $HOME/src/deploy.sh/docs/pxe/startnet.cmd $host:/tftpboot/kali/
    rsync -av $HOME/src/deploy.sh/docs/pxe/pxelinux.cfg/ $host:/tftpboot/pxelinux.cfg/
done

rsync -av $HOME/src/deploy.sh/docs/pxe/dnsmasq.vm.conf zmvm:/etc/dnsmasq.conf
ssh zmvm systemctl restart dnsmasq
rsync -av $HOME/src/deploy.sh/docs/pxe/dnsmasq.conf nas:/etc/dnsmasq.conf
ssh nas systemctl restart dnsmasq
