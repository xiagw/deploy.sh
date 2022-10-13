1. flameshot.%Y%m%d.%H%M%S
1. grub 
As such your /etc/default/grub should contain:

GRUB_RECORDFAIL_TIMEOUT=10
GRUB_TIMEOUT_STYLE=menu


type -p curl >/dev/null || sudo apt install curl -y
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
&& sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
&& sudo apt update \
&& sudo apt install gh -y


x11vnc on Ubuntu 22.04 desktop seems broken - Ask Ubuntu
https://askubuntu.com/questions/1412009/x11vnc-on-ubuntu-22-04-desktop-seems-broken

$ cat /lib/systemd/system/x11vnc-login.service 
[Unit]
Description=Start x11vnc at startup.
After=multi-user.target

[Service]
Type=simple
User=gdm    <<=== Ubuntu 21.04 need process DISPLAY owner id
ExecStart=/usr/bin/x11vnc -auth /run/user/126/gdm/Xauthority -forever -loop -repeat -rfbauth /home/gdm/.vnc/passwd -rfbport 5902 -shared -display :0
[Install]
WantedBy=multi-user.target

$ cat /lib/systemd/system/x11vnc.service 
[Unit]
Description=Start x11vnc at startup.
After=multi-user.target

[Service]
Type=simple
User=WHO  <<=== Now the session user
ExecStart=ExecStart=/usr/bin/x11vnc -auth /run/user/1XXX/gdm/Xauthority -forever -loop -noxdamage -repeat -rfbauth /home/WHO/.vnc/passwd -rfbport 5900 -shared -xkb -display :1
#
# Or if you have a problem with keys not working you might
#   need to add: -skip_keycodes CODE,CODE... flag
#   See below for more details
#
[Install]
WantedBy=multi-user.target

# sudo systemctl enable x11vnc-login
# sudo systemctl enable x11vnc
# sudo systemctl start x11vnc-login
# sudo systemctl start x11vnc