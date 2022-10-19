#!/usr/bin/env bash

me_path="$(dirname "$(readlink -f "$0")")"
## 修改内存占用值，
if [ -z "$JAVA_OPTS" ]; then
    JAVA_OPTS='java -Xms256m -Xmx384m'
fi
## 设置启动调用参数或配置文件
profile_name=
## 自动探测环境变量，默认值 profile.test，(Dockerfile.maven ARG MVN_PROFILE=test)
for f in "$me_path"/profile.*; do
    if [[ -f "$f" ]]; then
        echo "found $f"
        profile_name="--spring.profiles.active=${f##*.}"
        break
    fi
done
## 自动探测 yml 配置文件，覆盖上面的 profile.*
for y in "$me_path"/application*.yml; do
    if [[ -f "$y" ]]; then
        echo "Found $y, rewrite profile_name"
        profile_name="-Dspring.config.additional-location=${y##*/}"
        break
    fi
done

[ -d /app/log ] || mkdir /app/log
date >>/app/log/run.log

_start() {
    ## start *.jar / 启动所有 jar 包
    for jar in "$me_path"/*.jar; do
        [[ -f "$jar" ]] || continue
        echo "[INFO] start $jar ..."
        $JAVA_OPTS -jar "$jar" $profile_name &
        pids="$pids $!"
    done
    ## allow debug / 方便开发者调试，可以直接kill java, 不会停止容器
    tail -f /app/log/*.log &
    pids="$pids $!"
}

_kill() {
    echo "[INFO] Receive SIGTERM"
    for pid in $pids; do
        kill "$pid"
        wait "$pid"
    done
}

trap _kill HUP INT QUIT TERM

_start

wait
