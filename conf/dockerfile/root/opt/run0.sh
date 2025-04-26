#!/usr/bin/env bash
# 容器启动脚本：处理初始化和服务启动

# 初始化变量
declare -a pids=()

cleanup() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 接收到终止信号，正在停止进程: ${pids[*]}"
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            wait "$pid"
        fi
    done
}

trap cleanup HUP INT PIPE QUIT TERM

## 需要root权限的初始化程序
for i in /opt/init.sh /app/init.sh; do
    if [ -f "$i" ] ; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 执行初始化脚本: $i"
        bash "$i" || echo "警告: $i 执行失败，返回码: $?"
    fi
done

## 非 root 账号启动的程序
run_normal_user=false
for u in spring node; do
    if id "$u" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 使用普通用户 [$u] 启动服务"
        chown -R 1000:1000 /opt
        su "$u" -c "bash /opt/run1.sh" &
        pids+=("$!")
        run_normal_user=true
        break
    fi
done

if [ "$run_normal_user" = false ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 未找到普通用户，使用当前用户启动服务"
    bash /opt/run1.sh &
    pids+=("$!")
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - 所有服务已启动，进程ID: ${pids[*]}"
wait
