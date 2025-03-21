#!/usr/bin/env bash
# shellcheck disable=1090,1091
# -*- coding: utf-8 -*-
#
# Deployment module for handling various deployment methods
# Including Kubernetes, Aliyun Functions, Rsync, FTP, etc.

format_release_name() {
    local release_name
    if ${ENV_REMOVE_PROJ_PREFIX:-false}; then
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
        release_name="n${release_name}"
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
    echo "${release_name}"
}

# Deploy to Kubernetes cluster
deploy_to_kubernetes() {
    _msg step "[deploy] Deploy to Kubernetes with Helm"
    is_demo_mode "deploy_k8s" && return 0
    local release_name previous_image rs0 bad_pod revision
    release_name="$(format_release_name)"

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
        _msg purple "Helm charts not exist, generating new Helm charts"
        helm_dir="${G_DATA}/helm/${G_REPO_GROUP_PATH_SLUG}/${release_name}"
        mkdir -p "$helm_dir"
        create_helm_chart "${helm_dir}"
    fi

    echo "helm upgrade ${release_name} $helm_dir/ -i -n ${G_NAMESPACE} --history-max 1 --set image.repository=${ENV_DOCKER_REGISTRY},image.tag=${G_IMAGE_TAG}" | sed "s#$HOME#\$HOME#g" | tee -a "$G_LOG"
    ${GH_ACTION:-false} && return 0

    ## helm install / helm 安装  --atomic
    $HELM_OPT upgrade "${release_name}" "$helm_dir/" --install --history-max 1 --hide-notes \
        --namespace "${G_NAMESPACE}" --create-namespace --timeout 120s --set image.pullPolicy='Always' \
        --set "image.repository=${ENV_DOCKER_REGISTRY},image.tag=${G_IMAGE_TAG}" >/dev/null || return 1

    # 检查是否在忽略列表中（不探测发布结果）
    if echo "${ENV_IGNORE_DEPLOY_CHECK[*]}" | grep -qw "${G_REPO_NAME}"; then
        _msg purple "Skipping deployment check for ${G_REPO_NAME} as it's in the ignore list"
    else
        _msg time "Monitoring [${release_name}] in [${G_NAMESPACE}] (timeout: 120s)"
        if ! $KUBECTL_OPT -n "${G_NAMESPACE}" rollout status deployment "${release_name}" --timeout 120s >/dev/null; then
            deploy_result=1
            _msg red "Deployment probe timed out. Please check container status and logs in Kubernetes"
            _msg red "此处探测超时，无法判断应用是否正常，请检查k8s内容器状态和日志"
            revision="$(helm -n "${G_NAMESPACE}" history "${release_name}" | awk 'END {print $1}')"
            echo "helm -n ${G_NAMESPACE} rollback ${release_name} $((revision - 1))" | tee -a "$G_LOG"
        fi
    fi

    # Record current image info / 记录当前镜像信息
    local image_record_file="${G_DATA}/image_logs/${release_name}_last_image"
    local current_image="${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG}"
    # Read and delete previous image if exists / 如果存在则读取并删除上一个镜像
    if [[ -f "${image_record_file}" && "${deploy_result:-0}" -eq 0 ]]; then
        previous_image=$(cat "${image_record_file}")
        if [[ -n "${previous_image}" && "${previous_image}" != "${current_image}" ]]; then
            _msg time "Deleting previous image: ${previous_image}"
            skopeo delete "docker://${previous_image}"
        fi
    fi

    # Save current image info / 保存当前镜像信息
    echo "${current_image}" >"${image_record_file}"

    ## Clean up rs 0 0 / 清理 rs 0 0
    {
        while read -r rs0; do
            $KUBECTL_OPT -n "${G_NAMESPACE}" delete rs "${rs0}" &>/dev/null || true
        done < <($KUBECTL_OPT -n "${G_NAMESPACE}" get rs | awk '$2=="0" && $3=="0" && $4=="0" {print $1}')
        while read -r bad_pod; do
            $KUBECTL_OPT -n "${G_NAMESPACE}" delete pod "${bad_pod}" &>/dev/null || true
        done < <(
            $KUBECTL_OPT -n "${G_NAMESPACE}" get pod | awk '/Evicted/ {print $1}'
        )
    } &

    if [ -f "$G_REPO_DIR/deploy.custom.sh" ]; then
        _msg time "Executing custom deployment script"
        source "$G_REPO_DIR/deploy.custom.sh"
    fi

    _msg time "Kubernetes deployment completed"
    return "${deploy_result:-0}"
}

