#!/usr/bin/env bash
# shellcheck disable=1090,1091,2154
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

execute_custom_deploy_hook() {
    # 执行项目自定义部署钩子（可选）
    # The hook is sourced so it can access deployment variables like
    # G_NAMESPACE, release_name, and other environment state.
    # If the hook is absent, this is a no-op.
    local custom_script="${G_REPO_DIR}/deploy.custom.sh"
    if [[ -f "${custom_script}" ]]; then
        _msg task "Executing custom deployment script: ${custom_script}"
        ## 子壳内以 errexit 运行：钩子遇错即停，其 exit 只结束子壳、不杀主流程；
        ## 失败标记 G_DEPLOY_RESULT=1 但不中断，保证 handle_notify 仍执行
        local hook_rc=0
        set +e
        (set -e; source "${custom_script}")
        hook_rc=$?
        set -e
        if [[ "${hook_rc}" -ne 0 ]]; then
            _msg error "custom deploy hook failed (exit ${hook_rc}): ${custom_script}"
            G_DEPLOY_RESULT=1
        fi
    fi
}

_project_hosts() {
    # 输出当前命名空间下项目配置中的所有 hosts 行（每行一个 JSON），无配置时输出为空
    [[ -f "${G_CONF:-}" ]] || return 0
    jq -c --arg branch "${G_NAMESPACE:-}" \
        '.branches[] | select(.branch == $branch) | .hosts[]? | select(. != null)' \
        "$G_CONF" 2>/dev/null
}

_rsync_exclude_file() {
    # 返回 rsync exclude 文件路径: 项目内优先，否则使用脚本自带默认
    local f="${G_REPO_DIR}/rsync.exclude"
    [[ -f "$f" ]] || f="${G_PATH}/conf/rsync.exclude"
    printf '%s' "$f"
}

_project_rsync_src() {
    # 根据语言返回默认上传源目录
    local lang="${1:-}"
    case "$lang" in
    java) printf '%s' "$G_REPO_DIR/build_output/" ;;
    node) printf '%s' "$G_REPO_DIR/dist/" ;;
    *) printf '%s' "$G_REPO_DIR/" ;;
    esac
}

_project_oss_dest() {
    # 返回当前命名空间的 OSS 目标地址（oss:// 开头）: 项目配置优先，其次 ENV_OSS_DEST
    local dest=""
    if [[ -n "${G_CONF:-}" && -f "${G_CONF}" ]]; then
        dest=$(jq -r --arg branch "${G_NAMESPACE:-}" \
            '.branches[] | select(.branch == $branch) | .hosts[]? | select((.rsync_dest // "") | startswith("oss://")) | .rsync_dest' \
            "${G_CONF}" 2>/dev/null | head -n 1 || true)
    fi
    [[ -n "$dest" ]] || dest="${ENV_OSS_DEST:-}"
    printf '%s' "$dest"
}

record_deployed_image() {
    # 把本 release/命名空间 当前部署的镜像标记为 live（供 _clean_indexed_images 判定存活）
    # deploy_ok != 0 时不动 live 指针：失败部署的镜像已无人引用，留作 push 行由下次清理删除
    local release_name="${1:?release_name is required}"
    local deploy_ok="${2:-0}"
    [[ "${deploy_ok}" -eq 0 ]] || return 0
    _image_index_set_live "${release_name}-${G_NAMESPACE}" "${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}"
}

cleanup_evicted_pods() {
    # 清理指定 namespace 下 Evicted 的 pod
    local namespace="${1:-${G_NAMESPACE}}"
    {
        while read -r bad_pod; do
            $KUBECTL_OPT -n "${namespace}" delete pod "${bad_pod}" &>/dev/null || true
        done < <(
            $KUBECTL_OPT -n "${namespace}" get pod | awk '/Evicted/ {print $1}'
        )
    } &
}

_duration_to_seconds() {
    # k8s 时长（"120s"/"5m"/"1h30m"）或裸秒 → 秒
    local d="${1:-}" num unit total=0
    [[ "$d" =~ ^[0-9]+$ ]] && { printf '%s' "$d"; return 0; }
    while [[ -n "$d" ]]; do
        [[ "$d" =~ ^([0-9]+)([smhd])(.*)$ ]] || break
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
        d="${BASH_REMATCH[3]}"
        case "$unit" in
            s) total=$((total + num)) ;;
            m) total=$((total + num * 60)) ;;
            h) total=$((total + num * 3600)) ;;
            d) total=$((total + num * 86400)) ;;
        esac
    done
    [[ "$total" -gt 0 ]] || total=180
    printf '%s' "$total"
}

_rollout_diagnostics() {
    # 收集并打印 pod 状态 + 日志，诊断 rollout 失败
    local release_name="${1:?release_name is required}"
    local diag_pods=()
    _msg task "Fetching pod status and logs for [${release_name}] to diagnose"
    mapfile -t diag_pods < <($KUBECTL_OPT -n "${G_NAMESPACE}" get pods -l "app.kubernetes.io/instance=${release_name}" --no-headers 2>/dev/null | awk '{print $1}')
    if [[ "${#diag_pods[@]}" -eq 0 ]]; then
        _msg warn "No pods found by instance label, falling back to name grep"
        mapfile -t diag_pods < <($KUBECTL_OPT -n "${G_NAMESPACE}" get pods --no-headers 2>/dev/null | grep "${release_name}" | awk '{print $1}')
    fi
    if [[ "${#diag_pods[@]}" -eq 0 ]]; then
        _msg warn "Still no pods matched, listing all pods in namespace ${G_NAMESPACE}"
        $KUBECTL_OPT -n "${G_NAMESPACE}" get pods 2>&1 || true
    else
        for pod in "${diag_pods[@]}"; do
            _msg task "=== Pod ${pod} ==="
            $KUBECTL_OPT -n "${G_NAMESPACE}" get pod "${pod}" 2>&1 || true
            _msg task "--- Logs (last 50 lines) ---"
            $KUBECTL_OPT -n "${G_NAMESPACE}" logs --tail=50 "${pod}" 2>&1 || true
        done
    fi
}

