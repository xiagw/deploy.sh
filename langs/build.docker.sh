#!/usr/bin/env bash

echo_time_step "build image [docker]..."
DOCKER_BUILDKIT=1 docker build ${quiet_flag} --tag "${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}:${image_tag}" \
    --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE:-false}" "${gitlab_project_dir}"
echo_time "end docker build."
