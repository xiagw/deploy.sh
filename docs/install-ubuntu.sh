#!/usr/bin/env bash

set -xe

## 增加虚拟内存 8G
sudo dd if=/dev/zero of=/swapfile bs=1G count=8
sudo mkswap /swapfile
sudo swapon /swapfile
## 或增加到 /etc/fstab
grep '/swapfile' /etc/fstab || echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab

# sudo sed -i -e \
# 's/archive.ubuntu/mirrors.aliyun/' \
# -e 's/security.ubuntu/mirrors.aliyun/' \
# /etc/apt/sources.list

## gitlab server change ssh port
# sudo sed -i '/Port/s/22/23/' /etc/ssh/sshd_config
# sudo sed -i '/^#Port/s/#//' /etc/ssh/sshd_config
# sudo systemctl restart sshd

## fresh dns cache
sudo systemd-resolve --flush-caches

## fix locale error
sudo locale-gen zh_CN.UTF-8

## upgrade system
sudo apt update
sudo apt upgrade

## change hostname
# sudo hostnamectl set-hostname <chamgeme>

## 本机安装 install openssh-server
sudo apt update
sudo apt install -y openssh-server

## install terminator
sudo apt install terminator

## Ubuntu 默认仓库自带 git （非最新版）
sudo apt install -y vim curl

# 最新版git
sudo add-apt-repository ppa:git-core/ppa
sudo apt update
sudo apt install -y git

# 本机安装 安装zsh 和 oh my zsh
sudo apt install -y zsh
sudo usermod -s /usr/bin/zsh "$USER"
## 此处假如失败，可以尝试代理:
# export http_proxy=http://192.168.6.1:1080
# export https_proxy=http://192.168.6.1:1080
sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
sed -i -e "s/robbyrussell/ys/" ~/.zshrc
# plugins=(sudo git docker docker-compose zsh-syntax-highlighting rsync systemd)
sed -i -e "/plugins=/s/=.*/=\(git docker docker-compose systemd\)/" ~/.zshrc
## 退出，并重新登录 ssh

## tmm3
sudo apt install libmediainfo0v5 openjdk-11-jre

# sudo apt install openjdk-18-jre

## install docker
curl -fsSL https://get.docker.com | sudo bash
## 系统自带
# sudo apt install docker.io docker-compose

## 以下需要退出 ssh 或退出桌面登录，重新登录才生效
sudo apt-get install -y uidmap
sudo usermod -aG docker "$USER"

sudo systemctl enable docker
sudo systemctl start docker
#sudo systemctl disable docker
# 如果需要,可以更换为中国镜像,也可以不改
# cat <<'EOF'| sudo tee -a /etc/docker/daemon.json
# {
#     "registry-mirrors": ["https://registry.docker-cn.com"]
# }
# EOF

## 截屏软件
sudo apt install -y flameshot

## install vscode
# Download Visual Studio Code - Mac, Linux, Windows
# https://code.visualstudio.com/download

# 基于 Laradock 在 PHPStorm 和 VS Code 下使用 Xdebug (Mac 篇) | Laravel China 社区 - 高品质的 Laravel 开发者社区
# https://learnku.com/articles/19659

## 密码管理器（本地数据库，非在线）
# Download - KeePassXC
# https://keepassxc.org/download/

## xdroid，可安装企业微信
# 安装 · GitBook
# https://www.linzhuotech.com/Public/Home/img/gitbook/user_manual_nv/_book/part2/anzhuang.html

## 数据库管理工具软件
# Download | DBeaver Community
# https://dbeaver.io/download/

# 本机安装 install google chrome
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -y ./google-chrome-stable_current_amd64.deb

## 准备copy原来的git 认证文件
# copy C:\Users\xxx\.ssh\id_rsa* /home/xxx/.ssh/
# copy C:\Users\xxx\.gitconfig /home/xxx/

## 本机安装 install wps

## 本机安装 install chrome,

## 本机安装 install vscode insider, 或者 vscode
# https://code.visualstudio.com/insiders/

# 令人惊叹的Visual Studio Code插件 - Sroot - 博客园
# https://www.cnblogs.com/Sroot/p/7429186.html

# 基于 Laradock 在 PHPStorm 和 VS Code 下使用 Xdebug (Mac 篇) | Laravel China 社区 - 高品质的 Laravel 开发者社区
# https://learnku.com/articles/19659

# sudo snap connect remmina:avahi-observe :avahi-observe
# sudo snap connect remmina:cups-control :cups-control
# sudo snap connect remmina:mount-observe :mount-observe
# sudo snap connect remmina:password-manager-service :password-manager-service

