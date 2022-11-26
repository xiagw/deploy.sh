#!/usr/bin/env bash

_start_jar() {
    ## 修改内存占用值，
    if [ -z "$JAVA_OPTS" ]; then
        JAVA_OPTS='java -Xms256m -Xmx384m'
    fi
    ## 自动探测环境变量，默认值 profile.test，(Dockerfile ARG MVN_PROFILE=test)
    ## Dockerfile 内生成文件 profile.test, profile.main 等分支名结尾
    for f in "$me_path"/profile.*; do
        if [[ -f "$f" ]]; then
            echo "found $f"
            profile_name="--spring.profiles.active=${f##*.}"
            break
        fi
    done
    cj=0
    for jar in "$me_path"/*.jar; do
        [[ -f "$jar" ]] || continue
        cj=$((cj + 1))
        cy=0
        ## !!!! 注意 !!!!,
        ## 自动探测 yml 配置文件, 按文件名自动排序对应 a.jar--a.yml, b.jar--b.yml
        for y in "$me_path"/*.yml; do
            [[ -f "$y" ]] || continue
            cy=$((cy + 1))
            [[ "$cj" -eq "$cy" ]] && config_yml="-Dspring.config.location=${y}"
        done
        echo "${cj}. start $jar ..."
        if [ -z "$profile_name" ]; then
            $JAVA_OPTS -jar "$jar" $profile_name &
        else
            $JAVA_OPTS $config_yml -jar "$jar" &
        fi
        pids="$pids $!"
    done
    ## allow debug / 方便开发者调试，可以直接kill java, 不会停止容器
    tail -f "$me_log" "$me_path"/log/*.log &
    pids="$pids $!"
}

_start_php() {
    ## 容器内代替 cronta
    [ -f /var/www/schedule.sh ] && bash /var/www/schedule.sh &
    [ -f "$me_path"/schedule.sh ] && bash "$me_path"/schedule.sh &
    if [ -f easyswoole ]; then
        exec php easyswoole server start -mode=config
    elif command -v php-fpm >/dev/null 2>&1; then
        exec php-fpm -F
    else
        echo "Give up php."
    fi
}

_kill() {
    echo "[INFO] Receive SIGTERM"
    for pid in $pids; do
        kill "$pid"
        wait "$pid"
    done
}

main() {
    me_path="$(dirname "$(readlink -f "$0")")"
    me_name="$(basename "$0")"
    me_log="${me_path}/${me_name}.log"
    date >>"$me_log"
    [ -d "$me_path"/log ] || mkdir "$me_path"/log
    ## 识别中断信号，停止 java 进程
    trap _kill HUP INT QUIT TERM
    ## start php
    _start_php
    ## 启动 java
    _start_jar
    ## 适用于 docker 中启动
    wait
}

main "$@"
