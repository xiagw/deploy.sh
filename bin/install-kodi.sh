#!/usr/bin/env bash

export http_proxy='http://192.168.6.1:1080'
export https_proxy='http://192.168.6.1:1080'
export all_proxy='http://192.168.6.1:1080'
apt_opt='sudo -E apt'
## 本机安装  openssh-server
$apt_opt update
$apt_opt autoremove
$apt_opt install -y openssh-server

## 不升级 kernel
sudo -E apt-mark hold linux-image-generic linux-headers-generic

## 添加 kodi 仓库
$apt_opt install -y software-properties-common
sudo -E add-apt-repository -y ppa:team-xbmc/ppa
$apt_opt update
$apt_opt install -y kodi

$apt_opt install -y kodi-pvr-argustv
$apt_opt install -y kodi-pvr-demo
$apt_opt install -y kodi-pvr-dvblink
$apt_opt install -y kodi-pvr-dvbviewer
$apt_opt install -y kodi-pvr-filmon
$apt_opt install -y kodi-pvr-freebox
$apt_opt install -y kodi-pvr-hdhomerun
$apt_opt install -y kodi-pvr-hts
$apt_opt install -y kodi-pvr-iptvsimple
$apt_opt install -y kodi-pvr-mediaportal-tvserver
$apt_opt install -y kodi-pvr-mythtv
$apt_opt install -y kodi-pvr-nextpvr
$apt_opt install -y kodi-pvr-njoy
$apt_opt install -y kodi-pvr-octonet
$apt_opt install -y kodi-pvr-pctv
$apt_opt install -y kodi-pvr-plutotv
$apt_opt install -y kodi-pvr-sledovanitv-cz
$apt_opt install -y kodi-pvr-stalker
$apt_opt install -y kodi-pvr-teleboy
$apt_opt install -y kodi-pvr-tvheadend-hts
$apt_opt install -y kodi-pvr-vbox
$apt_opt install -y kodi-pvr-vdr-vnsi
$apt_opt install -y kodi-pvr-vuplus
$apt_opt install -y kodi-pvr-waipu
$apt_opt install -y kodi-pvr-wmc
$apt_opt install -y kodi-pvr-zattoo

$apt_opt install -y kodi-audioencoder-vorbis
$apt_opt install -y kodi-audioencoder-flac
$apt_opt install -y kodi-audioencoder-lame
$apt_opt install -y kodi-audioencoder-wav

$apt_opt install -y kodi-audiodecoder-modplug
$apt_opt install -y kodi-audiodecoder-nosefart
$apt_opt install -y kodi-audiodecoder-sidplay
$apt_opt install -y kodi-audiodecoder-snesapu
$apt_opt install -y kodi-audiodecoder-stsound
$apt_opt install -y kodi-audiodecoder-timidity
$apt_opt install -y kodi-audiodecoder-vgmstream

$apt_opt install -y kodi-visualization-goom
$apt_opt install -y kodi-visualization-projectm
$apt_opt install -y kodi-visualization-shadertoy
$apt_opt install -y kodi-visualization-spectrum
$apt_opt install -y kodi-visualization-waveform
$apt_opt install -y xbmc-visualization-fishbmc

## Ubuntu 默认仓库自带 git （非最新版）
$apt_opt install -y vim curl git

## fstab
# echo '/dev/mapper/vg0-lv0    /media/lvm     ext4     defaults       0      0' | sudo tee -a /etc/fstab

# https://askubuntu.com/questions/4474/enable-remote-vnc-from-the-commandline
#!/bin/bash
$apt_opt install -y vino
export DISPLAY=:0
# read -r -e -p "VNC Password: " -i"xia" password
dconf write /org/gnome/desktop/remote-access/enabled true
dconf write /org/gnome/desktop/remote-access/prompt-enabled false
dconf write /org/gnome/desktop/remote-access/authentication-methods "['vnc']"
dconf write /org/gnome/desktop/remote-access/require-encryption false
dconf write /org/gnome/desktop/remote-access/vnc-password \"\'"$(echo -n "xiamima" | base64)"\'\"
dconf dump /org/gnome/desktop/remote-access/
sudo -E service lightdm restart
dconf write /org/gnome/desktop/screensaver/lock-enabled false
dconf write /org/gnome/desktop/screensaver/ubuntu-lock-on-suspend false
dconf write /org/gnome/desktop/session/idle-delay "uint32 0"

# 本机安装  google chrome
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
$apt_opt install -y google-chrome-stable_current_amd64.deb