# Poll the rollout until Ready (fast return), a terminal pod error (fail fast),
# or the overall deadline (fail with diagnostics). Returns 0 on success, 1 on failure.
#
_wait_kubernetes_rollout() {
    # 滚动更新期间旧 pod 一直健康，deployment 的 Available 条件恒为 True，
    # 不能用 pod/condition 判断完成状态，只有 `kubectl rollout status` 才能准确反馈。
    # 因此这里用 rollout status 短超时轮询：返回 0 即就绪，非 0 且仍在进展则继续等，
    # 命中终态错误/进度卡死则快速失败。
    local release_name="${1:?release_name is required}"
    local timeout="${2:-180}" poll_interval="${3:-5}"
    local deadline bad_pod current ret status_out
    deadline=$(( $(date +%s) + timeout ))

    _msg task "Monitoring [${release_name}] on branch [${G_NAMESPACE}] (timeout: ${timeout}s)"
    while :; do
        # Authoritative rolling-rollout check: blocks up to poll_interval, exits 0
        # only when the new RS is fully ready; non-zero while still in progress.
        status_out="$($KUBECTL_OPT -n "${G_NAMESPACE}" rollout status deployment "${release_name}" --timeout "${poll_interval}s" 2>&1)"
        ret=$?
        if [ $ret -eq 0 ]; then
            _msg task "helm release name: [${release_name}] is ready"
            return 0
        fi

        # 进度卡死: rollout status 直接报错, 无需再查 deployment conditions
        if [[ "${status_out}" == *"exceeded its progress deadline"* ]]; then
            _msg error "[${release_name}] rollout stuck (progress deadline exceeded)"
            _rollout_diagnostics "${release_name}"
            return 1
        fi

        # Terminal pod state → fail fast
        bad_pod="$($KUBECTL_OPT -n "${G_NAMESPACE}" get pods -l "app.kubernetes.io/instance=${release_name}" --no-headers 2>/dev/null | grep -E 'CrashLoopBackOff|ImagePullBackOff|ErrImagePull|Error|OOMKilled|RunContainerError|CreateContainerConfigError|CreateContainerError|DeadlineExceeded|ContainerCannotRun|InvalidImageName')"
        if [[ -n "${bad_pod}" ]]; then
            _msg error "[${release_name}] pod in terminal state:"
            echo "${bad_pod}"
            _rollout_diagnostics "${release_name}"
            return 1
        fi

        current="$(date +%s)"
        if [[ "${current}" -ge "${deadline}" ]]; then
            _msg error "$(_t "此处探测超时（${timeout}s），无法判断应用是否正常，请检查k8s内容器状态和日志" "Deployment probe timed out after ${timeout}s. Please check container status and logs in Kubernetes")"
            _rollout_diagnostics "${release_name}"
            return 1
        fi

        # rollout status 未完成时已阻塞 poll_interval; 仅在它快速返回(如 NotFound)时防空转
        sleep 1
    done
}

deploy_to_kubernetes() {
    # 部署到 k8s 集群
    _msg task "Deploy to Kubernetes with Helm"
    local release_name bad_pod helm_dir helm_dirs revision
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
        _msg note "Helm charts not exist, generating new Helm charts"
        helm_dir="${G_DATA}/helm/${G_REPO_GROUP_PATH_SLUG}/${release_name}"
        mkdir -p "$helm_dir"
        create_helm_chart "${helm_dir}"
    fi

    # Convert HELM_OPT into array
    local helm_opt_array
    read -ra helm_opt_array <<<"${HELM_OPT:-}"

    local helm_args=(
        "${helm_opt_array[@]}"
        upgrade
        "${release_name:?release_name parameter is required}"
        "$helm_dir"
        --install
        --namespace "${G_NAMESPACE:?namespace parameter is required}"
        --create-namespace
        --history-max "${ENV_HELM_HISTORY_MAX:-2}"
        --hide-notes
        --timeout "${ENV_HELM_TIMEOUT:-120s}"
        --set "image.pullPolicy=Always"
        --set "image.repository=${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}"
        --set "image.tag=${G_IMAGE_TAG}"
    )
    if [ "${G_NAMESPACE}" != main ]; then
        helm_args+=("--set" "replicaCount=1")
    fi
    if ${G_DRY_RUN:-false} || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        _msg note "[dry-run] skip helm upgrade/install, showing command only"
        _msg note "  ${helm_args[*]}"
        return 0
    fi
    ## 自动扩缩容互斥锁：helm 发布期间创建 per-user 锁（含 PID/时间/发布对象），
    ## ack scale-php/scale-pod 检测到则跳过扩缩容（mtime 5 分钟内生效）
    ## 运行时目录去尾斜杠：macOS $TMPDIR 带 / 会拼出 //，与 ack.sh run_once 同口径
    local runtime_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
    runtime_dir="${runtime_dir%/}"
    local scale_all_lock="${runtime_dir}/lock.scale.all"
    printf '%s\n' "$$ $(date '+%F %T') helm deploy ${release_name}/${G_NAMESPACE}" > "$scale_all_lock"
    trap 'rm -f "$scale_all_lock"' RETURN

    ## helm 部署：失败不静默 return，置 G_DEPLOY_RESULT 后统一走下方诊断/回滚提示块
    "${helm_args[@]}" >/dev/null || G_DEPLOY_RESULT=1

    # Pod health check / Pod 健康检查（helm 已失败则跳过等待）
    if [[ "${G_DEPLOY_RESULT:-0}" -eq 0 ]]; then
        local rollout_timeout
        rollout_timeout="$(_duration_to_seconds "${ENV_HELM_TIMEOUT:-180s}")"
        if ! _wait_kubernetes_rollout "${release_name}" "${rollout_timeout}"; then
            G_DEPLOY_RESULT=1
        fi
    fi
    # Display rollback cmd on failure / 部署失败时显示回滚命令
    if [[ "${G_DEPLOY_RESULT:-0}" -eq 1 ]]; then
        _msg error "Deployment failed: ${release_name}; rollback/diagnostic commands:"
        ## 可复用命令：仅在失败时输出，便于本机修复后手工重跑（$HOME 脱敏）
        echo "helm upgrade/install command (reusable):"
        echo "  ${helm_args[*]}" | sed "s#$HOME#\$HOME#g"
        revision="$(helm -n "${G_NAMESPACE}" history "${release_name}" 2>/dev/null | awk 'END {print $1}' || true)"
        if [[ -n "$revision" && "$revision" -gt 1 ]]; then
            ## helm rollback to previous revision / 回滚到上一个版本
            echo "helm -n ${G_NAMESPACE} rollback ${release_name} $((revision - 1))"
        fi
        ## kubectl rollback to previous revision / 回滚到上一个版本
        echo "kubectl -n ${G_NAMESPACE} rollout undo deployment/${release_name}"
        ## Scale down deployment to 0 replicas / 将部署缩减为 0 个副本
        echo "kubectl -n ${G_NAMESPACE} scale deployment/${release_name} --replicas=0"
        return 1
    fi

    record_deployed_image "${release_name}" "${G_DEPLOY_RESULT:-0}"

    # Clean up only evicted pods in this namespace.
    # Do not delete ReplicaSets globally; Helm/k8s already manage old RS history.
    cleanup_evicted_pods "${G_NAMESPACE}"

    execute_custom_deploy_hook

    _msg ok "Kubernetes deployment completed"
    return "${G_DEPLOY_RESULT:-0}"
}

