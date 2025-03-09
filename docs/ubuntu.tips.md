# Ubuntu 使用技巧

## 系统配置

### GRUB 配置
```bash
# 在 /etc/default/grub 中设置:
GRUB_RECORDFAIL_TIMEOUT=10
GRUB_TIMEOUT_STYLE=menu
```

### 显卡合成器
```bash
# 开关显卡合成
xfconf-query -c xfwm4 -p /general/use_compositing -s false  # 关闭
xfconf-query -c xfwm4 -p /general/use_compositing -s true   # 开启
```

## 远程访问

### x11vnc 服务配置

#### 登录界面 VNC 服务
```ini
# /lib/systemd/system/x11vnc-login.service
[Unit]
Description=Start x11vnc at startup.
After=multi-user.target

[Service]
Type=simple
User=gdm
ExecStart=/usr/bin/x11vnc -auth /run/user/126/gdm/Xauthority -forever -loop -repeat -rfbauth /home/gdm/.vnc/passwd -rfbport 5902 -shared -display :0

[Install]
WantedBy=multi-user.target
```

#### 用户桌面 VNC 服务
```ini
# /lib/systemd/system/x11vnc.service
[Unit]
Description=Start x11vnc at startup.
After=multi-user.target

[Service]
Type=simple
User=WHO
ExecStart=/usr/bin/x11vnc -auth /run/user/1XXX/gdm/Xauthority -forever -loop -noxdamage -repeat -rfbauth /home/WHO/.vnc/passwd -rfbport 5900 -shared -xkb -display :1

[Install]
WantedBy=multi-user.target
```

启用服务：
```bash
sudo systemctl enable x11vnc-login
sudo systemctl enable x11vnc
sudo systemctl start x11vnc-login
sudo systemctl start x11vnc
```

## 软件安装

### GitHub CLI
```bash
type -p curl >/dev/null || sudo apt install curl -y
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
&& sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
&& sudo apt update \
&& sudo apt install gh -y
```

## 虚拟化

### virt-install 示例
```bash
virt-install \
--name centos7 \
--ram 4096 \
--disk path=ubuntu16.img,size=30 \
--vcpus 4 \
--os-type linux \
--os-variant ubuntu16.04 \
--network bridge=br0 \
--graphics none \
--console pty,target_type=serial \
--location ubuntu-16.04.7-server-amd64.iso \
--extra-args 'console=ttyS0,115200n8 serial' \
--host-device 3b:00.0 \
--features kvm_hidden=on \
--machine q35
```

## 其他工具

1. x11vnc on Ubuntu 22.04 desktop seems broken - Ask Ubuntu https://askubuntu.com/questions/1412009/x11vnc-on-ubuntu-22-04-desktop-seems-broken
1. bash - Shell script common template - Stack Overflow https://stackoverflow.com/questions/14008125/shell-script-common-template
1. 写出安全 bash script 的简洁模板 – Evil-EXEC https://evex.one/posts/linux/safe-bash-script/
1. How to get rid of the 3 second delay ? · Issue #102 · LibVNC/x11vnc https://github.com/LibVNC/x11vnc/issues/102
1. Flameshot 截图命名格式：`flameshot.%Y%m%d.%H%M%S`
1. PiKVM：基于树莓派的开源 IP-KVM 解决方案 (https://pikvm.org/) (https://github.com/pikvm/pikvm)
1. Gitmoji：Git commit 表情指南 (https://gitmoji.dev/)
1. networking - x11vnc Headless on Ubuntu is very slow until monitor connected - Ask Ubuntu https://askubuntu.com/questions/950252/x11vnc-headless-on-ubuntu-is-very-slow-until-monitor-connected
1. PXE Boot & Install Windows 10 from a Samba Share (https://docs.j7k6.org/windows-10-pxe-installation/)