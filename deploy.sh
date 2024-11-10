#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=1090,1091,2086
################################################################################
#
# Description: deploy.sh is a CI/CD program.
# Author: xiagw <fxiaxiaoyu@gmail.com>
# License: GNU/GPL, see http://www.gnu.org/copyleft/gpl.html
# Create Date: 2019-04-03
#
################################################################################

## year month day - time - %u day of week (1..7); 1 is Monday - %j day of year (001..366) - %W week number of year, with Monday as first day of week (00..53)

_is_in_demo_mode() {
    local skip_msg="$1"
    if grep -qE '=your_(password|username)' "$SCRIPT_ENV"; then
        _msg purple "Found default docker credentials, skipping $skip_msg ..."
        return 0
    fi
    return 1
}

_test_unit() {
    local test_scripts=("$gitlab_project_dir/tests/unit_test.sh" "$SCRIPT_DATA/tests/unit_test.sh")

    for test_script in "${test_scripts[@]}"; do
        [[ -f "$test_script" ]] || continue
        _msg info "Executing unit test script: $test_script"
        if bash "$test_script"; then
            _msg green "Unit tests passed successfully"
        else
            _msg error "Unit tests failed"
        fi
        return
    done

    _msg purple "No unit test script found. Skipping unit tests."
}

_test_function() {
    local test_scripts=("$gitlab_project_dir/tests/func_test.sh" "$SCRIPT_DATA/tests/func_test.sh")

    for test_script in "${test_scripts[@]}"; do
        [[ -f "$test_script" ]] || continue
        _msg info "Executing functional test script: $test_script"
        if bash "$test_script"; then
            _msg green "Functional tests passed successfully"
            return 0
        else
            _msg error "Functional tests failed"
            return 1
        fi
    done

    _msg purple "No functional test script found. Skipping functional tests."
}

_run_sonarqube_analysis() {
    local sonar_url="${ENV_SONAR_URL:?empty}"
    local sonar_conf="$gitlab_project_dir/sonar-project.properties"

    if ! curl --silent --head --fail --connect-timeout 5 "$sonar_url" >/dev/null 2>&1; then
        _msg warning "SonarQube server not found, exiting."
        return 1
    fi

    if [[ ! -f "$sonar_conf" ]]; then
        _msg green "Creating $sonar_conf"
        cat >"$sonar_conf" <<EOF
sonar.host.url=$sonar_url
sonar.projectKey=${gitlab_project_namespace}_${gitlab_project_name}
sonar.qualitygate.wait=true
sonar.projectName=$gitlab_project_name
sonar.java.binaries=.
sonar.sourceEncoding=UTF-8
sonar.exclusions=\
docs/**/*,\
log/**/*,\
test/**/*
sonar.projectVersion=1.0
sonar.import_unknown_files=true
EOF
    fi

    ${github_action:-false} && return 0

    if ! $run_cmd -e SONAR_TOKEN="${ENV_SONAR_TOKEN:?empty}" -v "$gitlab_project_dir":/usr/src sonarsource/sonar-scanner-cli; then
        _msg error "SonarQube scan failed"
        return 1
    fi

    _msg time "[quality] Code quality check with SonarQube completed"
}

_run_zap_scan() {
    local target_url="${ENV_TARGET_URL}"
    local zap_image="${ENV_ZAP_IMAGE:-owasp/zap2docker-stable}"
    local zap_options="${ENV_ZAP_OPT:-"-t ${target_url} -r report.html"}"
    local zap_report_file
    zap_report_file="zap_report_$(date +%Y%m%d_%H%M%S).html"

    if $run_cmd_root -v "$(pwd):/zap/wrk" "$zap_image" zap-full-scan.sh $zap_options; then
        mv "$zap_report_file" "zap_report_latest.html"
        _msg green "ZAP scan completed. Report saved to zap_report_latest.html"
    else
        _msg error "ZAP scan failed."
        return 1
    fi
    _msg time "[scan] ZAP scan completed"
}
# _security_scan_zap "http://example.com" "my/zap-image" "-t http://example.com -r report.html -x report.xml"

_run_vulmap_scan() {
    # https://github.com/zhzyker/vulmap
    # $build_cmd run --rm -ti vulmap/vulmap  python vulmap.py -u https://www.example.com
    local config_file="$SCRIPT_DATA/config.cfg"
    local output_file="vulmap_report.html"

    # Load environment variables from config file
    source "$config_file"

    # Run vulmap scan
    $run_cmd_root -v "${PWD}:/work" vulmap -u "${ENV_TARGET_URL}" -o "/work/$output_file"
    if [[ -f "$output_file" ]]; then
        _msg green "Vulmap scan complete. Results saved to '$output_file'."
    else
        _msg error "Vulmap scan failed or no vulnerabilities found."
    fi
}

# _check_gitleaks /path/to/repo /path/to/config.toml
_check_gitleaks() {
    local path="$1"
    local config_file="$2"
    local gitleaks_image="zricethezav/gitleaks:v7.5.0"
    local gitleaks_cmd="gitleaks --path=/repo --config=/config.toml"

    $run_cmd_root \
        -v "$path:/repo" \
        -v "$config_file:/config.toml" \
        "$gitleaks_image" \
        $gitleaks_cmd
}

_deploy_flyway_docker() {
    local vol_conf="${gitlab_project_dir}/flyway_conf:/flyway/conf"
    local vol_sql="${gitlab_project_dir}/flyway_sql:/flyway/sql"
    local run="$build_cmd run --rm -v ${vol_conf} -v ${vol_sql} flyway/flyway"

    # SSH port-forward if needed
    [ -f "$SCRIPT_BIN/sshme" ] && source "$SCRIPT_BIN/sshme" port ssh_host ssh_forward_port

    # Execute Flyway
    if $run info | grep '^|' | grep -vE 'Category.*Version|Versioned.*Success|Versioned.*Deleted|DELETE.*Success'; then
        $run repair
        if $run migrate; then
            _msg green "Flyway migrate result = OK"
        else
            _msg error "Flyway migrate result = FAIL"
            return 1
        fi
        $run info | tail -n 10
    else
        _msg warning "No SQL migrations to apply."
    fi

    _msg time "[database] Deploy SQL files with Flyway"
}

_deploy_flyway_helm_job() {
    _msg step "[database] Deploy SQL with Flyway (Helm job)"

    if ${github_action:-false}; then
        _msg info "Skipping Flyway deployment in GitHub Actions"
        return 0
    fi

    echo "Image tag for Flyway: $image_tag_flyway"

    if ! $build_cmd build $build_cmd_opt --tag "${image_tag_flyway}" -f "${gitlab_project_dir}/Dockerfile.flyway" "${gitlab_project_dir}/"; then
        _msg error "Failed to build Flyway image"
        return 1
    fi

    if $run_cmd_root "$image_tag_flyway"; then
        _msg green "Flyway migration successful"
    else
        _msg error "Flyway migration failed"
        return 1
    fi

    _msg time "[database] Completed SQL deployment with Flyway (Helm job)"
}

# python-gitlab list all projects / 列出所有项目
# gitlab -o json -f path_with_namespace project list --page 1 --per-page 5 | jq -r '.[].path_with_namespace'
# 解决 Encountered 1 file(s) that should have been pointers, but weren't
# git lfs migrate import --everything$(awk '/filter=lfs/ {printf " --include='\''%s'\''", $1}' .gitattributes)

_login_docker_registry() {
    ${github_action:-false} && return 0
    local lock_login_registry="$SCRIPT_DATA/.docker.login.${ENV_DOCKER_LOGIN_TYPE:-none}.lock"
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
            $build_cmd login --username AWS --password-stdin "${ENV_DOCKER_REGISTRY%%/*}" >/dev/null; then
            touch "$lock_login_registry"
        else
            _msg error "AWS ECR login failed"
            return 1
        fi
        ;;
    *)
        _is_in_demo_mode "docker-login" && return 0

        if [[ -f "$lock_login_registry" ]]; then
            return 0
        fi
        if echo "${ENV_DOCKER_PASSWORD}" |
            $build_cmd login --username="${ENV_DOCKER_USERNAME}" --password-stdin "${ENV_DOCKER_REGISTRY%%/*}"; then
            touch "$lock_login_registry"
        else
            _msg error "Docker login failed"
            return 1
        fi
        ;;
    esac
}

