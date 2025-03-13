#!/usr/bin/env bash
# shellcheck disable=1090,1091
# -*- coding: utf-8 -*-
#
# Deployment module for handling various deployment methods
# Including Kubernetes, Aliyun Functions, Rsync, FTP, etc.

format_release_name() {
    if ${ENV_REMOVE_PROJ_PREFIX:-false}; then
        echo "remove project name prefix-"
        release_name=${G_REPO_NAME#*-}
    else
        release_name=${G_REPO_NAME}
    fi
    ## Convert to lower case / 转换为小写
    release_name="${release_name,,}"
    ## remove space / 去除空格
    release_name="${release_name// /}"
    ## replace special characters / 替换特殊字符
    release_name="${release_name//[@#$%^&*_.\/]/-}"
    ## start with numbers / 开头是数字
    if [[ "$release_name" == [0-9]* ]]; then
        release_name="a${release_name}"
    fi
    ## characters greate than 15 / 字符大于 15
    # if [[ ${#release_name} -gt 15 ]]; then
    #     ## replace - with '' / 替换 - 为 ''
    #     release_name="${release_name//-/}"
    # fi
    # if [[ ${#release_name} -gt 15 ]]; then
    #     ## cut 15 characters / 截取 15 个字符
    #     release_name="${release_name:0:15}"
    # fi
}

# Deploy to Aliyun Functions
# @param $1 lang The programming language of the project
deploy_aliyun_functions() {
    if "${ENV_DISABLE_K8S:-false}"; then
        _msg time "Kubernetes deployment is disabled"
        return
    fi
    local lang="${1:?'lang parameter is required'}"
    _install_aliyun_cli
    format_release_name
    ${GH_ACTION:-false} && return 0
    ${ENV_ENABLE_FUNC:-false} || {
        _msg time "Aliyun Functions deployment is disabled"
        return 0
    }
    [ "${G_NAMESPACE}" != main ] && release_name="${release_name}-${G_NAMESPACE}"

    ## create FC
    _msg step "[deploy] Creating/updating Aliyun Functions"
    local functions_conf_tmpl="$G_DATA/aliyun.functions.${lang}.json"
    local functions_conf="$G_DATA/aliyun.functions.json"
    if [ -f "$functions_conf_tmpl" ]; then
        TEMPLATE_NAME=$release_name TEMPLATE_REGISTRY=${ENV_DOCKER_REGISTRY} TEMPLATE_TAG=${G_IMAGE_TAG} envsubst <"$functions_conf_tmpl" >"$functions_conf"
    else
        functions_conf="$(mktemp)"
        cat >"$functions_conf" <<EOF
{
    "functionName": "$release_name",
    "runtime": "custom-container",
    "internetAccess": false,
    "cpu": 0.3,
    "memorySize": 512,
    "diskSize": 512,
    "handler": "index.handler",
    "instanceConcurrency": 200,
    "customContainerConfig": {
        "image": "${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG}",
        "port": 8080,
        "healthCheckConfig": {
            "initialDelaySeconds": 5
        }
    }
}
EOF
    fi

    if aliyun -p "${ENV_ALIYUN_PROFILE-}" fc GET /2023-03-30/functions --prefix "${release_name:0:3}" --limit 100 --header "Content-Type=application/json;" | jq -r '.functions[].functionName' | grep -qw "${release_name}$"; then
        _msg time "Updating function: $release_name"
        aliyun -p "${ENV_ALIYUN_PROFILE-}" --quiet fc PUT /2023-03-30/functions/"$release_name" --header "Content-Type=application/json;" --body "{\"tracingConfig\":{},\"customContainerConfig\":{\"image\":\"${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG}\"}}"
    else
        _msg time "Creating new function: $release_name"
        aliyun -p "${ENV_ALIYUN_PROFILE-}" --quiet fc POST /2023-03-30/functions --header "Content-Type=application/json;" --body "$(cat "$functions_conf")"
        _msg time "Creating HTTP trigger for function: $release_name"
        aliyun -p "${ENV_ALIYUN_PROFILE-}" --quiet fc POST /2023-03-30/functions/"$release_name"/triggers --header "Content-Type=application/json;" --body "{\"triggerType\":\"http\",\"triggerName\":\"defaultTrigger\",\"triggerConfig\":\"{\\\"methods\\\":[\\\"GET\\\",\\\"POST\\\",\\\"PUT\\\",\\\"DELETE\\\",\\\"OPTIONS\\\"],\\\"authType\\\":\\\"anonymous\\\",\\\"disableURLInternet\\\":false}\"}"
    fi
    rm -f "$functions_conf"

    _msg time "Aliyun Functions deployment completed"
}

# Deploy to Kubernetes cluster
deploy_to_kubernetes() {
    _msg step "[deploy] Deploy to Kubernetes with Helm"
    is_demo_mode "deploy_k8s" && return 0
    format_release_name

    # Ensure PVC exists before proceeding with deployment
    # kube_check_pv_pvc

    ## finding helm files folder / 查找 helm 文件目录
    helm_dirs=(
        "$G_REPO_DIR/helm/${release_name}"
        "$G_REPO_DIR/docs/helm/${release_name}"
        "$G_REPO_DIR/doc/helm/${release_name}"
        "${G_DATA}/helm/${G_REPO_GROUP_PATH_SLUG}/${G_NAMESPACE}/${release_name}"
        "${G_DATA}/helm/${G_REPO_GROUP_PATH_SLUG}/${release_name}"
        "${G_DATA}/helm/${release_name}"
    )
    for dir in "${helm_dirs[@]}"; do
        if [ -d "$dir" ]; then
            helm_dir="$dir"
            break
        fi
    done
    ## create helm charts / 创建 helm 文件
    if [ -z "$helm_dir" ]; then
        _msg purple "No Helm charts found in standard locations"
        echo "Generating new Helm charts"
        helm_dir="${G_DATA}/helm/${G_REPO_GROUP_PATH_SLUG}/${release_name}"
        mkdir -p "$helm_dir"
        create_helm_chart "${helm_dir}"
    fi

    echo "helm upgrade --install --history-max 1 ${release_name} $helm_dir/ --namespace ${G_NAMESPACE} --set image.repository=${ENV_DOCKER_REGISTRY} --set image.tag=${G_IMAGE_TAG}" | sed "s#$HOME#\$HOME#g" | tee -a "$G_LOG"
    ${GH_ACTION:-false} && return 0

    ## helm install / helm 安装  --atomic
    $HELM_OPT upgrade --install --history-max 1 \
        "${release_name}" "$helm_dir/" \
        --namespace "${G_NAMESPACE}" --create-namespace \
        --timeout 120s --set image.pullPolicy='Always' \
        --set image.repository="${ENV_DOCKER_REGISTRY}" \
        --set image.tag="${G_IMAGE_TAG}" >/dev/null || return 1

    echo "Monitoring deployment status for ${release_name} in namespace ${G_NAMESPACE} (timeout: 120s)..."
    # 检查是否在忽略列表中
    if echo "${ENV_IGNORE_DEPLOY_CHECK[*]}" | grep -qw "${G_REPO_NAME}"; then
        _msg purple "Skipping deployment check for ${G_REPO_NAME} as it's in the ignore list"
    else
        if ! $KUBECTL_OPT -n "${G_NAMESPACE}" rollout status deployment "${release_name}" --timeout 120s >/dev/null; then
            deploy_result=1
            _msg red "Deployment probe timed out. Please check container status and logs in Kubernetes"
            _msg red "此处探测超时，无法判断应用是否正常，请检查k8s内容器状态和日志"
        fi
    fi

    ## Clean up rs 0 0 / 清理 rs 0 0
    {
        $KUBECTL_OPT -n "${G_NAMESPACE}" get rs | awk '$2=="0" && $3=="0" && $4=="0" {print $1}' |
            xargs -t -r $KUBECTL_OPT -n "${G_NAMESPACE}" delete rs >/dev/null 2>&1 || true
        $KUBECTL_OPT -n "${G_NAMESPACE}" get pod | awk '/Evicted/ {print $1}' |
            xargs -t -r $KUBECTL_OPT -n "${G_NAMESPACE}" delete pod 2>/dev/null || true
    } &

    if [ -f "$G_REPO_DIR/deploy.custom.sh" ]; then
        _msg time "Executing custom deployment script"
        source "$G_REPO_DIR/deploy.custom.sh"
    fi

    _msg time "Kubernetes deployment completed"
    return "${deploy_result:-0}"
}

# Deploy via Rsync+SSH
# @param $1 lang The programming language of the project
deploy_via_rsync_ssh() {
    local lang="${1:?'lang parameter is required'}"
    _msg step "[deploy] Deploy files with Rsync+SSH"
    ## rsync exclude configuration
    rsync_exclude="${G_REPO_DIR}/rsync.exclude"
    [[ ! -f "$rsync_exclude" ]] && rsync_exclude="${G_PATH}/conf/rsync.exclude"

    # 检查配置文件格式并设置解析工具
    local parse_cmd
    if [[ "${G_CONF}" =~ \.(yaml|yml)$ ]]; then
        parse_cmd="yq"
    elif [[ "${G_CONF}" =~ \.json$ ]]; then
        parse_cmd="jq"
    else
        _msg error "Unsupported configuration file format: ${G_CONF}"
        return 1
    fi
    if ! $parse_cmd -e ".projects[] | select(.project == \"${G_REPO_GROUP_PATH}\") | .branches[] | select(.branch == \"${G_NAMESPACE}\") | .hosts[]" "$G_CONF"; then
        _msg warn "No host configuration found for project '${G_REPO_GROUP_PATH}' branch '${G_NAMESPACE}' in $G_CONF"
    fi

    while read -r line; do
        if [[ "$parse_cmd" == "yq" ]]; then
            ssh_host=$(echo "$line" | yq -r '.ssh_host // ""')
            ssh_port=$(echo "$line" | yq -r '.ssh_port // "22"')
            rsync_src_from_conf=$(echo "$line" | yq -r '.rsync_src // ""')
            rsync_dest=$(echo "$line" | yq -r '.rsync_dest // ""')
        else
            ssh_host=$(echo "$line" | jq -r '.ssh_host // empty')
            ssh_port=$(echo "$line" | jq -r '.ssh_port // "22"')
            rsync_src_from_conf=$(echo "$line" | jq -r '.rsync_src // empty')
            rsync_dest=$(echo "$line" | jq -r '.rsync_dest // empty')
        fi

        [[ -z "$ssh_host" ]] && {
            _msg error "ssh_host is required but not found in config"
            continue
        }

        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=10 -p ${ssh_port:-22}"

        case "$lang" in
        java) rsync_relative_path="jars/" ;;
        node) rsync_relative_path="dist/" ;;
        *) rsync_relative_path="" ;;
        esac

        if [[ -n "$rsync_src_from_conf" ]]; then
            rsync_src="${rsync_src_from_conf%/}/"
            _msg info "Using configured source path: $rsync_src"
        else
            rsync_src="${G_REPO_DIR%/}/${rsync_relative_path:+${rsync_relative_path%/}/}"
            _msg info "Using default source path: $rsync_src"
        fi

        rsync_opt="rsync -acvzt --timeout=10 --no-times --exclude-from=${rsync_exclude}"
        [[ "$lang" == "node" ]] && rsync_opt+=" --delete"

        if [[ "$rsync_dest" == "none" || -z "$rsync_dest" ]]; then
            rsync_dest="${ENV_PATH_DEST_PRE}/${G_NAMESPACE}_${G_REPO_NAME}/"
        fi

        if [[ "${rsync_dest}" =~ 'oss://' ]]; then
            if is_demo_mode "deploy_aliyun_oss"; then
                _msg purple "Demo mode: Aliyun OSS deployment simulation:"
                _msg purple "  Source: ${rsync_src}"
                _msg purple "  Destination: ${rsync_dest}"
                continue
            fi
            deploy_aliyun_oss "${rsync_src}" "${rsync_dest}"
            continue
        fi

        _msg info "Deploying to ${ssh_host}:${rsync_dest}"
        if is_demo_mode "deploy_rsync_ssh"; then
            _msg purple "Demo mode: Command simulation:"
            _msg purple "  $ssh_opt -n \"$ssh_host\" \"mkdir -p $rsync_dest\""
            _msg purple "  ${rsync_opt} -e \"$ssh_opt\" \"$rsync_src\" \"${ssh_host}:${rsync_dest}\""
            continue
        fi
        $ssh_opt -n "$ssh_host" "mkdir -p $rsync_dest"
        ${rsync_opt} -e "$ssh_opt" "$rsync_src" "${ssh_host}:${rsync_dest}"

        if [[ -f "${G_DATA}/bin/deploy.custom.sh" ]]; then
            _msg time "Executing custom deployment script"
            bash "${G_DATA}/bin/deploy.custom.sh" "$ssh_host" "$rsync_dest"
            _msg time "Custom deployment completed"
        fi

        if ${exec_deploy_docker_compose:-false}; then
            _msg step "[deploy] Deploying with Docker Compose"
            $ssh_opt -n "$ssh_host" "cd docker/laradock && docker compose up -d $G_REPO_NAME"
        fi
    done < <(
        if [[ "$parse_cmd" == "yq" ]]; then
            yq -o=json -I=0 ".projects[] | select(.project == \"${G_REPO_GROUP_PATH}\") | .branches[] | select(.branch == \"${G_NAMESPACE}\") | .hosts[] | select(. != null)" "$G_CONF"
        else
            jq -c ".projects[] | select(.project == \"${G_REPO_GROUP_PATH}\") | .branches[] | select(.branch == \"${G_NAMESPACE}\") | .hosts[] | select(. != null)" "$G_CONF"
        fi
    )
}

