#!/bin/bash
# shellcheck disable=SC2207
set -xe

build_base_image() {
    local ver="$1" reg cmd cmd_opt
    local reg='registry.cn-hangzhou.aliyuncs.com/flyh5/flyh5'

    case "$ver" in
    5.6 | 7.1 | 7.3 | 7.4 | 8.1 | 8.2 | 8.3 | 8.4)
        cmd_opt+=(
            --build-arg PHP_VERSION="$ver"
            -f Dockerfile.base.php
            --tag "$reg":laradock-php-fpm-"$ver"
        )
        ;;
    redis)
        cmd_opt+=(
            -f Dockerfile."$ver"
            --tag "$reg":laradock-"$ver"
        )
        ;;
    nginx)
        cmd_opt+=(
            -f Dockerfile."$ver"
            --tag "$reg":"$ver"-alpine-base
        )
        ;;
    mysql-5.6 | mysql-5.7 | mysql-8.0 | mysql-8.4)
        cmd_opt+=(
            --build-arg MYSQL_VERSION="${ver#*-}"
            -f Dockerfile.mysql
            --tag "$reg":laradock-"$ver"
        )
        ;;
    spring-8 | spring-17 | spring-21)
        cmd_opt+=(
            --build-arg JDK_VERSION="${ver#*-}"
            -f Dockerfile.base.java
            --tag "$reg":laradock-"$ver"
        )
        ;;
    nodejs-18 | nodejs-20 | nodejs-21 | nodejs-22)
        cmd_opt+=(
            --build-arg NODE_VERSION="${ver#*-}"
            -f Dockerfile.base.node
            --tag "$reg":laradock-"$ver"
        )
        ;;
    esac

    # https://docs.docker.com/build/building/multi-platform/#build-multi-platform-images
    if ! ls /proc/sys/fs/binfmt_misc/qemu-aarch64; then
        $cmd run --privileged --rm tonistiigi/binfmt --install all
    fi

    # echo "${cmd_opt[@]} $me_path/"
    "${cmd_opt[@]}" "$me_path/"
}

cmd_arg="${*}"
all_args=(5.6 7.1 7.3 7.4 8.1 8.2 8.3 8.4 mysql-5.6 mysql-5.7 mysql-8.0 mysql-8.4 spring-8 spring-17 spring-21 spring-23 nodejs-18 nodejs-20 nodejs-21 redis nginx)

me_path="$(dirname "$(readlink -f "$0")")"
cmd="$(command -v docker || command -v podman)"
cmd_opt=(
    "$cmd"
    build
    --pull
    --push
    --progress=plain
    --platform "linux/amd64,linux/arm64"
    --build-arg CHANGE_SOURCE=true
    --build-arg IN_CHINA=true
    --build-arg HTTP_PROXY="${http_proxy-}"
    --build-arg HTTPS_PROXY="${http_proxy-}"
)

case "$cmd_arg" in
all)
    for i in "${all_args[@]}"; do
        build_base_image "$i"
    done
    ;;
*)
    if [ -z "$cmd_arg" ]; then
        select_arg=$(echo "${all_args[@]}" | sed 's/\ /\n/g' | fzf)
    else
        select_arg="$*"
    fi
    build_base_image "$select_arg"
    ;;
esac
