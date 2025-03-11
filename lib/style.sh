#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2154,2034

################################################################################
# Description: Consolidated style checking functions for various programming languages
# Author: xiagw <fxiaxiaoyu@gmail.com>
# License: GNU/GPL
################################################################################

# PHP Style Check
check_php_style() {
    _msg step '[style] Running PHP Code Sniffer (PSR12)'
    [[ "${GH_ACTION:-0}" -eq 1 ]] && return 0

    if ! ${G_DOCK} images | grep -q 'deploy/phpcs'; then
        ${G_DOCK} build ${G_ARGS} -t deploy/phpcs -f "$me_dockerfile/Dockerfile.phpcs" "$me_dockerfile" >/dev/null
    fi

    local phpcs_result=0
    for i in $(git --no-pager diff --name-only HEAD^ | awk '/\.php$/{if (NR>0){print $0}}'); do
        if [ ! -f "$G_REPO_DIR/$i" ]; then
            echo_warn "$G_REPO_DIR/$i not exists."
            continue
        fi
        if ! $docker_run -v "$G_REPO_DIR":/project deploy/phpcs phpcs -n --standard=PSR12 --colors --report="${phpcs_report:-full}" "/project/$i"; then
            phpcs_result=$((phpcs_result + 1))
        fi
    done
    return "$phpcs_result"
}

# Android Style Check
check_android_style() {
    _msg step "[style] Checking Android code style"
    echo "PIPELINE_ANDROID_CODE_STYLE: ${PIPELINE_ANDROID_CODE_STYLE:-0}"
    if [[ "${PIPELINE_ANDROID_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/project" openjdk:11 \
            /bin/bash -c "cd /project && ./gradlew ktlintCheck"
    else
        echo '<skip>'
    fi
}

# Python Style Check
check_python_style() {
    _msg step "[style] Checking Python code style"
    if [[ "${PIPELINE_PYTHON_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/code" python:3 \
            /bin/bash -c "cd /code && pip install pylint && pylint *.py"
    else
        echo '<skip>'
    fi
}

# Node.js Style Check
check_node_style() {
    _msg step "[style] Checking Node.js code style"
    if [[ "${PIPELINE_NODE_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/app" node:latest \
            /bin/bash -c "cd /app && npm install eslint && npx eslint ."
    else
        echo '<skip>'
    fi
}

# Java Style Check
check_java_style() {
    _msg step "[style] Checking Java code style"
    if [[ "${PIPELINE_JAVA_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/src" openjdk:11 \
            /bin/bash -c "cd /src && ./gradlew checkstyle"
    else
        echo '<skip>'
    fi
}

# Go Style Check
check_go_style() {
    _msg step "[style] Checking Go code style"
    if [[ "${PIPELINE_GO_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/go/src/app" golang:latest \
            /bin/bash -c "cd /go/src/app && go fmt ./... && golint ./..."
    else
        echo '<skip>'
    fi
}

# Ruby Style Check
check_ruby_style() {
    _msg step "[style] Checking Ruby code style"
    if [[ "${PIPELINE_RUBY_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/app" ruby:latest \
            /bin/bash -c "cd /app && gem install rubocop && rubocop"
    else
        echo '<skip>'
    fi
}

# C/C++ Style Check
check_c_style() {
    _msg step "[style] Checking C/C++ code style"
    if [[ "${PIPELINE_C_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/src" gcc:latest \
            /bin/bash -c "cd /src && clang-format -i *.{c,h,cpp,hpp}"
    else
        echo '<skip>'
    fi
}

# Docker Style Check
check_docker_style() {
    _msg step "[style] Checking Dockerfile style"
    if [[ "${PIPELINE_DOCKER_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/work" hadolint/hadolint:latest \
            hadolint /work/Dockerfile*
    else
        echo '<skip>'
    fi
}

# iOS Style Check
check_ios_style() {
    _msg step "[style] Checking iOS code style"
    if [[ "${PIPELINE_IOS_CODE_STYLE:-0}" -eq 1 ]]; then
        # Note: iOS style checking typically requires macOS environment
        # This is a placeholder for SwiftLint or similar tools
        echo "iOS style checking requires macOS environment"
    else
        echo '<skip>'
    fi
}

# Django Style Check
check_django_style() {
    _msg step "[style] Checking Django code style"
    if [[ "${PIPELINE_DJANGO_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/app" python:3 \
            /bin/bash -c "cd /app && pip install pylint-django && pylint --load-plugins pylint_django *.py"
    else
        echo '<skip>'
    fi
}

# 添加并行处理
parallel_style_check() {
    local languages=("$@")
    local pids=()

    for lang in "${languages[@]}"; do
        style_check "$lang" &
        pids+=($!)
    done

    # 等待所有检查完成
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# 使用示例
# parallel_style_check php python node

# Main style check function that determines which specific checker to run
style_check() {
    local lang="$1"

    ## 在 gitlab 的 pipeline 配置环境变量 MAN_CODE_STYLE ，true 启用，false 禁用[default]
    _msg step "[style] Running code style checks"
    echo "MAN_CODE_STYLE: ${MAN_CODE_STYLE:-false}"
    if ! ${MAN_CODE_STYLE:-false}; then
        return 0
    fi

    case "$lang" in
    php) check_php_style ;;
    android) check_android_style ;;
    python) check_python_style ;;
    node) check_node_style ;;
    java) check_java_style ;;
    go) check_go_style ;;
    ruby) check_ruby_style ;;
    c) check_c_style ;;
    docker) check_docker_style ;;
    ios) check_ios_style ;;
    django) check_django_style ;;
    *) _msg warn "No style checker available for language: $lang" ;;
    esac
}
