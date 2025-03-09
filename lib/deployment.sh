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
        _msg time "!!! disable deploy to k8s !!!"
        return
    fi
    local lang="${1:?'lang parameter is required'}"
    _install_aliyun_cli
    format_release_name
    ${GH_ACTION:-false} && return 0
    ${ENV_ENABLE_FUNC:-false} || {
        _msg time "!!! disable deploy to functions3.0 aliyun !!!"
        return 0
    }
    [ "${G_NAMESPACE}" != main ] && release_name="${release_name}-${G_NAMESPACE}"

    ## create FC
    _msg step "[deploy] create/update functions"
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
        _msg time "update function $release_name"
        aliyun -p "${ENV_ALIYUN_PROFILE-}" --quiet fc PUT /2023-03-30/functions/"$release_name" --header "Content-Type=application/json;" --body "{\"tracingConfig\":{},\"customContainerConfig\":{\"image\":\"${ENV_DOCKER_REGISTRY}:${G_IMAGE_TAG}\"}}"
    else
        _msg time "create function $release_name"
        aliyun -p "${ENV_ALIYUN_PROFILE-}" --quiet fc POST /2023-03-30/functions --header "Content-Type=application/json;" --body "$(cat "$functions_conf")"
        _msg time "create trigger for function $release_name"
        aliyun -p "${ENV_ALIYUN_PROFILE-}" --quiet fc POST /2023-03-30/functions/"$release_name"/triggers --header "Content-Type=application/json;" --body "{\"triggerType\":\"http\",\"triggerName\":\"defaultTrigger\",\"triggerConfig\":\"{\\\"methods\\\":[\\\"GET\\\",\\\"POST\\\",\\\"PUT\\\",\\\"DELETE\\\",\\\"OPTIONS\\\"],\\\"authType\\\":\\\"anonymous\\\",\\\"disableURLInternet\\\":false}\"}"
    fi
    rm -f "$functions_conf"

    _msg time "[deploy] create/update functions end"
}

# Deploy to Kubernetes cluster
deploy_to_kubernetes() {
    _msg step "[deploy] deploy k8s with helm"
    is_demo_mode "deploy_k8s" && return 0
    format_release_name

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
        _msg purple "Not found helm files"
        echo "Try to generate helm files"
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

    ## 检测 helm upgrade 状态
    echo "Checking deployment status for ${release_name} in namespace ${G_NAMESPACE}, timeout 120s..."
    if ! $KUBECTL_OPT -n "${G_NAMESPACE}" rollout status deployment "${release_name}" --timeout 120s >/dev/null; then
        deploy_result=1
        _msg red "此处探测超时，无法判断应用是否正常，请检查k8s内容器状态和日志"
    fi

    ## Clean up rs 0 0 / 清理 rs 0 0
    {
        $KUBECTL_OPT -n "${G_NAMESPACE}" get rs | awk '$2=="0" && $3=="0" && $4=="0" {print $1}' |
            xargs -t -r $KUBECTL_OPT -n "${G_NAMESPACE}" delete rs >/dev/null 2>&1 || true
        $KUBECTL_OPT -n "${G_NAMESPACE}" get pod | awk '/Evicted/ {print $1}' |
            xargs -t -r $KUBECTL_OPT -n "${G_NAMESPACE}" delete pod 2>/dev/null || true
    } &

    if [ -f "$G_REPO_DIR/deploy.custom.sh" ]; then
        _msg time "custom deploy."
        source "$G_REPO_DIR/deploy.custom.sh"
    fi

    _msg time "[deploy] deploy k8s with helm"
    return "${deploy_result:-0}"
}