deploy_aliyun_functions() {
    # 部署到阿里云函数计算
    # @param $1 lang The programming language of the project
    local release_name lang functions_conf functions_conf_tmpl
    lang="${1:?'lang parameter is required'}"
    release_name="$(format_release_name)"

    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && return 0
    [ "${G_NAMESPACE}" != main ] && release_name="${release_name}-${G_NAMESPACE}"

    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] deploy_aliyun_functions (function: ${release_name}):"
        _msg note "  aliyun fc PUT/POST /2023-03-30/functions/${release_name} --body <customContainerConfig image=${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}>"
        return 0
    fi
    _install_aliyun_cli

    ## create FC
    _msg task "Creating/updating Aliyun Functions"
    functions_conf="$(mktemp)"
    functions_conf_tmpl="$G_DATA/conf/aliyun.functions.json"
    if [[ -f "$functions_conf_tmpl" ]]; then
        _msg note "Using customized function template: $functions_conf_tmpl"
        TEMPLATE_FUNC_NAME="$release_name" \
        TEMPLATE_REGISTRY="${ENV_DOCKER_REGISTRY%/}" \
        TEMPLATE_IMAGE="$G_IMAGE_NAME" \
        TEMPLATE_TAG="$G_IMAGE_TAG" \
        envsubst <"$functions_conf_tmpl" >"$functions_conf"
    else
        _msg note "No $functions_conf_tmpl found, using minimal built-in template (no NAS/VPC)"
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

    local aliyun_cli
    aliyun_cli=(aliyun -p "${ENV_ALIYUN_CLI_PROFILE:-default}" --header "Content-Type=application/json;")
    if "${aliyun_cli[@]}" fc GET /2023-03-30/functions --prefix "${release_name:0:3}" --limit 100 | jq -r '.functions[].functionName' | grep -qw "${release_name}$"; then
        _msg task "Updating function: $release_name"
        if ! "${aliyun_cli[@]}" fc PUT /2023-03-30/functions/"${release_name}" --body "{\"tracingConfig\":{},\"customContainerConfig\":{\"image\":\"${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}\"}}"; then
            G_DEPLOY_RESULT=1
            _msg error "Failed to update Aliyun function: $release_name"
        fi
    else
        _msg task "Creating new function: $release_name"
        if ! "${aliyun_cli[@]}" fc POST /2023-03-30/functions --body "$(cat "$functions_conf")"; then
            G_DEPLOY_RESULT=1
            _msg error "Failed to create Aliyun function: $release_name"
        else
            _msg task "Creating HTTP trigger for function: $release_name"
            "${aliyun_cli[@]}" fc POST /2023-03-30/functions/"${release_name}"/triggers --body "{\"triggerType\":\"http\",\"triggerName\":\"defaultTrigger\",\"triggerConfig\":\"{\\\"methods\\\":[\\\"GET\\\",\\\"POST\\\",\\\"PUT\\\",\\\"DELETE\\\",\\\"OPTIONS\\\"],\\\"authType\\\":\\\"anonymous\\\",\\\"disableURLInternet\\\":false}\"}" || G_DEPLOY_RESULT=1
        fi
    fi
    rm -f "$functions_conf"

    ## 记录本次引用并删上一张（函数计算与 k8s 同样长期引用 registry 镜像，漏记会被索引清理误删）
    record_deployed_image "${release_name}" "${G_DEPLOY_RESULT:-0}"

    [[ "${G_DEPLOY_RESULT:-0}" -eq 0 ]] && _msg task "Aliyun Functions deployment completed"
}

deploy_via_rsync_ssh() {
    # 通过 rsync+ssh 部署
    # @param $1 lang The programming language of the project
    local lang="${1:?'lang parameter is required'}"
    _msg task "Deploy files with Rsync+SSH"
    local rsync_exclude ssh_user ssh_host_ip ssh_port rsync_src_from_conf rsync_dest
    local ssh_host ssh_opt rsync_src rsync_opt
    rsync_exclude="$(_rsync_exclude_file)"

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

    ## 模板示例值检查已在 find_project_config 公共层统一拦截

    ## 验证配置是否存在
    if ! _project_hosts | grep -q "."; then
        _msg error "No host configuration found for project '${G_REPO_GROUP_PATH}' branch '${G_NAMESPACE}' in $G_CONF"
        _msg error "Nothing was deployed. Add hosts[] for this branch in the project config, or use a different deploy method."
        return 1
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
        ssh_host="${ssh_user:+${ssh_user}@}${ssh_host_ip}"

        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=10 -p ${ssh_port:-22}"

        if [[ -n "$rsync_src_from_conf" ]]; then
            rsync_src="${rsync_src_from_conf%/}/"
            echo "Using configured source: $rsync_src"
        else
            rsync_src="$(_project_rsync_src "$lang")"
            echo "Using default source path: $rsync_src"
        fi

        rsync_opt="rsync -acvzt --timeout=10 --no-times --exclude-from=${rsync_exclude}"
        [[ "$lang" == "node" ]] && rsync_opt+=" --delete"

        if [[ "$rsync_dest" == "none" || -z "$rsync_dest" ]]; then
            rsync_dest="${ENV_PATH_DEST_PRE:-/var/www}/${G_NAMESPACE}_${G_REPO_NAME}/"
        fi

        if [[ "${rsync_dest}" =~ 'oss://' ]]; then
            if ${G_DRY_RUN:-false} || [[ "${GITHUB_ACTIONS}" == "true" ]]; then
                _msg note "[dry-run] deploy_aliyun_oss:"
                _msg note "  Source: ${rsync_src}"
                _msg note "  Destination: ${rsync_dest}"
                continue
            fi
            _oss_upload "${rsync_src}" "${rsync_dest}"
            continue
        fi

        echo "Destination: ${ssh_host}:${rsync_dest}"
        if ${G_DRY_RUN:-false} || [[ "${GITHUB_ACTIONS}" == "true" ]]; then
            _msg note "[dry-run] deploy_rsync_ssh:"
            _msg note "  $ssh_opt -n \"$ssh_host\" \"mkdir -p $rsync_dest\""
            _msg note "  ${rsync_opt} -e \"$ssh_opt\" \"$rsync_src\" \"${ssh_host}:${rsync_dest}\""
            continue
        fi
        if $ssh_opt -n "$ssh_host" "mkdir -p $rsync_dest" && ${rsync_opt} -e "$ssh_opt" "$rsync_src" "${ssh_host}:${rsync_dest}"; then
            _msg ok "rsync+ssh deployment succeeded for ${ssh_host}:${rsync_dest}"
        else
            G_DEPLOY_RESULT=1
            _msg error "rsync+ssh deployment failed for ${ssh_host}:${rsync_dest}"
            continue
        fi

        if [[ -f "${G_DATA}/bin/deploy.custom.sh" ]]; then
            if ${G_DRY_RUN:-false}; then
                dry_run_note "bash ${G_DATA}/bin/deploy.custom.sh ${ssh_host} ${rsync_dest}"
            else
                _msg task "Executing custom deployment script"
                if bash "${G_DATA}/bin/deploy.custom.sh" "$ssh_host" "$rsync_dest"; then
                    _msg task "Custom deployment completed"
                else
                    G_DEPLOY_RESULT=1
                    _msg error "Custom deployment script failed for ${ssh_host}"
                fi
            fi
        fi
    done < <(_project_hosts)
}