# Deploy to Aliyun OSS
# @param $1 source_path The source path to upload from
# @param $2 oss_dest The OSS destination path (format: oss://bucket-name/path)
deploy_aliyun_oss() {
    local source_path="${1:?'source_path parameter is required'}"
    local oss_dest="${2:?'oss_dest parameter is required (format: oss://bucket-name/path)'}"

    _msg step "[deploy] Deploy files to Aliyun OSS"
    _install_ossutil

    _msg time "Starting file transfer"
    if ossutil cp "${source_path}/" "${oss_dest}" --recursive --force; then
        _msg green "Deployment successful"
    else
        _msg error "Deployment failed"
    fi
    _msg time "Aliyun OSS deployment completed"
}

# Deploy via Rsync
deploy_via_rsync() {
    _msg step "[deploy] Deploy files to Rsyncd server"
    rsyncd_conf="$G_DATA/rsyncd.conf"
    source "$rsyncd_conf"

    rsync_options="rsync -avz"
    $rsync_options --exclude-from="$EXCLUDE_FILE" "$SOURCE_DIR/" "$RSYNC_USER@$RSYNC_HOST::$TARGET_DIR"
}

# Deploy via FTP
deploy_via_ftp() {
    _msg step "[deploy] Deploy files to FTP server"
    upload_file="${G_REPO_DIR}/ftp.tgz"
    tar czvf "${upload_file}" -C "${G_REPO_DIR}" .
    ftp -inv "${ssh_host}" <<EOF
user $FTP_USERNAME $FTP_PASSWORD
cd $FTP_DIRECTORY
passive on
binary
delete $upload_file
put $upload_file
passive off
bye
EOF
    _msg time "FTP deployment completed"
}

