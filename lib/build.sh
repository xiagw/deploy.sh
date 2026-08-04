#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2154,2034,1090,1091,2086
################################################################################
# Description: Consolidated build functions for various programming languages
# Author: xiagw <fxiaxiaoyu@gmail.com>
# License: GNU/GPL
################################################################################

# 在 k8s 中创建 buildx builder
# docker buildx create --driver kubernetes --name deploy-builder --driver-opt namespace=buildkit,replicas=1,rootless=false --driver-opt image=docker.m.daocloud.io/moby/buildkit:buildx-stable-1 --bootstrap
ensure_buildx_builder() {
    [[ "${G_DEBUG_ON:-false}" == true ]] && return
    [[ -z "${ENV_BUILDX_REMOTE_HOSTS[*]:-}" ]] && return

    local builder_name="deploy-builder"
    if ! docker buildx inspect "$builder_name" >/dev/null 2>&1; then
        local c=0 append_flag=()
        local buildkit_image="${ENV_BUILDX_IMAGE:-docker.m.daocloud.io/moby/buildkit:buildx-stable-1}"
        for dk_host in "${ENV_BUILDX_REMOTE_HOSTS[@]}"; do
            ((++c))
            docker buildx create --name "$builder_name" "${append_flag[@]}" \
                --node "node$c" --driver docker-container \
                --driver-opt image="${buildkit_image}" "$dk_host" ||
                _msg error "创建buildx节点node$c失败: ${dk_host}"
            append_flag=(--append)
        done
    fi
    export G_BUILDER="--builder $builder_name"
}

# Alternative remote buildx modes.
# These helpers are defined and ready for manual switching by changing the call in build_image().

ensure_buildx_builder_context() {
    [[ "${G_DEBUG_ON:-false}" == true ]] && return
    [[ -z "${ENV_BUILDX_REMOTE_HOSTS[*]:-}" ]] && return

    local builder_name="deploy-builder"
    if ! docker buildx inspect "$builder_name" >/dev/null 2>&1; then
        local idx=$((RANDOM % ${#ENV_BUILDX_REMOTE_HOSTS[@]}))
        local target_host="${ENV_BUILDX_REMOTE_HOSTS[$idx]}"
        local buildkit_image="${ENV_BUILDX_IMAGE:-docker.m.daocloud.io/moby/buildkit:buildx-stable-1}"
        docker buildx create --name "$builder_name" --driver docker-container \
            --driver-opt image="${buildkit_image}" \
            "$target_host" || _msg error "创建 buildx builder on $target_host 失败"
    fi
    export G_BUILDER="--builder $builder_name"
}

ensure_buildx_builder_kubernetes() {
    [[ "${G_DEBUG_ON:-false}" == true ]] && return
    [[ -z "${ENV_BUILDX_KUBERNETES_NAMESPACE:-}" ]] && return

    local builder_name="deploy-builder-k8s"
    if ! docker buildx inspect "$builder_name" >/dev/null 2>&1; then
        local buildkit_image="${ENV_BUILDX_IMAGE:-docker.m.daocloud.io/moby/buildkit:buildx-stable-1}"
        docker buildx create --driver kubernetes --name "$builder_name" \
            --driver-opt namespace="${ENV_BUILDX_KUBERNETES_NAMESPACE:-buildkit}" \
            --driver-opt replicas="${ENV_BUILDX_KUBERNETES_REPLICAS:-1}" \
            --driver-opt rootless=false \
            --driver-opt image="${buildkit_image}" \
            --bootstrap || _msg error "创建 kubernetes buildx builder 失败"
    fi
    export G_BUILDER="--builder $builder_name"
}

enable_buildx_mode() {
    local mode="${ENV_BUILDX_MODE:-remote}"
    mode="${mode,,}"

    case "${mode}" in
    auto)
        if [[ -n "${ENV_BUILDX_KUBERNETES_NAMESPACE:-}" ]]; then
            ensure_buildx_builder_kubernetes
        elif [[ -n "${ENV_BUILDX_REMOTE_HOSTS[*]:-}" ]]; then
            ensure_buildx_builder
        else
            _msg warn "ENV_BUILDX_MODE=auto but no buildx host or kubernetes namespace configured"
        fi
        ;;
    kubernetes)
        ensure_buildx_builder_kubernetes
        ;;
    context)
        ensure_buildx_builder_context
        ;;
    remote | "")
        ensure_buildx_builder
        ;;
    *)
        _msg warn "Unknown ENV_BUILDX_MODE=${mode}, falling back to remote"
        ensure_buildx_builder
        ;;
    esac
}