deploy_aliyun_oss() {
    # 部署到阿里云 OSS
    # @param $1 source_path The source path to upload from
    # @param $2 oss_dest The OSS destination path (format: oss://bucket-name/path)
    local source_path="${1:?'source_path parameter is required'}"
    local oss_dest="${2:?'oss_dest parameter is required (format: oss://bucket-name/path)'}"

    dry_run_skip "ossutil cp ${source_path%/}/ ${oss_dest} --recursive --force" && return 0
    _msg task "Deploy files to Aliyun OSS"
    _oss_upload "${source_path}" "${oss_dest}"
    _msg task "Aliyun OSS deployment completed"
}

_oss_upload() {
    # 内部函数：安装 ossutil 并把目录上传到 OSS
    # Reused by deploy_aliyun_oss (standalone -O) and deploy_via_rsync_ssh (oss:// branch)
    # @param $1 source_path The source path to upload from
    # @param $2 oss_dest The OSS destination path (format: oss://bucket-name/path)
    local source_path="${1:?'source_path parameter is required'}"
    local oss_dest="${2:?'oss_dest parameter is required (format: oss://bucket-name/path)'}"
    _install_ossutil

    if ossutil cp "${source_path%/}/" "${oss_dest}" --recursive --force; then
        _msg ok "Deployment successful"
    else
        G_DEPLOY_RESULT=1
        _msg error "Deployment failed"
    fi
}

deploy_via_rsync() {
    # 通过 rsync（rsyncd 守护进程，模块式）部署
    # 连接参数读取顺序: data/conf/rsyncd.conf (旧配置) > ENV_RSYNC_* (deploy.env)
    _msg task "Deploy files to Rsyncd server"
    local rsyncd_conf
    rsyncd_conf="$G_DATA/conf/rsyncd.conf"
    if [[ -f "$rsyncd_conf" ]]; then
        source "$rsyncd_conf"
    fi

    local exclude_file="${EXCLUDE_FILE:-${G_PATH}/conf/rsync.exclude}"
    local source_dir="${SOURCE_DIR:-$G_REPO_DIR}"
    local rsync_user="${RSYNC_USER:-${ENV_RSYNC_USER:-}}"
    local rsync_host="${RSYNC_HOST:-${ENV_RSYNC_HOST:-}}"
    local target_dir="${TARGET_DIR:-${ENV_RSYNC_TARGET_DIR:-}}"

    if [[ -z "$rsync_user" || -z "$rsync_host" || -z "$target_dir" ]]; then
        _msg error "Rsync daemon connection is not configured."
        _msg error "Set ENV_RSYNC_USER / ENV_RSYNC_HOST / ENV_RSYNC_TARGET_DIR in deploy.env,"
        _msg error "or provide EXCLUDE_FILE / SOURCE_DIR / RSYNC_USER / RSYNC_HOST / TARGET_DIR in ${G_DATA}/conf/rsyncd.conf"
        return 1
    fi

    local rsync_options="rsync -avz --exclude-from=${exclude_file}"
    dry_run_skip "${rsync_options} ${source_dir}/ ${rsync_user}@${rsync_host}::${target_dir}" && return 0
    if ! $rsync_options "${source_dir}/" "${rsync_user}@${rsync_host}::${target_dir}"; then
        G_DEPLOY_RESULT=1
        _msg error "rsync daemon deployment failed"
    fi
}

deploy_via_ftp() {
    # 通过 FTP 部署
    # 凭据来自 deploy.env: ENV_FTP_HOST / ENV_FTP_USERNAME / ENV_FTP_PASSWORD / ENV_FTP_DIRECTORY
    _msg task "Deploy files to FTP server"
    local ftp_host="${ENV_FTP_HOST:-}" ftp_username="${ENV_FTP_USERNAME:-}"
    local ftp_password="${ENV_FTP_PASSWORD:-}" ftp_directory="${ENV_FTP_DIRECTORY:-}"
    if [[ -z "$ftp_host" || -z "$ftp_username" || -z "$ftp_password" ]]; then
        _msg error "FTP deployment requires ENV_FTP_HOST / ENV_FTP_USERNAME / ENV_FTP_PASSWORD in deploy.env"
        return 1
    fi

    local upload_file="${G_REPO_DIR}/ftp.tgz" upload_name
    upload_name="$(basename "$upload_file")"
    dry_run_skip "tar czf ${upload_file} -C ${G_REPO_DIR} . && ftp -inv ${ftp_host} (user/pass, cd ${ftp_directory:-/}, put ${upload_name})" && return 0
    command -v ftp >/dev/null || { _msg error "ftp command not found"; return 1; }
    if ! tar czf "$upload_file" -C "$G_REPO_DIR" .; then
        G_DEPLOY_RESULT=1
        _msg error "Failed to create ${upload_file}"
        return 1
    fi
    if ftp -inv "$ftp_host" <<EOF
user $ftp_username $ftp_password
cd ${ftp_directory:-/}
passive on
binary
delete $upload_name
put $upload_file
passive off
bye
EOF
    then
        _msg task "FTP deployment completed"
    else
        G_DEPLOY_RESULT=1
        _msg error "FTP deployment failed"
    fi
    rm -f "$upload_file"
}

deploy_via_sftp() {
    # 通过 SFTP 部署
    # 目标主机读取顺序: 项目配置 hosts[].{user,host,port,rsync_dest} > ENV_SFTP_HOST/USERNAME/PORT/DIRECTORY
    # 上传方式: tar 打包后 sftp 批量命令上传; 若设置 ENV_SFTP_PASSWORD 则使用 sshpass 密码认证
    local lang="${1:-}"
    _msg task "Deploy files to SFTP server"

    local upload_file="${G_REPO_DIR}/sftp.tgz" upload_name
    upload_name="$(basename "$upload_file")"
    local has_host=false
    local ssh_user ssh_host_ip ssh_port remote_dir

    dry_run_skip "tar czf ${upload_file} -C ${G_REPO_DIR} . && sftp -b <batch> <user@host> (mkdir/put ${upload_name})" && return 0
    command -v sftp >/dev/null || { _msg error "sftp command not found"; return 1; }
    if ! tar czf "$upload_file" -C "$G_REPO_DIR" .; then
        G_DEPLOY_RESULT=1
        _msg error "Failed to create ${upload_file}"
        return 1
    fi

    while read -r line; do
        ssh_user=$(echo "$line" | jq -r '.user // empty')
        ssh_host_ip=$(echo "$line" | jq -r '.host // empty')
        ssh_port=$(echo "$line" | jq -r '.port // "22"')
        remote_dir=$(echo "$line" | jq -r '.rsync_dest // empty')
        [[ -z "$ssh_host_ip" ]] && continue
        has_host=true
        [[ -z "$remote_dir" ]] && remote_dir="/var/www/${G_NAMESPACE}_${G_REPO_NAME}"
        _sftp_upload_one "${ssh_user:-}" "$ssh_host_ip" "$ssh_port" "$remote_dir" "$upload_file"
    done < <(_project_hosts)

    if ! $has_host; then
        ssh_host_ip="${ENV_SFTP_HOST:-}"
        if [[ -z "$ssh_host_ip" ]]; then
            _msg error "SFTP deployment requires hosts[] in project config or ENV_SFTP_HOST in deploy.env"
            rm -f "$upload_file"
            return 1
        fi
        ssh_user="${ENV_SFTP_USERNAME:-}"
        ssh_port="${ENV_SFTP_PORT:-22}"
        if [[ -n "${ENV_SFTP_DIRECTORY:-}" ]]; then
            remote_dir="${ENV_SFTP_DIRECTORY}"
        else
            remote_dir="/var/www/${G_NAMESPACE}_${G_REPO_NAME}"
        fi
        _sftp_upload_one "$ssh_user" "$ssh_host_ip" "$ssh_port" "$remote_dir" "$upload_file"
    fi
    rm -f "$upload_file"
    [[ "${G_DEPLOY_RESULT:-0}" -eq 0 ]] && _msg task "SFTP deployment completed"
}