_get_docker_context() {
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
        position_file="${SCRIPT_DATA:-.}/.docker_context_history"
        [[ -f "$position_file" ]] || echo 0 >"$position_file"
        # Read current position / 读取当前轮询位置
        position=$(<"$position_file")
        # Select context / 输出当前位置的值
        selected_context="${docker_contexts[position]}"
        # Update position / 更新轮询位置
        echo $((++position % ${#docker_contexts[@]})) >"$position_file"
        ;;
    esac

    build_cmd="${build_cmd:+"$build_cmd "}--context $selected_context"
    echo "$build_cmd"
}

_build_image() {
    ${github_action:-false} && return 0
    _msg step "[image] build container image"

    _get_docker_context

    ## build from Dockerfile.base
    local registry_base
    if [[ -z "$ENV_DOCKER_REGISTRY_BASE" ]]; then
        _msg warn "ENV_DOCKER_REGISTRY_BASE is undefined, using $ENV_DOCKER_REGISTRY instead."
        registry_base=$ENV_DOCKER_REGISTRY
    else
        registry_base=$ENV_DOCKER_REGISTRY_BASE
    fi
    if [[ -f "${gitlab_project_dir}/Dockerfile.base" ]]; then
        if [[ -f "${gitlab_project_dir}/build.base.sh" ]]; then
            _msg info "Found ${gitlab_project_dir}/build.base.sh, running it..."
            bash "${gitlab_project_dir}/build.base.sh"
        else
            local base_tag="${registry_base}:${gitlab_project_name}-${gitlab_project_branch}"
            _msg info "Building base image: $base_tag"
            $build_cmd build $build_cmd_opt \
                --tag "$base_tag" $build_arg \
                -f "${gitlab_project_dir}/Dockerfile.base" "${gitlab_project_dir}" || {
                _msg error "Failed to build base image"
                return 1
            }
            $build_cmd push $quiet_flag "$base_tag" || {
                _msg error "Failed to push base image"
                return 1
            }

        fi
        _msg time "[image] build base image"
        exit_directly=true
        return
    fi

    $build_cmd build $build_cmd_opt \
        --tag "${ENV_DOCKER_REGISTRY}:${image_tag}" $build_arg \
        "${gitlab_project_dir}" || {
        _msg error "Failed to build main image"
        return 1
    }

    if [[ "${MAN_TTL_SH:-false}" == true ]] || ${ENV_IMAGE_TTL:-false}; then
        local image_uuid
        image_uuid="ttl.sh/$(uuidgen):1h"
        _msg info "Temporary image tag for ttl.sh: $image_uuid"
        echo "## If you want to push the image to ttl.sh, please execute the following commands on gitlab-runner:"
        echo "  $build_cmd tag ${ENV_DOCKER_REGISTRY}:${image_tag} ${image_uuid}"
        echo "  $build_cmd push $image_uuid"
        echo "## Then execute the following commands on remote server:"
        echo "  $build_cmd pull $image_uuid"
        echo "  $build_cmd tag $image_uuid laradock_spring"
    fi
}

_push_image() {
    _msg step "[image] Pushing container image"
    _is_in_demo_mode "push-image" && return 0
    _login_docker_registry

    local push_error=false

    # Push main image
    if ! $build_cmd push $quiet_flag "${ENV_DOCKER_REGISTRY}:${image_tag}"; then
        push_error=true
    else
        $build_cmd rmi "${ENV_DOCKER_REGISTRY}:${image_tag}" >/dev/null
    fi

    # Push Flyway image if enabled
    if ${ENV_FLYWAY_HELM_JOB:-false}; then
        $build_cmd push $quiet_flag "$image_tag_flyway" || push_error=true
    fi

    # Check for errors
    $push_error && _msg error "got an error here, probably caused by network..."

    _msg time "[image] Image push completed"
}

_format_release_name() {
    if ${ENV_REMOVE_PROJ_PREFIX:-false}; then
        echo "remove project name prefix-"
        release_name=${gitlab_project_name#*-}
    else
        release_name=${gitlab_project_name}
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

_create_helm_chart() {
    local helm_chart_path helm_chart_name helm_chart_env protocol port port2
    helm_chart_path="$1"
    helm_chart_name="${helm_chart_path#"$(dirname $helm_chart_path)"/}"
    ## 获取 release 名称/协议/端口/等信息
    helm_chart_env=$SCRIPT_DATA/create_helm_chart.env
    ## create_helm_chart.env 格式： project_name  protocol  port  <port2> ，port2 可以为空
    if [ -f "${helm_chart_env}" ]; then
        read -ra values_array <<<"$(grep "^${helm_chart_name}\s" "${helm_chart_env}")"
        protocol="${values_array[1]}"
        port="${values_array[2]}"
        port2="${values_array[3]}"
    fi
    protocol="${protocol:-tcp}"
    port="${port:-8080}"
    port2="${port2:-8081}"

    ## 创建 helm chart
    helm create "$helm_chart_path"
    _msg "helm create $helm_chart_path" >>$SCRIPT_LOG
    ## 需要修改的配置文件
    local file_values="$helm_chart_path/values.yaml"
    local file_svc="$helm_chart_path/templates/service.yaml"
    local file_deploy="$helm_chart_path/templates/deployment.yaml"
    ## remove serviceaccount.yaml
    # rm -f "$helm_chart_path/templates/serviceaccount.yaml"

    ## change values.yaml
    sed -i -e "s@port: 80@port: ${port}@" "$file_values"
    [ -n "${port2}" ] && sed -i "/port: ${port}/ a \  port2: ${port2}" "$file_values"

    ## disable serviceAccount
    sed -i -e "/create: true/s/true/false/" "$file_values"
    ## resources limit
    # sed -i -e "/^resources: {}/s//resources:/" "$file_values"
    # sed -i -e "/^resources:/ a \    cpu: 500m" "$file_values"
    # sed -i -e "/^resources:/ a \  requests:" "$file_values"

    # sed -i -e '/autoscaling:/,$ s/enabled: false/enabled: true/' "$file_values"
    sed -i -e '/autoscaling:/,$ s/maxReplicas: 100/maxReplicas: 9/' "$file_values"

    sed -i -e "/volumes: \[\]/s//volumes:/" "$file_values"
    sed -i -e "/volumes:/ a \      claimName: ${ENV_HELM_VALUES_CNFS:-cnfs-pvc-www}" "$file_values"
    sed -i -e "/volumes:/ a \    persistentVolumeClaim:" "$file_values"
    sed -i -e "/volumes:/ a \  - name: volume-cnfs" "$file_values"

    sed -i -e "/volumeMounts: \[\]/s//volumeMounts:/" "$file_values"
    sed -i -e "/volumeMounts:/ a \    mountPath: \"\/${ENV_HELM_VALUES_MOUNT_PATH:-app2}\"" "$file_values"
    sed -i -e "/volumeMounts:/ a \  - name: volume-cnfs" "$file_values"

    ## set livenessProbe, spring delay 30s
    sed -i \
        -e '/livenessProbe/ a \  initialDelaySeconds: 30' \
        -e '/readinessProbe/a \  initialDelaySeconds: 30' \
        "$file_values"
    if [[ "${protocol}" == 'tcp' ]]; then
        sed -i \
            -e "s/httpGet:/#httpGet:/" \
            -e "/httpGet:/ a \  tcpSocket:" \
            -e "s@\ \ \ \ path: /@#     path: /@g" \
            -e "s/port: http/port: ${port}/" \
            "$file_values"
    else
        sed -i -e "s@port: http@port: ${port}@g" "$file_values"
    fi

    ## change service.yaml
    sed -i -e "s@targetPort: http@targetPort: {{ .Values.service.port }}@" "$file_svc"
    sed -i -e '/name: http$/ a \    {{- end }}' "$file_svc"
    sed -i -e '/name: http$/ a \      name: http2' "$file_svc"
    sed -i -e '/name: http$/ a \      protocol: TCP' "$file_svc"
    sed -i -e '/name: http$/ a \      targetPort: {{ .Values.service.port2 }}' "$file_svc"
    sed -i -e '/name: http$/ a \    - port: {{ .Values.service.port2 }}' "$file_svc"
    sed -i -e '/name: http$/ a \    {{- if .Values.service.port2 }}' "$file_svc"

    ## change deployment.yaml
    sed -i -e '/  protocol: TCP/ a \            {{- end }}' "$file_deploy"
    sed -i -e '/  protocol: TCP/ a \              containerPort: {{ .Values.service.port2 }}' "$file_deploy"
    sed -i -e '/  protocol: TCP/ a \            - name: http2' "$file_deploy"
    sed -i -e '/  protocol: TCP/ a \            {{- if .Values.service.port2 }}' "$file_deploy"
    sed -i -e '/name: http2/ a \              protocol: TCP' "$file_deploy"

    ## dns config
    cat <<EOF >>"$file_deploy"
      dnsConfig:
        options:
        - name: ndots
          value: "2"
EOF

    # sed -i -e "/serviceAccountName/s/^/#/" "$file_deploy"
}

_deploy_to_aliyun_functions() {
    _format_release_name
    ${github_action:-false} && return 0
    ${ENV_ENABLE_FUNC:-false} || {
        _msg time "!!! disable deploy to functions3.0 aliyun !!!"
        return 0
    }
    [ "${env_namespace}" != main ] && release_name="${release_name}-${env_namespace}"

    ## create FC
    _msg step "[deploy] create/update functions"
    functions_conf_tmpl="$SCRIPT_DATA/aliyun.functions.${project_lang}.json"
    functions_conf="$SCRIPT_DATA/aliyun.functions.json"
    if [ -f "$functions_conf_tmpl" ]; then
        TEMPLATE_NAME=$release_name TEMPLATE_REGISTRY=${ENV_DOCKER_REGISTRY} TEMPLATE_TAG=${image_tag} envsubst <$functions_conf_tmpl >$functions_conf
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
        "image": "${ENV_DOCKER_REGISTRY}:${image_tag}",
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
        aliyun -p "${ENV_ALIYUN_PROFILE-}" --quiet fc PUT /2023-03-30/functions/"$release_name" --header "Content-Type=application/json;" --body "{\"tracingConfig\":{},\"customContainerConfig\":{\"image\":\"${ENV_DOCKER_REGISTRY}:${image_tag}\"}}"
    else
        _msg time "create function $release_name"
        aliyun -p "${ENV_ALIYUN_PROFILE-}" --quiet fc POST /2023-03-30/functions --header "Content-Type=application/json;" --body "$(cat "$functions_conf")"
        _msg time "create trigger for function $release_name"
        aliyun -p "${ENV_ALIYUN_PROFILE-}" --quiet fc POST /2023-03-30/functions/"$release_name"/triggers --header "Content-Type=application/json;" --body "{\"triggerType\":\"http\",\"triggerName\":\"defaultTrigger\",\"triggerConfig\":\"{\\\"methods\\\":[\\\"GET\\\",\\\"POST\\\",\\\"PUT\\\",\\\"DELETE\\\",\\\"OPTIONS\\\"],\\\"authType\\\":\\\"anonymous\\\",\\\"disableURLInternet\\\":false}\"}"
    fi
    rm -f "$functions_conf"

    ## provision-config
    # aliyun  -p "${ENV_ALIYUN_PROFILE-}" --quiet fc PUT /2023-03-30/functions/"$release_name"/provision-config --qualifier LATEST --header "Content-Type=application/json;" --body "{\"target\":1}"
    _msg time "[deploy] create/update functions end"
}

_deploy_to_kubernetes() {
    if "${ENV_DISABLE_K8S:-false}"; then
        _msg time "!!! disable deploy to k8s !!!"
        return
    fi
    _msg step "[deploy] deploy k8s with helm"
    _is_in_demo_mode "deploy-helm" && return 0
    _format_release_name

    ## finding helm files folder / 查找 helm 文件目录
    helm_dirs=(
        "$gitlab_project_dir/helm/${release_name}"
        "$gitlab_project_dir/docs/helm/${release_name}"
        "$gitlab_project_dir/doc/helm/${release_name}"
        "${SCRIPT_DATA}/helm/${gitlab_project_path_slug}/${env_namespace}/${release_name}"
        "${SCRIPT_DATA}/helm/${gitlab_project_path_slug}/${release_name}"
        "${SCRIPT_DATA}/helm/${release_name}"
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
        helm_dir="${SCRIPT_DATA}/helm/${gitlab_project_path_slug}/${release_name}"
        mkdir -p "$helm_dir"
        _create_helm_chart "${helm_dir}"
    fi

    echo "helm upgrade --install --history-max 1 ${release_name} $helm_dir/ --namespace ${env_namespace} --set image.repository=${ENV_DOCKER_REGISTRY} --set image.tag=${image_tag}" | sed "s#$HOME#\$HOME#g" | tee -a "$SCRIPT_LOG"
    ${github_action:-false} && return 0

    ## helm install / helm 安装  --atomic
    $helm_opt upgrade --install --history-max 1 \
        "${release_name}" "$helm_dir/" \
        --namespace "${env_namespace}" --create-namespace \
        --timeout 120s --set image.pullPolicy='Always' \
        --set image.repository="${ENV_DOCKER_REGISTRY}" \
        --set image.tag="${image_tag}" >/dev/null

    ## Clean up rs 0 0 / 清理 rs 0 0
    $kubectl_opt -n "${env_namespace}" get rs | awk '/.*0\s+0\s+0/ {print $1}' | xargs -t -r $kubectl_opt -n "${env_namespace}" delete rs >/dev/null 2>&1 || true
    $kubectl_opt -n "${env_namespace}" get pod | awk '/Evicted/ {print $1}' | xargs -t -r $kubectl_opt -n "${env_namespace}" delete pod 2>/dev/null || true
    # sleep 3
    ## 检测 helm upgrade 状态
    $kubectl_opt -n "${env_namespace}" rollout status deployment "${release_name}" --timeout 120s >/dev/null || deploy_result=1
    if [[ "$deploy_result" -eq 1 ]]; then
        echo "此处探测超时值120秒，不能百分之百以此作为应用是否正常的依据，如遇错误，需要去k8s内检查容器是否正常，或者通过日志去判断"
    fi

    if [ -f "$gitlab_project_dir/deploy.custom.sh" ]; then
        _msg time "custom deploy."
        source "$gitlab_project_dir/deploy.custom.sh"
    fi

    ## helm install flyway jobs / helm 安装 flyway 任务
    if ${ENV_FLYWAY_HELM_JOB:-false} && [[ -d "${SCRIPT_CONF_PATH}"/helm/flyway ]]; then
        $helm_opt upgrade flyway "${SCRIPT_CONF_PATH}/helm/flyway/" --install --history-max 1 \
            --namespace "${env_namespace}" --create-namespace \
            --set image.repository="${ENV_DOCKER_REGISTRY}" \
            --set image.tag="${gitlab_project_name}-flyway-${gitlab_commit_short_sha}" \
            --set image.pullPolicy='Always' >/dev/null
    fi
    _msg time "[deploy] deploy k8s with helm"
}

_deploy_via_rsync_ssh() {
    _msg step "[deploy] deploy files with rsync+ssh"
    ## rsync exclude some files / rsync 排除某些文件
    rsync_exclude="${gitlab_project_dir}/rsync.exclude"
    [[ ! -f "$rsync_exclude" ]] && rsync_exclude="${SCRIPT_CONF_PATH}/rsync.exclude"

    ## read conf, get project,branch,jar/war etc. / 读取配置文件，获取 项目/分支名/war包目录
    # grep "^${gitlab_project_path}:${env_namespace}" "$SCRIPT_CONF" | awk -F: '{print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10}' "$SCRIPT_CONF"
    conf_line="$(jq -c ".[] | select (.project == \"${gitlab_project_path}\") | .branchs[] | select (.branch == \"${env_namespace}\") | .hosts[]" "$SCRIPT_CONF" | wc -l)"
    if [ "$conf_line" -eq 0 ]; then
        _msg warn "[deploy] not config $SCRIPT_CONF"
        return
    fi

    while read -r line; do
        ssh_host=$(echo "$line" | jq -r '.ssh_host')
        ssh_port=$(echo "$line" | jq -r '.ssh_port')
        rsync_src_from_conf=$(echo "$line" | jq -r '.rsync_src')
        rsync_dest=$(echo "$line" | jq -r '.rsync_dest')
        # db_host=$(echo "$line" | jq -r '.db_host')
        # db_user=$(echo "$line" | jq -r '.db_user')
        # db_name=$(echo "$line" | jq -r '.db_name')
        ## Prevent empty variable / 防止出现空变量（若有空变量则自动退出）
        echo "ssh host: ${ssh_host:?when stop here, please check $SCRIPT_CONF}, port: ${ssh_port:-22}"
        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=10 -p ${ssh_port:-22}"

        ## node/java use rsync --delete / node/java 使用 rsync --delete
        [[ "${project_lang}" =~ (node) ]] && rsync_delete='--delete'
        rsync_opt="rsync -acvzt --exclude=.svn --exclude=.git --timeout=10 --no-times --exclude-from=${rsync_exclude} $rsync_delete"

        ## rsync source folder / rsync 源目录
        ## define rsync_relative_path in bin/build.*.sh / 在 bin/build.*.sh 中定义 rsync_relative_path
        ## default: rsync_relative_path=''
        case "$project_lang" in
        java) rsync_relative_path=jars/ ;;
        node) rsync_relative_path=dist/ ;;
        *) rsync_relative_path='' ;;
        esac

        rsync_src="${rsync_src_from_conf:-${gitlab_project_dir}/${rsync_relative_path-}}/"

        ## rsycn dest folder / rsync 目标目录
        if [[ "$rsync_dest" == 'none' || -z "$rsync_dest" ]]; then
            rsync_dest="${ENV_PATH_DEST_PRE}/${env_namespace}.${gitlab_project_name}/"
        fi
        ## deploy to aliyun oss / 发布到 aliyun oss 存储
        if [[ "${rsync_dest}" =~ 'oss://' ]]; then
            _install_aliyun_cli
            aliyun oss cp "${rsync_src}" "$rsync_dest" --recursive --force
            ## 如果使用 rclone， 则需要安装和配置
            # rclone sync "${gitlab_project_dir}/" "$rsync_dest/"
            return
        fi

        echo "destination: ${ssh_host}:${rsync_dest}"
        $ssh_opt -n "${ssh_host}" "mkdir -p $rsync_dest"
        ## rsync to remote server / rsync 到远程服务器
        ${rsync_opt} -e "$ssh_opt" "${rsync_src}" "${ssh_host}:${rsync_dest}"

        if [ -f "$SCRIPT_DATA_BIN/deploy.custom.sh" ]; then
            _msg time "custom deploy..."
            bash "$SCRIPT_DATA_BIN/deploy.custom.sh" ${ssh_host} ${rsync_dest}
            _msg time "custom deploy."
        fi

        if ${exec_deploy_docker_compose:-false}; then
            _msg step "deploy to server with docker-compose"
            $ssh_opt -n "$ssh_host" "cd docker/laradock && docker compose up -d $gitlab_project_name"
        fi
    done < <(jq -c ".[] | select (.project == \"${gitlab_project_path}\") | .branchs[] | select (.branch == \"${env_namespace}\") | .hosts[]" "$SCRIPT_CONF")
    _msg time "[deploy] deploy files with rsync+ssh"
}

_deploy_aliyun_oss() {
    _msg step "[deploy] deploy files to Aliyun OSS"
    # Check if deployment is enabled
    if ${DEPLOYMENT_ENABLED:-false}; then
        echo '<skip>'
        return
    fi

    # Check if OSS CLI is installed
    _install_ossutil
    oss_config_file=${SCRIPT_DATA}/aliyun.oss.key.conf
    bucket_name=demo-bucket
    remote_dir=demo-dir

    # Deploy files to Aliyun OSS
    _msg time "copy start"
    if ossutil cp -r "${gitlab_project_dir}/" "oss://${bucket_name}/${remote_dir}" --config="${oss_config_file}"; then
        _msg green "Result = OK"
    else
        _msg error "Result = FAIL"
    fi
    _msg time "[oss] deploy files to Aliyun OSS"
}

_deploy_rsync() {
    _msg step "[deploy] deploy files to rsyncd server"
    # Load configuration from file
    rsyncd_conf="$SCRIPT_DATA/rsyncd.conf"
    source "$rsyncd_conf"

    # Deploy files with rsync
    rsync_options="rsync -avz"
    $rsync_options --exclude-from="$EXCLUDE_FILE" "$SOURCE_DIR/" "$RSYNC_USER@$RSYNC_HOST::$TARGET_DIR"
}

_deploy_ftp() {
    _msg step "[deploy] deploy files to ftp server"
    upload_file="${gitlab_project_dir}/ftp.tgz"
    tar czvf "${upload_file}" -C "${gitlab_project_dir}" .
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

_deploy_sftp() {
    _msg step "[deploy] deploy files to sftp server"
}

_notify_zoom() {
    # Send message to Zoom channel
    # ENV_ZOOM_CHANNEL="https://api.zoom.us/v2/im/chat/messages"
    #
    curl -s -X POST -H "Content-Type: application/json" -d '{"text": "'"${g_msg_body}"'"}' "${ENV_ZOOM_CHANNEL}"
}

_notify_feishu() {
    # Send message to Feishu 飞书
    # ENV_WEBHOOK_URL="https://open.feishu.cn/open-apis/bot/v2/hook/your-webhook-url"
    curl -s -X POST -H "Content-Type: application/json" -d '{"text": "'"$g_msg_body"'"}' "$ENV_WEBHOOK_URL"
}

_deploy_notify() {
    msg_describe="${msg_describe:-$(if [ -d .git ]; then git --no-pager log --no-merges --oneline -1; else echo 'not-git'; fi)}"

    g_msg_body="
[Gitlab Deploy]
Project = ${gitlab_project_path}/${gitlab_project_id}
Branche = ${gitlab_project_branch}
Pipeline = ${gitlab_pipeline_id}/JobID=$gitlab_job_id
Describe = [${gitlab_commit_short_sha}]/${msg_describe}
Who = ${gitlab_user_id}/${gitlab_username}
Result = $([ "${deploy_result:-0}" = 0 ] && echo OK || echo FAIL)
$(if [ -n "${test_result}" ]; then echo "Test_Result: ${test_result}" else :; fi)
"

    case ${ENV_NOTIFY_TYPE:-skip} in
    wecom)
        ## work chat / 发送至 企业微信
        _msg time "notify to wecom"
        _notify_wecom "${ENV_WECOM_KEY}" "$g_msg_body"
        ;;
    telegram)
        ## Telegram / 发送至 Telegram
        _msg time "notify to Telegram"
        telegram_api_msg="https://api.telegram.org/bot${ENV_TG_API_KEY}/sendMessage"
        # telegram_api_doc="https://api.telegram.org/bot${ENV_TG_API_KEY}/sendDocument"
        g_msg_body="$(echo "$g_msg_body" | sed -e ':a;N;$!ba;s/\n/%0a/g' -e 's/&/%26/g')"
        curl -sSLo /dev/null -X POST -d "chat_id=${ENV_TG_GROUP_ID}&text=$g_msg_body" "$telegram_api_msg"
        ;;
    element)
        ## element / 发送至 element
        _msg time "notify to Element"
        echo "$g_msg_body" | python3 "$SCRIPT_LIB/utils/element.py" ${ENV_ELM_SERVER:? } ${ENV_ELM_USERID:? } ${ENV_ELM_PASSWORD:? } ${ENV_ELM_ROOMID:? }
        ;;
    email)
        ## email / 发送至 email
        # mogaal/sendemail: lightweight, command line SMTP email client
        # https://github.com/mogaal/sendemail
        _msg time "notify to Email"
        "$SCRIPT_BIN/sendEmail" \
            -s "$ENV_EMAIL_SERVER" \
            -f "$ENV_EMAIL_FROM" \
            -xu "$ENV_EMAIL_USERNAME" \
            -xp "$ENV_EMAIL_PASSWORD" \
            -t "$ENV_EMAIL_TO" \
            -o message-content-type=text/html \
            -o message-charset=utf-8 \
            -u "[Gitlab Deploy] ${gitlab_project_path} ${gitlab_project_branch} ${gitlab_pipeline_id}/${gitlab_job_id}" \
            -m "$g_msg_body"
        ;;
    *)
        _msg "<skip>"
        ;;
    esac
}