# 根据 lang（固定三段式 lang:ver:docker_flag，字段可为空）生成 docker-bake.hcl
# $1 lang, $2 bake 文件路径, $3 应用镜像 tag, $4 可选 base 镜像 tag（存在 Dockerfile.base 时）
generate_bake_file() {
    local lang="${1:?lang required}" bake_file="${2:?bake file required}"
    local repo_tag="${3:?repo tag required}" base_tag="${4:-}"
    local lang_type ver docker_flag lang_args="" extra_args="" mirror="${ENV_DOCKER_MIRROR:+${ENV_DOCKER_MIRROR%/}/}"
    IFS=: read -r lang_type ver docker_flag <<<"${lang}"
    lang_type="${lang_type:-unknown}"

    ## lang[:ver] → "BUILD_IMAGE BUILD_TAG RUN_IMAGE RUN_TAG"
    ## Dockerfile 全变量化（ARG 默认值是 java），必须四项全量注入
    ## 精确 key 未命中时回退到 lang key（默认版本）
    declare -A LANG_IMAGE_MAP=(
        ["java"]="maven 3.8-amazoncorretto-8 amazoncorretto 8-base"
        ["java:1.7"]="maven 3.6-jdk-7 amazoncorretto 7"
        ["java:7"]="maven 3.6-jdk-7 amazoncorretto 7"
        ["java:11"]="maven 3.9-amazoncorretto-11 amazoncorretto 11-base"
        ["java:17"]="maven 3.9-amazoncorretto-17 amazoncorretto 17-base"
        ["java:21"]="maven 3.9-amazoncorretto-21 amazoncorretto 21-base"
        ["java:25"]="maven 3.9-amazoncorretto-25 amazoncorretto 25-base"
        ["java:26"]="maven 3.9-amazoncorretto-26 amazoncorretto 26-base"
        ["node"]="node 22-slim node 22-slim"
        ["go"]="golang 1.26 alpine latest"
        ["golang"]="golang 1.26 alpine latest"
        ["python"]="python 3.12-slim python 3.12-slim"
        ["php"]="phpswoole/swoole 6.1-php8.4 ubuntu 24.04"
    )

    local map_val="${LANG_IMAGE_MAP[${lang_type}:${ver}]:-${LANG_IMAGE_MAP[${lang_type}]:-}}"
    if [[ -n "${map_val}" ]]; then
        local build_image build_tag run_image run_tag
        read -r build_image build_tag run_image run_tag <<<"${map_val}"
        ## node/python 等 tag 直接跟随版本号；go 仅编译镜像跟随版本
        case "${lang_type}" in
        node) [[ -n "${ver}" ]] && { build_tag="${ver}-slim"; run_tag="${ver}-slim"; } ;;
        python) [[ -n "${ver}" ]] && { build_tag="${ver}-slim"; run_tag="${ver}-slim"; } ;;
        go | golang) [[ -n "${ver}" ]] && build_tag="${ver}" ;;
        esac
        ## node 最低版本限制 18
        if [[ "${lang_type}" == node ]]; then
            local _node_num="${run_tag%%-*}"
            [[ -n "${_node_num}" && "${_node_num}" -lt 18 ]] 2>/dev/null && { build_tag="18-slim"; run_tag="18-slim"; }
        fi
        lang_args+="
        BUILD_IMAGE = \"${build_image}\"
        BUILD_TAG = \"${build_tag}\"
        RUN_IMAGE = \"${run_image}\"
        RUN_TAG = \"${run_tag}\""
    fi

    ## 语言特有的附加参数
    case "${lang_type}" in
    java)
        lang_args+="
        MVN_PROFILE = \"${G_REPO_BRANCH}\"
        MVN_DEBUG = \"${G_DEBUG_ON:-false}\""

        ;;
    node)
        lang_args+="
        ONBUILD_CHOWN = \"1000:1000\"
        ONBUILD_COPY_SRC = \".\"
        ONBUILD_COPY_DEST = \"/app/\""
        ;;
    esac
    ## README 文件中声明的额外安装需求(变量名转为全大写变量值为 true 小写)
    local f
    for f in "${G_REPO_DIR}"/{README,readme}*; do
        [ -f "$f" ] || continue
        if ! grep -qi '^install_.*=.*true' "$f"; then
            continue
        fi
        lang_args+="
        $(grep -ih '^install_.*=.*true' "$f" | tr '[:lower:]' '[:upper:]' | sed 's/TRUE/"true"/g')"
    done

    ## BUILD_SCRIPT_ARG 和 RUN_SCRIPT_ARG 仅在非空时注入（避免覆盖 Dockerfile 默认值）
    [[ -n "${ENV_BUILD_SCRIPT_ARG:-}" ]] && extra_args+="
        BUILD_SCRIPT_ARG = \"${ENV_BUILD_SCRIPT_ARG}\""
    [[ -n "${ENV_RUN_SCRIPT_ARG:-}" ]] && extra_args+="
        RUN_SCRIPT_ARG = \"${ENV_RUN_SCRIPT_ARG}\""


    cat >"${bake_file}" <<EOF
