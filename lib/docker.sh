#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=1090,1091,2086

# Docker operations module for deploy.sh
# Handles Docker login, context management, image building and pushing

docker_login() {
    ${GITHUB_ACTION:-false} && return 0
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
        is_demo_mode "docker-login" && return 0

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
}

build_image() {
    ${GITHUB_ACTION:-false} && return 0
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
            $DOCKER build $DOCKER_OPT \
                --tag "$base_tag" $BUILD_ARG \
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

    $DOCKER build $DOCKER_OPT \
        --tag "${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG}" $BUILD_ARG \
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
    is_demo_mode "push-image" && return 0
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