_set_proxy() {
    case "$1" in
    on | 1)
        if [ -z "$ENV_HTTP_PROXY" ]; then
            _msg warn "empty var ENV_HTTP_PROXY"
        else
            _msg time "set http_proxy https_proxy all_proxy"
            export http_proxy="$ENV_HTTP_PROXY"
            export https_proxy="$ENV_HTTP_PROXY"
            export all_proxy="$ENV_HTTP_PROXY"
        fi
        ;;
    off | 0)
        _msg time "unset http_proxy https_proxy all_proxy"
        unset http_proxy https_proxy all_proxy
        ;;
    esac
}

_renew_ssl_certificates() {
    _msg step "[cert] renew SSL cert with acme.sh using dns+api"
    acme_home="${HOME}/.acme.sh"
    acme_cmd="${acme_home}/acme.sh"
    acme_cert_dest="${ENV_CERT_INSTALL:-${acme_home}/dest}"
    file_reload_nginx="$acme_home/reload.nginx"

    ## install acme.sh / 安装 acme.sh
    if [[ ! -x "${acme_cmd}" ]]; then
        _install_cron
        curl https://get.acme.sh | bash -s email=deploy@deploy.sh
    fi

    [ -d "$acme_cert_dest" ] || mkdir -p "$acme_cert_dest"

    run_touch_file="$acme_home/hook.sh"
    echo "touch ${file_reload_nginx}" >"$run_touch_file"
    chmod +x "$run_touch_file"
    ## According to multiple different account files, loop renewal / 根据多个不同的账号文件,循环续签
    ## support multiple account.conf.* / 支持多账号
    ## 多个账号用文件名区分，例如： account.conf.xxx.dns_ali, account.conf.yyy.dns_cf
    for file in "${acme_home}"/account.conf.*.dns_*; do
        if [ -f "$file" ]; then
            _msg blue "Found $file"
        else
            continue
        fi
        source "$file"
        dns_type=${file##*.}
        profile_name=${file%.dns_*}
        profile_name=${profile_name##*.}
        _set_proxy on
        case "${dns_type}" in
        dns_gd)
            _msg yellow "dns type: Goddady"
            api_head="Authorization: sso-key ${SAVED_GD_Key:-none}:${SAVED_GD_Secret:-none}"
            api_goddady="https://api.godaddy.com/v1/domains"
            domains="$(curl -fsSL -X GET -H "$api_head" "$api_goddady" | jq -r '.[].domain' || true)"
            export GD_Key="${SAVED_GD_Key:-none}"
            export GD_Secret="${SAVED_GD_Secret:-none}"
            ;;
        dns_cf)
            _msg yellow "dns type: cloudflare"
            _install_flarectl
            domains="$(flarectl zone list | awk '/active/ {print $3}' || true)"
            export CF_Token="${SAVED_CF_Token:-none}"
            export CF_Account_ID="${SAVED_CF_Account_ID:-none}"
            ;;
        dns_ali)
            _msg yellow "dns type: aliyun"
            _install_aliyun_cli
            aliyun configure set \
                --mode AK \
                --profile "deploy_${profile_name}" \
                --region "${SAVED_Ali_region:-none}" \
                --access-key-id "${SAVED_Ali_Key:-none}" \
                --access-key-secret "${SAVED_Ali_Secret:-none}"
            domains="$(aliyun --profile "deploy_${profile_name}" domain QueryDomainList --PageNum 1 --PageSize 100 | jq -r '.Data.Domain[].DomainName' || true)"
            export Ali_Key=$SAVED_Ali_Key
            export Ali_Secret=$SAVED_Ali_Secret
            ;;
        dns_tencent)
            _msg yellow "dns type: tencent"
            _install_tencent_cli
            tccli configure set secretId "${SAVED_Tencent_SecretId:-none}" secretKey "${SAVED_Tencent_SecretKey:-none}"
            domains="$(tccli domain DescribeDomainNameList --output json | jq -r '.DomainSet[] | .DomainName' || true)"
            ;;
        from_env)
            _msg yellow "get domains from env file"
            source "$file"
            ;;
        *)
            _msg yellow "unknown dns type: $dns_type"
            continue
            ;;
        esac

        ## single account may have multiple domains / 单个账号可能有多个域名
        for domain in ${domains}; do
            _msg orange "Checking domain: $domain"
            if "${acme_cmd}" list | grep -qw "$domain"; then
                ## renew cert / 续签证书
                "${acme_cmd}" --accountconf "$file" --renew -d "${domain}" --reloadcmd "$run_touch_file" || true
            else
                ## create cert / 创建证书
                "${acme_cmd}" --accountconf "$file" --issue -d "${domain}" -d "*.${domain}" --dns $dns_type --renew-hook "$run_touch_file" || true
            fi
            "${acme_cmd}" --accountconf "$file" -d "${domain}" --install-cert --key-file "$acme_cert_dest/${domain}.key" --fullchain-file "$acme_cert_dest/${domain}.pem" || true
            "${acme_cmd}" --accountconf "$file" -d "${domain}" --install-cert --key-file "${acme_home}/dest/${domain}.key" --fullchain-file "${acme_home}/dest/${domain}.pem" || true
        done
    done
    ## deploy with gitlab CI/CD,
    if [ -f "$file_reload_nginx" ]; then
        _msg green "found $file_reload_nginx"
        for id in "${ENV_NGINX_PROJECT_ID[@]}"; do
            _msg "gitlab create pipeline, project id is $id"
            gitlab project-pipeline create --ref main --project-id $id
        done
        rm -f "$file_reload_nginx"
    else
        _msg warn "not found $file_reload_nginx"
    fi
    ## deploy with custom method / 自定义部署方式
    if [[ -f "${acme_home}/custom.acme.sh" ]]; then
        echo "Found ${acme_home}/custom.acme.sh"
        bash "${acme_home}/custom.acme.sh"
    fi
    _msg time "[cert] completed"

    if ${github_action:-false}; then
        return 0
    fi
    if ${exec_single_job:-false}; then
        exit 0
    fi
}

