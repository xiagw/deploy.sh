#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2154,2034,1090,1091,2086
################################################################################
# Description: Consolidated build functions for various programming languages
# Author: xiagw <fxiaxiaoyu@gmail.com>
# License: GNU/GPL
################################################################################

# Java Build
build_java() {
    local jars_path="$G_REPO_DIR/jars"

    if [[ -f "$G_REPO_DIR/build.gradle" ]]; then
        _msg step "[build] with gradle"
        gradle -q
    else
        _msg step "[build] with maven"
        local maven_settings=""
        local maven_quiet=""

        [[ -f $G_REPO_DIR/settings.xml ]] && maven_settings="--settings settings.xml"
        ${DEBUG_ON:-false} || maven_quiet='--quiet'

        ## Create maven cache
        if ! $DOCKER volume ls | grep -q maven-repo; then
            $DOCKER volume create --name maven-repo
        fi

        $DOCKER_RUN0 -v maven-repo:/var/maven/.m2:rw maven:"${ENV_MAVEN_VER:-3.8-jdk-8}" bash -c "chown -R 1000.1000 /var/maven"
        $DOCKER_RUN0 --user "$(id -u):$(id -g)" \
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

    _msg step "[build] yarn install"
    ${GH_ACTION:-false} && return 0

    # Custom build check
    if [ -f "$G_REPO_DIR/build.custom.sh" ]; then
        $DOCKER_RUN -v "${G_REPO_DIR}":/app -w /app "${build_image_from:-node:18-slim}" bash build.custom.sh
        return
    fi

    # Install dependencies
    if ${yarn_install}; then
        $DOCKER_RUN -v "${G_REPO_DIR}":/app -w /app "${build_image_from:-node:18-slim}" bash -c "yarn install" &&
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

    $DOCKER_RUN -v "${G_REPO_DIR}":/app -w /app "${build_image_from:-node:18-slim}" bash -c "yarn run ${build_opt}"

    [ -d "${G_REPO_DIR}"/build ] && rsync -a --delete "${G_REPO_DIR}"/build/ "${G_REPO_DIR}"/dist/
    _msg stepend "[build] yarn"
}

# Python Build
build_python() {
    _msg step "[build] python build"
    if [ -f "$G_REPO_DIR/requirements.txt" ]; then
        pip install -r requirements.txt
    fi
    _msg stepend "[build] python build"
}

# Android Build
build_android() {
    _msg step "[build] android build"
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
    _msg step "[build] iOS build"
    if [ -f "$G_REPO_DIR/Podfile" ]; then
        pod install
        xcodebuild -workspace "*.xcworkspace" -scheme "Release" build
    fi
    _msg stepend "[build] iOS build"
}

# Ruby Build
build_ruby() {
    _msg step "[build] ruby build"
    if [ -f "$G_REPO_DIR/Gemfile" ]; then
        bundle install
    fi
    _msg stepend "[build] ruby build"
}

# Go Build
build_go() {
    _msg step "[build] go build"
    go build -v ./...
    _msg stepend "[build] go build"
}

# C/C++ Build
build_c() {
    _msg step "[build] C/C++ build"
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
    _msg step "[build] docker build"
    if [ -f "$G_REPO_DIR/Dockerfile" ]; then
        docker build -t "${G_REPO_NAME}:latest" .
    fi
    _msg stepend "[build] docker build"
}

# Django Build
build_django() {
    _msg step "[build] django build"
    if [ -f "$G_REPO_DIR/manage.py" ]; then
        python manage.py collectstatic --noinput
        python manage.py migrate
    fi
    _msg stepend "[build] django build"
}

# PHP Build
build_php() {
    _msg step "[build] php build"
    if [ -f "$G_REPO_DIR/composer.json" ]; then
        composer install --no-dev
    fi
    _msg stepend "[build] php build"
}

# Shell Build
build_shell() {
    _msg step "[build] shell build"
    ${DEBUG_ON} && return 0
    local exit_code=0 script s=0
    command -v shellcheck >/dev/null 2>&1 && sc=true
    command -v shfmt >/dev/null 2>&1 && sf=true
    # Process shell scripts
    while IFS= read -r script; do
        _msg info "Processing: ${script}"

        $sc && shellcheck "$script" || exit_code=$?
        $sf && shfmt -d "$script" || exit_code=$?
        # chmod 750 "$script"
    done < <(find "$G_REPO_DIR" -type f -name "*.sh") || true

    if [ $exit_code -eq 0 ]; then
        _msg info "All shell scripts passed checks"
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
            $DOCKER login --username AWS --password-stdin "${ENV_DOCKER_REGISTRY%%/*}" >/dev/null; then
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
            $DOCKER login --username="${ENV_DOCKER_USERNAME}" --password-stdin "${ENV_DOCKER_REGISTRY%%/*}"; then
            touch "$lock_login_registry"
        else
            _msg error "Docker login failed"
            return 1
        fi
        ;;
    esac
}