target "default" {
    context = "${G_REPO_DIR}"
    dockerfile = "Dockerfile"
    platforms = ["linux/amd64"]
    args = {
        IN_CHINA = "${ENV_IN_CHINA:-false}"
        MIRROR = "${mirror}"
        BUILD_OUTPUT_DIR = "/build_output"${lang_args}${extra_args}
    }
    tags = ["${repo_tag}"]
}
EOF
    if [ -n "${base_tag}" ]; then
        cat >>"${bake_file}" <<EOF
target "base" {
    inherits = ["default"]
    dockerfile = "Dockerfile.base"
    tags = ["${base_tag}"]
}
EOF
    fi
}

run_command_with_log() {
    local log_file="$1"
    shift

    local old_pipefail
    if (set -o | grep -q '^pipefail[[:space:]]*on$'); then
        old_pipefail=on
    else
        old_pipefail=off
    fi
    set +o pipefail

    "$@" 2>&1 | tee "$log_file" >/dev/null
    local ret=${PIPESTATUS[0]}

    [[ "$old_pipefail" = on ]] && set -o pipefail
    return "$ret"
}

build_image() {
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && return 0
    local retention_mode="${1}" lang="${2:-}"
    local custom_build_script dockerfile_base_path dockerfile_path buildx_push_option image_uuid target_image_tag base_image_tag bake_file_path docker_mirror

    ## Ensure buildx builder is available
    enable_buildx_mode

    ## If build.base.sh exists, run it and preserve its exit status
    custom_build_script="${G_REPO_DIR}/build.base.sh"
    if [[ -f "${custom_build_script}" ]]; then
        echo "Found ${custom_build_script}, running it..."
        [[ "${G_DEBUG_ON:-false}" == true ]] && debug_flag="-x"
        bash "${custom_build_script}" $debug_flag
        local custom_build_ret=$?
        export EXIT_MAIN=true
        return "${custom_build_ret}"
    fi

    # 根据参数决定是否需要 push 镜像。默认 push，除非指定保留镜像模式
    if [[ -z "${retention_mode}" || "${retention_mode}" = 'push' ]]; then
        docker_login
        buildx_push_option="--push"
    else
        buildx_push_option="--load"
    fi

    ## 如果存在 Dockerfile.base，则生成 base 镜像的 tag
    dockerfile_base_path="${G_REPO_DIR}/Dockerfile.base"
    dockerfile_path="${G_REPO_DIR}/Dockerfile"
    if [[ -f "${dockerfile_base_path}" ]]; then
        base_image_tag="${ENV_DOCKER_REGISTRY%/}/aa:${G_REPO_NAME}-${G_REPO_BRANCH}"
        echo "FROM ${base_image_tag}" >"${dockerfile_path}"
    fi

    ## 生成 docker-bake.hcl 文件
    target_image_tag="${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}"
    bake_file_path="${G_REPO_DIR}/docker-bake.hcl"
    generate_bake_file "${lang}" "${bake_file_path}" "${target_image_tag}" "${base_image_tag:-}"
    ## 如果是 dry-run 模式，则仅显示构建计划，不实际执行构建
    if ${DRY_RUN:-false}; then
        _msg warn "[dry-run] skip docker buildx bake, showing build plan only"
        if [[ -f "${dockerfile_base_path}" ]]; then
            echo "$G_DOCK buildx bake ${G_BUILDER:-} ${G_PROGRESS} base"
            $G_DOCK buildx bake ${G_BUILDER:-} --progress=quiet base --print
        fi
        echo "$G_DOCK buildx bake ${G_BUILDER:-} ${G_PROGRESS}"
        $G_DOCK buildx bake ${G_BUILDER:-} --progress=quiet --print
        export EXIT_MAIN=true
        return 0
    fi
    ## 如果存在 Dockerfile.base，则先构建 base 镜像
    if [[ -f "${dockerfile_base_path}" ]]; then
        echo "Found ${dockerfile_base_path}, building base image:"
        echo "  ${base_image_tag}"
        local base_build_log="${G_DATA:-.}/logs/${G_REPO_NAME}-base-build.log"
        echo "log file: $base_build_log"
        mkdir -p "$(dirname "$base_build_log")"
        $G_DOCK buildx bake ${G_BUILDER:-} --file "${bake_file_path}" ${buildx_push_option} ${G_PROGRESS} base 2>&1 | tee "$base_build_log" >/dev/null
        ret="${PIPESTATUS[0]}"
        if [ "$ret" -ne 0 ]; then
            echo "============================================================"
            _msg error "Base image build failed (exit code: $ret), showing last 100 lines of build log:"
            echo "============================================================"
            tail -100 "$base_build_log"
            _msg error "Full build log: $base_build_log"
            return 1
        fi
    fi

    # Docker build 输出到日志文件，默认不显示构建详情
    # 构建失败时显示最后100行日志便于排查
    local build_log="${G_DATA:-.}/logs/${G_REPO_NAME}-build.log"
    echo "log file: $build_log"
    mkdir -p "$(dirname "$build_log")"
    if ! run_command_with_log "$build_log" $G_DOCK buildx bake ${G_BUILDER:-} --file "${bake_file_path}" ${buildx_push_option} ${G_PROGRESS}; then
        ret=$?
        echo "============================================================"
        _msg error "Image build failed (exit code: $ret), showing last 100 lines of build log:"
        echo "============================================================"
        tail -100 "$build_log"
        _msg error "Full build log: $build_log"
        return 1
    fi
    _msg time "[build] Image build completed"

    ## 不包含敏感信息的镜像可以推送到公开仓库 push to ttl.sh
    if [[ "${PP_TTL_SH:-false}" == "true" || "${ENV_IMAGE_TTL:-false}" == "true" ]]; then
        image_uuid="ttl.sh/$(uuidgen):1h"
        echo "Temporary image tag: $image_uuid"
        $G_DOCK tag ${target_image_tag} ${image_uuid}
        $G_DOCK push $image_uuid
        echo "## Then execute the following commands on REMOTE SERVER."
        echo "  $G_DOCK pull $image_uuid"
        echo "  $G_DOCK tag $image_uuid laradock-spring"
    fi

    # auto mode:            push=1, keep=0, keep_image=
    # arg build:            push=0, keep=0, keep_image=remove
    # arg build keep:       push=0, keep=1, keep_image=keep
    # arg build push:       push=1, keep=0, keep_image=push

    # 根据参数决定是否保留当前镜像
    if [[ -z "${keep_image}" || "${keep_image}" =~ ^(remove|push)$ ]]; then
        $G_DOCK rmi "${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}" >/dev/null &
        _msg time "Image removed on $G_DOCK"
    else
        _msg time "Image keeped on $G_DOCK"
    fi
}

