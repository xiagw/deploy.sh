#!/usr/bin/env bash

## 需要root权限的初始化程序
[ -f /opt/init.sh ] && bash /opt/init.sh
[ -f /app/init.sh ] && bash /app/init.sh
for i in /opt/*.jar; do
    [[ -f "$i" ]] || continue
    mv -vf "$i" /app/
done
# (
#     echo '127.0.0.1    redis'
#     echo '127.0.0.1    mysql'
# )>>/etc/hosts

## 需要普通账号启动的程序
if id spring; then
    su spring -c "bash /opt/run.sh"
elif id node; then
    su node -c "bash /opt/run.sh"
else
    bash /opt/run.sh
fi
