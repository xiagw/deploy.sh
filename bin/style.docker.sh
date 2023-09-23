#!/usr/bin/env bash

_msg step "[TODO] vsc-extension-hadolint..."
docker run $ENV_ADD_HOST --rm -i hadolint/hadolint < $gitlab_project_dir/Dockerfile