_sftp_upload_one() {
    # 单台主机 SFTP 上传（内部函数）
    local ssh_user="$1" ssh_host_ip="$2" ssh_port="$3" remote_dir="$4" upload_file="$5"
    local ssh_host sftp_batch sftp_cmd
    ssh_host="${ssh_user:+${ssh_user}@}${ssh_host_ip}"
    sftp_batch="$(mktemp)"
    cat >"$sftp_batch" <<EOF
-mkdir $remote_dir
cd $remote_dir
put $upload_file
EOF
    if [[ -n "${ENV_SFTP_PASSWORD:-}" ]]; then
        command -v sshpass >/dev/null || {
            G_DEPLOY_RESULT=1
            _msg error "sshpass command not found (required for ENV_SFTP_PASSWORD)"
            rm -f "$sftp_batch"
            return 1
        }
        # 密码经 SSHPASS 环境变量传入，避免出现在进程 argv（ps 可见）
        export SSHPASS="${ENV_SFTP_PASSWORD}"
        sftp_cmd=(sshpass -e sftp)
    else
        unset SSHPASS
        sftp_cmd=(sftp)
    fi
    if ! "${sftp_cmd[@]}" -P "${ssh_port:-22}" -o StrictHostKeyChecking=no -b "$sftp_batch" "$ssh_host"; then
        G_DEPLOY_RESULT=1
        _msg error "SFTP upload failed for ${ssh_host}"
    fi
    rm -f "$sftp_batch"
}

deploy_to_docker_compose() {
    # 用 docker compose 部署
    # 目标主机读取项目配置 hosts[]，上传源码/构建产物后执行 docker compose up -d --build
    # @param $1 lang The programming language of the project
    local lang="${1:-}"
    _msg task "Deploy with Docker Compose"
    local rsync_exclude ssh_user ssh_host_ip ssh_port rsync_src_from_conf rsync_dest service
    local ssh_host ssh_opt rsync_src rsync_opt hosts_found=false
    rsync_exclude="$(_rsync_exclude_file)"

    while read -r line; do
        ssh_user=$(echo "$line" | jq -r '.user // empty')
        ssh_host_ip=$(echo "$line" | jq -r '.host // empty')
        ssh_port=$(echo "$line" | jq -r '.port // "22"')
        rsync_src_from_conf=$(echo "$line" | jq -r '.rsync_src // empty')
        rsync_dest=$(echo "$line" | jq -r '.rsync_dest // empty')
        service=$(echo "$line" | jq -r '.service // empty')

        [[ -z "$ssh_host_ip" ]] && continue
        hosts_found=true

        ssh_host="${ssh_user:+${ssh_user}@}${ssh_host_ip}"
        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=10 -p ${ssh_port:-22}"
        [[ -n "$rsync_src_from_conf" ]] && rsync_src="${rsync_src_from_conf%/}/" || rsync_src="$(_project_rsync_src "$lang")"
        [[ -n "$rsync_dest" ]] || rsync_dest="/opt/${G_REPO_NAME}"
        [[ -n "$service" ]] || service="$G_REPO_NAME"
        rsync_opt="rsync -acvzt --timeout=10 --no-times --exclude-from=${rsync_exclude}"

        echo "Destination: ${ssh_host}:${rsync_dest} (docker compose service: ${service})"
        if ${G_DRY_RUN:-false}; then
            dry_run_note "${rsync_opt} -e \"$ssh_opt\" \"$rsync_src\" \"${ssh_host}:${rsync_dest}/\""
            dry_run_note "$ssh_opt ${ssh_host} 'cd $rsync_dest && docker compose up -d --build ${service}'"
            continue
        fi
        if $ssh_opt -n "$ssh_host" "mkdir -p $rsync_dest" &&
            ${rsync_opt} -e "$ssh_opt" "$rsync_src" "${ssh_host}:${rsync_dest}/" &&
            $ssh_opt -n "$ssh_host" "cd $rsync_dest && docker compose up -d --build $service"; then
            _msg ok "Docker Compose deployment completed for ${ssh_host}"
        else
            G_DEPLOY_RESULT=1
            _msg error "Docker Compose deployment failed for ${ssh_host}:${rsync_dest}"
        fi
    done < <(_project_hosts)

    if ! $hosts_found; then
        _msg error "Docker Compose deployment requires hosts[] in project config (data/conf/namespace/project-name.json)"
        return 1
    fi
}

