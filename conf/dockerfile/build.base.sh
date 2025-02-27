#!/bin/bash
# shellcheck disable=SC2207
set -xe

_build() {
    local v="$1"
    local reg=registry.cn-hangzhou.aliyuncs.com/flyh5/flyh5
    case "$v" in
    5.6 | 7.1 | 7.3 | 7.4 | 8.1 | 8.2 | 8.3 | 8.4)
        cmd_opt+=(
            -f Dockerfile.php.base
            --tag "$reg":laradock-php-fpm-"$v"
            --build-arg PHP_VERSION="$v"
        )
        ;;
    redis)
        cmd_opt+=(
            -f Dockerfile."$v"
            --tag "$reg":laradock-"$v"
        )
        ;;
    nginx)
        cmd_opt+=(
            -f Dockerfile."$v"
            --tag "$reg":"$v"-alpine-base
        )
        ;;
    mysql-5.6 | mysql-5.7 | mysql-8.0 | mysql-8.4)
        cmd_opt+=(
            -f Dockerfile.mysql
            --tag "$reg":laradock-"$v"
            --build-arg MYSQL_VERSION="${v#*-}"
        )
        ;;
    spring-8 | spring-17 | spring-21)
        cmd_opt+=(
            -f Dockerfile.java.base
            --tag "$reg":laradock-"$v"
            --build-arg JDK_VERSION="${v#*-}"
        )
        ;;
    nodejs-18 | nodejs-20 | nodejs-21)
        cmd_opt+=(
            -f Dockerfile.node.base
            --tag "$reg":laradock-"$v"
            --build-arg NODE_VERSION="${v#*-}"
        )
        ;;
    esac

    # https://docs.docker.com/build/building/multi-platform/#build-multi-platform-images
    if ! ls /proc/sys/fs/binfmt_misc/qemu-aarch64; then
        docker run --privileged --rm tonistiigi/binfmt --install all
    fi

    # echo "${cmd_opt[@]} $me_path/"
    "${cmd_opt[@]}" "$me_path/"
}

cmd_opt+=(
    $(if command -v docker; then
        echo build
    elif command -v podman; then
        echo build --force-rm --format=docker
    fi)
    --progress=plain
    --platform "linux/amd64,linux/arm64"
    --build-arg CHANGE_SOURCE=true
    --build-arg IN_CHINA=true
    --build-arg HTTP_PROXY="${http_proxy-}"
    --build-arg HTTPS_PROXY="${http_proxy-}"
    --push
)

me_path="$(dirname "$(readlink -f "$0")")"
args=(5.6 7.1 7.3 7.4 8.1 8.2 8.3 8.4 mysql-5.6 mysql-5.7 mysql-8.0 mysql-8.4 spring-8 spring-17 spring-21 nodejs-18 nodejs-20 nodejs-21 redis nginx)
arg="${1:-}"

case "$arg" in
all)
    for i in "${args[@]}"; do
        _build "$i"
    done
    ;;
*)
    if [ -z "$arg" ]; then
        arg=$(echo "${args[@]}" | sed 's/\ /\n/g' | fzf)
    fi
    _build "$arg"
    ;;
esac
