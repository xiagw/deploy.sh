#!/usr/bin/env bash

echo_time_step "[TODO] vsc-extension-hadolint..."
docker run --rm -i hadolint/hadolint < $gitlab_project_dir/Dockerfile