# Main build function that determines which specific builder to run
# Priority: Docker build (if available) > System command build
# @param $1 lang The programming language
# @param $2 keep_image Optional parameter for image retention
build_all() {
    local lang="${1:?'lang parameter is required'}"
    local keep_image="${2:-}"
    local lang_type="${lang%%:*}" # Extract language type without version/docker suffix
    local has_dockerfile=false
    local docker_build_failed=false

    _msg step "[build] Starting build process for ${lang}"

    ## 检查配置文件中的构建方式覆盖
    if [[ -n "${PROJECT_BUILD_METHOD:-}" && "${PROJECT_BUILD_METHOD}" != "auto" ]]; then
        case "${PROJECT_BUILD_METHOD}" in
        docker)
            if check_docker_available; then
                _msg info "Using configured build method: docker"
                build_image "${keep_image}" "${lang}"
                return $?
            else
                _msg error "Configured build method 'docker' but Docker is not available"
                return 1
            fi
            ;;
        system)
            _msg info "Using configured build method: system command"
            # Skip Docker check, go directly to system build
            has_dockerfile=false
            ;;
        esac
    fi

    # Check if Dockerfile exists
    for file in Dockerfile{,.*}; do
        if [[ -f "${G_REPO_DIR}/${file}" ]]; then
            has_dockerfile=true
            break
        fi
    done

    # Priority 1: Try Docker build if Dockerfile exists and Docker is available
    if [[ "$has_dockerfile" == true ]]; then
        if check_docker_available; then
            _msg info "Found Dockerfile and dockerd is available → attempting Docker build"
            # Check if lang already has :docker suffix, if not, try Docker build first
            if [[ "$lang" != *:docker ]]; then
                # Try Docker build with fallback
                if build_image "${keep_image}" "${lang}"; then
                    _msg green "Docker build completed successfully"
                    return 0
                else
                    _msg warn "Docker build failed, falling back to system command build"
                    docker_build_failed=true
                fi
            else
                # Lang already marked as docker, use Docker build directly
                build_image "${keep_image}" "${lang}"
                return $?
            fi
        else
            _msg warn "Found Dockerfile but Docker is not available, using system command build"
        fi
    fi

    # Priority 2: Use system command build
    # If Docker build was attempted and failed, or no Dockerfile/Docker available
    if [[ "$docker_build_failed" == true ]] || [[ "$has_dockerfile" != true ]] || ! check_docker_available; then
        _msg info "Using system command build for ${lang_type}"
        case "$lang_type" in
        java) build_java ;;
        node) build_node ;;
        python) build_python ;;
        android) build_android ;;
        ios) build_ios ;;
        ruby) build_ruby ;;
        go | golang) build_go ;;
        c) build_c ;;
        django) build_django ;;
        php) build_php ;;
        shell) build_shell ;;
        *)
            _msg warn "No build function available for language: $lang_type"
            return 1
            ;;
        esac
    fi
}

