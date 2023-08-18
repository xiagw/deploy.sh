#!/bin/bash

set -xe
me_path="$(dirname "$(readlink -f "$0")")"

if [[ -z "$1" ]]; then
    vers=(5.6 7.1 7.4 8.1 8.2)
else
    vers=("$1")
fi

for ver in "${vers[@]}"; do
    tag="fly-php${ver/./}"
    DOCKER_BUILDKIT=0 docker build \
        --build-arg PHP_VERSION="$ver" \
        --build-arg IN_CHINA="true" \
        -f Dockerfile.php \
        -t deploy/base:"$tag" \
        "$me_path"

    echo "FROM deploy/base:$tag" >Dockerfile.php2

    DOCKER_BUILDKIT=0 docker build \
        --build-arg BASE_TAG="$tag" \
        -f Dockerfile.php2 \
        -t deploy/php:"$ver" \
        "$me_path"

    docker tag deploy/php:"$ver" laradock-php-fpm
    docker save laradock-php-fpm | gzip -c >/tmp/laradock-php-fpm.$ver.tar.gz
    ossutil cp /tmp/laradock-php-fpm.$ver.tar.gz oss://bucket_name/docker/ -f

    rm -f Dockerfile.php2
done

