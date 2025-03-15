#!/bin/bash
# shellcheck disable=SC2207
set -xe

build_base_image() {
    local tag="$1"
    local reg="registry.cn-hangzhou.aliyuncs.com/flyh5"
    local base_tag="${reg}/${tag}-base"

    case "$tag" in
    php:*)
        cmd_opt+=(
            --build-arg PHP_VERSION="${tag#*:}"
            -f "$me_path/Dockerfile.base.${tag%:*}"
        )
        ;;
    redis:*)
        cmd_opt+=(
            -f "$me_path/Dockerfile.base.${tag%:*}"
        )
        ;;
    nginx:*)
        cmd_opt+=(
            -f "$me_path/Dockerfile.base.${tag%:*}"
        )
        ;;
    mysql:*)
        cmd_opt+=(
            --build-arg MYSQL_VERSION="${tag#*:}"
            -f "$me_path/Dockerfile.base.${tag%:*}"
        )
        ;;
    amazoncorretto:*)
        cmd_opt+=(
            --build-arg MVN_PROFILE="base"
            --build-arg MVN_IMAGE="${reg}/${tag%:*}"
            --build-arg JDK_IMAGE="${reg}/${tag%:*}"
            --build-arg JDK_VERSION="${tag#*:}"
            -f "$me_path/Dockerfile.base.java"
        )
        ;;
    node:*)
        cmd_opt+=(
            --build-arg NODE_VERSION="${tag#*:}"
            -f "$me_path/Dockerfile.base.${tag%:*}"
        )
        ;;
    esac
    cmd_opt+=(--tag "${base_tag}")

    # https://docs.docker.com/build/building/multi-platform/#build-multi-platform-images
    if ! ls /proc/sys/fs/binfmt_misc/qemu-aarch64; then
        $cmd run --privileged --rm tonistiigi/binfmt --install all
    fi

    "${cmd_opt[@]}" "$me_path/"
}

cmd_arg="${*}"

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

all_args=(
    "php:5.6" "php:7.1" "php:7.3" "php:7.4" "php:8.1" "php:8.2" "php:8.3" "php:8.4"
    "mysql:5.6" "mysql:5.7" "mysql:8.0" "mysql:8.4" "mysql:9.0"
    "amazoncorretto:8" "amazoncorretto:17" "amazoncorretto:21" "amazoncorretto:23"
    "node:18" "node:20" "node:21" "node:22"
    "redis:latest"
    "nginx:stable-alpine"
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
