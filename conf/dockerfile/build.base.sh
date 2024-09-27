#!/bin/bash

set -xe

if [[ -z "$1" ]]; then
    ver=$(echo -e "5.6\n7.1\n7.3\n7.4\n8.1\n8.2\n8.3" | fzf)
else
    ver="$1"
fi

me_path="$(dirname "$(readlink -f "$0")")"

if command -v docker >/dev/null 2>&1; then
    cmd=$(command -v docker)
    cmd_opt="$cmd build --progress=plain --platform linux/amd64,linux/arm64"
elif command -v podman >/dev/null 2>&1; then
    cmd=$(command -v podman)
    cmd_opt="$cmd build --progress=plain --force-rm --format=docker"
else
    echo "No docker or podman command found."
    exit 1
fi

tag=registry-vpc.cn-hangzhou.aliyuncs.com/flyh5/flyh5:laradock-php-fpm-${ver}
## build base
$cmd_opt -f Dockerfile.php.base -t "$tag" --build-arg PHP_VERSION="$ver" --build-arg IN_CHINA="true" "$me_path"
$cmd push "$tag"