_check_aliyun_account_balance() {
    ${github_action:-false} && return 0
    _msg step "[finance] Check Aliyun account balance"

    local current_balance alarm_balance alarm_daily yesterday current_month daily_spending

    alarm_balance=${ENV_ALARM_ALIYUN_BALANCE:-3000}
    alarm_daily=${ENV_ALARM_ALIYUN_DAILY:-100}
    yesterday=$(date +%F -d yesterday)
    current_month=$(date +%Y-%m -d yesterday)

    for profile in "${ENV_ALARM_ALIYUN_PROFILE[@]}"; do
        _msg info "Checking balance for profile: $profile"

        # 检查当前余额
        current_balance=$(aliyun -p "$profile" bssopenapi QueryAccountBalance 2>/dev/null |
            jq -r '.Data.AvailableAmount | gsub(","; "")')
        if [[ -z "$current_balance" ]]; then
            _msg warn "Failed to retrieve balance for profile $profile"
            continue
        fi

        _msg green "Current balance: $current_balance"
        if (($(echo "$current_balance < $alarm_balance" | bc -l))); then
            g_msg_body="Aliyun account: $profile, 余额: $current_balance 过低需要充值"
            _notify_wecom "${ENV_ALARM_WECOM_KEY}" "$g_msg_body"
        fi

        # 检查昨日消费
        daily_spending=$(aliyun -p "$profile" bssopenapi QueryAccountBill \
            --BillingCycle "$current_month" --BillingDate "$yesterday" --Granularity DAILY |
            jq -r '.Data.Items.Item[].CashAmount | tostring | gsub(","; "")')

        _msg red "Yesterday's spending: $daily_spending"
        if (($(echo "$daily_spending > $alarm_daily" | bc -l))); then
            g_msg_body=$(printf "Aliyun account: %s, 昨日消费金额: %.2f , 超过告警阈值：%.2f" "$profile" "$daily_spending" "${alarm_daily}")
            _notify_wecom "${ENV_ALARM_WECOM_KEY}" "$g_msg_body"
        fi
    done

    _msg time "[finance] completed"
    if [[ "${MAN_RENEW_CERT:-false}" == true ]] || ${arg_renew_cert:-false}; then
        return 0
    fi
    if ${exec_single_job:-false}; then
        exit 0
    fi
}

_is_china() {
    if ${ENV_IN_CHINA:-false} || ${CHANGE_SOURCE:-false} || grep -q 'ENV_IN_CHINA=true' "$SCRIPT_ENV"; then
        return 0
    fi
    return 1
}

