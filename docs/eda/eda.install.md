
yum install -y autossh

OPTIONS=-M 0 -NT -o "ServerAliveInterval 60" -o "ServerAliveCountMax 3" -l autossh -i /path/to/id_rsa -L 7474:127.0.0.1:22 120.78.90.153

OPTIONS=-M 0 -N -F /etc/autossh/.help help

## pixz
configure; make; sudo make install

## yum
sed -e 's|^mirrorlist=|#mirrorlist=|g' \
-e 's|^#baseurl=http://mirror.centos.org/centos|baseurl=https://mirrors.ustc.edu.cn/centos|g' \
-i.bak \
/etc/yum.repos.d/CentOS-Base.repo

## wireguard
yum install epel-release elrepo-release
yum install yum-plugin-elrepo
yum install kmod-wireguard wireguard-tools
sed -i '/^enable/s/1/0/g' /etc/yum.repos.d/elrepo.repo

## NFS
sed -i -e 's/^ONBOOT=no/ONBOOT=yes/' /etc/sysconfig/network-scripts/ifcfg-eth0
sed -i '5 a Domain = quantum.edu'  /etc/idmapd.conf
## rpcbind 有先后顺序
for i in nfs ypserv yppasswdd ypxfrd rpcbind.socket rpcbind; do systemctl stop $i; done
for i in rpcbind.socket rpcbind nfs ypxfrd ypserv yppasswdd; do systemctl start $i; done

## host
sed -i '/192.168.7/d' /etc/hosts
for i in $(seq -w 11 20); do echo "192.168.7.$i node${i}.quantum.edu node$i" >>/etc/hosts; done

## NIS
yum -y install ypbind rpcbind
ypdomainname quantum.edu
echo "NISDOMAIN=quantum.edu" >> /etc/sysconfig/network
authconfig --enablenis --nisdomain=quantum.edu --nisserver=node11.quantum.edu --enablemkhomedir --update
for i in ypbind rpcbind.socket rpcbind; do systemctl stop $i; done
for i in rpcbind.socket rpcbind ypbind; do systemctl start $i; done

## VNC
yum -y groups install "Server with GUI"
yum --enablerepo=epel -y groups install "Xfce"
yum install cjkuni-ukai-fonts
yum install -y tigervnc-server
# echo "exec /usr/bin/xfce4-session" >> ~/.xinitrc
firewall-cmd --add-port=5900-5920/tcp --permanent; firewall-cmd --reload
for i in $(seq 1 9); do grep -q eda$i /etc/sysconfig/vncusers || echo ":$i=eda0$i" >>/etc/sysconfig/vncusers; done

systemctl get-default
systemctl set-default multi-user.target
systemctl set-default graphical.target

## 禁止三键重启
systemctl mask ctrl-alt-del.target
gsettings set org.gnome.settings-daemon.plugins.media-keys logout ''
# cat /etc/dconf/db/local.d/00-disable-CAD
[org/gnome/settings-daemon/plugins/media-keys]
logout=''
# dconf update

## disable shutdown / reboot from desktop
linux - What is the correct way to prevent non-root users from issuing shutdowns or reboots - Super User
https://superuser.com/questions/354678/what-is-the-correct-way-to-prevent-non-root-users-from-issuing-shutdowns-or-rebo

Try this: create a file named, say,  in /etc/polkit-1/rules.d/55-inhibit-shutdown.rules with the following contents:

polkit.addRule(function(action, subject) {
  if ((action.id == "org.freedesktop.consolekit.system.stop" || action.id == "org.freedesktop.consolekit.system.restart") && subject.isInGroup("admin")) {
    return polkit.Result.YES;
  } else {
    return polkit.Result.NO;
  }
});

polkit.addRule(function(action, subject) {
  if ((action.id == "org.freedesktop.consolekit.system.stop" || action.id == "org.freedesktop.consolekit.system.restart") && subject.isInGroup("users")) {
    return subject.active ? polkit.Result.AUTH_ADMIN : polkit.Result.NO;
  }
});