detect_deployment_method() {
    # 依据项目文件与环境探测部署方式
    # Priority order:
    #   1. Helm charts (if exist and k8s available) → deploy_k8s
    #   2. Dockerfile (if exist and k8s available) → deploy_k8s
    #   3. docker-compose.yml → deploy_docker
    #   4. Project config with hosts → deploy_rsync_ssh
    #   5. Default → deploy_rsync_ssh (with warning)
    # Returns:
    #   deploy_method: The determined deployment method
    local file
    local release_name has_dockerfile=false has_docker_compose=false has_project_config=false

    # Get release name for Helm charts check
    release_name="$(format_release_name 2>/dev/null || echo "")"

    _msg task "Determining deployment method" >&2

    ## 检查配置文件中的部署方式覆盖
    if [[ -n "${PROJECT_DEPLOY_METHOD:-}" && "${PROJECT_DEPLOY_METHOD}" != "auto" ]]; then
        case "${PROJECT_DEPLOY_METHOD}" in
        k8s)
            if check_k8s_available; then
                _msg note "Using configured deployment method: deploy_k8s" >&2
                echo "deploy_k8s"
                return 0
            else
                _msg warn "Configured method 'k8s' but k8s is not available, falling back to auto detection" >&2
            fi
            ;;
        docker)
            _msg note "Using configured deployment method: deploy_docker" >&2
            echo "deploy_docker"
            return 0
            ;;
        rsync)
            _msg note "Using configured deployment method: deploy_rsync_ssh" >&2
            echo "deploy_rsync_ssh"
            return 0
            ;;
        ftp)
            _msg note "Using configured deployment method: deploy_ftp" >&2
            echo "deploy_ftp"
            return 0
            ;;
        fc)
            _msg note "Using configured deployment method: deploy_aliyun_func" >&2
            echo "deploy_aliyun_func"
            return 0
            ;;
        oss)
            _msg note "Using configured deployment method: deploy_aliyun_oss" >&2
            echo "deploy_aliyun_oss"
            return 0
            ;;
        sftp)
            _msg note "Using configured deployment method: deploy_sftp" >&2
            echo "deploy_sftp"
            return 0
            ;;
        esac
    fi

    # Step 1: Check for Helm charts (highest priority for k8s)
    # prefer_k8s=false: 跳过 k8s，顺延到 docker-compose / rsync
    if [[ "${PROJECT_PREFER_K8S:-true}" == true ]] && check_helm_charts_exist "${release_name}"; then
        if check_k8s_available; then
            _msg note "found Helm charts and k8s is available → deploy_k8s" >&2
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

    if [[ "${PROJECT_PREFER_K8S:-true}" == true ]] && [[ "$has_dockerfile" == true ]]; then
        if check_k8s_available; then
            _msg note "Found Dockerfile and k8s is available → deploy_k8s" >&2
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
        _msg note "Found docker-compose.yml → deploy_docker" >&2
        echo "deploy_docker"
        return 0
    fi

    # Step 4: Check for project config with valid hosts
    if [[ -n "${G_CONF:-}" && -f "${G_CONF}" ]]; then
        # Check if config has valid hosts for current namespace
        if jq -e --arg branch "${G_NAMESPACE:-}" \
            '.branches[] | select(.branch == $branch) | .hosts[] | select(.host != null and .host != "")' \
            "${G_CONF}" &>/dev/null; then
            has_project_config=true
        fi
    fi

    if [[ "$has_project_config" == true ]]; then
        _msg note "Found project config with hosts → deploy_rsync_ssh" >&2
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

stage_deploy() {
    # 部署主入口：按方式分发到对应 deploy_*
    _msg stage "$(_t '部署' 'deployment')"
    ## 部署方式单一来源: 用户显式指定（RUN_DEPLOY 非空）时按优先级取首个启用项；
    ## 自动模式（RUN_DEPLOY 为空）留空 type，走下方 detect_deployment_method 探测链路
    local -a deploy_order=(deploy_k8s deploy_rsync_ssh deploy_rsync deploy_ftp deploy_sftp deploy_aliyun_func deploy_aliyun_oss deploy_docker)
    local deploy_key deploy_first="" type=""
    if [[ ${#RUN_DEPLOY[@]} -gt 0 ]]; then
        for deploy_key in "${deploy_order[@]}"; do
            [[ -z "$deploy_first" && "${RUN_DEPLOY[*]}" == *"$deploy_key"* ]] && deploy_first="$deploy_key"
        done
        type="$deploy_first"
    fi

    ## 语言类型由部署流程内部探测（detect_repo_language 有缓存，重复调用廉价）
    local lang
    lang="$(detect_repo_language | cut -d: -f1)"
    ## 保持 $@ 首位为 lang（下游 deploy_* 函数读取 $1）
    set -- "${lang}"

    # 如果没有指定部署方法，先进行探测
    if [ -z "$type" ]; then
        type=$(detect_deployment_method "$@")
    fi

    case "$type" in
    deploy_k8s)
        G_DEPLOY_RESULT=0
        deploy_to_kubernetes "$@" || G_DEPLOY_RESULT=$?
        ;;
    deploy_docker)
        G_DEPLOY_RESULT=0
        deploy_to_docker_compose "$@" || G_DEPLOY_RESULT=$?
        ;;
    deploy_aliyun_func)
        G_DEPLOY_RESULT=0
        deploy_aliyun_functions "$@" || G_DEPLOY_RESULT=$?
        ;;
    deploy_aliyun_oss)
        G_DEPLOY_RESULT=0
        local oss_src oss_dest oss_lang="${1:-}"
        oss_dest=$(_project_oss_dest)
        if [[ -z "$oss_dest" ]]; then
            _msg error "OSS deployment requires a host with oss:// rsync_dest in project config, or ENV_OSS_DEST in deploy.env"
            G_DEPLOY_RESULT=1
        else
            oss_src="${ENV_OSS_SOURCE:-}"
            [[ -n "$oss_src" ]] || oss_src="$(_project_rsync_src "$oss_lang")"
            deploy_aliyun_oss "$oss_src" "$oss_dest" || G_DEPLOY_RESULT=$?
        fi
        ;;
    deploy_rsync)
        G_DEPLOY_RESULT=0
        deploy_via_rsync "$@" || G_DEPLOY_RESULT=$?
        ;;
    deploy_ftp)
        G_DEPLOY_RESULT=0
        deploy_via_ftp "$@" || G_DEPLOY_RESULT=$?
        ;;
    deploy_sftp)
        G_DEPLOY_RESULT=0
        deploy_via_sftp "$@" || G_DEPLOY_RESULT=$?
        ;;
    deploy_rsync_ssh)
        G_DEPLOY_RESULT=0
        deploy_via_rsync_ssh "$@" || G_DEPLOY_RESULT=$?
        ;;
    *)
        G_DEPLOY_RESULT=1
        _msg error "Unknown or invalid deployment method: $type"
        ;;
    esac
    ## 部署结果写入 G_DEPLOY_RESULT 供通知与最终退出码使用；main 是裸调用，
    ## 此处固定返回 0，避免 set -e 中断流水线导致 handle_notify 被跳过
    ## 部署后清理索引里已失效的镜像引用（随机仓库池的遗留 + 删除失败重试）
    _clean_indexed_images || true
    return 0
}

# Export the function
# export -f detect_deployment_method

copy_docker_image() {
    # 把镜像从源仓库复制到目标仓库
    # @param $1 source_image Source image name (e.g., nginx:latest)
    # @param $2 target_registry Target registry (e.g., registry.example.com)
    ## RUN 单数组成员（-c/--copy-image 触发，parse 组装并必填校验 arg_src）
    ## 守卫: 防御性校验 arg_src（parse 的 ${2:?} 已保证非空）
    [[ -n "${arg_src:-}" ]] || return 0
    local source_image="${arg_src}" target_registry image_name tag target base_name

    ## 目标 registry 缺省回退到镜像源地址，仍为空则终止
    [ -z "$arg_target" ] && arg_target="${ENV_DOCKER_MIRROR:-}"
    [ -z "$arg_target" ] && exit 1
    target_registry="${arg_target}"

    if ${G_DRY_RUN:-false}; then
        dry_run_note "skopeo --override-os linux copy --multi-arch all docker://${source_image} docker://${target_registry%/}/..."
        exit 0
    fi

    if ! command -v skopeo >/dev/null 2>&1; then
        _msg error "skopeo command not found. Please install skopeo first."
        exit 1
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

    # 检查目标镜像是否已存在但是只警告
    if skopeo inspect "docker://${target}" &>/dev/null; then
        _msg warn "Target image already exists: ${target}"
    fi

    echo "Copying multi-arch image to custom registry..."
    echo "skopeo --override-os linux copy --multi-arch all docker://${source_image} docker://${target}"

    if skopeo --override-os linux copy --multi-arch all \
        "docker://${source_image}" \
        "docker://${target}"; then
        _msg ok "Successfully copied image to ${target}"
        exit 0
    else
        _msg error "Failed to copy image to ${target}"
        exit 1
    fi
}