# Java Build
build_java() {
    local jars_path="$G_REPO_DIR/jars"

    if [[ -f "$G_REPO_DIR/build.gradle" ]]; then
        _msg time "[build] Building with gradle"
        gradle -q
    else
        _msg time "[build] Building with maven"
        local maven_settings=""
        local maven_debug=""

        [[ -f $G_REPO_DIR/settings.xml ]] && maven_settings="--settings settings.xml"
        [[ "${G_DEBUG_ON:-false}" == true ]] && maven_debug='-X'

        ## Create maven cache
        if ! $G_DOCK volume ls | grep -q maven-repo; then
            $G_DOCK volume create --name maven-repo
        fi

        $G_RUN -u 0:0 -v maven-repo:/var/maven/.m2:rw maven:"${ENV_MAVEN_VER:-3.8-jdk-8}" bash -c "chown -R 1000.1000 /var/maven"
        $G_RUN --user "$(id -u):$(id -g)" \
            -e MAVEN_CONFIG=/var/maven/.m2 \
            -v maven-repo:/var/maven/.m2:rw \
            -v "$G_REPO_DIR":/src:rw -w /src \
            maven:"${ENV_MAVEN_VER:-3.8-jdk-8}" \
            mvn -T 1C clean $maven_debug \
            --update-snapshots package \
            --define skipTests \
            --define user.home=/var/maven \
            --define maven.compile.fork=true \
            --activate-profiles "${G_REPO_BRANCH}" $maven_settings
    fi

    [ -d "$jars_path" ] || mkdir "$jars_path"

    # Move JAR files
    local jar_files=(
        "${G_REPO_DIR}"/target/*.jar
        "${G_REPO_DIR}"/*/target/*.jar
        "${G_REPO_DIR}"/*/*/target/*.jar
    )
    for jar in "${jar_files[@]}"; do
        [ -f "$jar" ] || continue
        case "$jar" in
        framework*.jar | gdp-module*.jar | sdk*.jar | *-commom-*.jar) echo 'skip' ;;
        *-dao-*.jar | lop-opensdk*.jar | core-*.jar) echo 'skip' ;;
        *) mv -vf "$jar" "$jars_path"/ ;;
        esac
    done

    # Copy YAML files if needed
    if [[ "${MVN_COPY_YAML:-false}" == true || "${exec_deploy_helm:-false}" = 'true' ]]; then
        local yml_files=(
            "${G_REPO_DIR}"/*/*/*/resources/*"${MVN_PROFILE:-main}".yml
            "${G_REPO_DIR}"/*/*/*/resources/*"${MVN_PROFILE:-main}".yaml
        )
        local c=0
        for yml in "${yml_files[@]}"; do
            [ -f "$yml" ] || continue
            c=$((c + 1))
            cp -vf "$yml" "$jars_path"/"${c}.${yml##*/}"
        done
    fi

    _msg stepend "[build] java build"
}

