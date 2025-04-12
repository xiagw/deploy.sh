#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2154,2034,1090,1091,2086
################################################################################
# Description: Consolidated build functions for various programming languages
# Author: xiagw <fxiaxiaoyu@gmail.com>
# License: GNU/GPL
################################################################################

get_docker_context() {
    ## ENV_DOCKER_CONTEXT: local/remote/both
    [[ ${ENV_DOCKER_CONTEXT:-local} == local ]] && return

    local docker_contexts docker_endpoints selected_context response
    # 获取context列表
    response="$(docker context ls --format json)"
    read -ra docker_endpoints <<<"$(echo "$response" | jq -r '.DockerEndpoint' | tr '\n' ' ')"
    # 创建缺失的远程上下文
    local c=0 context_created=false
    for dk_host in "${ENV_DOCKER_CONTEXT_HOSTS[@]}"; do
        ((++c))
        if [[ ! " ${docker_endpoints[*]} " =~ ${dk_host} ]]; then
            docker context create "remote$c" --docker "host=${dk_host}" || _msg error "创建Docker上下文remote$c失败: ${dk_host}"
            context_created=true
        fi
    done

    # 如果创建了新context则刷新列表
    [[ "$context_created" = true ]] && response="$(docker context ls --format json)"
    if [[ ${ENV_DOCKER_CONTEXT:-local} == remote ]]; then
        read -ra docker_contexts <<<"$(echo "$response" | jq -r '.Name' | grep -v '^default$' | tr '\n' ' ')"
    else
        read -ra docker_contexts <<<"$(echo "$response" | jq -r '.Name' | tr '\n' ' ')"
    fi
    # 选择上下文
    case ${ENV_DOCKER_CONTEXT_ALGO:-rr} in
    rand)
        ## random algorithm / 随机算法
        selected_context="${docker_contexts[RANDOM % ${#docker_contexts[@]}]}"
        ;;
    rr)
        ## round-robin algorithm / 轮询算法
        position_file="${G_DATA:-.}/.docker_context_history"
        [[ -f "$position_file" ]] || echo 0 >"$position_file"
        # Read current position / 读取当前轮询位置
        position=$(<"$position_file")
        # Select context / 输出当前位置的值
        selected_context="${docker_contexts[position]}"
        # Update position / 更新轮询位置
        echo $((++position % ${#docker_contexts[@]})) >"$position_file"
        ;;
    esac

    G_DOCK="${G_DOCK:+"$G_DOCK "}--context $selected_context"
    echo "  $G_DOCK"
    export G_DOCK
}

build_image() {
    [ "${GH_ACTION:-false}" = "true" ] && return 0
    local keep_image="${1}" chars chars_rand base_file push_flag image_uuid

    _msg step "[build] Building image"

    get_docker_context

    ## build from build.base.sh or Dockerfile.base
    local build_sh="${G_REPO_DIR}/build.base.sh"
    if [[ -f "${build_sh}" ]]; then
        echo "Found ${build_sh}, running it..."
        ${DEBUG_ON:-false} && debug_flag="-x"
        bash "${build_sh}" $debug_flag
        export EXIT_MAIN=true
        return
    fi

    # 根据参数决定是否需要push
    if [[ -z "${keep_image}" || "${keep_image}" = 'push' ]]; then
        docker_login
        push_flag="--push"
    fi

    base_file="${G_REPO_DIR}/Dockerfile.base"
    if [[ -f "${base_file}" ]]; then
        base_tag="${ENV_DOCKER_REGISTRY%/*}/aa:${G_REPO_NAME}-${G_REPO_BRANCH}"
        echo "Found ${base_file}, building base image:"
        echo "  ${base_tag}"
        echo "FROM ${base_tag}" >"${G_REPO_DIR}/Dockerfile"
        $G_DOCK build $G_ARGS --tag "${base_tag}" ${push_flag} -f "${base_file}" "${G_REPO_DIR}"
    fi

    repo_tag="${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG}"
    # echo "$G_DOCK build $G_ARGS --tag ${repo_tag} ${push_flag} ${G_REPO_DIR}"  && exit
    $G_DOCK build $G_ARGS --tag "${repo_tag}" ${push_flag} "${G_REPO_DIR}" 2>&1 | grep -v 'error reading preface from client dummy'
    _msg time "[build] Image build completed"

    ## push to ttl.sh
    if [[ "${MAN_TTL_SH:-false}" == true ]] || ${ENV_IMAGE_TTL:-false}; then
        image_uuid="ttl.sh/$(uuidgen):1h"
        echo "Temporary image tag: $image_uuid"
        $G_DOCK tag ${repo_tag} ${image_uuid}
        $G_DOCK push $image_uuid
        echo "## Then execute the following commands on REMOTE SERVER."
        echo "  $G_DOCK pull $image_uuid"
        echo "  $G_DOCK tag $image_uuid laradock-spring"
    fi

    # auto mode:            push=1, keep=0, keep_image=
    # arg build:            push=0, keep=0, keep_image=remove
    # arg build keep:       push=0, keep=1, keep_image=keep
    # arg build push:       push=1, keep=0, keep_image=push

    # 根据参数决定是否保留镜像
    if [[ -z "${keep_image}" || "${keep_image}" =~ ^(remove|push)$ ]]; then
        $G_DOCK rmi "${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG}" >/dev/null &
        _msg time "Image removed on $G_DOCK"
    else
        _msg time "Image keeped on $G_DOCK"
    fi
}

# Main build function that determines which specific builder to run
# @param $1 lang The programming language
# @param $2 keep_image Optional parameter for image retention
build_all() {
    local lang="${1:?'lang parameter is required'}"
    local keep_image="${2:-}"

    _msg step "[build] Starting build process for ${lang}"

    # Language specific build
    case "$lang" in
    *:docker) build_image "${keep_image}" ;;
    java:*) build_java ;;
    node:*) build_node ;;
    python:*) build_python ;;
    android:*) build_android ;;
    ios:*) build_ios ;;
    ruby:*) build_ruby ;;
    go:*) build_go ;;
    c:*) build_c ;;
    django:*) build_django ;;
    php:*) build_php ;;
    shell:*) build_shell ;;
    *) _msg warn "No build function available for language: $lang" ;;
    esac
}