disable_function() {

    docker login --username=xxx@yyy.com registry.cn-shenzhen.aliyuncs.com
    docker pull registry.cn-shenzhen.aliyuncs.com/jztech/repo2:php72
    docker pull registry.cn-shenzhen.aliyuncs.com/jztech/repo2:redis
    docker pull registry.cn-shenzhen.aliyuncs.com/jztech/repo2:nginx2

    docker image tag registry.cn-shenzhen.aliyuncs.com/jztech/repo2:php72 laradock_php-fpm
    docker image tag registry.cn-shenzhen.aliyuncs.com/jztech/repo2:nginx2 laradock_nginx
    docker image tag registry.cn-shenzhen.aliyuncs.com/jztech/repo2:redis laradock_redis

    sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
    sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target

    ## set vnc remote
    # https://wiki.archlinux.org/index.php/Vino
    gsettings set org.gnome.Vino require-encryption false
    dbus-launch gsettings set org.gnome.Vino prompt-enabled false
    dbus-launch gsettings set org.gnome.desktop.lockdown disable-user-switching true
    dbus-launch gsettings set org.gnome.desktop.lockdown disable-log-out true
    dbus-launch gsettings set org.gnome.desktop.interface enable-animations false
    dbus-launch gsettings set org.gnome.Vino authentication-methods "['vnc']"
    dbus-launch gsettings set org.gnome.Vino vnc-password "$(echo -n "mypassword" | base64)"

    # https://askubuntu.com/questions/4474/enable-remote-vnc-from-the-commandline
    #!/bin/bash
    sudo apt install vino
    export DISPLAY=:0
    read -r -e -p "VNC Password: " -i"ubuntu" password
    dconf write /org/gnome/desktop/remote-access/enabled true
    dconf write /org/gnome/desktop/remote-access/prompt-enabled false
    dconf write /org/gnome/desktop/remote-access/authentication-methods "['vnc']"
    dconf write /org/gnome/desktop/remote-access/require-encryption false
    dconf write /org/gnome/desktop/remote-access/vnc-password \"\'"$(echo -n "$password" | base64)"\'\"
    dconf dump /org/gnome/desktop/remote-access/
    sudo service lightdm restart

    dconf write /org/gnome/desktop/screensaver/lock-enabled false
    dconf write /org/gnome/desktop/screensaver/ubuntu-lock-on-suspend false
    dconf write /org/gnome/desktop/session/idle-delay "uint32 0"
    ## install kodi

    # shortcut keys - How to change screenshot application to Flameshot on Ubuntu 18.04? - Ask Ubuntu
    # https://askubuntu.com/questions/1036473/how-to-change-screenshot-application-to-flameshot-on-ubuntu-18-04

    # If you need or want to replace the PrtScr shortcut do the following:
    # Release the PrtScr binding by this command
    gsettings set org.gnome.settings-daemon.plugins.media-keys screenshot '[]'
    # Go to Settings - - and scroll to the end. Press + and you will create custom shortcut. >Devices >Keyboard
    # Enter name: "flameshot", command: /usr/bin/flameshot gui
    # Set shortcut to PrtScr 'print'.
    # That is it. Next time you push PrtScr flameshot will be launched.
    # Ubuntu/Windows10文件快速预览 - 知乎
    # https://zhuanlan.zhihu.com/p/100041036
    sudo apt install gnome-sushi

    ## install vnc
    sudo apt install xserver-xorg-video-dummy

    cat >/usr/share/X11/xorg.conf.d/20-intel.conf <<EOF
Section "Device"
    Identifier  "Configured Video Device"
    Driver      "dummy"
EndSection

Section "Monitor"
    Identifier  "Configured Monitor"
    HorizSync 31.5-48.5
    VertRefresh 50-70
EndSection

Section "Screen"
    Identifier  "Default Screen"
    Monitor     "Configured Monitor"
    Device      "Configured Video Device"
    DefaultDepth 24
    SubSection "Display"
    Depth 24
    Modes "1400x1050"
    EndSubSection
EndSection
EOF

    # dconf write /org/gnome/desktop/screensaver/lock-enabled false
    # dconf write /org/gnome/desktop/screensaver/ubuntu-lock-on-suspend false

    # xfconf-query -c xfwm4 -p /general/use_compositing -s false
    # xfconf-query -c xfwm4 -p /general/vblank_mode -s off

    # 将主文件夹的文件夹中文名称改为英文
    # LANG=en_US xdg-user-dirs-gtk-update ## 点是
    # LANG=zh_CN.UTF-8 xdg-user-dirs-gtk-update  ## 点保留

    ## set mirror
    if [ -f /etc/apt/sources.list.d/official-package-repositories.list ]; then
        sudo sed -i 's#packages.linuxmint.com#mirrors.aliyun.com/linuxmint-packages#' /etc/apt/sources.list.d/official-package-repositories.list
        sudo sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/' /etc/apt/sources.list
        sudo sed -i 's/security.ubuntu.com/mirrors.aliyun.com/' /etc/apt/sources.list
        sudo apt update
        sudo apt upgrade
    fi

    sudo visudo -f /etc/sudoers.d/xia

    grep 'GRUB_RECORDFAIL_TIMEOUT' /etc/default/grub || echo 'GRUB_RECORDFAIL_TIMEOUT=3' | sudo tee -a /etc/default/grub
    sudo update-grub && grep -B3 "set timeout=" /boot/grub/grub.cfg

    sudo apt install -y x11vnc
    # xset dpms force on  ## 降低屏幕延迟
    cat <<EOF | sudo tee /etc/systemd/system/x11vnc.service
[Unit]
Description=Start x11vnc at startup.
After=multi-user.target display-manager.service

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -auth guess -forever -noxdamage -repeat -rfbauth /home/ops/.vnc/passwd -rfbport 5900 -display :0 -shared
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable x11vnc.service
    ## macos mount nfs
    # mount -o resvport 10.0.0.55:/nfsdata ttt
}
