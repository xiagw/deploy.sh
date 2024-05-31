#!/usr/bin/env bash

## 需要root权限的初始化程序
[ -f /opt/init.sh ] && bash /opt/init.sh
[ -f /app/init.sh ] && bash /app/init.sh

## 需要普通账号启动的程序
if id spring; then
    su -l spring -c "export LANG=C.UTF-8; bash /opt/run.sh"
elif id node; then
    su -l node -c "export LANG=C.UTF-8; bash /opt/run.sh"
else
    bash /opt/run.sh
fi
