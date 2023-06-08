#!/usr/bin/env bash

_msg() {
    echo "[$(date)], [RUN] $*"
}

_log() {
    echo "[$(date)], [RUN] $*" | tee -a "$me_log"
}

_start_java() {
    if [ "${USE_JEMALLOC:-false}" = true ]; then
        export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
        echo "USE_JEMALLOC: $USE_JEMALLOC"
        echo "LD_PRELOAD: $LD_PRELOAD"
    else
        unset LD_PRELOAD
    fi
    ## 修改内存占用值，
    [ -z "$JAVA_OPTS" ] && JAVA_OPTS='java -Xms256m -Xmx384m'
    # -XX:+UseG1GC

    ## 启动方式三，nohup 后台启动
    [[ "${start_nohup:-0}" -eq 1 ]] && JAVA_OPTS="nohup $JAVA_OPTS"

    ## 启动方式一， jar 内置配置(profile)文件 yml，
    ## Dockerfile ARG MVN_PROFILE=test （此处对应 git 分支名） 镜像内生成文件 profile.<分支名>
    for file in "$app_path"/profile.*; do
        [[ -f "$file" ]] || continue
        profile_name="--spring.profiles.active=${file##*.}"
        _msg "Found $profile_name, start with profile..."
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
            ## 启动方式一， jar 内置配置(profile)文件 yml，
            $JAVA_OPTS -jar "$jar" "$profile_name" &>>"$me_log" &
        elif [ "$config_yml" ]; then
            ## 启动方式二，配置文件 yml 在 jar 包外，非内置
            $JAVA_OPTS "$config_yml" -jar "$jar" &>>"$me_log" &
        else
            ##
            $JAVA_OPTS -jar "$jar" &>>"$me_log" &
        fi
        pids="$pids $!"
    done
}

_start_php() {
    local php_count=0
    for i in /usr/sbin/php-fpm*; do
        [ -f "$i" ] && php_count=$((php_count + 1))
    done
    [[ "$php_count" -eq 0 ]] && return
    ## index for default site

    [ -d /var/lib/php/sessions ] && chmod -R 777 /var/lib/php/sessions
    [ -d /run/php ] || mkdir -p /run/php
    [ -d $html_path ] || mkdir $html_path
    [ -f $html_path/index.html ] || date >>$html_path/index.html

    ## create runtime for ThinkPHP
    while [ -d $html_path ]; do
        for dir in $html_path/ $html_path/tp/ "$html_path"/tp/*/; do
            [ -d "$dir" ] || continue
            need_runtime=0
            ## ThinkPHP 5.1
            [[ -f "${dir}"think && -d ${dir}thinkphp && -d ${dir}application ]] && need_runtime=1
            ## ThinkPHP 6.0
            [[ -f "${dir}"think && -d ${dir}thinkphp && -d ${dir}app ]] && need_runtime=1
            if [[ "$need_runtime" -eq 1 ]]; then
                run_dir="${dir}runtime"
                [[ -d "$run_dir" ]] || mkdir "$run_dir"
                dir_owner="$(stat -t -c %U "$run_dir")"
                [[ "$dir_owner" == www-data ]] || chown -R www-data:www-data "$run_dir"
            fi
        done
        sleep 600
    done &

    ## remove runtime log files
    while [ -d $html_path ]; do
        for dir in $html_path/ $html_path/tp/ "$html_path"/tp/*/; do
            [ -d "$dir" ] || continue
            find "${dir}runtime" -type f -iname '*.log' -ctime +5 -print0 | xargs -t --null rm -f
        done
        sleep 86400
    done >/dev/null 2>&1 &

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
    pids="$pids $!"
}

_kill() {
    _msg "receive SIGTERM, kill $pids"
    for pid in $pids; do
        kill "$pid"
        wait "$pid"
    done
}

_check_jemalloc() {
    sleep 40
    for pid in $pids; do
        if grep -q jemalloc "/proc/$pid/smaps"; then
            _msg "PID $pid using jemalloc..."
        else
            _msg "PID $pid not use jemalloc"
        fi
    done
}

_schedule_upgrade() {
    local file_local=upgrade_auto
    if [[ -f "$html_path/$file_local" || -f $app_path/$file_local ]]; then
        :
    else
        return 0
    fi

    file_remote=upgrade_check.txt
    touch /tmp/$file_remote
    curl -fsSLo "/tmp/$file_remote" "${app_upgrade_url:-http://cdn.flyh6.com/docker}/$file_remote" 2>/dev/null
    app_id_remote=$(awk -F= '/^app_id=/ {print $2}' "/tmp/$file_remote")
    app_ver_remote=$(awk -F= '/^app_ver=/ {print $2}' "/tmp/$file_remote")

    # shellcheck source=/dev/null
    source "$html_path/$file_local"
    if [[ "${app_id:-1}" == "$app_id_remote" && "${app_ver:-1}" == "$app_ver_remote" ]]; then
        return 0
    fi
    while read -r line; do
        curl -fsSLo /tmp/"${line}" "${app_upgrade_url%/}/$line"
        curl -fsSLo /tmp/"${line}".sha256 "${app_upgrade_url%/}/${line}.sha256"
        if cd /tmp && sha256sum -c "${line}".sha256; then
            _msg "decompress $line."
            tar -C "$html_path/" -zxf /tmp/"${line}" && rm -f /tmp/"${line}"*
        fi
    done < <(awk -F= '/^app_zip=/ {print $2}' "/tmp/$file_remote")
    _msg "set app_ver=$app_ver_remote to $html_path/$file_local"
    sed -i "/^app_ver=/s/=.*/=$app_ver_remote/" "$html_path/$file_local"
    rm -f /tmp/${file_remote}*
}

_set_jemalloc() {
    case "$LARADOCK_PHP_VERSION" in
    8.*)
        _msg "disable jemalloc."
        ;;
    *)
        _msg "enable jemalloc..."
        if [ -f /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 ]; then
            export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
        fi
        # 1. lsof -Pn -p $(pidof mariadbd) | grep jemalloc，配置正确的话会有jemalloc.so的输出；
        # 2. cat /proc/$(pidof mariadbd)/smaps | grep jemalloc，和上述命令有类似的输出。
        ;;
    esac
}

main() {
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="${me_path}/${me_name}.log"

    app_path="/app"
    if [ -w "$app_path" ]; then
        me_log="$app_path/${me_name}.log"
    elif [ -w "$me_path" ]; then
        me_log="${me_path}/${me_name}.log"
    else
        me_log="/tmp/${me_name}.log"
    fi
    [ -d "$app_path"/log ] || mkdir -p "$app_path"/log

    html_path=/var/www/html

    _set_jemalloc

    if [ -f /opt/run.init.sh ]; then
        bash /opt/run.init.sh
    fi

    ## 适用于 nohup 独立启动
    if [[ "$1" == nohup || -f "$app_path"/.run.nohup ]]; then
        start_nohup=1
    fi

    _msg "Startup $me_path/$me_name ..." >>"$me_log"
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

    _check_jemalloc &

    ## 适用于 docker 中启动
    if [[ "${start_nohup:-0}" -eq 0 ]]; then
        ## method 1: allow debug / use tail -f，方便开发者调试，可以直接 kill java, 不会停止容器
        # exec tail -f "$app_path"/log/*.log
        ## method 2: use wait, kill java, stop container
        exec tail -f "$me_log" &
        wait
    fi
}

main "$@"
