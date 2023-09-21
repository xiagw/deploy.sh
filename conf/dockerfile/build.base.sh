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
    cmd_opt="$cmd build --progress=plain --force-rm --format=docker"
else
    cmd='docker'
    cmd_opt="$cmd build --progress=plain"
fi
for ver in "${vers[@]}"; do
    ## build base
    tag="php-${ver}"
    $cmd_opt \
        --build-arg PHP_VERSION="$ver" \
        --build-arg IN_CHINA="true" \
        -f Dockerfile.php.base \
        -t deploy/base:"$tag" \
        "$me_path"
    ## build for laradock
    echo "FROM deploy/base:$tag" >Dockerfile.php
    $cmd_opt \
        -f Dockerfile.php \
        -t deploy/php:"$ver" \
        "$me_path"
    ## upload to OSS:
    $cmd tag deploy/php:"$ver" laradock-php-fpm
    $cmd save laradock-php-fpm | gzip -c >/tmp/laradock-php-fpm.$ver.tar.gz
    select b in $(ossutil ls -s | grep '^oss:') quit; do
        [ "$b" = quit ] && break
        ossutil cp /tmp/laradock-php-fpm.$ver.tar.gz $b/docker/ -f
        break
    done
done
