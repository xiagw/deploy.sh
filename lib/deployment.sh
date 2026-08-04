#!/usr/bin/env bash
# shellcheck disable=1090,1091
# -*- coding: utf-8 -*-
#
# Deployment module for handling various deployment methods
# Including Kubernetes, Aliyun Functions, Rsync, FTP, etc.

format_release_name() {
    local release_name
    if ${ENV_REMOVE_HELM_PREFIX:-false}; then
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

# Execute optional project-level custom deployment hook.
# The hook is sourced so it can access deployment variables like
# G_NAMESPACE, release_name, and other environment state.
# If the hook is absent, this is a no-op.
execute_custom_deploy_hook() {
    local custom_script="${G_REPO_DIR}/deploy.custom.sh"
    if [[ -f "${custom_script}" ]]; then
        _msg time "Executing custom deployment script: ${custom_script}"
        source "${custom_script}"
    fi
}

# Record the currently deployed image reference for this release/namespace,
# and optionally delete the previous image if the deployment succeeded.
record_deployed_image() {
    local release_name="${1:?release_name is required}"
    local deploy_result="${2:-0}"
    local image_record_dir="${G_DATA}/image_records"
    local current_image="${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}"
    local image_record_file="${image_record_dir}/${release_name}-${G_NAMESPACE}.current"

    mkdir -p "${image_record_dir}"

    if [[ -f "${image_record_file}" && "${deploy_result}" -eq 0 ]]; then
        local previous_image
        previous_image=$(<"${image_record_file}")
        if [[ -n "${previous_image}" && "${previous_image}" != "${current_image}" ]]; then
            _msg time "Deleting previous image: ${previous_image}"
            if command -v skopeo >/dev/null 2>&1; then
                skopeo delete "docker://${previous_image}" &
            elif command -v aliyun >/dev/null 2>&1; then
                # Try aliyun CLI for ACR deletion when registry matches
                # previous_image format: <registry>/<repo_path>:<tag>
                local registry_prefix="${ENV_DOCKER_REGISTRY%/}"
                if [[ "${previous_image}" == "${registry_prefix}"* ]]; then
                    local rest repo_and_tag image_repo image_tag repo_ns repo_name
                    rest="${previous_image#${registry_prefix}/}"
                    repo_and_tag="${rest}"
                    image_repo="${repo_and_tag%:*}"
                    image_tag="${repo_and_tag#*:}"
                    if [[ "${image_repo}" == "${image_tag}" ]]; then
                        image_tag="latest"
                    fi
                    repo_ns="${image_repo%/*}"
                    repo_name="${image_repo##*/}"
                    _msg time "Deleting ACR image via aliyun CLI: ${repo_ns}/${repo_name}:${image_tag}"
                    aliyun -p "${ENV_ALIYUN_CLI_PROFILE:-default}" cr DeleteImage --RepoNamespace "${repo_ns}" --RepoName "${repo_name}" --ImageTag "${image_tag}" >/dev/null &
                else
                    _msg warn "Previous image registry does not match ENV_DOCKER_REGISTRY, skipping aliyun delete"
                fi
            else
                _msg warn "Neither skopeo nor aliyun CLI found; skip remote delete of ${previous_image}"
            fi
        fi
    fi

    printf '%s\n' "${current_image}" >"${image_record_file}"
}

# Clean up Evicted pods in the given namespace.
cleanup_evicted_pods() {
    local namespace="${1:-${G_NAMESPACE}}"
    {
        while read -r bad_pod; do
            $KUBECTL_OPT -n "${namespace}" delete pod "${bad_pod}" &>/dev/null || true
        done < <(
            $KUBECTL_OPT -n "${namespace}" get pod | awk '/Evicted/ {print $1}'
        )
    } &
}

# Deploy to Kubernetes cluster
deploy_to_kubernetes() {
    _msg step "[deploy] Deploy to Kubernetes with Helm"
    local release_name previous_image bad_pod
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

    # Convert HELM_OPT into array
    read -ra helm_opt_array <<<"${HELM_OPT:-}"

    local helm_args=(
        "${helm_opt_array[@]}"
        upgrade
        "${release_name:?release_name parameter is required}"
        "$helm_dir"
        --install
        --namespace "${G_NAMESPACE:?namespace parameter is required}"
        --create-namespace
        --history-max 3
        --hide-notes
        --timeout 120s
        --set "image.pullPolicy='Always'"
        --set "image.repository=${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME},image.tag=${G_IMAGE_TAG}"
    )
    if [ "${G_NAMESPACE}" != main ]; then
        helm_args+=("--set" "replicaCount=1")
    fi
    if [[ "$DRY_RUN" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
        _msg warn "[dry-run] skip helm upgrade/install, showing command only"
        echo "${helm_args[@]}"
        export EXIT_MAIN=true
        return 0
    fi
    ## 显示可复用命令
    echo "helm upgrade/install command (reusable):"
    echo "${helm_args[@]}" | sed "s#$HOME#\$HOME#g" | tee -a "$G_LOG"

    ## helm install / helm 安装  --atomic
    "${helm_args[@]}" >/dev/null || return 1

    # Pod health check / Pod 健康检查
    _msg time "Monitoring [${release_name}] in [${G_NAMESPACE}] (timeout: 120s)"
    if ! $KUBECTL_OPT -n "${G_NAMESPACE}" rollout status deployment "${release_name}" --timeout 120s >/dev/null; then
        deploy_result=1
        _msg red "Deployment probe timed out. Please check container status and logs in Kubernetes"
        _msg red "此处探测超时，无法判断应用是否正常，请检查k8s内容器状态和日志"
    fi
    # Rollback on failure / 部署失败时回滚
    if [[ "${deploy_result:-0}" -eq 1 ]]; then
        _msg red "Rolling back deployment ${release_name}"
        revision="$(helm -n "${G_NAMESPACE}" history "${release_name}" | awk 'END {print $1}')"
        ## helm rollback to previous revision / 回滚到上一个版本
        echo "helm -n ${G_NAMESPACE} rollback ${release_name} $((revision - 1))"
        ## kubectl rollback to previous revision / 回滚到上一个版本
        $KUBECTL_OPT -n "${G_NAMESPACE}" rollout undo deployment/"${release_name}" 2>/dev/null || true
        ## 显示回滚命令 / Show rollback command
        echo "$KUBECTL_OPT -n ${G_NAMESPACE} rollout undo deployment/${release_name}"
        ## Scale down deployment to 0 replicas / 将部署缩减为 0 个副本
        echo "$KUBECTL_OPT -n ${G_NAMESPACE} scale deployment/${release_name} --replicas=0"
        return 1
    fi

    record_deployed_image "${release_name}" "${deploy_result:-0}"

    # Clean up only evicted pods in this namespace.
    # Do not delete ReplicaSets globally; Helm/k8s already manage old RS history.
    cleanup_evicted_pods "${G_NAMESPACE}"

    execute_custom_deploy_hook

    _msg time "Kubernetes deployment completed"
    return "${deploy_result:-0}"
}

# Deploy to Aliyun Functions
# @param $1 lang The programming language of the project
deploy_aliyun_functions() {
    _install_aliyun_cli
    local release_name lang functions_conf_tmpl functions_conf
    lang="${1:?'lang parameter is required'}"
    release_name="$(format_release_name)"

    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && return 0
    [ "${G_NAMESPACE}" != main ] && release_name="${release_name}-${G_NAMESPACE}"

    ## create FC
    _msg step "[deploy] Creating/updating Aliyun Functions"
    functions_conf_tmpl="$G_DATA/aliyun.functions.${lang}.json"
    functions_conf="$G_DATA/aliyun.functions.json"
    if [ -f "$functions_conf_tmpl" ]; then
        TEMPLATE_NAME=$release_name TEMPLATE_REGISTRY=${ENV_DOCKER_REGISTRY} TEMPLATE_NAME=${G_IMAGE_NAME} TEMPLATE_TAG=${G_IMAGE_TAG} envsubst <"$functions_conf_tmpl" >"$functions_conf"
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
        "image": "${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}",
        "port": 8080,
        "healthCheckConfig": {
            "initialDelaySeconds": 5
        }
    }
}
EOF
    fi

    if aliyun -p "${ENV_ALIYUN_CLI_PROFILE:-default}" fc GET /2023-03-30/functions --prefix "${release_name:0:3}" --limit 100 --header "Content-Type=application/json;" | jq -r '.functions[].functionName' | grep -qw "${release_name}$"; then
        _msg time "Updating function: $release_name"
        aliyun -p "${ENV_ALIYUN_CLI_PROFILE:-default}" --quiet fc PUT /2023-03-30/functions/"$release_name" --header "Content-Type=application/json;" --body "{\"tracingConfig\":{},\"customContainerConfig\":{\"image\":\"${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}\"}}"
    else
        _msg time "Creating new function: $release_name"
        aliyun -p "${ENV_ALIYUN_CLI_PROFILE:-default}" --quiet fc POST /2023-03-30/functions --header "Content-Type=application/json;" --body "$(cat "$functions_conf")"
        _msg time "Creating HTTP trigger for function: $release_name"
        aliyun -p "${ENV_ALIYUN_CLI_PROFILE:-default}" --quiet fc POST /2023-03-30/functions/"$release_name"/triggers --header "Content-Type=application/json;" --body "{\"triggerType\":\"http\",\"triggerName\":\"defaultTrigger\",\"triggerConfig\":\"{\\\"methods\\\":[\\\"GET\\\",\\\"POST\\\",\\\"PUT\\\",\\\"DELETE\\\",\\\"OPTIONS\\\"],\\\"authType\\\":\\\"anonymous\\\",\\\"disableURLInternet\\\":false}\"}"
    fi
    rm -f "$functions_conf"

    _msg time "Aliyun Functions deployment completed"
}

# Deploy via Rsync+SSH
# @param $1 lang The programming language of the project
deploy_via_rsync_ssh() {
    local lang="${1:?'lang parameter is required'}"
    _msg step "[deploy] Deploy files with Rsync+SSH"
    ## rsync exclude configuration
    rsync_exclude="${G_REPO_DIR}/rsync.exclude"
    [[ ! -f "$rsync_exclude" ]] && rsync_exclude="${G_PATH}/conf/rsync.exclude"

    ## 检查配置文件格式（仅支持 JSON）
    if [[ ! "${G_CONF}" =~ \.json$ ]]; then
        _msg error "Unsupported configuration file format: ${G_CONF}"
        _msg error "Supported format: .json only"
        return 1
    fi
    ## 验证配置文件格式（仅支持项目专用配置格式）
    ## 项目专用配置格式: { "project": "...", "branches": [...] }
    if ! jq -e 'has("project") and has("branches")' "$G_CONF" >/dev/null 2>&1; then
        _msg error "Invalid configuration format. Expected project-specific format with 'project' and 'branches' fields."
        _msg error "Configuration file: $G_CONF"
        return 1
    fi

    ## 检查是否为模板配置（示例配置）
    ## 如果配置中包含示例 IP 地址或示例域名，说明是未修改的模板配置
    if jq -e '.branches[].hosts[] | select(.host == "192.168.100.102" or .host == "192.168.100.104" or .host | contains("example.com"))' "$G_CONF" >/dev/null 2>&1; then
        _msg error "================================================================"
        _msg error "ERROR: Configuration file contains example/template values!"
        _msg error "================================================================"
        _msg error "The configuration file appears to be unmodified template:"
        _msg error "  Configuration file: $G_CONF"
        _msg error ""
        _msg error "Please edit the configuration file and update:"
        _msg error "  - hosts[].host: Replace example IPs (192.168.100.102/104) with real server IPs"
        _msg error "  - hosts[].user: Replace example usernames with real SSH usernames"
        _msg error "  - hosts[].rsync_dest: Replace example paths with real deployment paths"
        _msg error "  - hosts[].db_host: Replace example database hosts with real ones"
        _msg error ""
        _msg error "Rsync+SSH deployment cannot proceed with template configuration."
        _msg error "After editing, run the deployment command again."
        return 1
    fi

    ## 验证配置是否存在
    local config_query=".branches[] | select(.branch == \"${G_NAMESPACE}\") | .hosts[]"
    if ! jq -e "${config_query}" "$G_CONF" 2>/dev/null | grep -q "."; then
        _msg warn "No host configuration found for project '${G_REPO_GROUP_PATH}' branch '${G_NAMESPACE}' in $G_CONF"
    fi

    while read -r line; do
        ssh_user=$(echo "$line" | jq -r '.user // empty')
        ssh_host_ip=$(echo "$line" | jq -r '.host // empty')
        ssh_port=$(echo "$line" | jq -r '.port // "22"')
        rsync_src_from_conf=$(echo "$line" | jq -r '.rsync_src // empty')
        rsync_dest=$(echo "$line" | jq -r '.rsync_dest // empty')

        [[ -z "$ssh_host_ip" ]] && {
            _msg error "host is required but not found in config"
            continue
        }

        # 构建 ssh_host 变量（user@host 格式）供后续代码使用
        if [[ -n "$ssh_user" ]]; then
            ssh_host="${ssh_user}@${ssh_host_ip}"
        else
            ssh_host="$ssh_host_ip"
        fi

        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=10 -p ${ssh_port:-22}"

        case "$lang" in
        java) rsync_relative_path="jars/" ;;
        node) rsync_relative_path="dist/" ;;
        *) rsync_relative_path="" ;;
        esac

        if [[ -n "$rsync_src_from_conf" ]]; then
            rsync_src="${rsync_src_from_conf%/}/"
            echo "Using configured source: $rsync_src"
        else
            rsync_src="${G_REPO_DIR%/}/${rsync_relative_path:+${rsync_relative_path%/}/}"
            echo "Using default source path: $rsync_src"
        fi

        rsync_opt="rsync -acvzt --timeout=10 --no-times --exclude-from=${rsync_exclude}"
        [[ "$lang" == "node" ]] && rsync_opt+=" --delete"

        if [[ "$rsync_dest" == "none" || -z "$rsync_dest" ]]; then
            rsync_dest="${ENV_PATH_DEST_PRE:-/var/www}/${G_NAMESPACE}_${G_REPO_NAME}/"
        fi

        if [[ "${rsync_dest}" =~ 'oss://' ]]; then
            if ${DRY_RUN:-false} || [[ "${GITHUB_ACTIONS}" == "true" ]]; then
                _msg purple "[dry-run] deploy_aliyun_oss:"
                _msg purple "  Source: ${rsync_src}"
                _msg purple "  Destination: ${rsync_dest}"
                continue
            fi
            deploy_aliyun_oss "${rsync_src}" "${rsync_dest}"
            continue
        fi

        echo "Destination: ${ssh_host}:${rsync_dest}"
        if ${DRY_RUN:-false} || [[ "${GITHUB_ACTIONS}" == "true" ]]; then
            _msg purple "[dry-run] deploy_rsync_ssh:"
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
        ## 读取项目专用配置格式中的 hosts
        jq -c ".branches[] | select(.branch == \"${G_NAMESPACE}\") | .hosts[] | select(. != null)" "$G_CONF"
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