# Deploy via SFTP
deploy_via_sftp() {
    _msg step "[deploy] Deploy files to SFTP server"
    # TODO: Implement SFTP deployment
}

# Determine the deployment method based on project files
# @param $1 repo_dir Repository directory to check
# Sets deployment related flags based on found files
# Returns:
#   deploy_method: The determined deployment method (rsync_ssh/docker-compose/helm)
determine_deployment_method() {
    local file deploy_method=deploy_rsync_ssh

    for file in Dockerfile{,.*} docker-compose.{yml,yaml} deploy.method.*; do
        [[ -f "${G_REPO_DIR}/${file}" ]] || continue

        case $file in
        docker-compose.yml)
            deploy_method=deploy_docker
            break
            ;;
        Dockerfile | Dockerfile*)
            deploy_method=deploy_k8s
            ;;
        esac
    done
    echo "$deploy_method"
    return 0
}

# Main deployment function
handle_deploy() {
    local type="${1:-}"
    shift

    # 如果没有指定部署方法，先进行探测
    if [ -z "$type" ]; then
        type=$(determine_deployment_method "$@")
    fi

    case "$type" in
    deploy_k8s)
        deploy_to_kubernetes "$@"
        ;;
    deploy_docker)
        deploy_to_docker_compose "$@"
        ;;
    deploy_aliyun_func)
        deploy_aliyun_functions "$@"
        ;;
    deploy_aliyun_oss)
        deploy_aliyun_oss "$@"
        ;;
    deploy_rsync)
        deploy_via_rsync "$@"
        ;;
    deploy_ftp)
        deploy_via_ftp "$@"
        ;;
    deploy_sftp)
        deploy_via_sftp "$@"
        ;;
    deploy_rsync_ssh)
        deploy_via_rsync_ssh "$@"
        ;;
    *)
        _msg error "Unknown or invalid deployment method: $type"
        return 1
        ;;
    esac
}

