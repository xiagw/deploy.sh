#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2154,2034

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

        $DOCKER run --rm -i -v maven-repo:/var/maven/.m2:rw maven:"${ENV_MAVEN_VER:-3.8-jdk-8}" bash -c "chown -R 1000.1000 /var/maven"
        $DOCKER run --rm -i --user "$(id -u):$(id -g)" \
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
    ${GITHUB_ACTION:-false} && return 0

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

# Main build function that determines which specific builder to run
build_lang() {
    local lang="$1" action="$2"
    if [[ "${action}" =~ ^(helm|docker)$ ]]; then
        return 0
    fi
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
    *) _msg warn "No build function available for language: $lang" ;;
    esac
}