# Java Build
build_java() {
    local jars_path="$G_REPO_DIR/jars"

    if [[ -f "$G_REPO_DIR/build.gradle" ]]; then
        _msg step "[build] Building with gradle"
        gradle -q
    else
        _msg step "[build] Building with maven"
        local maven_settings=""
        local maven_quiet=""

        [[ -f $G_REPO_DIR/settings.xml ]] && maven_settings="--settings settings.xml"
        ${DEBUG_ON:-false} || maven_quiet='--quiet'

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
            mvn -T 1C clean $maven_quiet \
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

    _msg step "[build] Running yarn install"
    ${GH_ACTION:-false} && return 0

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
    _msg step "[build] Running python build"
    if [ -f "$G_REPO_DIR/requirements.txt" ]; then
        pip install -r requirements.txt
    fi
    _msg stepend "[build] python build"
}

# Android Build
build_android() {
    _msg step "[build] Running android build"
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
    _msg step "[build] Running iOS build"
    if [ -f "$G_REPO_DIR/Podfile" ]; then
        pod install
        xcodebuild -workspace "*.xcworkspace" -scheme "Release" build
    fi
    _msg stepend "[build] iOS build"
}

# Ruby Build
build_ruby() {
    _msg step "[build] Running ruby build"
    if [ -f "$G_REPO_DIR/Gemfile" ]; then
        bundle install
    fi
    _msg stepend "[build] ruby build"
}

# Go Build
build_go() {
    _msg step "[build] Running go build"
    go build -v ./...
    _msg stepend "[build] go build"
}

# C/C++ Build
build_c() {
    _msg step "[build] Running C/C++ build"
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
    _msg step "[build] Running docker build"
    if [ -f "$G_REPO_DIR/Dockerfile" ]; then
        docker build -t "${G_REPO_NAME}:latest" .
    fi
    _msg stepend "[build] docker build"
}

# Django Build
build_django() {
    _msg step "[build] Running django build"
    if [ -f "$G_REPO_DIR/manage.py" ]; then
        python manage.py collectstatic --noinput
        python manage.py migrate
    fi
    _msg stepend "[build] django build"
}

# PHP Build
build_php() {
    _msg step "[build] Running php build"
    if [ -f "$G_REPO_DIR/composer.json" ]; then
        composer install --no-dev
    fi
    _msg stepend "[build] php build"
}

# Shell Build
build_shell() {
    _msg step "[build] Running shell build"
    ${DEBUG_ON} && return 0
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
    ${GH_ACTION:-false} && return 0
    local lock_login_registry="$G_DATA/.docker.login.${ENV_DOCKER_LOGIN_TYPE:-none}.lock"
    local time_last

    case "${ENV_DOCKER_LOGIN_TYPE:-none}" in
    aws)
        time_last="$(stat -t -c %Y "$lock_login_registry" 2>/dev/null || echo 0)"
        ## Compare the last login time, login again after 12 hours / 比较上一次登陆时间，超过12小时则再次登录
        if [[ "$(date +%s -d '12 hours ago')" -lt "${time_last:-0}" ]]; then
            return 0
        fi
        _msg time "[login] aws ecr login [${ENV_DOCKER_LOGIN_TYPE:-none}]..."
        if aws ecr get-login-password --profile="${ENV_AWS_PROFILE}" --region "${ENV_REGION_ID:?undefine}" |
            $G_DOCK login --username AWS --password-stdin "${ENV_DOCKER_REGISTRY%%/*}" >/dev/null; then
            touch "$lock_login_registry"
        else
            _msg error "AWS ECR login failed"
            return 1
        fi
        ;;
    *)
        is_demo_mode "docker_login" && return 0

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
    pack build "${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG}" \
        --builder "$builder" \
        --env BP_INCLUDE_FILES="project.toml" \
        --path "$target_dir"
}