# Export the function
# export -f determine_deployment_method

# Copy Docker image from source to target registry
# @param $1 source_image Source image name (e.g., nginx:latest)
# @param $2 target_registry Target registry (e.g., registry.example.com)
copy_docker_image() {
    local source_image="$1" target_registry="$2" image_name tag target

    if ! command -v skopeo >/dev/null 2>&1; then
        _msg error "skopeo command not found. Please install skopeo first."
        return 1
    fi

    if [[ -z "$source_image" || -z "$target_registry" ]]; then
        _msg error "Missing required parameters"
        _msg error "Usage: copy_docker_image source_image target_registry"
        _msg error "Example: copy_docker_image nginx:latest registry.example.com"
        return 1
    fi

    # 如果镜像标签是 latest，则移除它
    image_name="${source_image%:latest}"
    # 将路径中的 / 替换为 -
    tag="${image_name//\//-}"
    # 将剩余的 : 替换为 -
    tag="${tag//:/-}"
    # 构建最终的目标镜像名
    target="${target_registry}:${tag}"

    _msg info "Copying multi-arch image from Docker Hub to custom registry..."
    _msg info "Source: ${source_image}"
    _msg info "Target: ${target}"

    # Copy all available platforms
    # skopeo copy --multi-arch index-only "docker://docker.io/${source_image}" "docker://${target}"
    skopeo copy "docker://docker.io/${source_image}" "docker://${target}"

    echo "Successfully copied multi-arch image ${source_image} to ${target}"
}

# Example usage:
# copy_docker_image "nginx:latest" "registry.example.com"  # -> registry.example.com:nginx
# copy_docker_image "nginx" "registry.example.com"        # -> registry.example.com:nginx
# copy_docker_image "ubuntu:22.04" "registry.example.com" # -> registry.example.com:ubuntu-22.04

# copy_docker_image "$@"
