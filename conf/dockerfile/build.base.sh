#!/bin/bash

set -xe
if [[ -z "$1" ]]; then
    vers=(5.6 7.1 7.4 8.1 8.2)
else
    vers=("$1")
fi

for ver in "${vers[@]}"; do
    DOCKER_BUILDKIT=0 docker build \
        -f Dockerfile.php \
        -t deploy/base:fly-php"${ver/./}" \
        --build-arg PHP_VERSION="$ver" \
        --build-arg IN_CHINA="true" \
        .

    echo "FROM deploy/base:fly-php${ver/./}" >Dockerfile
    DOCKER_BUILDKIT=0 docker build \
        --build-arg=BASE_TAG="fly-php${ver/./}" \
        -t deploy/php:"$ver" \
        .
done