# Node.js Build
build_node() {
    local path_for_rsync='dist/'
    local file_json
    local file_json_md5
    local yarn_install

    file_json="${G_REPO_DIR}/package.json"
    file_json_md5="$G_REPO_GROUP_PATH/$G_NAMESPACE/$(md5sum "$file_json" | awk '{print $1}')"
    yarn_install=false

    if grep -q "$file_json_md5" "${me_log}"; then
        echo "Same checksum for ${file_json}, skip yarn install."
    else
        echo "New checksum for ${file_json}, run yarn install."
        yarn_install=true
    fi

    [ ! -d "${G_REPO_DIR}/node_modules" ] && yarn_install=true

    _msg time "[build] Running yarn install"
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && return 0

    # Custom build check
    if [ -f "$G_REPO_DIR/build.custom.sh" ]; then
        $G_RUN -u 1000:1000 -v "${G_REPO_DIR}":/app -w /app "${build_image_from:-node:18-slim}" bash build.custom.sh
        return
    fi

    # Install dependencies
    if ${yarn_install}; then
        $G_RUN -u 1000:1000 -v "${G_REPO_DIR}":/app -w /app "${build_image_from:-node:18-slim}" bash -c "yarn install" &&
            echo "$file_json_md5" >>"${me_log}"
    else
        _msg time "skip yarn install..."
    fi

    # Determine build option based on namespace
    local build_opt
    case $G_NAMESPACE in
    *uat* | *test*) build_opt=build:stage ;;
    *master* | *main* | *prod*) build_opt=build:prod ;;
    *) build_opt=build ;;
    esac

    $G_RUN -u 1000:1000 -v "${G_REPO_DIR}":/app -w /app "${build_image_from:-node:18-slim}" bash -c "yarn run ${build_opt}"

    [ -d "${G_REPO_DIR}"/build ] && rsync -a --delete "${G_REPO_DIR}"/build/ "${G_REPO_DIR}"/dist/
    _msg stepend "[build] yarn"
}

# Python Build
build_python() {
    _msg time "[build] Running python build"
    if [ -f "$G_REPO_DIR/requirements.txt" ]; then
        pip install -r requirements.txt
    fi
    _msg stepend "[build] python build"
}

# Android Build
build_android() {
    _msg time "[build] Running android build"
    if [ -f "$G_REPO_DIR/gradlew" ]; then
        chmod +x "$G_REPO_DIR/gradlew"
        "$G_REPO_DIR/gradlew" clean assembleRelease
    else
        _msg warn "No gradlew found in project"
    fi
    _msg stepend "[build] android build"
}