# Example usage:
# copy_docker_image "nginx:latest" "registry.example.com/ns"         # -> registry.example.com/ns/nginx:latest
# copy_docker_image "nginx" "registry.example.com/ns"              # -> registry.example.com/ns/nginx:latest
# copy_docker_image "ubuntu:22.04" "registry.example.com/ns"       # -> registry.example.com/ns/ubuntu:22.04

_image_index_add() {
    # 登记一个"本工具 push 过、尚需跟踪删除"的引用（台账行: push <ref>），已登记过则跳过
    # 在 push 前调用：中断或后续删除失败都不会丢引用（索引是唯一取证来源）
    local ref="${1:?image ref required}"
    mkdir -p "$(dirname "${G_IMAGE_INDEX}")"
    ## live 行与 push 行都是" ref" 结尾，命中任一即无需重复登记
    if [[ -f "${G_IMAGE_INDEX}" ]] && grep -Fq -- " ${ref}" "${G_IMAGE_INDEX}"; then
        return 0
    fi
    printf 'push %s\n' "${ref}" >>"${G_IMAGE_INDEX}"
}

_image_index_set_live() {
    # 把 key（<release_name>-<命名空间>）的当前部署引用标记为 live：
    #   旧 live 引用降级为 push（下次清理删除），新引用升为 live 并删掉它可能存在的 push 行
    # 索引是清理的唯一依据，故整文件原子重写（tmp + mv），不原地改
    local key="${1:?key required}" ref="${2:?image ref required}"
    local tmp="${G_IMAGE_INDEX}.tmp.$$" state f1 f2 old=""
    mkdir -p "$(dirname "${G_IMAGE_INDEX}")"
    : >"${tmp}"
    if [[ -f "${G_IMAGE_INDEX}" ]]; then
        while read -r state f1 f2; do
            [[ -n "${state}" ]] || continue
            case "${state}" in
            live)
                if [[ "${f1}" == "${key}" ]]; then
                    old="${f2}"
                else
                    printf 'live %s %s\n' "${f1}" "${f2}" >>"${tmp}"
                fi
                ;;
            push)
                [[ "${f1}" == "${ref}" ]] || printf 'push %s\n' "${f1}" >>"${tmp}"
                ;;
            *)
                _msg error "Corrupted index line, abort: ${state} ${f1} ${f2}"
                rm -f "${tmp}"
                return 1
                ;;
            esac
        done <"${G_IMAGE_INDEX}"
    fi
    [[ -n "${old}" && "${old}" != "${ref}" ]] && printf 'push %s\n' "${old}" >>"${tmp}"
    printf 'live %s %s\n' "${key}" "${ref}" >>"${tmp}"
    mv -f "${tmp}" "${G_IMAGE_INDEX}"
}

_image_ref_exists() {
    # 判断引用是否仍在 registry（ref 形如 <reg>[/<ns>...]/<repo>:<tag>；repo 可含多级路径，按最后一个 ':' 切 tag）
    [[ "${1:-}" == *:* ]] || return 1
    local ref="${1}" repo="${1%:*}" tag="${1##*:}"
    skopeo list-tags "docker://${repo}" 2>/dev/null | grep -Fq "\"${tag}\""
}

_clean_indexed_images() {
    # 清理索引里已不再存活的镜像引用（只删本工具 push 过的，不碰同仓库里其他项目的 tag）
    # 存活 = live 行，或本次运行引用；push 行非存活才删
    # 删除成功或引用本就不存在 → 移出索引；删除失败且引用仍在 → 保留待下次重试
    # 索引出现无法解析的行 → 报错并放弃清理（宁可留残留，也不误删存活镜像）
    [[ -f "${G_IMAGE_INDEX}" ]] || return 0
    if ! command -v skopeo >/dev/null 2>&1; then
        _msg note "skopeo not found; skip indexed image cleanup"
        return 0
    fi
    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] clean indexed images: ${G_IMAGE_INDEX}"
        return 0
    fi

    local state f1 f2
    local current_ref="${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME:-}:${G_IMAGE_TAG:-}"
    local -A live_refs=()
    local -a live_lines=() push_refs=()
    while read -r state f1 f2; do
        [[ -n "${state}" ]] || continue
        case "${state}" in
        live)
            live_refs["${f2}"]=1
            live_lines+=("live ${f1} ${f2}")
            ;;
        push)
            push_refs+=("${f1}")
            ;;
        *)
            _msg error "Corrupted index line, abort cleanup: ${state} ${f1} ${f2}"
            return 1
            ;;
        esac
    done <"${G_IMAGE_INDEX}"

    local ref deleted=0 kept=0
    local -a keep=()
    for ref in "${push_refs[@]}"; do
        ## 已有 live 行记录它 → 台账行冗余，丢弃
        [[ -n "${live_refs[${ref}]:-}" ]] && continue
        ## 本次运行刚 push、还没确认部署成功 → 保持跟踪（纯构建运行时不会有 live 行）
        if [[ "${ref}" == "${current_ref}" ]]; then
            keep+=("push ${ref}")
            kept=$((kept + 1))
            continue
        fi
        if skopeo delete "docker://${ref}" >/dev/null 2>&1; then
            ## 与 _clean_tags_one 的粒度一致：逐条删除用 note，批次结果用 task
            _msg note "Deleted stale image: ${ref}"
            deleted=$((deleted + 1))
        elif _image_ref_exists "${ref}"; then
            _msg warn "Failed to delete stale image, keep for retry: ${ref}"
            keep+=("push ${ref}")
            kept=$((kept + 1))
        else
            _msg note "Stale image already gone: ${ref}"
        fi
    done

    local tmp="${G_IMAGE_INDEX}.tmp.$$"
    : >"${tmp}"
    [[ "${#live_lines[@]}" -gt 0 ]] && printf '%s\n' "${live_lines[@]}" >>"${tmp}"
    [[ "${#keep[@]}" -gt 0 ]] && printf '%s\n' "${keep[@]}" >>"${tmp}"
    mv -f "${tmp}" "${G_IMAGE_INDEX}"
    ## 无删除也无保留（绝大多数部署）时不打印，避免每次部署一条 deleted=0, kept=0 噪音
    if [[ "${deleted}" -gt 0 || "${kept}" -gt 0 ]]; then
        _msg task "Indexed image cleanup: deleted=${deleted}, kept=${kept}"
    fi
}