# Determine the deployment method based on project files and environment
# Priority order:
#   1. Helm charts (if exist and k8s available) → deploy_k8s
#   2. Dockerfile (if exist and k8s available) → deploy_k8s
#   3. docker-compose.yml → deploy_docker
#   4. Project config with hosts → deploy_rsync_ssh
#   5. Default → deploy_rsync_ssh (with warning)
# Returns:
#   deploy_method: The determined deployment method
determine_deployment_method() {
    local file
    local release_name has_dockerfile=false has_docker_compose=false has_project_config=false

    # Get release name for Helm charts check
    release_name="$(format_release_name 2>/dev/null || echo "")"

    _msg step "[detect] Determining deployment method" >&2

    ## 检查配置文件中的部署方式覆盖
    if [[ -n "${PROJECT_DEPLOY_METHOD:-}" && "${PROJECT_DEPLOY_METHOD}" != "auto" ]]; then
        case "${PROJECT_DEPLOY_METHOD}" in
        k8s)
            if check_k8s_available; then
                _msg info "Using configured deployment method: deploy_k8s" >&2
                echo "deploy_k8s"
                return 0
            else
                _msg warn "Configured method 'k8s' but k8s is not available, falling back to auto detection" >&2
            fi
            ;;
        docker)
            _msg info "Using configured deployment method: deploy_docker" >&2
            echo "deploy_docker"
            return 0
            ;;
        rsync)
            _msg info "Using configured deployment method: deploy_rsync_ssh" >&2
            echo "deploy_rsync_ssh"
            return 0
            ;;
        ftp)
            _msg info "Using configured deployment method: deploy_ftp" >&2
            echo "deploy_ftp"
            return 0
            ;;
        fc)
            _msg info "Using configured deployment method: deploy_aliyun_func" >&2
            echo "deploy_aliyun_func"
            return 0
            ;;
        esac
    fi

    # Step 1: Check for Helm charts (highest priority for k8s)
    if check_helm_charts_exist "${release_name}"; then
        if check_k8s_available; then
            _msg info "Found Helm charts and k8s is available → deploy_k8s" >&2
            echo "deploy_k8s"
            return 0
        else
            _msg warn "Found Helm charts but k8s is not available, will try other methods" >&2
        fi
    fi

    # Step 2: Check for Dockerfile
    for file in Dockerfile{,.*}; do
        if [[ -f "${G_REPO_DIR}/${file}" ]]; then
            has_dockerfile=true
            break
        fi
    done

    if [[ "$has_dockerfile" == true ]]; then
        if check_k8s_available; then
            _msg info "Found Dockerfile and k8s is available → deploy_k8s" >&2
            echo "deploy_k8s"
            return 0
        else
            _msg warn "Found Dockerfile but k8s is not available, will try docker-compose or rsync" >&2
        fi
    fi

    # Step 3: Check for docker-compose.yml
    for file in docker-compose.{yml,yaml}; do
        if [[ -f "${G_REPO_DIR}/${file}" ]]; then
            has_docker_compose=true
            break
        fi
    done

    if [[ "$has_docker_compose" == true ]]; then
        _msg info "Found docker-compose.yml → deploy_docker" >&2
        echo "deploy_docker"
        return 0
    fi

    # Step 4: Check for project config with valid hosts
    if [[ -n "${G_CONF:-}" && -f "${G_CONF}" ]]; then
        # Check if config has valid hosts for current namespace
        if jq -e ".branches[] | select(.branch == \"${G_NAMESPACE:-}\") | .hosts[] | select(.host != null and .host != \"\")" "${G_CONF}" &>/dev/null; then
            has_project_config=true
        fi
    fi

    if [[ "$has_project_config" == true ]]; then
        _msg info "Found project config with hosts → deploy_rsync_ssh" >&2
        echo "deploy_rsync_ssh"
        return 0
    fi

    # Step 5: Default fallback
    _msg warn "No deployment method detected, defaulting to deploy_rsync_ssh" >&2
    _msg warn "Consider:" >&2
    _msg warn "  - Adding Dockerfile for k8s deployment" >&2
    _msg warn "  - Adding docker-compose.yml for docker deployment" >&2
    _msg warn "  - Configuring hosts in project config for rsync deployment" >&2
    echo "deploy_rsync_ssh"
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
    local source_image="$1" target_registry="$2" image_name tag target

    if ! command -v skopeo >/dev/null 2>&1; then
        _msg error "skopeo command not found. Please install skopeo first."
        return 1
    fi

    # 1. image:tag --> mirror/ns/image:tag
    # 2. xxx/image:tag --> mirror/ns/image:tag
    # 3. 先查询 skopeo inspect mirror/ns/image:tag 是否存在， 存在就报错退出，不存在就直接copy

    # 移除 target_registry 末尾的斜杠（如果有）
    target_registry="${target_registry%/}"

    # 解析源镜像名称和标签
    image_name="${source_image%:*}"
    tag="${source_image#*:}"

    # 如果没有标签，使用 latest
    [[ "$image_name" == "$source_image" ]] && tag="latest"

    # 移除可能存在的 docker.io/ 前缀
    image_name="${image_name#docker.io/}"

    # 移除 image_name 开头和结尾的斜杠（如果有）
    image_name="${image_name#/}"
    image_name="${image_name%/}"

    # 获取镜像的最后一部分作为基本名称
    base_name="${image_name##*/}"

    # 构建目标镜像完整路径
    target="${target_registry}/${base_name}:${tag}"

    # 检查目标镜像是否已存在
    if skopeo inspect "docker://${target}" &>/dev/null; then
        _msg error "Target image already exists: ${target}"
        return 1
    fi

    echo "Copying multi-arch image to custom registry..."
    echo "skopeo --override-os linux copy --multi-arch all docker://${source_image} docker://${target}"

    if skopeo --override-os linux copy --multi-arch all \
        "docker://${source_image}" \
        "docker://${target}"; then
        _msg green "Successfully copied image to ${target}"
        return 0
    else
        _msg error "Failed to copy image to ${target}"
        return 1
    fi
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
            skopeo delete "docker://${repository}:${tag}" &
            sleep 1
        done
    else
        _msg time "No old tags to delete / 没有需要删除的旧标签"
    fi
}