# iOS Build
build_ios() {
    _msg time "[build] Running iOS build"
    if [ -f "$G_REPO_DIR/Podfile" ]; then
        pod install
        xcodebuild -workspace "*.xcworkspace" -scheme "Release" build
    fi
    _msg stepend "[build] iOS build"
}

# Ruby Build
build_ruby() {
    _msg time "[build] Running ruby build"
    if [ -f "$G_REPO_DIR/Gemfile" ]; then
        bundle install
    fi
    _msg stepend "[build] ruby build"
}

# Go Build
build_go() {
    _msg time "[build] Running go build"
    go build -v ./...
    _msg stepend "[build] go build"
}

# C/C++ Build
build_c() {
    _msg time "[build] Running C/C++ build"
    if [ -f "$G_REPO_DIR/CMakeLists.txt" ]; then
        mkdir -p build && cd build || exit
        cmake ..
        make
        cd .. || exit
    elif [ -f "$G_REPO_DIR/Makefile" ]; then
        make
    fi
    _msg stepend "[build] C/C++ build"
}

# Docker Build
build_docker() {
    _msg time "[build] Running docker build"
    if [ -f "$G_REPO_DIR/Dockerfile" ]; then
        docker build -t "${G_REPO_NAME}:latest" .
    fi
    _msg stepend "[build] docker build"
}

# Django Build
build_django() {
    _msg time "[build] Running django build"
    if [ -f "$G_REPO_DIR/manage.py" ]; then
        python manage.py collectstatic --noinput
        python manage.py migrate
    fi
    _msg stepend "[build] django build"
}

# PHP Build
build_php() {
    _msg time "[build] Running php build"
    if [ -f "$G_REPO_DIR/composer.json" ]; then
        composer install --no-dev
    fi
    _msg stepend "[build] php build"
}

# Shell Build
build_shell() {
    _msg time "[build] Running shell build"
    [[ "${G_DEBUG_ON:-false}" == true ]] && return 0
    _install_shellcheck
    _install_shfmt
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        return 0
    fi
    local exit_code=0 script s=0
    command -v shellcheck >/dev/null 2>&1 && sc=true
    command -v shfmt >/dev/null 2>&1 && sf=true
    # Process shell scripts
    while IFS= read -r script; do
        echo "Processing: ${script}"

        $sc && shellcheck "$script" || exit_code=$?
        $sf && shfmt -d "$script" || exit_code=$?
        # chmod 750 "$script"
    done < <(find "$G_REPO_DIR" -type f -name "*.sh") || true

    if [ $exit_code -eq 0 ]; then
        echo "All shell scripts passed checks"
    else
        _msg error "Some shell scripts failed checks"
    fi
    _msg stepend "[build] shell build"
    return $exit_code
}

# Docker operations module for deploy.sh
# Handles Docker login, context management, image building and pushing

docker_login() {
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && return 0
    local lock_login_registry="$G_DATA/.docker.login.${ENV_DOCKER_LOGIN_TYPE:-aliyun}.lock"
    local time_last

    case "${ENV_DOCKER_LOGIN_TYPE:-aliyun}" in
    aws)
        time_last="$(stat -t -c %Y "$lock_login_registry" 2>/dev/null || echo 0)"
        ## Compare the last login time, login again after 12 hours / 比较上一次登陆时间，超过12小时则再次登录
        if [[ "$(date +%s -d '12 hours ago')" -lt "${time_last:-0}" ]]; then
            return 0
        fi
        _msg time "[login] aws ecr login [${ENV_DOCKER_LOGIN_TYPE:-aliyun}]..."
        if aws ecr get-login-password --profile="${ENV_AWS_PROFILE}" --region "${ENV_REGION_ID:?undefine}" |
            $G_DOCK login --username AWS --password-stdin "${ENV_DOCKER_REGISTRY%%/*}" >/dev/null; then
            touch "$lock_login_registry"
        else
            _msg error "AWS ECR login failed"
            return 1
        fi
        ;;
    *)
        ${DRY_RUN:-false} && return 0

        if [[ -f "$lock_login_registry" ]]; then
            return 0
        fi
        if echo "${ENV_DOCKER_PASSWORD}" |
            $G_DOCK login --username="${ENV_DOCKER_USERNAME}" --password-stdin "${ENV_DOCKER_REGISTRY%%/*}"; then
            touch "$lock_login_registry"
        else
            _msg error "Docker login failed"
            return 1
        fi
        ;;
    esac
}

