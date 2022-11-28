#!/usr/bin/env bash

_start_jar() {
    ## 修改内存占用值，
    if [ -z "$1" ]; then
        JAVA_OPTS='java -Xms256m -Xmx512m'
    else
        JAVA_OPTS='nohup java -Xms256m -Xmx512m'
    fi
    ## 启动方式一， jar 内置配置文件 yml，
    ## Dockerfile ARG MVN_PROFILE=test （此处对应 git 分支名）
    ## Dockerfile 镜像内生成文件 profile.<分支名>
    for f in "$me_path"/profile.*; do
        [[ -f "$f" ]] || continue
        echo "found $f"
        profile_name="--spring.profiles.active=${f##*.}"
        break
    done
    cj=0
    for jar in "$me_path"/*.jar; do
        [[ -f "$jar" ]] || continue
        cj=$((cj + 1))
        cy=0
        ## 启动方式二，配置文件 yml 在 jar 包外，非内置
        ## !!!! 注意 !!!!,
        ## 自动探测 yml 配置文件, 按文件名自动排序对应 a.jar--a.yml, b.jar--b.yml
        for y in "$me_path"/*.yml; do
            [[ -f "$y" ]] || continue
            cy=$((cy + 1))
            [[ "$cj" -eq "$cy" ]] && config_yml="-Dspring.config.location=${y}"
        done
        if [ -n "$profile_name" ]; then
            echo "${cj}. start $jar with $profile_name ..."
            $JAVA_OPTS -jar "$jar" $profile_name &>>"$me_log" &
        else
            echo "${cj}. start $jar with $config_yml ..."
            $JAVA_OPTS $config_yml -jar "$jar" &>>"$me_log" &
        fi
        pids="${pids} $!"
    done
}

_start_php() {
    ## 容器内代替 crontab
    [ -f /var/www/schedule.sh ] && bash /var/www/schedule.sh &
    [ -f "$me_path"/schedule.sh ] && bash "$me_path"/schedule.sh &
    if [ -f easyswoole ]; then
        ## 前台启动需配置到 config 文件内
        exec php easyswoole server start -mode=config
        pids="${pids} $!"
    elif command -v php-fpm >/dev/null 2>&1; then
        ## 前台启动
        # exec php-fpm -F
        ## 后台启动 background
        exec php-fpm
    else
        echo "Give up php."
    fi
}

_kill() {
    echo "[INFO] Receive SIGTERM, kill $pids"
    for pid in $pids; do
        kill "$pid"
        wait "$pid"
    done
}

main() {
    me_path="$(dirname "$(readlink -f "$0")")"
    me_name="$(basename "$0")"
    me_log="${me_path}/${me_name}.log"
    echo "$(date), start..." | tee -a "$me_log"
    [ -d "$me_path"/log ] || mkdir "$me_path"/log
    ## 识别中断信号，停止 java 进程
    trap _kill HUP INT QUIT TERM
    ## 统一兼容启动 start php
    _start_php
    ## 统一兼容启动 start java
    _start_jar $1
    ## allow debug / 方便开发者调试，可以直接 kill java, 不会停止容器
    tail -f "$me_log" "$me_path"/log/*.log &
    ## 适用于 docker 中启动
    if [[ -z "$1" ]]; then
        wait
    fi
}

main "$@"
