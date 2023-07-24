#!/bin/bash

set -xe
tags=(5.6 7.1 7.4 8.1 8.2)
for tag in "${tags[@]}"; do
    DOCKER_BUILDKIT=0 docker build \
        -f Dockerfile.php \
        -t deploy/base:fly-php"${tag/./}" \
        --build-arg PHP_VERSION="$tag" \
        --build-arg IN_CHINA="true" \
        .

    echo "FROM deploy/base:fly-php${tag/./}" >Dockerfile
    DOCKER_BUILDKIT=0 docker build \
        --build-arg=BASE_TAG="fly-php${tag/./}" \
        -t deploy/php:"$tag" \
        .
done