# Common layers for all images
generate_base_dockerfile() {
    # Base images for different languages
    declare -A BASE_IMAGES=(
        ["java"]="eclipse-temurin:17-jre-alpine"
        ["python"]="python:3.11-slim"
        ["node"]="node:18-alpine"
        ["go"]="golang:1.20-alpine"
    )
    cat <<EOF
FROM ${BASE_IMAGES[$1]}

# Common security updates
RUN set -ex && \
    apk update --no-cache && \
    apk upgrade --no-cache

# Add non-root user
RUN adduser -D -u 1000 appuser
USER appuser

# Common environment variables
ENV TZ=Asia/Shanghai
ENV LANG=en_US.UTF-8
EOF
}

# Language specific layers
generate_lang_dockerfile() {
    local lang="$1"
    local dockerfile="Dockerfile.${lang}"

    generate_base_dockerfile "$lang" >"$dockerfile"

    case "$lang" in
    java)
        cat <<EOF >>"$dockerfile"
COPY target/*.jar app.jar
CMD ["java", "-jar", "app.jar"]
EOF
        ;;
    python)
        cat <<EOF >>"$dockerfile"
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "app.py"]
EOF
        ;;
        # 其他语言的特定配置...
    esac
}

repo_language_detect_and_build() {
    local target_dir="${1:-.}"
    local lang_type

    # 首先检测语言
    lang_type=$(repo_language_detect)

    # 根据语言选择合适的builder
    case "${lang_type%%:*}" in
    java)
        builder="gcr.io/buildpacks/builder:java"
        ;;
    python)
        builder="gcr.io/buildpacks/builder:python"
        ;;
    node)
        builder="gcr.io/buildpacks/builder:nodejs"
        ;;
    go)
        builder="gcr.io/buildpacks/builder:go"
        ;;
    php)
        builder="paketobuildpacks/builder:base"

        # 创建 project.toml 配置文件来指定 PHP 版本和扩展
        cat >"${target_dir}/project.toml" <<EOF
[[build.env]]
name = "BP_PHP_VERSION"
value = "${PHP_VERSION:-8.3}"  # 默认使用 PHP 8.3，可以通过环境变量覆盖

[[build.env]]
name = "BP_PHP_SERVER"
value = "nginx"  # 使用 nginx 作为 web 服务器

[[build.env]]
name = "BP_PHP_WEB_DIR"
value = "public"  # web 根目录，可以根据项目修改

# PHP 扩展配置
[[build.env]]
name = "BP_PHP_ENABLE_EXTENSIONS"
value = "${PHP_EXTENSIONS:-bcmath,gd,intl,pdo_mysql,redis,zip,soap}"  # 默认扩展列表，可以通过环境变量覆盖

# PECL 扩展配置
[[build.env]]
name = "BP_PHP_ENABLE_PECL_EXTENSIONS"
value = "${PHP_PECL_EXTENSIONS:-}"  # 可以通过环境变量指定 PECL 扩展

# PHP-FPM 配置
[[build.env]]
name = "BP_PHP_FPM_CONFIGURATION"
value = """
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
"""

# PHP INI 配置
[[build.env]]
name = "BP_PHP_INI_CONFIGURATION"
value = """
memory_limit = 512M
max_execution_time = 60
upload_max_filesize = 64M
post_max_size = 64M
"""
EOF

        # 如果存在自定义的 PHP 配置目录，复制配置文件
        if [ -d "${target_dir}/.php/conf.d" ]; then
            mkdir -p "${target_dir}/.php.ini.d"
            cp "${target_dir}/.php/conf.d/"*.ini "${target_dir}/.php.ini.d/" 2>/dev/null || true
        fi
        ;;
    *)
        builder="gcr.io/buildpacks/builder:base"
        ;;
    esac

    # 使用buildpack构建镜像
    pack build "${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}" \
        --builder "$builder" \
        --env BP_INCLUDE_FILES="project.toml" \
        --path "$target_dir"
}
