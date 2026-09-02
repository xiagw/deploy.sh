#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2154,2034

################################################################################
# Description: Consolidated style checking functions for various programming languages
# Author: xiagw <fxiaxiaoyu@gmail.com>
# License: GNU/GPL
################################################################################

# PHP Style Check
style_check_php() {
    _msg task '[style] Running PHP Code Sniffer (PSR12) + php-cs-fixer'
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && return 0

    ## 使用社区维护的 PHP 质量工具镜像（含 phpcs、php-cs-fixer），替代仓库内已不存在的 Dockerfile.phpcs 本地构建
    local php_image="jakzal/phpqa:latest"

    local style_result=0
    for i in $(git --no-pager diff --name-only HEAD | awk '/\.php$/{if (NR>0){print $0}}'); do
        if [ ! -f "$G_REPO_DIR/$i" ]; then
            _msg warn "$G_REPO_DIR/$i not exists."
            continue
        fi
        if ! ${G_RUN} -v "$G_REPO_DIR":/project "$php_image" phpcs -n --standard=PSR12 --colors --report=full "/project/$i"; then
            style_result=$((style_result + 1))
        fi
        ## php-cs-fixer --dry-run: 只读检查（返回 1 表示需要格式化），不原地改文件
        if ! ${G_RUN} -v "$G_REPO_DIR":/project "$php_image" php-cs-fixer fix --dry-run --diff --using-cache=no "/project/$i"; then
            style_result=$((style_result + 1))
        fi
    done
    return "$style_result"
}