get_docker_context() {
    ## use local context / 使用本地 context
    [[ ${ENV_DOCKER_CONTEXT:-local} == local ]] && return

    local docker_contexts docker_endpoints selected_context

    ## use remote context (exclude local) / 使用远程 context
    if [[ ${ENV_DOCKER_CONTEXT:-local} == remote ]]; then
        read -ra docker_contexts <<<"$(docker context ls --format json | jq -r 'select(.Name != "default") | .Name' | tr '\n' ' ')"
        read -ra docker_endpoints <<<"$(docker context ls --format json | jq -r 'select(.Name != "default") | .DockerEndpoint' | tr '\n' ' ')"
    else
        ## use local and remote context / 使用本地和远程 context
        read -ra docker_contexts <<<"$(docker context ls --format json | jq -r '.Name' | tr '\n' ' ')"
        read -ra docker_endpoints <<<"$(docker context ls --format json | jq -r '.DockerEndpoint' | tr '\n' ' ')"
    fi

    ## create context when not found remote / 没有 remote 时则根据环境变量创建
    local c=0
    for dk_host in "${ENV_DOCKER_CONTEXT_HOSTS[@]}"; do
        ((++c))
        if echo "${docker_endpoints[@]}" | grep -qw "$dk_host"; then
            : ## found docker endpoint
        else
            ## not found docker endpoint, create it
            docker context create "remote$c" --docker "host=${dk_host}" || _msg error "Failed to create docker context remote$c: ${dk_host}"
        fi
    done
    ## use remote context (exclude local) / 使用远程 context
    ## Refresh context list after potential new additions
    if [[ ${ENV_DOCKER_CONTEXT:-local} == remote ]]; then
        read -ra docker_contexts <<<"$(docker context ls --format json | jq -r 'select(.Name != "default") | .Name' | tr '\n' ' ')"
        read -ra docker_endpoints <<<"$(docker context ls --format json | jq -r 'select(.Name != "default") | .DockerEndpoint' | tr '\n' ' ')"
    else
        ## use local and remote context / 使用本地和远程 context
        read -ra docker_contexts <<<"$(docker context ls --format json | jq -r '.Name' | tr '\n' ' ')"
        read -ra docker_endpoints <<<"$(docker context ls --format json | jq -r '.DockerEndpoint' | tr '\n' ' ')"
    fi

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

    DOCKER="${DOCKER:+"$DOCKER "}--context $selected_context"
    echo "$DOCKER"
    export DOCKER
}

build_image() {
    [ "${GH_ACTION:-false}" = "true" ] && return 0
    _msg step "[image] build container image"

    get_docker_context

    ## build from Dockerfile.base
    local registry_base=${ENV_DOCKER_REGISTRY_BASE:-$ENV_DOCKER_REGISTRY}
    if [[ -f "${G_REPO_DIR}/Dockerfile.base" ]]; then
        if [[ -f "${G_REPO_DIR}/build.base.sh" ]]; then
            _msg info "Found ${G_REPO_DIR}/build.base.sh, running it..."
            ${DEBUG_ON:-false} && debug_flag="-x"
            bash "${G_REPO_DIR}/build.base.sh" $debug_flag
        else
            local base_tag="${registry_base}:${G_REPO_NAME}-${G_REPO_BRANCH}"
            _msg info "Building base image: $base_tag"
            $DOCKER build $BUILD_ARG --tag "$base_tag" \
                -f "${G_REPO_DIR}/Dockerfile.base" "${G_REPO_DIR}" || {
                _msg error "Failed to build base image"
                return 1
            }
            $DOCKER push $G_QUIET "$base_tag" || {
                _msg error "Failed to push base image"
                return 1
            }
        fi
        _msg time "[image] build base image"
        return
    fi

    $DOCKER build $BUILD_ARG --tag "${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG}" \
        "${G_REPO_DIR}" || {
        _msg error "Failed to build image"
        return 1
    }

    if [[ "${MAN_TTL_SH:-false}" == true ]] || ${ENV_IMAGE_TTL:-false}; then
        local image_uuid
        image_uuid="ttl.sh/$(uuidgen):1h"
        _msg info "Temporary image tag for ttl.sh: $image_uuid"
        echo "## If you want to push the image to ttl.sh, please execute the following commands on gitlab-runner:"
        echo "  $DOCKER tag ${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG} ${image_uuid}"
        echo "  $DOCKER push $image_uuid"
        echo "## Then execute the following commands on remote server:"
        echo "  $DOCKER pull $image_uuid"
        echo "  $DOCKER tag $image_uuid laradock_spring"
    fi
}

push_image() {
    _msg step "[image] Pushing container image"
    is_demo_mode "push_image" && return 0
    docker_login

    local push_error=false

    # Push main image
    if $DOCKER push $G_QUIET "${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG}"; then
        $DOCKER rmi "${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG}" >/dev/null
    else
        push_error=true
    fi

    # Check for errors
    if $push_error; then
        _msg error "Image push failed: network connectivity issue detected"
        _msg error "Please verify:"
        _msg error "  - Network connection is stable"
        _msg error "  - Docker registry (${ENV_DOCKER_REGISTRY}) is accessible"
        _msg error "  - Docker credentials are valid"
    fi

    _msg time "[image] Image push completed"
}

# Main build function that determines which specific builder to run
build_lang() {
    local lang="$1"
    case "$lang" in
    java) build_java ;;
    node) build_node ;;
    python) build_python ;;
    android) build_android ;;
    ios) build_ios ;;
    ruby) build_ruby ;;
    go) build_go ;;
    c) build_c ;;
    docker) build_docker ;;
    django) build_django ;;
    php) build_php ;;
    shell) build_shell ;;
    *) _msg warn "No build function available for language: $lang" ;;
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
        cat > "${target_dir}/project.toml" <<EOF
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