# Deploy to Aliyun Functions
# @param $1 lang The programming language of the project
deploy_aliyun_functions() {
    if "${ENV_DISABLE_K8S:-false}"; then
        _msg time "Kubernetes deployment is disabled"
        return
    fi
    local release_name lang functions_conf_tmpl functions_conf
    lang="${1:?'lang parameter is required'}"
    _install_aliyun_cli
    release_name="$(format_release_name)"

    ${GH_ACTION:-false} && return 0
    ${ENV_ENABLE_FUNC:-false} || {
        _msg time "Aliyun Functions deployment is disabled"
        return 0
    }
    [ "${G_NAMESPACE}" != main ] && release_name="${release_name}-${G_NAMESPACE}"

    ## create FC
    _msg step "[deploy] Creating/updating Aliyun Functions"
    functions_conf_tmpl="$G_DATA/aliyun.functions.${lang}.json"
    functions_conf="$G_DATA/aliyun.functions.json"
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

# Deploy via Rsync+SSH
# @param $1 lang The programming language of the project
deploy_via_rsync_ssh() {
    local lang="${1:?'lang parameter is required'}" parse_cmd
    _msg step "[deploy] Deploy files with Rsync+SSH"
    ## rsync exclude configuration
    rsync_exclude="${G_REPO_DIR}/rsync.exclude"
    [[ ! -f "$rsync_exclude" ]] && rsync_exclude="${G_PATH}/conf/rsync.exclude"

    # 检查配置文件格式并设置解析工具
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
            echo "Using configured source path: $rsync_src"
        else
            rsync_src="${G_REPO_DIR%/}/${rsync_relative_path:+${rsync_relative_path%/}/}"
            echo "Using default source path: $rsync_src"
        fi

        rsync_opt="rsync -acvzt --timeout=10 --no-times --exclude-from=${rsync_exclude}"
        [[ "$lang" == "node" ]] && rsync_opt+=" --delete"

        if [[ "$rsync_dest" == "none" || -z "$rsync_dest" ]]; then
            rsync_dest="${ENV_PATH_DEST_PRE}/${G_NAMESPACE}_${G_REPO_NAME}/"
        fi

        if [[ "${rsync_dest}" =~ 'oss://' ]]; then
            if is_demo_mode "deploy_aliyun_oss"; then
                echo "Demo mode: Aliyun OSS deployment simulation:"
                _msg purple "  Source: ${rsync_src}"
                _msg purple "  Destination: ${rsync_dest}"
                continue
            fi
            deploy_aliyun_oss "${rsync_src}" "${rsync_dest}"
            continue
        fi

        echo "Deploying to ${ssh_host}:${rsync_dest}"
        if is_demo_mode "deploy_rsync_ssh"; then
            echo "Demo mode: Command simulation:"
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
# @param $3 keep_original_tag Whether to keep the original tag (true/false, default: true)
copy_docker_image() {
    local source_image="$1" target_registry="$2" keep_original_tag="${3:-true}" image_name tag target

    if ! command -v skopeo >/dev/null 2>&1; then
        _msg error "skopeo command not found. Please install skopeo first."
        return 1
    fi

    # 移除 target_registry 末尾的斜杠（如果有）
    target_registry="${target_registry%/}"

    if [[ "$keep_original_tag" == "true" ]]; then
        # 保持原始标签，使用 / 分隔符
        image_name="${source_image%:*}"
        tag="${source_image#*:}"
        # 如果没有标签，使用 latest
        [[ "$image_name" == "$source_image" ]] && tag="latest"
        # 移除可能存在的 docker.io/ 前缀
        image_name="${image_name#docker.io/}"
        # 移除 image_name 开头和结尾的斜杠（如果有）
        image_name="${image_name#/}"
        image_name="${image_name%/}"
        # 构建最终的目标镜像名（使用 / 分隔符）
        target="${target_registry}/${image_name}:${tag}"
    else
        # 原有的标签转换逻辑
        # 如果镜像标签是 latest，则移除它
        image_name="${source_image%:latest}"
        # 将路径中的 / 替换为 -
        tag="${image_name//\//-}"
        # 将剩余的 : 替换为 -
        tag="${tag//:/-}"
        # 构建最终的目标镜像名（使用 : 分隔符）
        target="${target_registry}:${tag}"
    fi

    echo "Copying multi-arch image from Docker Hub to custom registry..."
    echo "skopeo --override-os linux copy --multi-arch all docker://docker.io/${source_image} docker://${target}"

    skopeo --override-os linux copy --multi-arch all \
        "docker://docker.io/${source_image}" \
        "docker://${target}"
}

# Example usage:
# copy_docker_image "nginx:latest" "registry.example.com/ns"         # -> registry.example.com/ns/nginx:latest
# copy_docker_image "nginx:latest" "registry.example.com/ns" false  # -> registry.example.com/ns:nginx
# copy_docker_image "nginx" "registry.example.com/ns"              # -> registry.example.com/ns/nginx:latest
# copy_docker_image "ubuntu:22.04" "registry.example.com/ns"       # -> registry.example.com/ns/ubuntu:22.04
# copy_docker_image "ubuntu:22.04" "registry.example.com/ns" false # -> registry.example.com/ns:ubuntu-22.04

# Clean old tags from registry / 清理注册表中的旧标签
# This function removes tags older than 6 months from a specified Docker registry repository
# 此函数从指定的 Docker 注册表仓库中删除 6 个月以前的标签
#
# @param $1 repository The repository to clean / 要清理的仓库
# @return 0 on success, 1 on failure / 成功返回 0，失败返回 1
#
# Example usage / 使用示例:
# clean_old_tags "registry.example.com/myapp"
clean_old_tags() {
    # Required parameter validation / 必需参数验证
    local repository="${1:?'repository parameter is required'}" cutoff_time current_time tags_file tags_to_delete=()

    _msg step "[clean] Cleaning old tags from registry"

    # Calculate cutoff time (6 months ago in seconds) / 计算截止时间（6个月前的秒数）
    current_time=$(date +%s)
    cutoff_time=$((current_time - 180 * 24 * 60 * 60))

    # Get all tags using skopeo / 使用 skopeo 获取所有标签
    tags_file=$(mktemp)
    echo "tags file is: ${tags_file}"
    if ! skopeo list-tags "docker://${repository}" >"$tags_file"; then
        _msg error "Failed to get tags from registry / 从注册表获取标签失败"
        rm -f "$tags_file"
        return 1
    fi
    if [[ "${repository}" =~ flyh6/flyh6 ]]; then
        delete_force=true
    fi

    # Parse tags and check timestamps / 解析标签并检查时间戳
    while read -r tag; do
        # Skip empty tags / 跳过空标签
        [ -z "$tag" ] && continue

        # Try to extract timestamp from tag / 尝试从标签中提取时间戳
        # .*-([0-9]+)$ means:
        # .* - match any characters
        # -  - match a hyphen
        # ([0-9]+) - capture one or more digits (stored in BASH_REMATCH[1])
        # $ - ensure the digits are at the end
        if [[ "$tag" =~ .*-([0-9]+)$ ]]; then
            # BASH_REMATCH[0] contains the entire match
            # BASH_REMATCH[1] contains just the captured digits
            tag_timestamp="${BASH_REMATCH[1]}"

            # Validate timestamp range (from 2000-01-01 to now) / 验证时间戳范围（从2000-01-01到现在）
            if [ "$tag_timestamp" -lt 946684800 ] || [ "$tag_timestamp" -gt "$current_time" ]; then
                _msg warn "Invalid timestamp range, will delete: $tag"
                tags_to_delete+=("$tag")
                continue
            fi

            # Compare with cutoff time / 与截止时间比较
            if [ "$tag_timestamp" -lt "$cutoff_time" ]; then
                tags_to_delete+=("$tag")
            fi
        else
            if [[ "${delete_force}" = true ]]; then
                # Tag without timestamp will also be deleted / 没有时间戳的标签也会被删除
                _msg warn "Tag without timestamp, will delete: $tag"
                tags_to_delete+=("$tag")
                continue
            fi
        fi
    done < <(jq -r '.Tags[]' "$tags_file")

    # Print summary / 打印摘要
    total_tags=$(jq '.Tags | length' "$tags_file")
    _msg time "Total tags / 总标签数: $total_tags"
    _msg time "Tags to delete / 要删除的标签数: ${#tags_to_delete[@]}"

    # Clean up temporary file / 清理临时文件
    rm -f "$tags_file"

    # Delete old tags / 删除旧标签
    if [ "${#tags_to_delete[@]}" -gt 0 ]; then
        _msg time "Deleting old tags... / 正在删除旧标签..."
        for tag in "${tags_to_delete[@]}"; do
            _msg purple "Deleting / 正在删除: $tag"
            if ! skopeo delete "docker://${repository}:${tag}"; then
                _msg warn "Failed to delete tag / 删除标签失败: $tag"
            fi
        done
    else
        _msg time "No old tags to delete / 没有需要删除的旧标签"
    fi
}