_setup_environment() {
    _check_distribution
    _check_sudo >/dev/null || true

    pkgs=()

    case "${lsb_dist:-}" in
    debian | ubuntu | linuxmint)
        # RUN apt-get update && \
        #        apt-get -y install sudo dialog apt-utils
        # RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
        export DEBIAN_FRONTEND=noninteractive
        ## fix gitlab-runner exit error / 修复 gitlab-runner 退出错误
        [[ -f "$HOME"/.bash_logout ]] && mv -f "$HOME"/.bash_logout "$HOME"/.bash_logout.bak

        command -v apt-extracttemplates >/dev/null || pkgs+=(apt-utils)
        command -v git >/dev/null || pkgs+=(git)
        git lfs version >/dev/null 2>&1 || pkgs+=(git-lfs)
        command -v curl >/dev/null || pkgs+=(curl)
        command -v unzip >/dev/null || pkgs+=(unzip)
        command -v rsync >/dev/null || pkgs+=(rsync)
        command -v pip3 >/dev/null || pkgs+=(python3-pip)
        command -v shc >/dev/null || pkgs+=(shc)
        ;;
    centos | amzn | rhel | fedora)
        rpm -q epel-release >/dev/null || {
            if [ "${lsb_dist:-}" = amzn ]; then
                ${use_sudo:-} amazon-linux-extras install -y epel >/dev/null
            else
                _install_packages epel-release >/dev/null
            fi
        }
        command -v git >/dev/null || pkgs+=(git2u)
        git lfs version >/dev/null 2>&1 || pkgs+=(git-lfs)
        command -v curl >/dev/null || pkgs+=(curl)
        command -v unzip >/dev/null || pkgs+=(unzip)
        command -v rsync >/dev/null || pkgs+=(rsync)
        ;;
    alpine)
        command -v openssl >/dev/null || pkgs+=(openssl)
        command -v git >/dev/null || pkgs+=(git)
        git lfs version >/dev/null 2>&1 || pkgs+=(git-lfs)
        command -v curl >/dev/null || pkgs+=(curl)
        command -v unzip >/dev/null || pkgs+=(unzip)
        command -v rsync >/dev/null || pkgs+=(rsync)
        ;;
    macos)
        command -v openssl >/dev/null || pkgs+=(openssl)
        command -v git >/dev/null || pkgs+=(git)
        git lfs version >/dev/null 2>&1 || pkgs+=(git-lfs)
        command -v curl >/dev/null || pkgs+=(curl)
        command -v unzip >/dev/null || pkgs+=(unzip)
        command -v rsync >/dev/null || pkgs+=(rsync)
        ;;
    *)
        _msg error "Unsupported OS distribution. Exiting."
        return 1
        ;;
    esac

    _install_packages "${pkgs[@]}" >/dev/null
}

_clean_up_disk_space() {
    local disk_usage clean_disk_threshold=80 aggressive=false

    # Get disk usage more reliably
    disk_usage=$(df -P / | awk 'NR==2 {print int($5)}')

    if ((disk_usage < clean_disk_threshold)); then
        return 0
    fi

    _msg warning "Disk usage (${disk_usage}%) exceeds threshold (${clean_disk_threshold}%). Starting cleanup..."

    # Determine if we should use aggressive cleaning
    if ((disk_usage >= clean_disk_threshold + 10)); then
        aggressive=true
        _msg warning "Disk usage is critically high. Using aggressive cleaning."
    fi

    # Clean up Docker images
    if command -v docker >/dev/null 2>&1; then
        _msg info "Cleaning up Docker resources..."
        docker image prune -f
        docker builder prune -f
        docker image ls --format '{{.Repository}}:{{.Tag}}' "${ENV_DOCKER_REGISTRY}" | xargs -r docker rmi 2>/dev/null || true
        if $aggressive; then
            docker system prune -af --volumes
        fi
    fi

    # Clean up temporary files
    _msg info "Cleaning up temporary files..."
    sudo find /tmp -type f -atime +10 -delete 2>/dev/null || true
    sudo find /var/tmp -type f -atime +10 -delete 2>/dev/null || true

    # Clean up old log files
    _msg info "Cleaning up old log files..."
    sudo find /var/log -type f -name "*.log" -mtime +30 -delete 2>/dev/null || true

    # Clean up old core dumps if aggressive
    if $aggressive; then
        _msg info "Cleaning up old core dumps..."
        sudo find /var/crash -type f -delete 2>/dev/null || true
    fi

    # Final disk usage check
    disk_usage_after=$(df -P / | awk 'NR==2 {print int($5)}')
    _msg info "Cleanup completed. Disk usage now: ${disk_usage_after}%"

    if ((disk_usage_after >= disk_usage)); then
        _msg error "Warning: Cleanup did not free up space. Further investigation may be needed."
    else
        _msg success "Successfully freed up $((disk_usage - disk_usage_after))% of disk space."
    fi
}

# https://github.com/sherpya/geolite2legacy
# https://www.miyuru.lk/geoiplegacy
# https://github.com/leev/ngx_http_geoip2_module

_update_nginx_geoip_db() {
    local tmp_dir country_url city_url
    tmp_dir="$(mktemp -d)"
    country_url="https://dl.miyuru.lk/geoip/maxmind/country/maxmind.dat.gz"
    city_url="https://dl.miyuru.lk/geoip/maxmind/city/maxmind.dat.gz"

    _msg step "[geoip] Updating Nginx GeoIP database"

    if [[ -z "${ENV_NGINX_IPS}" ]]; then
        _msg error "ENV_NGINX_IPS is not defined or is empty"
        return 1
    fi

    _download_and_extract() {
        local url="$1" output="$2"
        if ! curl -LqsSf "$url" | gunzip -c >"$output"; then
            _msg error "Failed to download or extract $url"
            return 1
        fi
    }

    _download_and_extract "$country_url" "$tmp_dir/maxmind-Country.dat" || return 1
    _download_and_extract "$city_url" "$tmp_dir/maxmind-City.dat" || return 1

    _msg info "GeoIP databases downloaded successfully"

    _update_server() {
        local ip="$1"
        if rsync -av "${tmp_dir}/" "root@$ip:/etc/nginx/conf.d/"; then
            _msg success "Updated GeoIP database on $ip"
        else
            _msg error "Failed to update GeoIP database on $ip"
        fi
    }

    for ip in ${ENV_NGINX_IPS}; do
        _update_server "$ip" &
    done

    wait

    rm -rf "$tmp_dir"
    _msg success "Nginx GeoIP database update completed"
}

_generate_api_documentation() {
    local apidoc_config="${gitlab_project_dir}/apidoc.json"
    [[ ! -f "$apidoc_config" ]] && return 0

    local input_dir="${ENV_APIDOC_INPUT_DIR:-app}"
    local output_dir="${ENV_APIDOC_OUTPUT_DIR:-public/apidoc}"
    local apidoc_cmd="apidoc -i ${input_dir} -o ${output_dir}"

    _msg step "[apidoc] Generating API documentation"

    _msg green "Using input directory: ${input_dir}"
    _msg blue "Using output directory: ${output_dir}"

    if $run_cmd -v "${gitlab_project_dir}":/app -w /app deploy/node bash -c "$apidoc_cmd"; then
        _msg success "API documentation generated successfully"
    else
        _msg error "Failed to generate API documentation"
        return 1
    fi

    _msg time "[apidoc] API documentation generation completed"
}

