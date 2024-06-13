#!/bin/bash

set -xe

if [[ -z "$1" ]]; then
    vers=(5.6 7.1 7.3 7.4 8.1 8.2 8.3)
else
    vers=("$1")
fi

me_path="$(dirname "$(readlink -f "$0")")"
if command -v docker >/dev/null 2>&1; then
    cmd=$(command -v docker)
    cmd_opt="$cmd build --progress=plain"
elif command -v podman >/dev/null 2>&1; then
    cmd=$(command -v podman)
    cmd_opt="$cmd build --progress=plain --force-rm --format=docker"
else
    echo "No docker or podman command found."
    exit 1
fi

image_repo=registry-vpc.cn-hangzhou.aliyuncs.com/flyh5/flyh5
for ver in "${vers[@]}"; do
    ## build base
    $cmd_opt -f Dockerfile.php.base -t $image_repo:"php-${ver}-base" --build-arg PHP_VERSION="$ver" --build-arg IN_CHINA="true" "$me_path"
    ## build for laradock
    echo "FROM $image_repo:php-${ver}-base" >Dockerfile.php
    $cmd_opt -f Dockerfile.php -t $image_repo:"php-$ver" "$me_path"
    $cmd push $image_repo:"php-$ver"
done
