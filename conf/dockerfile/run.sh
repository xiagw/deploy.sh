#!/usr/bin/env bash

_msg() {
    echo "[$(date)], $*"
}

_log() {
    echo "[$(date)], $*" | tee -a "$app_log"
}

_start_java() {
    ## 修改内存占用值，
    [ -z "$JAVA_OPTS" ] && JAVA_OPTS='java -Xms256m -Xmx384m'
    ## 启动方式三，nohup 后台启动
    [[ "${start_nohup:-0}" -eq 1 ]] && JAVA_OPTS="nohup $JAVA_OPTS"
    ## 启动方式一， jar 内置配置文件 yml，
    ## Dockerfile ARG MVN_PROFILE=test （此处对应 git 分支名） 镜像内生成文件 profile.<分支名>
    for f in "$app_path"/profile.*; do
        [[ -f "$f" ]] || continue
        profile_name="--spring.profiles.active=${f##*.}"
        _msg "try using $profile_name"
        break
    done

    for jar in "$app_path"/*.jar; do
        [[ -f "$jar" ]] || continue
        cj=$((${cj:-0} + 1))
        ## 启动方式二，配置文件 yml 在 jar 包外，非内置
        ## !!!! 注意 !!!!, 自动探测 yml 配置文件, 按文件名自动排序对应 axxx.jar--axxx.yml, bxxx.jar--bxxx.yml
        cy=0
        config_yml=
        for y in "$app_path"/*.yml "$app_path"/*.yaml; do
            [[ -f "$y" ]] || continue
            cy=$((cy + 1))
            if [[ "$cj" -eq "$cy" ]]; then
                config_yml="-Dspring.config.location=${y}"
                break
            fi
        done
        _msg "${cj}. start $jar $config_yml ..."
        if [ "$profile_name" ]; then
            $JAVA_OPTS -jar "$jar" "$profile_name" &>>"$app_log" &
        elif [ "$config_yml" ]; then
            $JAVA_OPTS "$config_yml" -jar "$jar" &>>"$app_log" &
        else
            $JAVA_OPTS -jar "$jar" &>>"$app_log" &
        fi
        pids="$pids $!"
    done
}

_start_php() {
    ## start php-fpm*
    for i in /usr/sbin/php-fpm*; do
        [ -x "$i" ] && exec $i ## php-fpm -F, 前台启动
    done
    if command -v nginx && nginx -t; then
        exec nginx -g "daemon off;" &
        pids="${pids} $!"
    elif command -v apachectl && apachectl -t; then
        exec apachectl -k start -D FOREGROUND &
        pids="${pids} $!"
    else
        _msg "Not found php."
    fi
}

_kill() {
    _msg "[WARN] Receive SIGTERM, kill $pids"
    for pid in $pids; do
        kill "$pid"
        wait "$pid"
    done
}

_schedule_upgrade() {
    file_up="$app_path/.up"
    ## project_id=1 ; project_ver=hash; project_upgrade_url=http://update.xxx.com
    [ -f "$file_up" ] || return 0
    source "$file_up"
    file_temp=/tmp/u.html
    curl -fsSLo "$file_temp" "${project_upgrade_url:-localhost}" 2>/dev/null
    remote_id=$(awk -F= '/^project_id=/ {print $2}' "$file_temp")
    remote_ver=$(awk -F= '/^project_ver=/ {print $2}' "$file_temp")
    file_update=spring.tgz
    if [[ "${project_id:-1}" == "$remote_id" && "${project_ver:-1}" != "$remote_ver" ]]; then
        curl -fsSLo /tmp/${file_update} "${project_upgrade_url%/}/$file_update"
        curl -fsSLo /tmp/${file_update}.sha "${project_upgrade_url%/}/${file_update}.sha"
        if (cd /tmp && sha256sum -c $file_update.sha) &>/dev/null; then
            tar -C "$app_path" -zxf /tmp/$file_update
            _kill
            _start_java
            sed -i "/^project_ver=/s/=.*/=$remote_ver/" "$file_up"
            rm -f /tmp/${file_update}*
        fi
    fi
}

main() {
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="${me_path}/${me_name}.log"
    app_path="/app"
    if [ -w "$app_path" ]; then
        app_log="$app_path/${me_name}.log"
    else
        app_log="/tmp/${me_name}.log"
    fi

    ## 适用于 nohup 独立启动
    if [[ "$1" == nohup || -f "$app_path"/.run.nohup ]]; then
        start_nohup=1
    fi
    [ -d "$app_path"/log ] || mkdir "$app_path"/log
    _msg "startup ..." | tee -a "$app_log"
    ## 识别中断信号，停止 java 进程
    trap _kill HUP INT QUIT TERM
    ## 统一兼容启动 start php
    _start_php "$@"
    ## 统一兼容启动 start java
    _start_java "$@"

    while true; do
        _schedule_upgrade
        sleep 60
    done &

    ## 适用于 docker 中启动
    if [[ "${start_nohup:-0}" -eq 0 ]]; then
        ## method 1: allow debug / use tail -f，方便开发者调试，可以直接 kill java, 不会停止容器
        # exec tail -f "$me_log" "$app_path"/log/*.log
        ## method 2: use wait, kill java, stop container
        exec tail -f "$me_log" "$app_log" "$app_path"/log/*.log &
        wait
    fi
}

main "$@"