_inject_project_files() {
    # 如果禁用注入，则直接返回
    [ "${exec_inject_files:-true}" = "false" ] && return 0
    _msg step "[inject] from ${SCRIPT_DATA}/inject/"

    # 定义路径变量 替换代码文件，例如 PHP 数据库配置等信息 .env 文件，例如 Java 数据库配置信息 yml 文件
    local inject_code_path="${SCRIPT_DATA}/inject/${gitlab_project_name}"
    local inject_code_path_branch="${SCRIPT_DATA}/inject/${gitlab_project_name}/${env_namespace}"
    ## 项目代码库内已存在的 Dockerfile
    local project_dockerfile="${gitlab_project_dir}/Dockerfile"
    ## 打包镜像时注入的 Dockerfile 优先查找 data/ 目录 其次查找 conf/ 目录
    local inject_dockerfile_1="${SCRIPT_DATA_DOCKERFILE}/Dockerfile.${project_lang}"
    local inject_dockerfile_2="${SCRIPT_DOCKERFILE}/Dockerfile.${project_lang}"
    ## 打包镜像时注入的 root/opt/ 目录
    local inject_root_path="${SCRIPT_DOCKERFILE}/root"
    ## 打包镜像时注入的 settings.xml 文件
    local inject_setting="${SCRIPT_DATA_DOCKERFILE}/settings.xml"
    ## 打包镜像时注入的 .dockerignore 文件
    local inject_dockerignore="${SCRIPT_DOCKERFILE}/.dockerignore"
    ## 打包镜像时注入的 /opt/init.sh 文件 容器启动时初始化配置文件 init.sh 可以注入 /etc/hosts 等配置
    local inject_init="${SCRIPT_DATA_DOCKERFILE}"/init.sh
    ## replace code files / 替换代码文件
    if [ -d "$inject_code_path_branch" ]; then
        _msg warning "found $inject_code_path_branch, sync to ${gitlab_project_dir}/"
        rsync -av "$inject_code_path_branch/" "${gitlab_project_dir}/"
    elif [ -d "$inject_code_path" ]; then
        _msg warning "found $inject_code_path, sync to ${gitlab_project_dir}/"
        rsync -av "$inject_code_path/" "${gitlab_project_dir}/"
    fi
    ## frontend (VUE) .env file / 替换前端代码内配置文件
    if [[ "$project_lang" == node ]]; then
        env_files="$(find "${gitlab_project_dir}" -maxdepth 2 -name "${env_namespace}-*")"
        for file in $env_files; do
            [[ -f "$file" ]] || continue
            echo "Found $file"
            if [[ "$file" =~ 'config' ]]; then
                cp -avf "$file" "${file/${env_namespace}./}" # vue2.x
            else
                cp -avf "$file" "${file/${env_namespace}/}" # vue3.x
            fi
        done
    fi
    ## 检查并注入 .dockerignore 文件
    if [[ -f "${project_dockerfile}" && ! -f "${gitlab_project_dir}/.dockerignore" ]]; then
        cp -avf "${inject_dockerignore}" "${gitlab_project_dir}/"
    fi

    # 设置构建参数
    build_arg="${build_arg:+"$build_arg "}--build-arg IN_CHINA=${ENV_IN_CHINA:-false}"
    if [ -n "${ENV_DOCKER_MIRROR}" ]; then
        build_arg="${build_arg:+"$build_arg "}--build-arg MVN_IMAGE=${ENV_DOCKER_MIRROR} --build-arg JDK_IMAGE=${ENV_DOCKER_MIRROR}"
    fi
    ## from data/deploy.env， 使用 data/ 全局模板文件替换项目文件
    ${arg_disable_inject:-false} && ENV_INJECT=keep
    echo ENV_INJECT: ${ENV_INJECT:-keep}

    case ${ENV_INJECT:-keep} in
    keep)
        echo '<skip>'
        ;;
    overwrite)
        ## 代码库内已存在 Dockerfile 不覆盖
        if [[ -f "${project_dockerfile}" ]]; then
            echo "found Dockerfile in project path, skip cp."
        else
            if [[ -f "${inject_dockerfile_1}" ]]; then
                cp -avf "${inject_dockerfile_1}" "${project_dockerfile}"
            elif [[ -f "${inject_dockerfile_2}" ]]; then
                cp -avf "${inject_dockerfile_2}" "${project_dockerfile}"
            fi
        fi
        ## build image files 打包镜像时需要注入的文件
        if [ -d "${gitlab_project_dir}/root/opt" ]; then
            echo "found exist path root/opt in project path, skip cp"
        else
            cp -af "${inject_root_path}" "$gitlab_project_dir/"
        fi
        if [[ -f "${inject_init}" && -d "$gitlab_project_dir/root/opt/" ]]; then
            cp -avf "${inject_init}" "$gitlab_project_dir/root/opt/"
        fi

        case "${project_lang}" in
        java)
            # Copy Java settings.xml if it exists 优先查找 data/ 目录
            [[ -f "${inject_setting}" ]] && cp -avf "${inject_setting}" "${gitlab_project_dir}/"

            # Read JDK version from README files
            jdk_version=$(grep -iE 'jdk_version=([0-9.]+)' "${gitlab_project_dir}"/{README,readme}* 2>/dev/null | sed -E 's/.*=([0-9.]+).*/\1/' | tail -n1)

            # Set Maven and JDK versions based on JDK version
            case "${jdk_version:-}" in
            1.7 | 7) MVN_VERSION="3.6-jdk-7" && JDK_VERSION="7" ;;
            1.8 | 8) MVN_VERSION="3.8-amazoncorretto-8" && JDK_VERSION="8" ;;
            11) MVN_VERSION="3.9-amazoncorretto-11" && JDK_VERSION="11" ;;
            17) MVN_VERSION="3.9-amazoncorretto-17" && JDK_VERSION="17" ;;
            21) MVN_VERSION="3.9-amazoncorretto-21" && JDK_VERSION="21" ;;
            *) MVN_VERSION="3.8-amazoncorretto-8" && JDK_VERSION="8" ;; # Default
            esac

            # Adjust versions if using Docker mirror
            if [ -n "${ENV_DOCKER_MIRROR}" ]; then
                MVN_VERSION="maven-${MVN_VERSION}"
                [[ "${JDK_VERSION}" == "7" ]] && JDK_VERSION="openjdk-7" || JDK_VERSION="amazoncorretto-${JDK_VERSION}"
            fi

            # Add build arguments
            build_arg+=" --build-arg MVN_VERSION=${MVN_VERSION} --build-arg JDK_VERSION=${JDK_VERSION}"

            # Check for additional installations
            for install in FFMPEG FONTS LIBREOFFICE; do
                if grep -qi "INSTALL_${install}=true" "${gitlab_project_dir}"/{README,readme}* 2>/dev/null; then
                    build_arg+=" --build-arg INSTALL_${install}=true"
                fi
            done
            ;;
        esac
        ;;
    remove)
        echo 'Removing Dockerfile (disable docker build)'
        rm -f "${project_dockerfile}"
        ;;
    create)
        ## TODO
        echo "Generating docker-compose.yml (enable deploy docker-compose)"
        echo '## deploy with docker-compose' >>"${gitlab_project_dir}/docker-compose.yml"
        ;;
    esac
}

_setup_deployment_environment() {
    local path_conf_base="${SCRIPT_DATA}"
    local conf_dirs=(".ssh" ".acme.sh" ".aws" ".kube" ".aliyun")
    local file_python_gitlab="${path_conf_base}/.python-gitlab.cfg"

    # Create and set permissions for SSH directory
    local ssh_dir="${path_conf_base}/.ssh"
    if [[ ! -d "${ssh_dir}" ]]; then
        mkdir -m 700 "${ssh_dir}"
        _msg warn "Generate ssh key file for gitlab-runner: ${ssh_dir}/id_ed25519"
        _msg purple "Please: cat $ssh_dir/id_ed25519.pub >> [dest_server]:~/.ssh/authorized_keys"
        ssh-keygen -t ed25519 -N '' -f "${ssh_dir}/id_ed25519" || _msg error "Failed to generate SSH key"
    fi

    # Ensure HOME .ssh directory exists
    [[ -d "$HOME/.ssh" ]] || mkdir -m 700 "$HOME/.ssh"

    # Link SSH files
    for file in "$ssh_dir"/*; do
        [[ -f "$HOME/.ssh/$(basename "${file}")" ]] && continue
        echo "Link $file to $HOME/.ssh/"
        chmod 600 "${file}"
        ln -s "${file}" "$HOME/.ssh/"
    done

    # Link configuration directories
    for dir in "${conf_dirs[@]}"; do
        [[ ! -d "$HOME/${dir}" && -d "${path_conf_base}/${dir}" ]] && ln -sf "${path_conf_base}/${dir}" "$HOME/"
    done

    # Link python-gitlab config file
    [[ ! -f "$HOME/.python-gitlab.cfg" && -f "${file_python_gitlab}" ]] && ln -sf "${file_python_gitlab}" "$HOME/"

    _msg green "Deployment environment setup completed"
}

_initialize_gitlab_variables() {
    # Set default values for GitLab CI variables
    gitlab_project_dir=${CI_PROJECT_DIR:-$PWD}
    gitlab_project_name=${CI_PROJECT_NAME:-${gitlab_project_dir##*/}}
    # read -rp "Enter gitlab project namespace: " -e -i 'root' gitlab_project_namespace
    gitlab_project_namespace=${CI_PROJECT_NAMESPACE:-root}
    # read -rp "Enter gitlab project path: [root/git-repo] " -e -i 'root/xxx' gitlab_project_path
    gitlab_project_path=${CI_PROJECT_PATH:-$gitlab_project_namespace/$gitlab_project_name}
    gitlab_project_path_slug=${CI_PROJECT_PATH_SLUG:-${gitlab_project_path//[.\/]/-}}
    # read -t 5 -rp "Enter branch name: " -e -i 'develop' gitlab_project_branch
    # Determine branch name
    if [ -d .git ]; then
        default_branch=$(git rev-parse --abbrev-ref HEAD)
    else
        default_branch=dev
    fi
    gitlab_project_branch=${CI_COMMIT_REF_NAME:-$default_branch}
    gitlab_project_branch=${gitlab_project_branch:-develop}
    [[ "${gitlab_project_branch}" == HEAD ]] && gitlab_project_branch=main

    # Get commit SHA
    if [ -d .git ]; then
        default_sha=$(git rev-parse --short HEAD)
    else
        default_sha=1234567
    fi
    gitlab_commit_short_sha=${CI_COMMIT_SHORT_SHA:-$default_sha}
    [[ -z "$gitlab_commit_short_sha" ]] && gitlab_commit_short_sha=1234567

    # Set other GitLab variables
    gitlab_project_id=${CI_PROJECT_ID:-1234}
    # read -t 5 -rp "Enter gitlab pipeline id: " -e -i '3456' gitlab_pipeline_id
    gitlab_pipeline_id=${CI_PIPELINE_ID:-3456}
    # read -rp "Enter gitlab job id: " -e -i '5678' gitlab_job_id
    gitlab_job_id=${CI_JOB_ID:-5678}
    # read -rp "Enter gitlab user id: " -e -i '1' gitlab_user_id
    gitlab_user_id=${GITLAB_USER_ID:-1}
    gitlab_username="${GITLAB_USER_LOGIN:-unknown}"
    env_namespace=$gitlab_project_branch

    # Handle crontab execution
    if ${run_with_crontab:-false}; then
        cron_save_file="$(find "${SCRIPT_DATA}" -name "crontab.${gitlab_project_id}.*" -print -quit)"
        if [[ -n "$cron_save_file" ]]; then
            cron_save_id="${cron_save_file##*.}"
            if [[ "${gitlab_commit_short_sha}" == "$cron_save_id" ]]; then
                _msg warn "no code change found, <skip>."
                exit 0
            else
                rm -f "${SCRIPT_DATA}/crontab.${gitlab_project_id}".*
                touch "${SCRIPT_DATA}/crontab.${gitlab_project_id}.${gitlab_commit_short_sha}"
            fi
        fi
    fi
}

_detect_project_language() {
    _msg step "[language] probe program language"
    local lang_files=("pom.xml" "composer.json" "package.json" "requirements.txt" "README.md" "readme.md" "README.txt" "readme.txt")
    local file

    for file in "${lang_files[@]}"; do
        [[ -f "${gitlab_project_dir}/${file}" ]] || continue
        _msg info "Found $file"
        case ${file,,} in
        pom.xml | build.gradle)
            project_lang="java"
            build_arg+=" --build-arg MVN_PROFILE=${gitlab_project_branch}"
            ${debug_on:-false} && build_arg+=" --build-arg MVN_DEBUG=on"
            ;;
        composer.json) project_lang="php" ;;
        package.json) project_lang="node" ;;
        requirements.txt) project_lang="python" ;;
        *)
            project_lang=$(awk -F= '/^project_lang/ {print tolower($2)}' "${gitlab_project_dir}/${file}" | tail -n 1)
            project_lang=${project_lang// /}
            ;;
        esac
        [[ -n $project_lang ]] && break
    done

    project_lang=${project_lang:-unknown}
    _msg info "Detected program language: ${project_lang}"
}