polkit.addRule(function(action, subject) {
  if (action.id.indexOf("org.freedesktop.login1.power-off") == 0 || action.id.indexOf("org.freedesktop.login1.reboot") == 0) {
    try {
      // user-may-reboot exits with success (exit code 0)
      // only if the passed username is authorized
      polkit.spawn(["/usr/local/bin/user-may-reboot", subject.user]);
      return polkit.Result.YES;
    } catch (error) {
      // Nope, but do allow admin authentication
      return polkit.Result.AUTH_ADMIN;
    }
  }
});

## IC617 Hotfix 702
ln -sf /usr/lib64/libcrypto.so.1.0.2k /usr/lib64/libcrypto.so.6

## openlava
```
## /eda/openlava-4.0/etc/openlava, line 102:
port1="$(lsof -i -P | awk '/^lim.*TCP/ {print $9}')"
firewall-cmd --add-port=${port1#*:}/tcp
```
8、添加lsf主机，修改 /data/softwares/openlava/etc/lsf.cluster.openlava

9、启动openlava，/etc/init.d/openlava start‘

10、在OpenLava master服务器执行重载

badmin reconfig

lsadmin reconfig


QRC安装问题 - Analog/RF IC 资料共享 - EETOP 创芯网论坛 (原名：电子顶级开发网) -
https://bbs.eetop.cn/thread-883025-1-1.html


配置Cadence符合自己的使用习惯——.cdsinit和.cdsenv文件的妙用 - 知乎
https://zhuanlan.zhihu.com/p/334782042

还有几个工具我们需要的innovus19，emx，HFSS

其他的cadence工具

CONFRML192  EXT191  GENUS191  IC617ISR22 SPECTRE191  SSV191  TEMPUS等


本帖隐藏的内容
https://downloadly.win/cadence-ic-design-virtuoso-06-17-721-specter-17-10-124/




version: "3.8"
services:
  wg-easy:
    environment:
      - WG_HOST=nas.quantum.edu
      - PASSWORD=kach2Ohph2
      - WG_DEFAULT_ADDRESS=10.9.0.25
      - WG_DEFAULT_DNS=114.114.114.114
      - WG_ALLOWED_IPS=10.9.0.0/24
    image: weejewel/wg-easy
    container_name: wg-easy
    volumes:
      - .:/etc/wireguard
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1


## Synology 群晖 NAS

Replacing OpenVPN with Wireguard, including on Synology devices | Martin Paul Eve | Professor of Literature, Technology and Publishing
https://eve.gd/2021/08/20/replacing-openvpn-with-wireguard-including-on-synology-devices/

How to install IPKG on Synology NAS | Synology Community
https://community.synology.com/enu/forum/1/post/127148

一些套件源：
1.packages： http://packages.synocommunity.com/?beta=1
2.KS7.0SPK：https://spk7.imnks.com/
3.ACMENet： http://synology.acmenet.ru
4.communitypackage hub：http://www.cphub.net
5.Cambier：https://synology.cambier.org/
6.Dierkse：http://syno.dierkse.nl/
7.FileBot：https://get.filebot.net/syno/
8.Hildinger：http://www.hildinger.us/sspks/

vi /etc/sysconfig/network-scripts/ifcfg-eth0:1
NAME=eth0:1
DEVICE=eth0:1
BOOTPROTO=static
IPADDR=192.168.7.10
PREFIX=24
ONBOOT=yes


How to Clear the DNS Cache on Linux
$ resolvectl flush-caches

[Desktop Entry]
Comment=cadence_ic
Comment[zh_CN]=脱发必备
Exec=/home/heweibao/Project_cadence/hellocadence
GenericName=cadence_ic
GenericName[zh_CN]=cadence_ic617
Name=cadence_ic
Name[zh_CN]=cadence_ic617
StartupNotify=false
Terminal=false
Type=Application
Icon=/home/heweibao/misc/selfbin/pic_icon/logo-cadence-newsroom.png