#!/usr/bin/env bash

## 需要root权限的初始化程序
if [ -f /opt/init.sh ]; then
    echo "Found /opt/init.sh..."
    bash /opt/init.sh
fi
if [ -f /app/init.sh ]; then
    echo "Found /app/init.sh..."
    bash /app/init.sh
fi

## 非 root 账号启动的程序
if id spring 2>/dev/null; then
    echo "Found normal user [spring]..."
    su spring -c "bash /opt/run.sh"
elif id node 2>/dev/null; then
    echo "Found normal user [node]..."
    su node -c "bash /opt/run.sh"
else
    bash /opt/run.sh
fi