_determine_deployment_method() {
    _msg step "[probe] deploy method"
    local deploy_method=rsync
    for f in Dockerfile* docker-compose.yml; do
        [[ -f "${gitlab_project_dir}"/${f} ]] || continue
        echo "Found $f"
        case $f in
        docker-compose.yml)
            exec_deploy_docker_compose=true
            deploy_method=docker-compose
            break
            ;;
        Dockerfile*)
            exec_build_image=true
            exec_push_image=true
            exec_deploy_k8s=true
            exec_build_langs=false
            exec_deploy_rsync_ssh=false
            deploy_method=helm
            break
            ;;
        esac
    done

    echo "Deploy method: $deploy_method"
}

_setup_svn_repo() {
    ${checkout_with_svn:-false} || return 0
    if [[ ! -d "$SCRIPT_BUILDS" ]]; then
        echo "Not found $SCRIPT_BUILDS, create it..."
        mkdir -p "$SCRIPT_BUILDS"
    fi
    local svn_repo_name
    svn_repo_name=$(basename "$svn_url")
    local svn_repo_dir
    svn_repo_dir="${SCRIPT_BUILDS}/${svn_repo_name}"

    if [ -d "$svn_repo_dir" ]; then
        echo "Updating existing repo: $svn_repo_dir"
        (cd "$svn_repo_dir" && svn update) || {
            echo "Failed to update svn repo: $svn_url"
            return 1
        }
    else
        echo "Checking out new repo: $svn_url"
        svn checkout "$svn_url" "$svn_repo_dir" || {
            echo "Failed to checkout svn repo: $svn_url"
            return 1
        }
    fi
}

_setup_git_repo() {
    ${arg_git_clone:-false} || return 0
    if [[ ! -d "$SCRIPT_BUILDS" ]]; then
        echo "Not found $SCRIPT_BUILDS, create it..."
        mkdir -p "$SCRIPT_BUILDS"
    fi
    local git_repo_name
    git_repo_name="$(basename $arg_git_clone_url)"
    local git_repo_dir="${SCRIPT_BUILDS}/${git_repo_name%.git}"

    if [ -d "$git_repo_dir" ]; then
        echo "Updating existing repo: $git_repo_dir"
        git -C "$git_repo_dir" fetch --quiet || return 1
        git -C "$git_repo_dir" checkout --quiet "${arg_git_clone_branch:-main}" || {
            echo "Failed to checkout ${arg_git_clone_branch:-main}"
            return 1
        }
        git -C "$git_repo_dir" pull --quiet || return 1
    else
        echo "Cloning git repo: $arg_git_clone_url"
        git clone --quiet -b "${arg_git_clone_branch:-main}" "$arg_git_clone_url" "$git_repo_dir" || {
            echo "Failed to clone git repo: $arg_git_clone_url"
            return 1
        }
    fi
}

_setup_kubernetes_cluster() {
    ${create_k8s_with_terraform:-false} || return 0
    local terraform_dir="$SCRIPT_DATA/terraform"
    [[ -d "$terraform_dir" ]] || return 0

    _msg step "[PaaS] create k8s cluster"
    cd "$terraform_dir" || return 1

    if terraform init -input=false && terraform apply -auto-approve; then
        _msg info "Kubernetes cluster created successfully"
    else
        _msg error "Failed to create Kubernetes cluster"
        return 1
    fi
}

_usage() {
    cat <<EOF
Usage: $0 [parameters ...]

Parameters:
    -h, --help               Show this help message.
    -v, --version            Show version info.
    -d, --debug              Run in debug mode.
    --cron                   Run as a cron job.
    --github-action          Run as a GitHub Action.
    --in-china               Set ENV_IN_CHINA to true.

    # Repository operations
    --git-clone URL          Clone git repo URL to builds/REPO_NAME.
    --git-clone-branch NAME  Specify git branch (default: main).
    --svn-checkout URL       Checkout SVN repository.

    # Build and push
    --build-langs            Build all languages.
    --build-docker           Build image with Docker.
    --build-podman           Build image with Podman.
    --push-image             Push image.

    # Deployment
    --deploy-k8s             Deploy to Kubernetes.
    --deploy-functions       Deploy to Aliyun Functions.
    --deploy-flyway          Deploy database with Flyway.
    --deploy-rsync-ssh       Deploy using rsync over SSH.
    --deploy-rsync           Deploy to rsync server.
    --deploy-ftp             Deploy to FTP server.
    --deploy-sftp            Deploy to SFTP server.

    # Testing and quality
    --test-unit              Run unit tests.
    --test-function          Run functional tests.
    --code-style             Check code style.
    --code-quality           Check code quality.

    # Kubernetes operations
    --create-helm DIR        Create Helm chart in specified directory.
    --create-k8s             Create K8s cluster with Terraform.

    # Miscellaneous
    --get-balance            Get balance from Aliyun.
    --disable-inject         Disable file injection.
    -r, --renew-cert         Renew all the certs.
EOF
}

_parse_args() {
    [[ ${CI_DEBUG_TRACE:-false} == true ]] && debug_on=true
    build_cmd=$(command -v podman || command -v docker || echo docker)

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        # Basic options
        -h | --help) _usage && exit 0 ;;
        -v | --version) echo "Version: 1.0" && exit 0 ;;
        -d | --debug) set -x && debug_on=true ;;
        --cron | --loop) run_with_crontab=true ;;
        --github-action) set -x && debug_on=true && github_action=true ;;
        --in-china) sed -i -e '/ENV_IN_CHINA=/s/false/true/' $SCRIPT_ENV ;;
        # Repository operations
        --git-clone) arg_git_clone=true && arg_git_clone_url="${2:?empty git clone url}" && shift ;;
        --git-clone-branch) arg_git_clone_branch="${2:?empty git clone branch}" && shift ;;
        --svn-checkout) checkout_with_svn=true && svn_url="${2:?empty svn url}" && shift ;;
        # Build and push
        --build-langs) arg_build_langs=true && exec_single_job=true ;;
        --build-docker) arg_build_image=true && exec_single_job=true && build_cmd=$(command -v docker || echo docker) ;;
        --build-podman) arg_build_image=true && exec_single_job=true && build_cmd=$(command -v podman || echo podman) && build_cmd_opt='--force-rm --format=docker' ;;
        --push-image) arg_push_image=true && exec_single_job=true ;;
        # Deployment
        --deploy-k8s) arg_deploy_k8s=true && exec_single_job=true ;;
        --deploy-functions) arg_deploy_functions=true && exec_single_job=true ;;
        --deploy-flyway) arg_deploy_flyway=true && exec_single_job=true ;;
        --deploy-rsync-ssh) arg_deploy_rsync_ssh=true && exec_single_job=true ;;
        --deploy-rsync) arg_deploy_rsync=true && exec_single_job=true ;;
        --deploy-ftp) arg_deploy_ftp=true && exec_single_job=true ;;
        --deploy-sftp) arg_deploy_sftp=true && exec_single_job=true ;;
        # Testing and quality
        --test-unit) arg_test_unit=true && exec_single_job=true ;;
        --test-function) arg_test_function=true && exec_single_job=true ;;
        --code-style) arg_code_style=true && exec_single_job=true ;;
        --code-quality) arg_code_quality=true && exec_single_job=true ;;
        # Kubernetes operations
        --create-helm) arg_create_helm=true && exec_single_job=true && exec_inject_files=false && helm_dir="$2" && shift ;;
        --create-k8s) create_k8s_with_terraform=true ;;
        # Miscellaneous
        --get-balance) arg_get_balance=true && exec_single_job=true ;;
        --disable-inject) arg_disable_inject=true ;;
        -r | --renew-cert) arg_renew_cert=true && exec_single_job=true ;;
        *) _usage && exit 1 ;;
        esac
        shift
    done

    ${debug_on:-false} && unset quiet_flag || quiet_flag='--quiet'
}

