#!/usr/bin/env bash

echo_msg step "[TODO] vsc-extension-hadolint..."
docker run --rm -i hadolint/hadolint < $gitlab_project_dir/Dockerfile