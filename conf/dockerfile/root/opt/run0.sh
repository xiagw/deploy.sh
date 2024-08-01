#!/usr/bin/env bash

## 需要root权限的初始化程序
for i in /opt/init.sh /app/init.sh; do
    if [ -f $i ]; then
        echo "Found $i ..."
        bash $i
    fi
done

## 非 root 账号启动的程序
for u in spring node; do
    if id $u 2>/dev/null; then
        echo "Found normal user [$u]..."
        su $u -c "bash /opt/run.sh"
        run_once=true
    fi
done

if [ "${run_once:-false}" = false ]; then
    bash /opt/run.sh
fi