# Android Style Check
style_check_android() {
    _msg task "Checking Android code style"
    echo "PIPELINE_ANDROID_CODE_STYLE: ${PIPELINE_ANDROID_CODE_STYLE:-0}"
    if [[ "${PIPELINE_ANDROID_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/project" openjdk:11 \
            /bin/bash -c "cd /project && ./gradlew ktlintCheck"
    else
        _msg note '<skip>'
    fi
}

# Python Style Check
style_check_python() {
    _msg task "Checking Python code style (pylint + black + isort)"
    if [[ "${PIPELINE_PYTHON_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/code" python:3 \
            /bin/bash -c "cd /code && pip install pylint black isort && black --check . && isort --check-only . && pylint *.py"
    else
        _msg note '<skip>'
    fi
}

# Node.js Style Check
style_check_node() {
    _msg task "Checking Node.js code style (eslint + prettier)"
    if [[ "${PIPELINE_NODE_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/app" node:latest \
            /bin/bash -c "cd /app && npx --yes eslint . && npx --yes prettier --check ."
    else
        _msg note '<skip>'
    fi
}

# Java Style Check
style_check_java() {
    _msg task "Checking Java code style"
    if [[ "${PIPELINE_JAVA_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/src" openjdk:11 \
            /bin/bash -c "cd /src && ./gradlew checkstyle"
    else
        _msg note '<skip>'
    fi
}

# Go Style Check
style_check_go() {
    _msg task "Checking Go code style (gofmt + golangci-lint)"
    if [[ "${PIPELINE_GO_CODE_STYLE:-0}" -eq 1 ]]; then
        ## gofmt -l 只读列出未格式化文件；golangci-lint 取代已废弃的 golint
        ${G_RUN} -v "$G_REPO_DIR:/app" golangci/golangci-lint:latest \
            /bin/bash -c 'cd /app && files=$(gofmt -l .); if [ -n "$files" ]; then echo "gofmt needed:"; echo "$files"; exit 1; fi; golangci-lint run ./...'
    else
        _msg note '<skip>'
    fi
}

# Rust Style Check
style_check_rust() {
    _msg task "Checking Rust code style (rustfmt + clippy)"
    if [[ "${PIPELINE_RUST_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/app" rust:latest \
            /bin/bash -c "cd /app && cargo fmt --check && cargo clippy -- -D warnings"
    else
        _msg note '<skip>'
    fi
}

# .NET Style Check
style_check_dotnet() {
    _msg task "Checking .NET code style (dotnet format)"
    if [[ "${PIPELINE_DOTNET_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/app" mcr.microsoft.com/dotnet/sdk:8.0 \
            /bin/bash -c "cd /app && dotnet format --verify-no-changes --no-restore"
    else
        _msg note '<skip>'
    fi
}

# Ruby Style Check
style_check_ruby() {
    _msg task "Checking Ruby code style"
    if [[ "${PIPELINE_RUBY_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/app" ruby:latest \
            /bin/bash -c "cd /app && gem install rubocop && rubocop"
    else
        _msg note '<skip>'
    fi
}

# C/C++ Style Check
style_check_c() {
    _msg task "Checking C/C++ code style"
    if [[ "${PIPELINE_C_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/src" gcc:latest \
            /bin/bash -c "cd /src && clang-format -i *.{c,h,cpp,hpp}"
    else
        _msg note '<skip>'
    fi
}

# Docker Style Check
style_check_docker() {
    _msg task "Checking Dockerfile style"
    if [[ "${PIPELINE_DOCKER_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/work" hadolint/hadolint:latest \
            hadolint /work/Dockerfile*
    else
        _msg note '<skip>'
    fi
}

# iOS Style Check
style_check_ios() {
    _msg task "Checking iOS code style"
    if [[ "${PIPELINE_IOS_CODE_STYLE:-0}" -eq 1 ]]; then
        # Note: iOS style checking typically requires macOS environment
        # This is a placeholder for SwiftLint or similar tools
        _msg note "iOS style checking requires macOS environment"
    else
        _msg note '<skip>'
    fi
}

# Django Style Check
style_check_django() {
    _msg task "Checking Django code style"
    if [[ "${PIPELINE_DJANGO_CODE_STYLE:-0}" -eq 1 ]]; then
        ${G_RUN} -v "$G_REPO_DIR:/app" python:3 \
            /bin/bash -c "cd /app && pip install pylint-django && pylint --load-plugins pylint_django *.py"
    else
        _msg note '<skip>'
    fi
}

# Shell Style Check / Shell 风格校验（shellcheck + shfmt）
style_check_shell() {
    _msg task "Running shell style check"
    [[ "${G_DEBUG_ON:-false}" == true ]] && return 0
    _install_shellcheck
    _install_shfmt
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        return 0
    fi
    local exit_code=0 script sc=false sf=false
    command -v shellcheck >/dev/null 2>&1 && sc=true
    command -v shfmt >/dev/null 2>&1 && sf=true
    # Process shell scripts
    while IFS= read -r script; do
        _msg note "Processing: ${script}"
        $sc && shellcheck "$script" || exit_code=$?
        $sf && shfmt -d "$script" || exit_code=$?
    done < <(find "$G_REPO_DIR" -type f -name "*.sh") || true

    if [ $exit_code -eq 0 ]; then
        _msg ok "All shell scripts passed checks"
    else
        _msg error "Some shell scripts failed checks"
    fi
    return $exit_code
}

# Main style check function that determines which specific checker to run
stage_code_style() {
    _msg stage "$(_t '代码风格' 'code style')"
    local lang
    lang="$(detect_repo_language | cut -d':' -f1)" # 获取语言类型

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_CODE_STYLE ，true 启用，false 禁用[default]
    _msg task "Code style check (optional: PIPELINE_CODE_STYLE=true)"
    [[ "${PIPELINE_CODE_STYLE:-false}" != true ]] && _msg note "$(_t '跳过' 'skipped') (PIPELINE_CODE_STYLE=false)"
    if ! ${PIPELINE_CODE_STYLE:-false}; then
        return 0
    fi

    dry_run_skip "run code style check for ${lang} (style_check_${lang})" && return 0

    case "$lang" in
    php) style_check_php ;;
    android) style_check_android ;;
    python) style_check_python ;;
    node) style_check_node ;;
    java) style_check_java ;;
    go | golang) style_check_go ;;
    rust) style_check_rust ;;
    ruby) style_check_ruby ;;
    c) style_check_c ;;
    docker) style_check_docker ;;
    ios) style_check_ios ;;
    django) style_check_django ;;
    dotnet) style_check_dotnet ;;
    *) _msg warn "No style checker available for language: $lang" ;;
    esac
}
