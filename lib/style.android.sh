#!/usr/bin/env bash

_msg step "[TODO] java code style..."

# write shell function:
# 1, check code style for android code
# 2, using docker

_check_android_style() {
    _msg step "[style] check Android code style"
    echo "PIPELINE_ANDROID_CODE_STYLE: ${PIPELINE_ANDROID_CODE_STYLE:-0}"
    if [[ "${PIPELINE_ANDROID_CODE_STYLE:-0}" -eq 1 ]]; then
        docker run $ENV_ADD_HOST --rm -v "$gitlab_project_dir:/project" \
            openjdk:11 \
            /bin/bash -c "cd /project && ./gradlew ktlintCheck"
    else
        echo '<skip>'
    fi
}
