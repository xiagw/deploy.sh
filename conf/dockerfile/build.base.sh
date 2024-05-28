#!/bin/bash

set -xe
me_path="$(dirname "$(readlink -f "$0")")"

if command -v podman; then
    cmd_opt="podman build --progress=plain --force-rm --format=docker"
else
    cmd_opt="docker build --progress=plain"
fi

if [[ -z "$1" ]]; then
    vers=(5.6 7.1 7.3 7.4 8.1 8.2)
else
    vers=("$1")
fi

image_repo=registry-vpc.cn-hangzhou.aliyuncs.com/flyh5/flyh5
for ver in "${vers[@]}"; do
    ## build base
    $cmd_opt -f Dockerfile.php.base -t $image_repo:"php-${ver}-base" --build-arg PHP_VERSION="$ver" --build-arg IN_CHINA="true" "$me_path"
    ## build for laradock
    echo "FROM $image_repo:php-${ver}-base" >Dockerfile.php
    $cmd_opt -f Dockerfile.php -t $image_repo:"php-$ver" "$me_path"

    docker push $image_repo:"php-$ver"
done