clean_old_tags() {
    # 清理注册表旧 tag 的入口（RUN 单数组成员，--clean-tags 触发）
    # 目标形态（可省略 registry，回退 ENV_DOCKER_REGISTRY，其值形如 host/namespace）:
    #   <reg>/<ns>/<repo>  /  <repo>              直接清理该仓库
    #   <reg>/<ns>/  /  /  /  <repo>/             散列仓库池（a-o × a-o = 225）→ fzf 多选后逐个清理
    # 天龄阈值 ENV_CLEAN_TAGS_DAYS（默认 180）；无时间戳 tag 是否强删由 ENV_CLEAN_TAGS_FORCE 控制
    [[ -n "${arg_clean_tags:-}" ]] || return 0
    local target
    target="$(_clean_tags_resolve "${arg_clean_tags}")"
    if [[ "${target}" != */* ]]; then
        _msg error "--clean-tags '${arg_clean_tags}' 无法解析成仓库（ENV_DOCKER_REGISTRY 未设置？）"
        return 1
    fi
    case "${target}" in
    */ | *'/*')
        _clean_tags_select "${target%/*}"
        return $?
        ;;
    esac
    _clean_tags_one "${target}"
}

_clean_tags_resolve() {
    # 相对写法补上 ENV_DOCKER_REGISTRY：首段为空或不含 '.'/':' 视为相对
    #   相对: fm / fm/ / / / /fm → ${ENV_DOCKER_REGISTRY}/fm ...
    #   绝对: registry.example.com/ns/repo、localhost:5000/ns/repo → 原样返回
    local value="${1-}" first="${1%%/*}"
    if [[ -n "${first}" && "${first}" == *.* || "${first}" == *:* ]]; then
        printf '%s' "${value}"
    elif [[ -n "${ENV_DOCKER_REGISTRY:-}" ]]; then
        printf '%s' "${ENV_DOCKER_REGISTRY%/}/${value#/}"
    else
        printf '%s' "${value}"
    fi
}

_clean_tags_one() {
    # 清理单个仓库：skopeo list-tags → 取 tag 尾部数字段当时间戳 → 超期删除
    # 仓库不存在/无权限时 list 失败，只 warn 并 return 1，不中断调用方（fzf 多选容易命中空仓库）
    local repository="${1:?repository required}" cutoff_time current_time tags_file tags_to_delete=() delete_force=false tag tag_timestamp
    local clean_days="${ENV_CLEAN_TAGS_DAYS:-180}"
    local total_tags
    delete_force="${ENV_CLEAN_TAGS_FORCE:-false}"

    _msg task "Cleaning old tags from registry: ${repository}"
    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] clean_old_tags:"
        _msg note "  skopeo list-tags docker://${repository} + delete tags older than ${clean_days} days"
        return 0
    fi

    # Calculate cutoff time (6 months ago in seconds) / 计算截止时间（N 天前的秒数）
    current_time=$(date +%s)
    cutoff_time=$((current_time - clean_days * 24 * 60 * 60))

    # Get all tags using skopeo / 使用 skopeo 获取所有标签
    tags_file=$(mktemp)
    echo "tags file is: ${tags_file}"
    if ! skopeo list-tags "docker://${repository}" >"$tags_file"; then
        _msg warn "Cannot list tags (repository missing or no permission), skip: ${repository}"
        rm -f "$tags_file"
        return 1
    fi

    # Parse tags and check timestamps / 解析标签并检查时间戳
    while read -r tag; do
        # Skip empty tags / 跳过空标签
        [ -z "$tag" ] && continue

        # Try to extract timestamp from tag / 尝试从标签中提取时间戳
        # 当前 tag 格式为 t<毫秒>（G_IMAGE_TAG="t$(date +%s%3N)"）；旧格式为 <shortsha>-<毫秒>。
        # 仅末尾为 10 位及以上数字段时按时间戳处理：13 位判定为毫秒，转成秒后再与截止时间比较。
        # 其余 tag 视为无时间戳，仅 delete_force 时删除。
        if [[ "$tag" =~ ([0-9]{10,})$ ]]; then
            # BASH_REMATCH[1] contains just the captured digits / 捕获的数字段
            tag_timestamp="${BASH_REMATCH[1]}"

            # Convert milliseconds to seconds / 毫秒时间戳（13 位）转秒
            if [ "${#tag_timestamp}" -ge 13 ]; then
                tag_timestamp=$((tag_timestamp / 1000))
            fi

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
    _msg task "Total tags / 总标签数: $total_tags"
    _msg task "Tags to delete / 要删除的标签数: ${#tags_to_delete[@]}"

    # Clean up temporary file / 清理临时文件
    rm -f "$tags_file"

    # Delete old tags / 删除旧标签
    local delete_failed=0
    if [ "${#tags_to_delete[@]}" -gt 0 ]; then
        _msg task "Deleting old tags... / 正在删除旧标签..."
        for tag in "${tags_to_delete[@]}"; do
            _msg note "Deleting / 正在删除: $tag"
            if ! skopeo delete "docker://${repository}:${tag}"; then
                _msg error "Failed to delete tag / 删除标签失败: ${tag}"
                delete_failed=1
            fi
            sleep 1
        done
    else
        _msg task "No old tags to delete / 没有需要删除的旧标签"
    fi
    return "$delete_failed"
}

_clean_tags_select() {
    # 候选 = 该命名空间下的散列仓库池（a-o × a-o = 225，与 G_IMAGE_NAME 的随机空间一致）
    # 不做存在性探测：ACR 个人版无 OpenAPI，225 次 list-tags 不划算；不存在的候选在清理阶段 warn 跳过
    # 交互: fzf -m（TAB 多选、ENTER 确认）；无 fzf 或非 tty 时直接报错，避免 CI 里静默误删
    local prefix="${1:?namespace prefix required}"
    local -a chars candidates=() selected=()
    local selection repo rc=0
    chars=({a..o})
    for c1 in "${chars[@]}"; do
        for c2 in "${chars[@]}"; do
            candidates+=("${prefix}/${c1}${c2}")
        done
    done

    if ! command -v fzf >/dev/null 2>&1; then
        _msg error "fzf not found; specify the repository explicitly (e.g. ${prefix}/ab)"
        return 1
    fi
    if [[ ! -t 0 || ! -t 1 ]]; then
        _msg error "not a tty; specify the repository explicitly (e.g. ${prefix}/ab)"
        return 1
    fi

    if ! selection=$(printf '%s\n' "${candidates[@]}" | fzf -m --header="TAB 多选, ENTER 确认; 候选为 ${prefix} 下的散列仓库(a-o x a-o)"); then
        _msg note "Selection cancelled"
        return 0
    fi
    [[ -n "${selection}" ]] || {
        _msg note "Nothing selected"
        return 0
    }
    readarray -t selected <<<"${selection}"

    for repo in "${selected[@]}"; do
        [[ -n "${repo}" ]] || continue
        _clean_tags_one "${repo}" || rc=1
    done
    return "$rc"
}
