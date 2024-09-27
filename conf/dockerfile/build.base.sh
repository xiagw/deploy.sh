#!/bin/bash

set -xe

_build() {
    local v="$1"
    case "$v" in
    5.6 | 7.1 | 7.3 | 7.4 | 8.1 | 8.2 | 8.3)
        docker_file=Dockerfile.php.base
        tag=registry.cn-hangzhou.aliyuncs.com/flyh5/flyh5:laradock-php-fpm-${v}
        php_ver=$v
        ;;
    redis | nginx)
        docker_file=Dockerfile.$v
        tag=registry.cn-hangzhou.aliyuncs.com/flyh5/flyh5:laradock-${v}
        ;;
    mysql-5.7 | mysql-8.0)
        docker_file=Dockerfile.mysql
        mysql_ver=${v#*-}
        tag=registry.cn-hangzhou.aliyuncs.com/flyh5/flyh5:laradock-${v}
        ;;
    spring-8 | spring-17 | spring-21)
        docker_file=Dockerfile.java.base
        jdk_ver=${v#*-}
        tag=registry.cn-hangzhou.aliyuncs.com/flyh5/flyh5:laradock-${v}
        ;;
    nodejs-18 | nodejs-20 | nodejs-21)
        docker_file=Dockerfile.node.base
        node_ver=${v#*-}
        tag=registry.cn-hangzhou.aliyuncs.com/flyh5/flyh5:laradock-${v}
        ;;
    esac

    $cmd_opt -f "$docker_file" \
        -t "$tag" \
        --build-arg CHANGE_SOURCE=true \
        --build-arg IN_CHINA=true \
        --build-arg HTTP_PROXY="${http_proxy-}" \
        --build-arg HTTPS_PROXY="${http_proxy-}" \
        --build-arg PHP_VERSION="$php_ver" \
        --build-arg MYSQL_VERSION="$mysql_ver" \
        --build-arg NODE_VERSION="$node_ver" \
        --build-arg JDK_VERSION="$jdk_ver" \
        --push \
        "$me_path/"

}

me_path="$(dirname "$(readlink -f "$0")")"

if command -v docker >/dev/null 2>&1; then
    cmd=$(command -v docker)
    cmd_opt="$cmd build --progress=plain --platform linux/amd64,linux/arm64"
elif command -v podman >/dev/null 2>&1; then
    cmd=$(command -v podman)
    cmd_opt="$cmd build --progress=plain --force-rm --format=docker --platform linux/amd64,linux/arm64"
else
    echo "No docker or podman command found."
    exit 1
fi

args=(5.6 7.1 7.3 7.4 8.1 8.2 8.3 mysql-5.7 mysql-8.0 spring-8 spring-17 spring-21 nodejs-18 nodejs-20 nodejs-21 redis nginx)
arg="$1"
case "$arg" in
all)
    for i in "${args[@]}"; do
        _build "$i"
    done
    ;;
"${args[@]}")
    _build "$arg"
    ;;
*)
    arg=$(for i in "${args[@]}"; do echo "$i"; done | fzf)
    _build "$arg"
    ;;
esac
