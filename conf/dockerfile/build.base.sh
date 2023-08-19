#!/bin/bash

set -xe
me_path="$(dirname "$(readlink -f "$0")")"

if [[ -z "$1" ]]; then
    vers=(5.6 7.1 7.4 8.1 8.2)
else
    vers=("$1")
fi

if command -v podman; then
    cmd='podman'
    cmd_opt='build --force-rm --format=docker'
else
    cmd='docker'
    cmd_opt='build'
fi
for ver in "${vers[@]}"; do
    tag="fly-php${ver/./}"
    DOCKER_BUILDKIT=0 $cmd $cmd_opt\
        --build-arg PHP_VERSION="$ver" \
        --build-arg IN_CHINA="true" \
        -f Dockerfile.php \
        -t deploy/base:"$tag" \
        "$me_path"

    echo "FROM deploy/base:$tag" >Dockerfile.php2

    DOCKER_BUILDKIT=0 $cmd $cmd_opt \
        --build-arg BASE_TAG="$tag" \
        -f Dockerfile.php2 \
        -t deploy/php:"$ver" \
        "$me_path"
    rm -f Dockerfile.php2

    $cmd tag deploy/php:"$ver" laradock-php-fpm
    $cmd save laradock-php-fpm | gzip -c >/tmp/laradock-php-fpm.$ver.tar.gz
    select b in $(ossutil ls -s | grep '^oss:'); do
        ossutil cp /tmp/laradock-php-fpm.$ver.tar.gz $b/docker/ -f
    done
done