main() {
    set -e ## 出现错误自动退出
    # set -u ## 变量未定义报错 # set -Eeuo pipefail
    SECONDS=0
    SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
    SCRIPT_PATH="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    source "$SCRIPT_PATH/lib/common.sh"
    _msg step "[deploy] BEGIN"
    ## Process parameters / 处理传入的参数
    _parse_args "$@"

    SCRIPT_CONF_PATH="${SCRIPT_PATH}/conf"
    SCRIPT_BIN="${SCRIPT_PATH}/bin"
    SCRIPT_LIB="${SCRIPT_PATH}/lib"
    SCRIPT_DATA="${SCRIPT_PATH}/data"
    SCRIPT_DATA_BIN="${SCRIPT_DATA}/bin"
    SCRIPT_BUILDS="${SCRIPT_PATH}/builds"
    SCRIPT_LOG="${SCRIPT_DATA}/${SCRIPT_NAME}.log"
    SCRIPT_CONF="${SCRIPT_DATA}/deploy.json"
    SCRIPT_ENV="${SCRIPT_DATA}/deploy.env"
    SCRIPT_DOCKERFILE="${SCRIPT_CONF_PATH}/dockerfile"
    SCRIPT_DATA_DOCKERFILE="${SCRIPT_DATA}/dockerfile"

    mkdir -p "${SCRIPT_DATA_BIN}"

    # Copy config files if they don't exist
    [[ -f "$SCRIPT_CONF" ]] || cp -v "${SCRIPT_CONF_PATH}/example-deploy.json" "$SCRIPT_CONF"
    [[ -f "$SCRIPT_ENV" ]] || cp -v "${SCRIPT_CONF_PATH}/example-deploy.env" "$SCRIPT_ENV"

    # Set PATH
    declare -a paths_append=(
        "/usr/local/sbin"
        "/snap/bin"
        "$SCRIPT_BIN"
        "$SCRIPT_DATA_BIN"
        "$SCRIPT_DATA/.acme.sh"
        "$HOME/.local/bin"
        "$HOME/.acme.sh"
        "$HOME/.config/composer/vendor/bin"
    )
    for p in "${paths_append[@]}"; do
        if [[ -d "$p" && "$PATH" != *":$p:"* ]]; then
            PATH="${PATH:+"$PATH:"}$p"
        fi
    done

    export PATH

    # Set up run commands
    run_cmd_root="$build_cmd run $ENV_ADD_HOST --interactive --rm"
    run_cmd+=" -u $(id -u):$(id -g)"
    build_cmd_opt="${build_cmd_opt:+"$build_cmd_opt "}$ENV_ADD_HOST $quiet_flag"
    ${debug_on:-false} && build_cmd_opt+=" --progress plain"

    ## check OS version/type/install command/install software / 检查系统版本/类型/安装命令/安装软件
    _setup_environment

    ## git clone repo / 克隆 git 仓库
    _setup_git_repo

    ## svn checkout repo / 克隆 svn 仓库
    _setup_svn_repo

    ## run deploy.sh by hand / 手动执行 deploy.sh 时假定的 gitlab 配置
    _initialize_gitlab_variables

    ## source ENV, get global variables / 获取 ENV_ 开头的所有全局变量
    source "$SCRIPT_ENV"

    # Set up kubectl and helm
    kubectl_opt="kubectl"
    helm_opt="helm"
    k_conf="$HOME/.kube/$env_namespace/config"
    if [ -f "$k_conf" ]; then
        kubectl_opt+=" --kubeconfig $k_conf"
        helm_opt+=" --kubeconfig $k_conf"
    fi

    image_tag="${gitlab_commit_short_sha}-$(date +%s%3N)"
    image_tag_flyway="${ENV_DOCKER_REGISTRY:?undefine}:${gitlab_project_name}-flyway-${gitlab_commit_short_sha}"
    ## install acme.sh/aws/kube/aliyun/python-gitlab/flarectl 安装依赖命令/工具
    ${ENV_INSTALL_AWS:-false} && _install_aws
    ${ENV_INSTALL_ALIYUN:-false} && _install_aliyun_cli
    ${ENV_INSTALL_JQ:-false} && _install_jq_cli
    ${ENV_INSTALL_TERRAFORM:-false} && _install_terraform
    ${ENV_INSTALL_KUBECTL:-false} && _install_kubectl
    ${ENV_INSTALL_HELM:-false} && _install_helm
    ${ENV_INSTALL_PYTHON_ELEMENT:-false} && _install_python_element
    ${ENV_INSTALL_PYTHON_GITLAB:-false} && _install_python_gitlab
    ${ENV_INSTALL_JMETER:-false} && _install_jmeter
    ${ENV_INSTALL_FLARECTL:-false} && _install_flarectl
    ${ENV_INSTALL_DOCKER:-false} && _install_docker "$(_is_china && echo "--mirror Aliyun")"
    ${ENV_INSTALL_PODMAN:-false} && _install_podman
    ${ENV_INSTALL_CRON:-false} && _install_cron

    ## clean up disk space / 清理磁盘空间
    _clean_up_disk_space

    ## create k8s / 创建 kubernetes 集群
    _setup_kubernetes_cluster

    ## setup ssh-config/acme.sh/aws/kube/aliyun/python-gitlab/cloudflare/rsync
    _setup_deployment_environment >/dev/null

    ## get balance of aliyun / 获取 aliyun 账户现金余额
    # echo "MAN_GET_BALANCE: ${MAN_GET_BALANCE:-false}"
    if [[ "${MAN_GET_BALANCE:-false}" == true ]] || ${arg_get_balance:-false}; then
        _check_aliyun_account_balance
    fi

    ## renew cert with acme.sh / 使用 acme.sh 重新申请证书
    # echo "MAN_RENEW_CERT: ${MAN_RENEW_CERT:-false}"
    if [[ "${MAN_RENEW_CERT:-false}" == true ]] || ${github_action:-false} || ${arg_renew_cert:-false}; then
        exec_single_job=true
        _renew_ssl_certificates
    fi

    ## probe program lang / 探测项目的程序语言
    _detect_project_language

    ## preprocess project config files / 预处理业务项目配置文件，覆盖配置文件等特殊处理
    _inject_project_files

    ## probe deploy method / 探测文件并确定发布方式
    _determine_deployment_method

    ## code style check / 代码格式检查
    code_style_sh="$SCRIPT_LIB/style/${project_lang}.sh"

    ## code build / 代码编译打包
    build_langs_sh="$SCRIPT_LIB/build/${project_lang}.sh"

    ################################################################################
    ## exec single task / 执行单个任务，适用于 gitlab-ci/jenkins 等自动化部署工具的单个 job 任务执行
    if ${exec_single_job:-false}; then
        _msg green "exec single jobs..."
        ${arg_code_quality:-false} && _run_sonarqube_analysis
        ${arg_code_style:-false} && {
            [[ -f "$code_style_sh" ]] && source "$code_style_sh"
        }
        ${arg_test_unit:-false} && _test_unit
        ${arg_deploy_flyway:-false} && _deploy_flyway_docker
        # ${exec_deploy_flyway:-false} && _deploy_flyway_helm_job
        ${exec_deploy_flyway:-false} && _deploy_flyway_docker
        ${arg_build_langs:-false} && {
            [[ -f "$build_langs_sh" ]] && source "$build_langs_sh"
        }
        ${arg_build_image:-false} && _build_image
        ${arg_push_image:-false} && _push_image
        ${arg_deploy_functions:-false} && _deploy_to_aliyun_functions
        ${arg_create_helm:-false} && _create_helm_chart "${helm_dir}"
        ${arg_deploy_k8s:-false} && _deploy_to_kubernetes
        ${arg_deploy_rsync_ssh:-false} && _deploy_via_rsync_ssh
        ${arg_deploy_rsync:-false} && _deploy_rsync
        ${arg_deploy_ftp:-false} && _deploy_ftp
        ${arg_deploy_sftp:-false} && _deploy_sftp
        ${arg_test_function:-false} && _test_function

        _msg green "exec single jobs...end"
        ${github_action:-false} || return 0
    fi
    ################################################################################

    ## default exec all tasks / 单个任务未启动时默认执行所有任务
    ## 在 gitlab 的 pipeline 配置环境变量 MAN_SONAR ，true 启用，false 禁用[default]
    _msg step "[quality] check code with sonarqube"
    echo "MAN_SONAR: ${MAN_SONAR:-false}"
    if [[ "${MAN_SONAR:-false}" == true ]]; then
        _run_sonarqube_analysis
    else
        echo "<skip>"
    fi

    ## 在 gitlab 的 pipeline 配置环境变量 MAN_CODE_STYLE ，true 启用，false 禁用[default]
    _msg step "[style] check code style"
    echo "MAN_CODE_STYLE: ${MAN_CODE_STYLE:-false}"
    if [[ "${MAN_CODE_STYLE:-false}" == true ]]; then
        if [[ -f "$code_style_sh" ]]; then
            source "$code_style_sh"
        else
            _msg time "not found $code_style_sh"
        fi
    else
        echo '<skip>'
    fi

    ## unit test / 单元测试
    ## 在 gitlab 的 pipeline 配置环境变量 MAN_UNIT_TEST ，true 启用，false 禁用[default]
    _msg step "[test] unit test"
    echo "MAN_UNIT_TEST: ${MAN_UNIT_TEST:-false}"
    if [[ "${MAN_UNIT_TEST:-false}" == true ]]; then
        _test_unit
    else
        echo "<skip>"
    fi

    ## use flyway deploy sql file / 使用 flyway 发布 sql 文件
    _msg step "[database] deploy SQL files with flyway"
    # ${ENV_FLYWAY_HELM_JOB:-false} && _deploy_flyway_helm_job
    # ${exec_deploy_flyway:-false} && _deploy_flyway_helm_job
    echo "MAN_FLYWAY: ${MAN_FLYWAY:-false}"
    if [[ "${MAN_FLYWAY:-false}" == true ]] || ${exec_deploy_flyway:-false}; then
        _deploy_flyway_docker
    else
        echo '<skip>'
    fi

    ## generate api docs / 利用 apidoc 产生 api 文档
    _generate_api_documentation

    ## build
    if ${exec_build_langs:-true}; then
        if [[ -f "$build_langs_sh" ]]; then
            source "$build_langs_sh"
        else
            _msg time "not found $build_langs_sh"
        fi
    fi
    ${exec_build_image:-false} && _build_image
    ${exit_directly:-false} && return

    ## push image
    ${exec_push_image:-false} && _push_image

    ## deploy k8s
    ${exec_deploy_k8s:-false} && _deploy_to_kubernetes
    ## deploy functions aliyun
    ${exec_deploy_functions:-true} && _deploy_to_aliyun_functions
    ## deploy rsync server
    ${exec_deploy_rsync:-false} && _deploy_rsync
    ## deploy ftp server
    ${exec_deploy_ftp:-false} && _deploy_ftp
    ## deploy sftp server
    ${exec_deploy_sftp:-false} && _deploy_sftp
    ## deploy with rsync / 使用 rsync 发布
    ${exec_deploy_rsync_ssh:-true} && _deploy_via_rsync_ssh

    ## function test / 功能测试
    ## 在 gitlab 的 pipeline 配置环境变量 MAN_FUNCTION_TEST ，true 启用，false 禁用[default]
    _msg step "[test] function test"
    echo "MAN_FUNCTION_TEST: ${MAN_FUNCTION_TEST:-false}"
    if [[ "${MAN_FUNCTION_TEST:-false}" == true ]]; then
        _test_function
    else
        echo "<skip>"
    fi

    ## 安全扫描
    _msg step "[security] ZAP scan"
    echo "MAN_SCAN_ZAP: ${MAN_SCAN_ZAP:-false}"
    if [[ "${MAN_SCAN_ZAP:-false}" == true ]]; then
        _run_zap_scan
    else
        echo '<skip>'
    fi

    _msg step "[security] vulmap scan"
    echo "MAN_SCAN_VULMAP: ${MAN_SCAN_VULMAP:-false}"
    if [[ "${MAN_SCAN_VULMAP:-false}" == true ]]; then
        _run_vulmap_scan
    else
        echo '<skip>'
    fi

    ## deploy notify info / 发布通知信息
    _msg step "[notify] message for result"
    ## 发送消息到群组, exec_deploy_notify ， false 不发， true 发.
    echo "MAN_NOTIFY: ${MAN_NOTIFY:-false}"
    ${github_action:-false} && deploy_result=0
    ((${deploy_result:-0})) && exec_deploy_notify=true
    ${ENV_ENABLE_MSG:-false} || exec_deploy_notify=false
    [[ "${ENV_DISABLE_MSG_BRANCH}" =~ $gitlab_project_branch ]] && exec_deploy_notify=false
    ${MAN_NOTIFY:-false} && exec_deploy_notify=true
    if ${exec_deploy_notify:-true}; then
        _deploy_notify
    fi

    _msg time "[deploy] END."

    ## deploy result:  0 成功， 1 失败
    return ${deploy_result:-0}
}

main "$@"
