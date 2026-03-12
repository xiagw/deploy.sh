#!/usr/bin/env bash
# 容器入口脚本：执行 init_root/init 后，以普通用户（spring/node）或当前用户启动 run1.sh；处理信号与进程回收。
# 由 Dockerfile CMD 调用，例如：CMD ["bash", "/opt/run0.sh"]
#
# 终止信号传递（docker stop -> 业务进程优雅退出）：
#   docker stop 发 SIGTERM 给 PID1(run0) -> run0 先向 run1 发 SIGTERM（读 /opt/run1.pid）
#   -> run1 的 trap 向 G_PIDS(Java/PHP/Node 等) 发 SIGTERM -> run0 再 kill/wait 自身记录的 pids(su 或 run1)

# 初始化变量
declare -a pids=()

# 函数：日志记录
log() {
    echo "[$(date +%Y%m%d_%u_%T.%3N)] [RUN0] $*"
}

# docker stop 发 SIGTERM 给 PID1(run0)。若用 su 启动 run1，kill(su) 不会把信号传给 run1，
# 故先向 run1 发 SIGTERM（通过 /opt/run1.pid），再由 run1 的 trap 向业务进程发 SIGTERM，最后 wait 子进程。
cleanup() {
    log "接收到终止信号，正在停止进程: ${pids[*]}"
    if [ -f /opt/run1.pid ]; then
        run1_pid=$(cat /opt/run1.pid 2>/dev/null)
        if [ -n "$run1_pid" ] && kill -0 "$run1_pid" 2>/dev/null; then
            log "向 run1 (PID $run1_pid) 发送 SIGTERM，由其向业务进程传递"
            kill -TERM "$run1_pid" 2>/dev/null || true
        fi
        rm -f /opt/run1.pid 2>/dev/null || true
    fi
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
}

trap cleanup HUP INT PIPE QUIT TERM

## 需要root权限的初始化程序
for i in /opt/init_root.sh /app/init_root.sh; do
    if [ -f "$i" ]; then
        log "执行初始化脚本: $i"
        bash "$i" || echo "警告: $i 执行失败，返回码: $?"
    fi
done

## 非 root 账号启动的程序
run_normal_user=false
for u in spring node; do
    if id "$u" &>/dev/null; then
        log "使用普通用户 [$u] 启动服务"
        chown -R 1000:1000 /opt
        su "$u" -c "bash /opt/run1.sh" &
        pids+=("$!")
        run_normal_user=true
        break
    fi
done

## 找不到普通账号，退回 root 启动
if [ "$run_normal_user" = false ]; then
    log "未找到普通用户，使用当前用户启动服务"
    bash /opt/run1.sh &
    pids+=("$!")
fi

log "所有服务已启动，进程ID: ${pids[*]}"

wait
