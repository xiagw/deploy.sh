#!/usr/bin/env bash

DOCKER_BUILDKIT=1 docker build ${quiet_flag} --tag "${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}:${gitlab_project_name}-${gitlab_commit_short_sha}" \
    --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE:-false}" "${gitlab_project_dir}"
echo_time "end docker build."
