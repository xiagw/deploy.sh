#!/usr/bin/env bash

_start_java() {
    ## 修改内存占用值，
    [ -z "$JAVA_OPTS" ] && JAVA_OPTS='java -Xms256m -Xmx384m'
    [[ "$1" == nohup || -f "$app_path"/.run.nohup ]] && JAVA_OPTS="nohup $JAVA_OPTS"
    ## 启动方式一， jar 内置配置文件 yml，
    ## Dockerfile ARG MVN_PROFILE=test （此处对应 git 分支名） 镜像内生成文件 profile.<分支名>
    for f in "$app_path"/profile.*; do
        [[ -f "$f" ]] || continue
        profile_name="--spring.profiles.active=${f##*.}"
        break
    done
    for jar in "$app_path"/*.jar; do
        [[ -f "$jar" ]] || continue
        cj=$((${cj:-0} + 1))
        ## 启动方式二，配置文件 yml 在 jar 包外，非内置
        ## !!!! 注意 !!!!, 自动探测 yml 配置文件, 按文件名自动排序对应 a.jar--a.yml, b.jar--b.yml
        for y in "$app_path"/*.yml; do
            [[ -f "$y" ]] || continue
            cy=$((${cy:-0} + 1))
            [[ "$cj" -eq "$cy" ]] && config_yml="-Dspring.config.location=${y}"
        done
        echo "${cj}. start $jar ..."
        if [ -n "$profile_name" ]; then
            $JAVA_OPTS -jar "$jar" "$profile_name" &>>"$app_log" &
        elif [ -n "$config_yml" ]; then
            $JAVA_OPTS "$config_yml" -jar "$jar" &>>"$app_log" &
        else
            $JAVA_OPTS -jar "$jar" &>>"$app_log" &
        fi
        pids="$pids $!"
    done
}

_start_php() {
    ## 容器内代替 crontab
    [ -f /var/www/schedule.sh ] && bash /var/www/schedule.sh &
    [ -f "$app_path"/schedule.sh ] && bash "$app_path"/schedule.sh &
    if [ -f easyswoole ]; then
        ## 前台启动需配置到 config 文件内
        exec php easyswoole server start -mode=config
        pids="${pids} $!"
    elif command -v php-fpm >/dev/null 2>&1; then
        ## 前台启动
        # exec php-fpm -F
        ## 后台启动 background
        exec php-fpm
        pids="${pids} $!"
    else
        echo "Not found php."
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
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="${me_path}/${me_name}.log"
    if [ -d /app ]; then
        app_path=/app
    else
        app_path=${me_path}
    fi
    app_log=$app_path/${me_name}.log
    [ -d "$app_path"/log ] || mkdir "$app_path"/log
    echo "$(date), startup ..." | tee -a "$app_log"
    ## 识别中断信号，停止 java 进程
    trap _kill HUP INT QUIT TERM
    ## 统一兼容启动 start php
    _start_php
    ## 统一兼容启动 start java
    _start_java "$@"
    ## allow debug / 方便开发者调试，可以直接 kill java, 不会停止容器
    # tail -f "$me_log" "$app_path"/log/*.log
    tail -f "$me_log" "$app_path"/log/*.log &
    ## 适用于 docker 中启动
    if [[ -z "$1" || ! -f "$app_path"/.run.nohup ]]; then
        wait
    fi
}

main "$@"