# Deploy via Rsync+SSH
# @param $1 lang The programming language of the project
deploy_via_rsync_ssh() {
    local lang="${1:?'lang parameter is required'}"
    _msg step "[deploy] deploy files with rsync+ssh"
    ## rsync exclude some files / rsync 排除某些文件
    rsync_exclude="${G_REPO_DIR}/rsync.exclude"
    [[ ! -f "$rsync_exclude" ]] && rsync_exclude="${G_PATH}/conf/rsync.exclude"

    ## read conf, get project,branch,jar/war etc. / 读取配置文件，获取 项目/分支名/war包目录
    ## debug for github action error
    if ! jq -e ".projects[] | select(.project == \"${G_REPO_GROUP_PATH}\") | .branchs[] | select(.branch == \"${G_NAMESPACE}\") | .hosts[]" "$G_CONF"; then
        _msg warn "[deploy] No hosts configured for project '${G_REPO_GROUP_PATH}' branch '${G_NAMESPACE}' in $G_CONF"
    fi

    while read -r line; do
        ssh_host=$(echo "$line" | jq -r '.ssh_host')
        ssh_port=$(echo "$line" | jq -r '.ssh_port')
        rsync_src_from_conf=$(echo "$line" | jq -r '.rsync_src')
        rsync_dest=$(echo "$line" | jq -r '.rsync_dest')

        # Setup SSH options
        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=10 -p ${ssh_port:-22}"

        # 2. Set language-specific relative path
        case "$lang" in
        java) rsync_relative_path="jars/" ;;
        node) rsync_relative_path="dist/" ;;
        *) rsync_relative_path="" ;;
        esac

        # 3 & 4. Determine source directory
        # If rsync_src is configured in deploy.json, use it; otherwise use repo_dir with language-specific path
        if [[ -n "$rsync_src_from_conf" ]]; then
            rsync_src="${rsync_src_from_conf%/}/"
            _msg info "Using configured source path: $rsync_src"
        else
            rsync_src="${G_REPO_DIR%/}/${rsync_relative_path:+${rsync_relative_path%/}/}"
            _msg info "Using default source path: $rsync_src"
        fi

        # Setup rsync options with excludes
        rsync_opt="rsync -acvzt --timeout=10 --no-times --exclude-from=${rsync_exclude}"
        # Add --delete option for Node.js projects
        [[ "$lang" == "node" ]] && rsync_opt+=" --delete"

        # Setup destination directory
        if [[ "$rsync_dest" == "none" || -z "$rsync_dest" ]]; then
            rsync_dest="${ENV_PATH_DEST_PRE}/${G_NAMESPACE}.${G_REPO_NAME}/"
        fi

        ## deploy to aliyun oss / 发布到 aliyun oss 存储
        if [[ "${rsync_dest}" =~ 'oss://' ]]; then
            if is_demo_mode "deploy_aliyun_oss"; then
                _msg purple "Demo mode: would deploy to Aliyun OSS:"
                _msg purple "  Source: ${rsync_src}"
                _msg purple "  Destination: ${rsync_dest}"
                continue
            fi
            deploy_aliyun_oss "${rsync_src}" "${rsync_dest}"
            continue
        fi

        # Create destination directory and sync files
        _msg info "Deploying to ${ssh_host}:${rsync_dest}"
        if is_demo_mode "deploy_rsync_ssh"; then
            _msg purple "Demo mode: would execute commands:"
            _msg purple "  $ssh_opt -n \"$ssh_host\" \"mkdir -p $rsync_dest\""
            _msg purple "  ${rsync_opt} -e \"$ssh_opt\" \"$rsync_src\" \"${ssh_host}:${rsync_dest}\""
            continue
        fi
        $ssh_opt -n "$ssh_host" "mkdir -p $rsync_dest"
        ${rsync_opt} -e "$ssh_opt" "$rsync_src" "${ssh_host}:${rsync_dest}"

        # Run custom deployment script if exists
        if [[ -f "${G_DATA}/bin/deploy.custom.sh" ]]; then
            _msg time "Running custom deployment script..."
            bash "${G_DATA}/bin/deploy.custom.sh" "$ssh_host" "$rsync_dest"
            _msg time "Custom deployment completed"
        fi

        # Handle docker-compose deployment
        if ${exec_deploy_docker_compose:-false}; then
            _msg step "Deploying with docker-compose"
            $ssh_opt -n "$ssh_host" "cd docker/laradock && docker compose up -d $G_REPO_NAME"
        fi
    done < <(jq -c ".projects[] | select (.project == \"${G_REPO_GROUP_PATH}\") | .branchs[] | select (.branch == \"${G_NAMESPACE}\") | .hosts[]" "$G_CONF")
}

# Deploy to Aliyun OSS
# @param $1 source_path The source path to upload from
# @param $2 oss_dest The OSS destination path (format: oss://bucket-name/path)
deploy_aliyun_oss() {
    local source_path="${1:?'source_path parameter is required'}"
    local oss_dest="${2:?'oss_dest parameter is required (format: oss://bucket-name/path)'}"

    _msg step "[deploy] deploy files to Aliyun OSS"
    # Check if OSS CLI is installed
    _install_ossutil

    # Deploy files to Aliyun OSS
    _msg time "copy start"
    if ossutil cp "${source_path}/" "${oss_dest}" --recursive --force; then
        _msg green "Result = OK"
    else
        _msg error "Result = FAIL"
    fi
    _msg time "[oss] deploy files to Aliyun OSS"
}

# Deploy via Rsync
deploy_via_rsync() {
    _msg step "[deploy] deploy files to rsyncd server"
    # Load configuration from file
    rsyncd_conf="$G_DATA/rsyncd.conf"
    source "$rsyncd_conf"

    # Deploy files with rsync
    rsync_options="rsync -avz"
    $rsync_options --exclude-from="$EXCLUDE_FILE" "$SOURCE_DIR/" "$RSYNC_USER@$RSYNC_HOST::$TARGET_DIR"
}

# Deploy via FTP
deploy_via_ftp() {
    _msg step "[deploy] deploy files to ftp server"
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
    _msg time "[deploy] deploy files to ftp server"
}

# Deploy via SFTP
deploy_via_sftp() {
    _msg step "[deploy] deploy files to sftp server"
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
