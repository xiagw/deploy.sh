#!/usr/bin/env bash

_msg step "[build] docker build image"

docker build ${quiet_flag} \
    --tag "${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}:${image_tag}" \
    --build-arg IN_CHINA="${ENV_IN_CHINA:-false}" \
    "${gitlab_project_dir}"

_msg time "[build] end docker build"
