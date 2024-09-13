#!/usr/bin/env bash
# shellcheck disable=1090,2086
################################################################################
#
# Description: deploy.sh is a CI/CD program.
# Author: xiagw <fxiaxiaoyu@gmail.com>
# License: GNU/GPL, see http://www.gnu.org/copyleft/gpl.html
# Date: 2019-04-03
#
################################################################################

_msg() {
    local color_on
    local color_off='\033[0m' # Text Reset
    time_hms="$((SECONDS / 3600))h$(((SECONDS / 60) % 60))m$((SECONDS % 60))s"
    timestamp="$(date +%Y%m%d-%u-%T.%3N)"

    case "${1:-none}" in
    info) color_on='' ;;
    warn | warning | yellow) color_on='\033[0;33m' ;;
    error | err | red) color_on='\033[0;31m' ;;
    question | ques | purple) color_on='\033[0;35m' ;;
    green) color_on='\033[0;32m' ;;
    blue) color_on='\033[0;34m' ;;
    cyan) color_on='\033[0;36m' ;;
    orange) color_on='\033[1;33m' ;;
    step)
        ((++STEP))
        color_on="\033[0;36m$timestamp - [$STEP] \033[0m"
        color_off=" - [$time_hms]"
        ;;
    time)
        color_on="$timestamp - [${STEP}] "
        color_off=" - [$time_hms]"
        ;;
    log)
        shift
        echo "$timestamp - $*" >>$me_log
        return
        ;;
    *)
        unset color_on color_off
        ;;
    esac
    [ "$#" -gt 1 ] && shift

    echo -e "${color_on}$*${color_off}"
}

## year month day - time - %u day of week (1..7); 1 is Monday - %j day of year (001..366) - %W week number of year, with Monday as first day of week (00..53)

_is_demo_mode() {
    local skip_msg="$1"
    if grep -q -E '=your_password|=your_username' $me_env; then
        _msg purple "Found default docker username/password, skip $skip_msg ..."
        return 0
    else
        return 1
    fi
}

_is_root() {
    if [ "$(id -u)" -eq 0 ]; then
        unset use_sudo
        return 0
    else
        use_sudo=sudo
        return 1
    fi
}

## install phpunit
_test_unit() {
    if [[ -f "$gitlab_project_dir"/tests/unit_test.sh ]]; then
        echo "Found $gitlab_project_dir/tests/unit_test.sh"
        bash "$gitlab_project_dir"/tests/unit_test.sh
    elif [[ -f "$me_path_data"/tests/unit_test.sh ]]; then
        echo "Found $me_path_data/tests/unit_test.sh"
        bash "$me_path_data"/tests/unit_test.sh
    else
        _msg purple "not found tests/unit_test.sh, skip unit test."
    fi
    _msg time "[test] unit test"
}

## install jdk/ant/jmeter
_test_function() {
    if [ -f "$gitlab_project_dir"/tests/func_test.sh ]; then
        echo "Found $gitlab_project_dir/tests/func_test.sh"
        bash "$gitlab_project_dir"/tests/func_test.sh
    elif [ -f "$me_path_data"/tests/func_test.sh ]; then
        echo "Found $me_path_data/tests/func_test.sh"
        bash "$me_path_data"/tests/func_test.sh
    else
        echo "Not found tests/func_test.sh, skip function test."
    fi
    _msg time "[test] function test"
}

_check_quality_sonar() {
    local sonar_url="${ENV_SONAR_URL:?empty}"
    local sonar_conf="$gitlab_project_dir/sonar-project.properties"
    if ! curl --silent --head --fail --connect-timeout 5 "$sonar_url" >/dev/null 2>&1; then
        _msg warning "Could not found sonarqube server, exit."
        return
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
    $run_cmd -e SONAR_TOKEN="${ENV_SONAR_TOKEN:?empty}" -v "$gitlab_project_dir":/usr/src sonarsource/sonar-scanner-cli
    _msg time "[quality] check code with sonarqube"
}

_scan_zap() {
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
    fi
    _msg time "[scan] run ZAP scan"
}
# _security_scan_zap "http://example.com" "my/zap-image" "-t http://example.com -r report.html -x report.xml"

_scan_vulmap() {
    # https://github.com/zhzyker/vulmap
    # $build_cmd run --rm -ti vulmap/vulmap  python vulmap.py -u https://www.example.com
    # Load environment variables from config file
    source $me_path_data/config.cfg
    # Run vulmap scan
    $run_cmd_root -v "${PWD}:/work" vulmap -u "${ENV_TARGET_URL}" -o "/work/vulmap_report.html"

    # Display scan results
    if [[ -f "vulmap_report.html" ]]; then
        echo "Vulmap scan complete. Results saved to 'vulmap_report.html'."
    else
        echo "Vulmap scan failed or no vulnerabilities found."
    fi
}

# _check_gitleaks /path/to/repo /path/to/config.toml
_check_gitleaks() {
    local path="$1"
    local config_file="$2"

    $run_cmd_root -v "$path:/repo" -v "$config_file:/config.toml" zricethezav/gitleaks:v7.5.0 gitleaks --path=/repo --config=/config.toml
}

_deploy_flyway_docker() {
    flyway_conf_volume="${gitlab_project_dir}/flyway_conf:/flyway/conf"
    flyway_sql_volume="${gitlab_project_dir}/flyway_sql:/flyway/sql"
    flyway_docker_run="$build_cmd run --rm -v ${flyway_conf_volume} -v ${flyway_sql_volume} flyway/flyway"

    ## ssh port-forward mysql 3306 to localhost / 判断是否需要通过 ssh 端口转发建立数据库远程连接
    [ -f "$me_path_bin/ssh-port-forward.sh" ] && source "$me_path_bin/ssh-port-forward.sh" port
    ## exec flyway
    if $flyway_docker_run info | grep '^|' | grep -vE 'Category.*Version|Versioned.*Success|Versioned.*Deleted|DELETE.*Success'; then
        $flyway_docker_run repair
        $flyway_docker_run migrate || deploy_result=1
        $flyway_docker_run info | tail -n 10
    else
        _msg warning "No SQL migrations to apply."
    fi
    if [ ${deploy_result:-0} = 0 ]; then
        _msg green "flyway migrate result = OK"
    else
        _msg error "flyway migrate result = FAIL"
    fi
    _msg time "[database] deploy SQL files with flyway"
}

_deploy_flyway_helm_job() {
    _msg step "[database] deploy SQL with flyway (helm job)"
    echo "$image_tag_flyway"
    ${github_action:-false} && return 0
    $build_cmd build $build_cmd_opt --tag "${image_tag_flyway}" -f "${gitlab_project_dir}/Dockerfile.flyway" "${gitlab_project_dir}/"
    $run_cmd_root "$image_tag_flyway" || deploy_result=1
    if [ ${deploy_result:-0} = 0 ]; then
        _msg green "flyway migrate result = OK"
    else
        _msg error "flyway migrate result = FAIL"
    fi
    _msg time "[database] deploy SQL with flyway (helm job)"
}

# python-gitlab list all projects / 列出所有项目
# gitlab -o json -f path_with_namespace project list --page 1 --per-page 5 | jq -r '.[].path_with_namespace'
# 解决 Encountered 1 file(s) that should have been pointers, but weren't
# git lfs migrate import --everything$(awk '/filter=lfs/ {printf " --include='\''%s'\''", $1}' .gitattributes)

_login_registry() {
    ${github_action:-false} && return 0
    local lock_login_registry="$me_path_data/.docker.login.${ENV_DOCKER_LOGIN_TYPE:-none}.lock"
    local time_last
    case "${ENV_DOCKER_LOGIN_TYPE:-none}" in
    aws)
        time_last="$(stat -t -c %Y "$lock_login_registry" 2>/dev/null || echo 0)"
        ## Compare the last login time, login again after 12 hours / 比较上一次登陆时间，超过12小时则再次登录
        if [[ "$(date +%s -d '12 hours ago')" -lt "${time_last:-0}" ]]; then
            return 0
        fi
        _msg time "[login] aws ecr login [${ENV_DOCKER_LOGIN_TYPE:-none}]..."
        aws ecr get-login-password --profile="${ENV_AWS_PROFILE}" --region "${ENV_REGION_ID:?undefine}" |
            $build_cmd login --username AWS --password-stdin ${ENV_DOCKER_REGISTRY%%/*} >/dev/null &&
            touch "$lock_login_registry"
        ;;
    *)
        _is_demo_mode "docker-login" && return 0

        if [[ -f "$lock_login_registry" ]]; then
            return 0
        fi
        echo "${ENV_DOCKER_PASSWORD}" |
            $build_cmd login --username="${ENV_DOCKER_USERNAME}" --password-stdin "${ENV_DOCKER_REGISTRY%%/*}" &&
            touch "$lock_login_registry"
        ;;
    esac
}

_get_docker_context() {
    ## use local context / 使用本地 context
    if [[ ${ENV_DOCKER_CONTEXT:-local} == local ]]; then
        return
    fi
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
    for dk_host in "${ENV_DOCKER_CONTEXT_HOSTS[@]}"; do
        ((++c))
        if echo "${docker_endpoints[@]}" | grep -q "$dk_host"; then
            : ## found docker endpoint
        else
            ## not found docker endpoint, create it
            docker context create remote$c --docker "host=${dk_host}" || _msg error "Failed to create docker context remote$c: ${dk_host}"
        fi
    done
    ## use remote context (exclude local) / 使用远程 context
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
        ## random algorithum
        random_index=$((RANDOM % ${#docker_contexts[@]}))
        selected_context="${docker_contexts[$random_index]}"
        ;;
    rr)
        ## round-robin algorithum
        position_file="${me_path_data:-.}/.docker_context_history"
        [[ -f "$position_file" ]] || echo 0 >"$position_file"
        # 读取当前轮询位置
        position=$(tail -n 1 $position_file)
        # 输出当前位置的值
        selected_context="${docker_contexts[$position]}"
        # 更新轮询位置
        position=$(((position + 1) % ${#docker_contexts[@]}))
        echo $position >$position_file
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
    if [[ -z "$ENV_DOCKER_REGISTRY_BASE" ]]; then
        _msg warn "ENV_DOCKER_REGISTRY_BASE is undefined, use $ENV_DOCKER_REGISTRY instead."
        registry_base=ENV_DOCKER_REGISTRY
    else
        registry_base=ENV_DOCKER_REGISTRY_BASE
    fi
    if [[ -f "${gitlab_project_dir}/Dockerfile.base" ]]; then
        if [[ -f "${gitlab_project_dir}/build.base.sh" ]]; then
            echo "Found ${gitlab_project_dir}/build.base.sh, run it..."
            bash "${gitlab_project_dir}/build.base.sh"
        else
            echo "$registry_base:${gitlab_project_name}-${gitlab_project_branch}"
            $build_cmd build $build_cmd_opt --tag $registry_base:${gitlab_project_name}-${gitlab_project_branch} $build_arg -f "${gitlab_project_dir}/Dockerfile.base" "${gitlab_project_dir}"
            $build_cmd push $quiet_flag $registry_base:${gitlab_project_name}-${gitlab_project_branch}
        fi
        _msg time "[image] build base image"
        exit_directly=true
        return
    fi
    ## build container image
    $build_cmd build $build_cmd_opt --tag "${ENV_DOCKER_REGISTRY}:${image_tag}" $build_arg "${gitlab_project_dir}"
    ## push image to ttl.sh
    if [[ "${MAN_TTL:-false}" == true ]] || ${ENV_IMAGE_TTL:-false}; then
        image_uuid="ttl.sh/$(uuidgen):1h"
        echo "## If you want to push the image to ttl.sh, please execute the following command on gitlab-runner:"
        echo "  $build_cmd tag ${ENV_DOCKER_REGISTRY}:${image_tag} ${image_uuid}"
        echo "  $build_cmd push $image_uuid"
        echo "## Then execute the following command on remote server:"
        echo "  $build_cmd pull $image_uuid"
        echo "  $build_cmd tag $image_uuid laradock_spring"
    fi
    _msg time "[image] build container image"
}

_push_image() {
    _msg step "[image] push container image"
    _is_demo_mode "push-image" && return 0
    _login_registry
    if $build_cmd push $quiet_flag "${ENV_DOCKER_REGISTRY}:${image_tag}"; then
        $build_cmd rmi "${ENV_DOCKER_REGISTRY}:${image_tag}" >/dev/null
    else
        push_error=true
    fi
    if ${ENV_FLYWAY_HELM_JOB:-false}; then
        $build_cmd push $quiet_flag "$image_tag_flyway" || push_error=true
    fi
    ${push_error:-false} && _msg error "got an error here, probably caused by network..."
    _msg time "[image] push container image"
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
    ## 获取 release 名称/端口/协议等信息
    release_name_path="$1"
    port_number=8080
    port_number2=8081
    protocol=tcp

    ## 创建 helm chart
    helm create "$release_name_path"
    _msg log "helm create $release_name_path" >>"$me_log"
    ## 需要修改的配置文件
    file_values="$release_name_path/values.yaml"
    file_svc="$release_name_path/templates/service.yaml"
    file_deploy="$release_name_path/templates/deployment.yaml"
    ## remove serviceaccount.yaml
    # rm -f "$release_name_path/templates/serviceaccount.yaml"

    ## change values.yaml
    sed -i \
        -e "/port: 80/ a \  port2: ${port_number2:-8081}" \
        -e "s@port: 80@port: ${port_number:-8080}@" \
        -e "s/create: true/create: false/" "$file_values"
    sed -i \
        -e '/livenessProbe/ a \  initialDelaySeconds: 30' \
        -e '/readinessProbe/a \  initialDelaySeconds: 30' \
        "$file_values"
    sed -i -e "/resources: {}/s//resources:/" "$file_values"
    sed -i -e "/resources:/ a \    cpu: 500m" "$file_values"
    sed -i -e "/resources:/ a \  requests:" "$file_values"

    sed -i -e '/autoscaling:/,$ s/enabled: false/enabled: true/' "$file_values"

    sed -i -e "/volumes: \[\]/s//volumes:/" "$file_values"
    sed -i -e "/volumes:/ a \      claimName: cnfs-pvc-www" "$file_values"
    sed -i -e "/volumes:/ a \    persistentVolumeClaim:" "$file_values"
    sed -i -e "/volumes:/ a \  - name: volume-cnfs" "$file_values"

    sed -i -e "/volumeMounts: \[\]/s//volumeMounts:/" "$file_values"
    sed -i -e "/volumeMounts:/ a \    mountPath: \"\/app2\"" "$file_values"
    sed -i -e "/volumeMounts:/ a \  - name: volume-cnfs" "$file_values"

    ## set livenessProbe
    if [[ "${protocol:-tcp}" == 'tcp' ]]; then
        sed -i \
            -e "s@httpGet:@tcpSocket:@g" \
            -e "s@\ \ \ \ path: /@#     path: /@g" \
            -e "s@port: http@port: ${port_number:-8080}@g" \
            "$file_values"
    else
        sed -i \
            -e "s@port: http@port: ${port_number:-8080}@g" \
            "$file_values"
    fi

    ## change service.yaml
    sed -i -e "s@targetPort: http@targetPort: {{ .Values.service.port }}@" "$file_svc"
    sed -i -e '/  ports:/ a \    {{- end }}' "$file_svc"
    sed -i -e '/  ports:/ a \      name: http2' "$file_svc"
    sed -i -e '/  ports:/ a \      protocol: TCP' "$file_svc"
    sed -i -e '/  ports:/ a \      targetPort: {{ .Values.service.port2 }}' "$file_svc"
    sed -i -e '/  ports:/ a \    - port: {{ .Values.service.port2 }}' "$file_svc"
    sed -i -e '/  ports:/ a \    {{- if .Values.service.port2 }}' "$file_svc"

    ## change deployment.yaml
    sed -i -e '/  ports:/ a \            {{- end }}' "$file_deploy"
    sed -i -e '/  ports:/ a \              protocol: TCP' "$file_deploy"
    sed -i -e '/  ports:/ a \              containerPort: {{ .Values.service.port2 }}' "$file_deploy"
    sed -i -e '/  ports:/ a \            - name: http2' "$file_deploy"
    sed -i -e '/  ports:/ a \            {{- if .Values.service.port2 }}' "$file_deploy"

    ## dns config
    cat >>"$file_deploy" <<EOF
      dnsConfig:
        options:
        - name: ndots
          value: "2"
EOF

    sed -i -e "/serviceAccountName/s/^/#/" "$file_deploy"
}

_deploy_functions_aliyun() {
    _format_release_name
    ${github_action:-false} && return 0
    ${ENV_ENABLE_FUNC:-false} || {
        _msg time "!!! disable deploy to functions3.0 aliyun !!!"
        return 0
    }
    if [ "${env_namespace}" != main ]; then
        release_name="${release_name}-${env_namespace}"
    fi
    ## create FC
    _msg step "[deploy] create/update functions"
    functions_conf_tmpl="$me_path_data"/aliyun.functions.${project_lang}.json
    functions_conf="$me_path_data"/aliyun.functions.json
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

    # _set_proxy off
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

_deploy_k8s() {
    if "${ENV_DISABLE_K8S:-false}"; then
        _msg time "!!! disable deploy to k8s !!!"
        return
    fi
    _msg step "[deploy] deploy k8s with helm"
    _is_demo_mode "deploy-helm" && return 0
    _format_release_name

    ## finding helm files folder / 查找 helm 文件目录
    helm_dirs=(
        "$gitlab_project_dir/helm/${release_name}"
        "$gitlab_project_dir/docs/helm/${release_name}"
        "$gitlab_project_dir/doc/helm/${release_name}"
        "${me_path_data}/helm/${gitlab_project_path_slug}/${env_namespace}/${release_name}"
        "${me_path_data}/helm/${gitlab_project_path_slug}/${release_name}"
        "${me_path_data}/helm/${release_name}"
    )
    for i in "${helm_dirs[@]}"; do
        if [ -d "$i" ]; then
            helm_dir="$i"
            break
        fi
    done
    ## create helm charts / 创建 helm 文件
    if [ -z "$helm_dir" ]; then
        _msg purple "Not found helm files"
        echo "Try to generate helm files"
        helm_dir="${me_path_data}/helm/${gitlab_project_path_slug}/${release_name}"
        [ -d "$helm_dir" ] || mkdir -p "$helm_dir"
        _create_helm_chart "${helm_dir}"
    fi

    echo "$helm_opt upgrade --install --history-max 1 ${release_name} $helm_dir/ --namespace ${env_namespace} --create-namespace --set image.pullPolicy=Always --timeout 120s --set image.repository=${ENV_DOCKER_REGISTRY} --set image.tag=${image_tag}" | sed "s#$HOME#\$HOME#g" | tee -a "$me_log"
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
        echo "此处探测应用是否正常超时120秒，不能百分之百以此作为依据，如遇错误，需要去k8s内检查容器是否正常，或者通过日志去判断"
    fi

    if [ -f "$gitlab_project_dir/deploy.custom.sh" ]; then
        _msg time "custom deploy."
        source "$gitlab_project_dir/deploy.custom.sh"
    fi

    ## helm install flyway jobs / helm 安装 flyway 任务
    if ${ENV_FLYWAY_HELM_JOB:-false} && [[ -d "${me_path_conf}"/helm/flyway ]]; then
        $helm_opt upgrade flyway "${me_path_conf}/helm/flyway/" --install --history-max 1 \
            --namespace "${env_namespace}" --create-namespace \
            --set image.repository="${ENV_DOCKER_REGISTRY}" \
            --set image.tag="${gitlab_project_name}-flyway-${gitlab_commit_short_sha}" \
            --set image.pullPolicy='Always' >/dev/null
    fi
    _msg time "[deploy] deploy k8s with helm"
}

_deploy_rsync_ssh() {
    _msg step "[deploy] deploy files with rsync+ssh"
    ## rsync exclude some files / rsync 排除某些文件
    if [[ -f "${gitlab_project_dir}/rsync.exclude" ]]; then
        rsync_exclude="${gitlab_project_dir}/rsync.exclude"
    else
        rsync_exclude="${me_path_conf}/rsync.exclude"
    fi
    ## read conf, get project,branch,jar/war etc. / 读取配置文件，获取 项目/分支名/war包目录
    # grep "^${gitlab_project_path}\s\+${env_namespace}" "$me_conf" | tee -a $conf_temp || true
    conf_line="$(jq -c ".[] | select (.project == \"${gitlab_project_path}\") | .branchs[] | select (.branch == \"${env_namespace}\") | .hosts[]" "$me_conf" | wc -l)"
    if [ "$conf_line" -eq 0 ]; then
        _msg warn "[deploy] not config $me_conf"
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
        echo "ssh host: ${ssh_host:?when stop here, please check $me_conf}, port: ${ssh_port:-22}"
        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=10 -p ${ssh_port:-22}"

        ## node/java use rsync --delete / node/java 使用 rsync --delete
        [[ "${project_lang}" =~ (node) ]] && rsync_delete='--delete'
        rsync_opt="rsync -acvzt --exclude=.svn --exclude=.git --timeout=10 --no-times --exclude-from=${rsync_exclude} $rsync_delete"

        ## rsync source folder / rsync 源目录
        ## define rsync_relative_path in bin/build.*.sh / 在 bin/build.*.sh 中定义 rsync_relative_path
        ## default: rsync_relative_path=''
        if [[ "$project_lang" == java ]]; then
            rsync_relative_path=jars/
        elif [[ "$project_lang" == node ]]; then
            rsync_relative_path=dist/
        fi
        if [[ -z "${rsync_src_from_conf}" ]]; then
            rsync_src="${gitlab_project_dir}/${rsync_relative_path-}"
        else
            rsync_src="${rsync_src_from_conf}/"
        fi
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
        $ssh_opt -n "${ssh_host}" "[[ -d $rsync_dest ]] || mkdir -p $rsync_dest"
        ## rsync to remote server / rsync 到远程服务器
        ${rsync_opt} -e "$ssh_opt" "${rsync_src}" "${ssh_host}:${rsync_dest}"

        if [ -f "$me_path_data_bin/deploy.custom.sh" ]; then
            _msg time "custom deploy..."
            bash "$me_path_data_bin/deploy.custom.sh" ${ssh_host} ${rsync_dest}
            _msg time "custom deploy."
        fi

        if ${exec_deploy_docker_compose:-false}; then
            _msg step "deploy to server with docker-compose"
            $ssh_opt -n "$ssh_host" "cd docker/laradock && docker compose up -d $gitlab_project_name"
        fi
    done < <(jq -c ".[] | select (.project == \"${gitlab_project_path}\") | .branchs[] | select (.branch == \"${env_namespace}\") | .hosts[]" "$me_conf")
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
    if ! command -v ossutil >/dev/null 2>&1; then
        curl https://gosspublic.alicdn.com/ossutil/install.sh | $use_sudo bash
    fi
    oss_config_file=${me_path_data}/aliyun.oss.key.conf
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
    rsyncd_conf="$me_path_data/rsyncd.conf"
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
    curl -s -X POST -H "Content-Type: application/json" -d '{"text": "'"${msg_body}"'"}' "${ENV_ZOOM_CHANNEL}"
}

_notify_feishu() {
    # Send message to Feishu 飞书
    # ENV_WEBHOOK_URL="https://open.feishu.cn/open-apis/bot/v2/hook/your-webhook-url"
    curl -s -X POST -H "Content-Type: application/json" -d '{"text": "'"$msg_body"'"}' "$ENV_WEBHOOK_URL"
}

_notify_wechat_work() {
    # Send message to weixin_work 企业微信
    local wechat_key=$1
    wechat_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$wechat_key"
    curl -s -X POST -H 'Content-Type: application/json' -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$msg_body\"}}" "$wechat_api"
}

_deploy_notify() {
    msg_describe="${msg_describe:-$(if [ -d .git ]; then git --no-pager log --no-merges --oneline -1; else echo 'not-git'; fi)}"

    msg_body="
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
    wechat)
        ## work chat / 发送至 企业微信
        _msg time "notify to wechat work"
        _notify_wechat_work ${ENV_WEIXIN_KEY}
        ;;
    telegram)
        ## Telegram / 发送至 Telegram
        _msg time "notify to Telegram"
        telegram_api_msg="https://api.telegram.org/bot${ENV_TG_API_KEY}/sendMessage"
        # telegram_api_doc="https://api.telegram.org/bot${ENV_TG_API_KEY}/sendDocument"
        msg_body="$(echo "$msg_body" | sed -e ':a;N;$!ba;s/\n/%0a/g' -e 's/&/%26/g')"
        curl -sSLo /dev/null -X POST -d "chat_id=${ENV_TG_GROUP_ID}&text=$msg_body" "$telegram_api_msg"
        ;;
    element)
        ## element / 发送至 element
        _msg time "notify to Element"
        python3 "$me_path_data_bin/element.py" "$msg_body"
        ;;
    email)
        ## email / 发送至 email
        # mogaal/sendemail: lightweight, command line SMTP email client
        # https://github.com/mogaal/sendemail
        _msg time "notify to Email"
        "$me_path_bin/sendEmail" \
            -s "$ENV_EMAIL_SERVER" \
            -f "$ENV_EMAIL_FROM" \
            -xu "$ENV_EMAIL_USERNAME" \
            -xp "$ENV_EMAIL_PASSWORD" \
            -t "$ENV_EMAIL_TO" \
            -o message-content-type=text/html \
            -o message-charset=utf-8 \
            -u "[Gitlab Deploy] ${gitlab_project_path} ${gitlab_project_branch} ${gitlab_pipeline_id}/${gitlab_job_id}" \
            -m "$msg_body"
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

_renew_cert() {
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
            _msg time "Found $file"
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
            _msg warn "dns type: Goddady"
            _set_proxy on
            api_head="Authorization: sso-key ${SAVED_GD_Key:-none}:${SAVED_GD_Secret:-none}"
            api_goddady="https://api.godaddy.com/v1/domains"
            domains="$(
                curl -fsSL -X GET -H "$api_head" "$api_goddady" | jq -r '.[].domain' || true
            )"
            ;;
        dns_cf)
            _msg warn "dns type: cloudflare"
            _set_proxy on
            _install_flarectl
            domains="$(
                flarectl zone list | awk '/active/ {print $3}' || true
            )"
            ;;
        dns_ali)
            _msg warn "dns type: aliyun"
            _install_aliyun_cli
            _set_proxy off
            aliyun configure set \
                --mode AK \
                --profile "deploy_${profile_name}" \
                --region "${SAVED_Ali_region:-none}" \
                --access-key-id "${SAVED_Ali_Key:-none}" \
                --access-key-secret "${SAVED_Ali_Secret:-none}"
            domains="$(
                aliyun --profile "deploy_${profile_name}" domain QueryDomainList --PageNum 1 --PageSize 100 | jq -r '.Data.Domain[].DomainName' || true
            )"
            ;;
        dns_tencent)
            _msg warn "dns type: tencent"
            _install_tencent_cli
            tccli configure set secretId "${SAVED_Tencent_SecretId:-none}" secretKey "${SAVED_Tencent_SecretKey:-none}"
            domains="$(
                tccli domain DescribeDomainNameList --output json | jq -r '.DomainSet[] | .DomainName' || true
            )"
            ;;
        from_env)
            _msg warn "get domains from env file"
            source "$file"
            ;;
        *)
            _msg warn "unknown dns type: $dns_type"
            continue
            ;;
        esac

        _set_proxy on
        /usr/bin/cp -vf "$file" "${acme_home}/account.conf"
        ## single account may have multiple domains / 单个账号可能有多个域名
        for domain in ${domains}; do
            if "${acme_cmd}" list | grep -qw "$domain"; then
                ## renew cert / 续签证书
                "${acme_cmd}" --renew -d "${domain}" --reloadcmd "$run_touch_file" || true
            else
                ## create cert / 创建证书
                export Ali_Key=$SAVED_Ali_Key
                export Ali_Secret=$SAVED_Ali_Secret
                "${acme_cmd}" --issue -d "${domain}" -d "*.${domain}" --dns $dns_type --renew-hook "$run_touch_file" || true
            fi
            "${acme_cmd}" -d "${domain}" --install-cert --key-file "$acme_cert_dest/${domain}.key" --fullchain-file "$acme_cert_dest/${domain}.pem" || true
            "${acme_cmd}" -d "${domain}" --install-cert --key-file "${acme_home}/dest/${domain}.key" --fullchain-file "${acme_home}/dest/${domain}.pem" || true
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
    _set_proxy off
    _msg time "[cert] renew cert with acme.sh using dns+api"

    if ${github_action:-false}; then
        return 0
    fi
    if ${exec_single_job:-false}; then
        exit 0
    fi
}

_get_balance_aliyun() {
    ${github_action:-false} && return 0
    _msg step "[balance] check balance of aliyun"
    for p in "${ENV_ALARM_ALIYUN_PROFILE[@]}"; do
        local amount
        amount="$(aliyun -p "$p" bssopenapi QueryAccountBalance 2>/dev/null | jq -r .Data.AvailableAmount | sed 's/,//')"
        [[ -z "$amount" ]] && continue
        _msg red "Current balance: $amount"
        if [[ $(echo "$amount < ${ENV_ALARM_ALIYUN_BALANCE:-3000}" | bc) -eq 1 ]]; then
            msg_body="Aliyun account: $p, 余额: $amount 过低需要充值"
            _notify_wechat_work $ENV_ALARM_WECHAT_KEY
        fi
        ## daily / 查询日账单
        daily_cash_amount=$(
            aliyun -p "$p" bssopenapi QueryAccountBill --BillingCycle "$(date +%Y-%m -d yesterday)" --BillingDate "$(date +%F -d yesterday)" --Granularity DAILY |
                jq -r '.Data.Items.Item[].CashAmount' | sed 's/,//'
        )
        _msg red "yesterday daily cash amount: $daily_cash_amount"
        if [[ $(echo "$daily_cash_amount > ${ENV_ALARM_ALIYUN_DAILY:-115}" | bc) -eq 1 ]]; then
            msg_body="Aliyun account: $p, 昨日消费金额: $daily_cash_amount 偏离告警金额：${ENV_ALARM_ALIYUN_DAILY:-115}"
            _notify_wechat_work $ENV_ALARM_WECHAT_KEY
        fi
    done
    echo
    _msg time "[balance] check balance of aliyun"
    if [[ "${MAN_RENEW_CERT:-false}" == true ]] || ${arg_renew_cert:-false}; then
        return 0
    fi
    if ${exec_single_job:-false}; then
        exit 0
    fi
}

_install_python_gitlab() {
    command -v gitlab >/dev/null && return
    _msg green "installing python3 gitlab api..."
    _set_mirror python
    python3 -m pip install --user --upgrade python-gitlab
    if python3 -m pip install --user --upgrade python-gitlab; then
        _msg green "python-gitlab is installed successfully"
    else
        _msg error "failed to install python-gitlab"
    fi
}

_install_python_element() {
    python3 -m pip list 2>/dev/null | grep -q matrix-nio && return
    _msg green "installing python3 element api..."
    _set_mirror python
    if python3 -m pip install --user --upgrade matrix-nio; then
        _msg green "matrix-nio is installed successfully"
    else
        _msg error "failed to install matrix-nio"
    fi
}

_install_flarectl() {
    command -v flarectl >/dev/null && return
    _msg green "installing flarectl"
    local ver='0.68.0'
    local url="https://github.com/cloudflare/cloudflare-go/releases/download/v${ver}/flarectl_${ver}_linux_amd64.tar.xz"

    if curl -fsSLo /tmp/flarectl.tar.xz $url; then
        #  | tar xJf - -C "/tmp/" flarectl
        tar -C /tmp -xJf /tmp/flarectl.tar.xz flarectl
        $use_sudo install -m 0755 /tmp/flarectl "${me_path_data_bin}/flarectl"
        _msg success "flarectl installed successfully"
    else
        _msg error "failed to download and install flarectl"
        return 1
    fi
}

_install_aliyun_cli() {
    command -v aliyun >/dev/null && return
    _msg green "install aliyun cli..."
    curl -fsSLo /tmp/aliyun.tgz https://aliyuncli.alicdn.com/aliyun-cli-linux-latest-amd64.tgz
    tar -C /tmp -zxf /tmp/aliyun.tgz
    $use_sudo install -m 0755 /tmp/aliyun "${me_path_data_bin}/aliyun"
}

_install_tencent_cli() {
    command -v tccli >/dev/null && return
    _msg green "install tencent cli..."
    python3 -m pip install tccli
}

_install_jq_cli() {
    command -v jq >/dev/null && return
    _msg green "install jq cli..."
    case "$os_type" in
    debian | ubuntu | linuxmint)
        $use_sudo apt-get update -qq
        $use_sudo apt-get install -yqq jq >/dev/null
        ;;
    centos | amzn | rhel | fedora)
        $use_sudo yum install -y jq >/dev/null
        ;;
    alpine)
        $use_sudo apk add --no-cache "jq" >/dev/null
        ;;
    *)
        echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2 or Arch Linux system"
        _msg error "Unsupported. exit."
        return 1
        ;;
    esac
}

_install_terraform() {
    command -v terraform >/dev/null && return
    _msg green "installing terraform..."
    $use_sudo apt-get update -qq && $use_sudo apt-get install -yqq gnupg software-properties-common curl
    curl -fsSL https://apt.releases.hashicorp.com/gpg |
        gpg --dearmor |
        $use_sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null 2>&1
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" |
        $use_sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null 2>&1
    $use_sudo apt-get update -qq
    $use_sudo apt-get install -yqq terraform >/dev/null
    # terraform version
    _msg green "terraform installed successfully!"
}

_install_aws() {
    command -v aws >/dev/null && return
    _msg green "installing aws cli..."
    curl -fsSLo "/tmp/awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    unzip -qq /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install --bin-dir "${me_path_data_bin}" --install-dir "${me_path_data}" --update
    rm -rf /tmp/aws
    ## install eksctl / 安装 eksctl
    curl -fsSL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    $use_sudo install -m 0755 /tmp/eksctl /usr/local/bin/
}

_install_kubectl() {
    command -v kubectl >/dev/null && return
    _msg green "installing kubectl..."
    local kver
    kver="$(curl -sL https://dl.k8s.io/release/stable.txt)"
    curl -fsSLO "https://dl.k8s.io/release/${kver}/bin/linux/amd64/kubectl"
    curl -fsSLO "https://dl.k8s.io/${kver}/bin/linux/amd64/kubectl.sha256"
    if echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check; then
        $use_sudo install -m 0755 kubectl "${me_path_data_bin}"/kubectl
        rm -f kubectl kubectl.sha256
    else
        _msg error "failed to install kubectl"
        return 1
    fi
}

_install_helm() {
    command -v helm >/dev/null && return
    _msg green "installing helm..."
    curl -fsSLo get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
    export HELM_INSTALL_DIR="${me_path_data_bin}"
    bash get_helm.sh
    rm -f get_helm.sh
}

_install_jmeter() {
    command -v jmeter >/dev/null && return
    _msg green "install jmeter..."
    local ver_jmeter='5.4.1'
    local path_temp
    path_temp=$(mktemp -d)

    ## 6. Asia, 31. Hong_Kong, 70. Shanghai
    if ! command -v java >/dev/null; then
        export DEBIAN_FRONTEND=noninteractive
        export DEBCONF_NONINTERACTIVE_SEEN=true
        export TIME_ZOME=Asia/Shanghai
        truncate -s0 /tmp/preseed.cfg
        echo "tzdata tzdata/Areas select Asia" >>/tmp/preseed.cfg
        echo "tzdata tzdata/Zones/Asia select Shanghai" >>/tmp/preseed.cfg
        debconf-set-selections /tmp/preseed.cfg
        rm -f /etc/timezone /etc/localtime
        $use_sudo apt-get update -yqq
        $use_sudo apt-get install -yqq tzdata
        rm -rf /tmp/preseed.cfg
        unset DEBIAN_FRONTEND DEBCONF_NONINTERACTIVE_SEEN TIME_ZOME
        ## install jdk
        $use_sudo apt-get install -yqq openjdk-17-jdk
    fi
    url_jmeter="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${ver_jmeter}.zip"
    curl --retry -C - -Lo "$path_temp"/jmeter.zip $url_jmeter
    (
        cd "$me_path_data"
        unzip -q "$path_temp"/jmeter.zip
        ln -sf apache-jmeter-${ver_jmeter} jmeter
    )
    rm -rf "$path_temp"
}

_install_docker() {
    command -v docker &>/dev/null && return
    _msg green "installing docker"
    local bash_temp
    bash_temp=$(mktemp)
    curl -fsSLo $bash_temp https://get.docker.com
    if _is_china; then
        $use_sudo bash $bash_temp --mirror Aliyun
    else
        $use_sudo bash $bash_temp
    fi
    rm -f $bash_temp
}

_install_podman() {
    command -v podman &>/dev/null && return
    _msg green "installing podman"
    $use_sudo apt-get update -qq
    $use_sudo apt-get install -yqq podman >/dev/null
}

_install_cron() {
    command -v crontab &>/dev/null && return
    _msg green "installing cron"
    $use_sudo apt-get update -qq
    $use_sudo apt-get install -yqq cron >/dev/null
}

_is_china() {
    if ${ENV_IN_CHINA:-false} || ${CHANGE_SOURCE:-false} || grep -q 'ENV_IN_CHINA=true' $me_env; then
        return 0
    else
        return 1
    fi
}

_set_mirror() {
    if ${set_in_china:-false}; then
        sed -i -e '/ENV_IN_CHINA=/s/false/true/' $me_env
    fi
    if _is_china; then
        url_deploy_raw=https://gitee.com/xiagw/deploy.sh/raw/main
    else
        url_deploy_raw=https://github.com/xiagw/deploy.sh/raw/main
        return
    fi
    case ${1:-none} in
    os)
        ## OS ubuntu:22.04 php
        if [ -f /etc/apt/sources.list ]; then
            $use_sudo sed -i -e 's/deb.debian.org/mirrors.ustc.edu.cn/g' \
                -e 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
        ## OS Debian
        elif [ -f /etc/apt/sources.list.d/debian.sources ]; then
            $use_sudo sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources
        ## OS alpine, nginx:alpine
        elif [ -f /etc/apk/repositories ]; then
            # sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories
            $use_sudo sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
        fi
        ;;
    maven)
        local m2_dir=/root/.m2
        [ -d $m2_dir ] || mkdir -p $m2_dir
        ## 项目内自带 settings.xml docs/settings.xml
        if [ -f settings.xml ]; then
            cp -vf settings.xml $m2_dir/
        elif [ -f docs/settings.xml ]; then
            cp -vf docs/settings.xml $m2_dir/
        elif [ -f /opt/settings.xml ]; then
            mv -vf /opt/settings.xml $m2_dir/
        else
            curl -Lo $m2_dir/settings.xml $url_deploy_raw/conf/dockerfile/root/opt/settings.xml
        fi
        ;;
    composer)
        _is_root || return
        composer config -g repo.packagist composer https://mirrors.aliyun.com/composer/
        mkdir -p /var/www/.composer /.composer
        chown -R 1000:1000 /var/www/.composer /.composer /tmp/cache /tmp/config.json /tmp/auth.json
        ;;
    node)
        # npm_mirror=https://mirrors.ustc.edu.cn/node/
        # npm_mirror=http://mirrors.cloud.tencent.com/npm/
        # npm_mirror=https://mirrors.huaweicloud.com/repository/npm/
        npm_mirror=https://registry.npmmirror.com/
        yarn config set registry $npm_mirror
        npm config set registry $npm_mirror
        ;;
    python)
        pip_mirror=https://pypi.tuna.tsinghua.edu.cn/simple
        python3 -m pip config set global.index-url $pip_mirror
        ;;
    *)
        echo "Nothing to do."
        ;;
    esac
}

_detect_os() {
    _is_root || use_sudo=sudo
    if [[ -e /etc/os-release ]]; then
        source /etc/os-release
        os_type="${ID}"
    elif [[ -e /etc/centos-release ]]; then
        os_type=centos
    elif [[ -e /etc/arch-release ]]; then
        os_type=arch
    elif [[ $OSTYPE == darwin* ]]; then
        os_type=macos
    fi
    pkgs=()
    case "$os_type" in
    debian | ubuntu | linuxmint)
        # RUN apt-get update && \
        #        apt-get -y install sudo dialog apt-utils
        # RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
        export DEBIAN_FRONTEND=noninteractive
        ## fix gitlab-runner exit error / 修复 gitlab-runner 退出错误
        [[ -f "$HOME"/.bash_logout ]] && mv -f "$HOME"/.bash_logout "$HOME"/.bash_logout.bak
        command -v git >/dev/null || pkgs+=(git)
        git lfs version >/dev/null 2>&1 || pkgs+=(git-lfs)
        command -v curl >/dev/null || pkgs+=(curl)
        command -v unzip >/dev/null || pkgs+=(unzip)
        command -v rsync >/dev/null || pkgs+=(rsync)
        command -v pip3 >/dev/null || pkgs+=(python3-pip)
        # command -v shc >/dev/null || $use_sudo apt-get install -qq -y shc

        if [[ "${#pkgs[*]}" -ne 0 ]]; then
            _set_mirror os
            $use_sudo apt-get update -qq
            $use_sudo apt-get install -yqq apt-utils >/dev/null
            $use_sudo apt-get install -yqq "${pkgs[@]}" >/dev/null
        fi
        ;;
    centos | amzn | rhel | fedora)
        rpm -q epel-release >/dev/null || {
            if [ "$os_type" = amzn ]; then
                $use_sudo amazon-linux-extras install -y epel >/dev/null
            else
                $use_sudo yum install -y epel-release >/dev/null
                # DNF="dnf --setopt=tsflags=nodocs -y"
                # $DNF install epel-release
            fi
        }
        command -v git >/dev/null || pkgs+=(git2u)
        git lfs version >/dev/null 2>&1 || pkgs+=(git-lfs)
        command -v curl >/dev/null || pkgs+=(curl)
        command -v unzip >/dev/null || pkgs+=(unzip)
        command -v rsync >/dev/null || pkgs+=(rsync)
        if [[ "${#pkgs[*]}" -ne 0 ]]; then
            _set_mirror os
            $use_sudo yum install -y "${pkgs[@]}" >/dev/null
        fi
        ;;
    alpine)
        command -v openssl >/dev/null || pkgs+=(openssl)
        command -v git >/dev/null || pkgs+=(git)
        git lfs version >/dev/null 2>&1 || pkgs+=(git-lfs)
        command -v curl >/dev/null || pkgs+=(curl)
        command -v unzip >/dev/null || pkgs+=(unzip)
        command -v rsync >/dev/null || pkgs+=(rsync)
        if [[ "${#pkgs[*]}" -ne 0 ]]; then
            _set_mirror os
            $use_sudo apk add --no-cache "${pkgs[@]}" >/dev/null
        fi
        ;;
    macos)
        command -v openssl >/dev/null || pkgs+=(openssl)
        command -v git >/dev/null || pkgs+=(git)
        git lfs version >/dev/null 2>&1 || pkgs+=(git-lfs)
        command -v curl >/dev/null || pkgs+=(curl)
        command -v unzip >/dev/null || pkgs+=(unzip)
        command -v rsync >/dev/null || pkgs+=(rsync)
        if (("${#pkgs[*]}")); then
            _set_mirror os
            brew install "${pkgs[@]}"
        fi
        ;;
    *)
        echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2 or Arch Linux system"
        _msg error "Unsupported. exit."
        return 1
        ;;
    esac
}

_clean_disk() {
    # Check disk usage and exit if below the threshold
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print int($5)}')
    local clean_disk_threshold=${ENV_CLEAN_DISK:-80}
    if ((disk_usage < clean_disk_threshold)); then
        return 0
    fi

    # Log disk usage and clean up images
    _msg "$(df /)"
    _msg warning "Disk space is less than ${clean_disk_threshold}%, removing images..."
    $build_cmd images "${ENV_DOCKER_REGISTRY}" | awk 'NR>1 {print $1":"$2}' | xargs -t -r $build_cmd rmi >/dev/null || true
    $build_cmd system prune -f >/dev/null || true
}

# https://github.com/sherpya/geolite2legacy
# https://www.miyuru.lk/geoiplegacy
# https://github.com/leev/ngx_http_geoip2_module
_get_maxmind_ip() {
    tmp_dir="$(mktemp -d)"
    tmp_country="$tmp_dir/maxmind-Country.dat"
    tmp_city="$tmp_dir/maxmind-City.dat"
    curl -LqsSf https://dl.miyuru.lk/geoip/maxmind/country/maxmind.dat.gz | gunzip -c >"$tmp_country"
    curl -LqsSf https://dl.miyuru.lk/geoip/maxmind/city/maxmind.dat.gz | gunzip -c >"$tmp_city"
    if [[ -z "${ENV_NGINX_IPS}" ]]; then
        _msg error "ENV_NGINX_IPS is not defined or is empty"
        return 1
    fi
    for ip in ${ENV_NGINX_IPS}; do
        echo "$ip"
        rsync -av "${tmp_dir}/" "root@$ip":/etc/nginx/conf.d/
    done
    rm -rf "$tmp_dir"
}

_generate_apidoc() {
    if [[ -f "${gitlab_project_dir}/apidoc.json" ]]; then
        _msg step "[apidoc] generate API Docs with apidoc"
        $run_cmd -v "${gitlab_project_dir}":/app -w /app deploy/node bash -c "apidoc -i app/ -o public/apidoc/"
    fi
}

_inject_files() {
    _msg step "[inject] from ${me_path_data}/inject/"
    ## backend (PHP/Java/Python) inject files
    ## 方便运维人员替换项目内文件，例如 PHP 数据库配置等信息 .env 文件，例如 Java 数据库配置信息 yml 文件
    local inject_dir="${me_path_data}/inject/${gitlab_project_name}"
    local inject_dir_env="${me_path_data}/inject/${gitlab_project_name}/${env_namespace}"
    if [ -d "$inject_dir_env" ]; then
        _msg warning "found $inject_dir_env, sync to ${gitlab_project_dir}/"
        rsync -av "$inject_dir_env"/ "${gitlab_project_dir}"/
    elif [ -d "$inject_dir" ]; then
        _msg warning "found $inject_dir, sync to ${gitlab_project_dir}/"
        rsync -av "$inject_dir"/ "${gitlab_project_dir}"/
    fi

    ## frontend (VUE) .env file
    if [[ "$project_lang" == node ]]; then
        config_env_path="$(find "${gitlab_project_dir}" -maxdepth 2 -name "${env_namespace}-*")"
        for file in $config_env_path; do
            [[ -f "$file" ]] || continue
            echo "Found $file"
            if [[ "$file" =~ 'config' ]]; then
                cp -avf "$file" "${file/${env_namespace}./}" # vue2.x
            else
                cp -avf "$file" "${file/${env_namespace}/}" # vue3.x
            fi
        done
    fi

    ## from data/deploy.env， 使用 data/ 全局模板文件替换项目文件
    ${arg_disable_inject:-false} && ENV_INJECT=keep
    echo ENV_INJECT: ${ENV_INJECT:-keep}
    build_arg="${build_arg:+"$build_arg "}--build-arg IN_CHINA=${ENV_IN_CHINA:-false}"
    project_dockerfile="${gitlab_project_dir}/Dockerfile"
    local repository_cn=registry-vpc.cn-hangzhou.aliyuncs.com/flyh5/flyh5
    case ${ENV_INJECT:-keep} in
    keep)
        echo '<skip>'
        ;;
    overwrite)
        if [[ -f "${project_dockerfile}" ]]; then
            echo "skip cp Dockerfile."
        else
            ## Dockerfile 优先查找 data/ 目录
            if [[ -f "${me_data_dockerfile}/Dockerfile.${project_lang}" ]]; then
                cp -avf "${me_data_dockerfile}/Dockerfile.${project_lang}" "${project_dockerfile}"
            ## Dockerfile 其次查找 conf/ 目录
            elif [[ -f "${me_dockerfile}/Dockerfile.${project_lang}" ]]; then
                cp -avf "${me_dockerfile}/Dockerfile.${project_lang}" "${project_dockerfile}"
            fi
        fi

        if [ -d "${gitlab_project_dir}/root/opt" ]; then
            echo "found exist ${gitlab_project_dir}/root/opt"
        else
            cp -af "${me_dockerfile}/root" "$gitlab_project_dir/"
        fi

        ## inject files for build container image
        if [[ -f "${me_data_dockerfile}"/init.sh && -d "$gitlab_project_dir/root/opt/" ]]; then
            cp -avf "${me_data_dockerfile}"/init.sh "$gitlab_project_dir/root/opt/"
        fi

        case "${project_lang}" in
        node) : ;;
        java)
            ## java settings.xml 优先查找 data/ 目录
            if [[ -f "${me_data_dockerfile}/settings.xml" ]]; then
                cp -avf "${me_data_dockerfile}/settings.xml" "${gitlab_project_dir}/"
            elif _is_china; then
                cp -avf "${me_dockerfile}/root/opt/settings.xml" "${gitlab_project_dir}/"
            fi
            ## find jdk version
            for f in "${gitlab_project_dir}"/{README,readme}.{md,txt}; do
                [ -f "$f" ] || continue
                case "$(grep -i 'jdk_version=' "${f}")" in
                *=1.7 | *=7)
                    sed -i -e "s@IMAGE_MVN=.*@IMAGE_MVN=${repository_cn}:maven-3.6-jdk-7@g" -e "s@IMAGE_JDK=.*@IMAGE_JDK=${repository_cn}:openjdk-7@g" "${project_dockerfile}"
                    ;;
                *=1.8 | *=8)
                    sed -i -e "s@IMAGE_MVN=.*@IMAGE_MVN=${repository_cn}:maven-3.8-jdk-8@g" -e "s@IMAGE_JDK=.*@IMAGE_JDK=${repository_cn}:openjdk-8@g" "${project_dockerfile}"
                    ;;
                *=11)
                    sed -i -e "s@IMAGE_MVN=.*@IMAGE_MVN=${repository_cn}:maven-3.8-jdk-11@g" -e "s@IMAGE_JDK=.*@IMAGE_JDK=${repository_cn}:amazoncorretto-11@g" "${project_dockerfile}"
                    ;;
                *=17)
                    sed -i -e "s@IMAGE_MVN=.*@IMAGE_MVN=${repository_cn}:maven-3.8-jdk-17@g" -e "s@IMAGE_JDK=.*@IMAGE_JDK=${repository_cn}:amazoncorretto-17@g" "${project_dockerfile}"
                    ;;
                *) : ;;
                esac
                case "$(grep -i 'INSTALL_.*=' "${f}")" in
                INSTALL_FFMPEG=true)
                    sed -i -e "s/INSTALL_FFMPEG=false/INSTALL_FFMPEG=true/g" "${project_dockerfile}"
                    ;;
                INSTALL_FONTS=true)
                    sed -i -e "s/INSTALL_FONTS=false/INSTALL_FONTS=true/g" "${project_dockerfile}"
                    ;;
                INSTALL_LIBREOFFICE=true)
                    sed -i -e "s/INSTALL_LIBREOFFICE=false/INSTALL_LIBREOFFICE=true/g" "${project_dockerfile}"
                    ;;
                *) : ;;
                esac
                break
            done
            ;;
        esac
        ;;
    remove)
        echo 'Removing Dockerfile (disable docker build)'
        rm -f "${project_dockerfile}"
        ;;
    create)
        echo "Generating docker-compose.yml (enable deploy docker-compose)"
        echo '## deploy with docker-compose' >>"${gitlab_project_dir}/docker-compose.yml"
        ;;
    esac
    ## docker ignore file / 使用全局模板文件替换项目文件
    if [[ -f "${project_dockerfile}" && ! -f "${gitlab_project_dir}/.dockerignore" ]]; then
        cp -avf "${me_dockerfile}/.dockerignore" "${gitlab_project_dir}/"
    fi

    ## flyway files sql & conf
    for sql in ${ENV_FLYWAY_SQL:-docs/sql} flyway_sql doc/sql sql; do
        path_flyway_sql_proj="${gitlab_project_dir}/${sql}"
        if [[ -d "${path_flyway_sql_proj}" ]]; then
            exec_deploy_flyway=true
            copy_flyway_file=true
            break
        fi
    done

    if ${copy_flyway_file:-false}; then
        path_flyway_conf="$gitlab_project_dir/flyway_conf"
        path_flyway_sql="$gitlab_project_dir/flyway_sql"
        [[ -d "$path_flyway_sql_proj" && ! -d "$path_flyway_sql" ]] && rsync -a "$path_flyway_sql_proj/" "$path_flyway_sql/"
        [[ -d "$path_flyway_conf" ]] || mkdir -p "$path_flyway_conf"
        [[ -d "$path_flyway_sql" ]] || mkdir -p "$path_flyway_sql"
        [[ -f "${gitlab_project_dir}/Dockerfile.flyway" ]] || cp -avf "${me_dockerfile}/Dockerfile.flyway" "${gitlab_project_dir}/"
    fi
}

_set_deploy_conf() {
    local path_conf_ssh="${me_path_data}/.ssh"
    local path_conf_acme="${me_path_data}/.acme.sh"
    local path_conf_aws="${me_path_data}/.aws"
    local path_conf_kube="${me_path_data}/.kube"
    local path_conf_aliyun="${me_path_data}/.aliyun"
    local file_python_gitlab="${me_path_data}/.python-gitlab.cfg"
    ## ssh config and key files
    if [[ ! -d "${path_conf_ssh}" ]]; then
        mkdir -m 700 "$path_conf_ssh"
        _msg warn "Generate ssh key file for gitlab-runner: $path_conf_ssh/id_ed25519"
        _msg purple "Please: cat $path_conf_ssh/id_ed25519.pub >> [dest_server]:\~/.ssh/authorized_keys"
        ssh-keygen -t ed25519 -N '' -f "$path_conf_ssh/id_ed25519"
    fi
    [ -d "$HOME"/.ssh ] || mkdir -m 700 "$HOME"/.ssh
    for file in "$path_conf_ssh"/*; do
        [ -f "$HOME/.ssh/$(basename "${file}")" ] && continue
        echo "Link $file to $HOME/.ssh/"
        chmod 600 "${file}"
        ln -s "${file}" "$HOME/.ssh/"
    done
    ## acme.sh/aws/kube/aliyun/python-gitlab
    [[ ! -d "${HOME}/.acme.sh" && -d "${path_conf_acme}" ]] && ln -sf "${path_conf_acme}" "$HOME/"
    [[ ! -d "${HOME}/.aws" && -d "${path_conf_aws}" ]] && ln -sf "${path_conf_aws}" "$HOME/"
    [[ ! -d "${HOME}/.kube" && -d "${path_conf_kube}" ]] && ln -sf "${path_conf_kube}" "$HOME/"
    [[ ! -d "${HOME}/.aliyun" && -d "${path_conf_aliyun}" ]] && ln -sf "${path_conf_aliyun}" "$HOME/"
    [[ ! -f "${HOME}/.python-gitlab.cfg" && -f "${file_python_gitlab}" ]] && ln -sf "${file_python_gitlab}" "$HOME/"
    return 0
}

_setup_gitlab_vars() {
    gitlab_project_dir=${CI_PROJECT_DIR:-$PWD}
    gitlab_project_name=${CI_PROJECT_NAME:-${gitlab_project_dir##*/}}
    # read -rp "Enter gitlab project namespace: " -e -i 'root' gitlab_project_namespace
    gitlab_project_namespace=${CI_PROJECT_NAMESPACE:-root}
    # read -rp "Enter gitlab project path: [root/git-repo] " -e -i 'root/xxx' gitlab_project_path
    gitlab_project_path=${CI_PROJECT_PATH:-$gitlab_project_namespace/$gitlab_project_name}
    gitlab_project_path_slug=${CI_PROJECT_PATH_SLUG:-${gitlab_project_path//[.\/]/-}}
    # read -t 5 -rp "Enter branch name: " -e -i 'develop' gitlab_project_branch
    gitlab_project_branch=${CI_COMMIT_REF_NAME:-$(if [ -d .git ]; then git rev-parse --abbrev-ref HEAD; else echo dev; fi)}
    gitlab_project_branch=${gitlab_project_branch:-develop}
    [[ "${gitlab_project_branch}" == HEAD ]] && gitlab_project_branch=main
    gitlab_commit_short_sha=${CI_COMMIT_SHORT_SHA:-$(if [ -d .git ]; then git rev-parse --short HEAD; else echo 1234567; fi)}
    if [[ -z "$gitlab_commit_short_sha" ]]; then
        _msg warn "WARN: \"\$gitlab_commit_short_sha\" set to \"1234567\""
        gitlab_commit_short_sha=1234567
    fi
    # read -rp "Enter gitlab project id: " -e -i '1234' gitlab_project_id
    gitlab_project_id=${CI_PROJECT_ID:-1234}
    # read -t 5 -rp "Enter gitlab pipeline id: " -e -i '3456' gitlab_pipeline_id
    gitlab_pipeline_id=${CI_PIPELINE_ID:-3456}
    # read -rp "Enter gitlab job id: " -e -i '5678' gitlab_job_id
    gitlab_job_id=${CI_JOB_ID:-5678}
    # read -rp "Enter gitlab user id: " -e -i '1' gitlab_user_id
    gitlab_user_id=${GITLAB_USER_ID:-1}
    gitlab_username="${GITLAB_USER_LOGIN:-unknown}"
    env_namespace=$gitlab_project_branch

    if ${run_with_crontab:-false}; then
        cron_save_file="$(find "${me_path_data}" -name "crontab.${gitlab_project_id}.*" -print -quit)"
        if [[ -n "$cron_save_file" ]]; then
            cron_save_id="${cron_save_file##*.}"
            if [[ "${gitlab_commit_short_sha}" == "$cron_save_id" ]]; then
                _msg warn "no code change found, <skip>."
                exit 0
            else
                rm -f "${me_path_data}/crontab.${gitlab_project_id}".*
                touch "${me_path_data}/crontab.${gitlab_project_id}.${gitlab_commit_short_sha}"
            fi
        fi
    fi
}

_probe_langs() {
    _msg step "[language] probe program language"
    for f in pom.xml {composer,package}.json requirements*.txt {README,readme}.{md,txt}; do
        [[ -f "${gitlab_project_dir}"/${f} ]] || continue
        echo "Found $f"
        case $f in
        composer.json)
            project_lang=php
            break
            ;;
        package.json)
            project_lang=node
            break
            ;;
        pom.xml)
            project_lang=java
            build_arg="${build_arg:+"$build_arg "}--build-arg MVN_PROFILE=${gitlab_project_branch}"
            if ${debug_on:-false}; then
                build_arg="${build_arg:+"$build_arg "}--build-arg MVN_DEBUG=on"
            fi
            break
            ;;
        requirements*.txt)
            project_lang=python
            break
            ;;
        *)
            project_lang=${project_lang:-$(awk -F= '/^project_lang/ {print $2}' "${gitlab_project_dir}/${f}" | tail -n 1)}
            project_lang=${project_lang// /}
            project_lang=${project_lang,,}
            ;;
        esac
    done
    project_lang=${project_lang:-unknown}
    echo "Probe program language: ${project_lang}"
}

_probe_deploy_method() {
    _msg step "[probe] deploy method"
    local deploy_method=rsync
    for f in Dockerfile* docker-compose.yml; do
        [[ -f "${gitlab_project_dir}"/${f} ]] || continue
        echo "Found $f"
        case $f in
        docker-compose.yml)
            exec_deploy_docker_compose=true
            deploy_method=docker-compose
            ;;
        Dockerfile*)
            exec_build_image=true
            exec_push_image=true
            exec_deploy_k8s=true
            exec_build_langs=false
            exec_deploy_rsync_ssh=false
            deploy_method=helm
            ;;
        esac
    done
    echo "deploy method: $deploy_method"
}

_checkout_svn_repo() {
    ${checkout_with_svn:-false} || return 0
    if [[ ! -d "$me_path_builds" ]]; then
        echo "Not found $me_path_builds, create it..."
        mkdir -p "$me_path_builds"
    fi
    local svn_repo_name
    svn_repo_name=$(echo "$svn_url" | awk -F '/' '{print $NF}')
    local svn_repo_dir="${me_path_builds}/${svn_repo_name}"
    if [ -d "$svn_repo_dir" ]; then
        echo "\"$svn_repo_dir\" exists"
        cd "$svn_repo_dir" && svn update
    else
        echo "checkout svn repo: $svn_url"
        svn checkout "$svn_url" "$svn_repo_dir" || {
            echo "Failed to checkout svn repo: $svn_url"
            exit 1
        }
    fi
}

_clone_git_repo() {
    ${arg_git_clone:-false} || return 0
    if [[ ! -d "$me_path_builds" ]]; then
        echo "Not found $me_path_builds, create it..."
        mkdir -p "$me_path_builds"
    fi
    local git_repo_name
    git_repo_name=$(echo "$arg_git_clone_url" | awk -F '/' '{print $NF}')
    local git_repo_dir="${me_path_builds}/${git_repo_name%.git}"
    if [ -d "$git_repo_dir" ]; then
        echo "\"$git_repo_dir\" exists"
        cd "$git_repo_dir"
        if [[ -n "$arg_git_clone_branch" ]]; then
            git checkout --quiet "$arg_git_clone_branch" || {
                echo "Failed to checkout $arg_git_clone_branch"
                exit 1
            }
        fi
    else
        echo "Clone git repo: $arg_git_clone_url"
        git clone --quiet -b "$arg_git_clone_branch" "$arg_git_clone_url" "$git_repo_dir" || {
            echo "Failed to clone git repo: $arg_git_clone_url"
            exit 1
        }
    fi
}

_create_k8s() {
    ${create_k8s_with_terraform:-false} || return 0
    local terraform_dir="$me_path_data/terraform"
    if [ ! -d "$terraform_dir" ]; then
        return 0
    fi
    _msg step "[PaaS] create k8s cluster"
    cd "$terraform_dir" || return 1
    if terraform init; then
        terraform apply -auto-approve
    else
        _msg error "Terraform init failed"
        exit $?
    fi
}

_usage() {
    echo "
Usage: $0 [parameters ...]

Parameters:
    -h, --help               Show this help message.
    -v, --version            Show version info.
    -r, --renew-cert         Renew all the certs.
    --get-balance            get balance from aliyun.
    --code-style             Check code style.
    --code-quality           Check code quality.
    --build-langs            Build all the languages.
    --build-docker           Build image with docker.
    --build-podman           Build image with podman.
    --push-image             Push image with docker.
    --deploy-k8s             Deploy to kubernetes.
    --deploy-flyway          Deploy database with flyway.
    --deploy-rsync-ssh       Deploy to rsync with ssh.
    --deploy-rsync           Deploy to rsync server.
    --deploy-ftp             Deploy to ftp server.
    --deploy-sftp            Deploy to sftp server.
    --test-unit              Run unit tests.
    --test-function          Run function tests.
    --debug                  Run with debug.
    --cron                   Run on crontab.
    --create-k8s             Create k8s with terraform.
    --git-clone https://xxx.com/yyy/zzz.git      Clone git repo url, clone to builds/zzz.git
    --git-clone-branch [dev|main] default \"main\"      git branch name
"
}

_set_args() {
    ## All tasks are performed by default / 默认执行所有任务
    ## if you want to exec some tasks, use --task1 --task2 / 如果需要执行某些任务，使用 --task1 --task2， 适用于单独的 gitlab job，（一个 pipeline 多个独立的 job）
    [[ ${CI_DEBUG_TRACE:-false} == true ]] && debug_on=true
    build_cmd=$(command -v podman || command -v docker || echo docker)
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --debug | -d)
            set -x
            debug_on=true
            ;;
        --cron | --loop)
            run_with_crontab=true
            ;;
        --create-k8s)
            create_k8s_with_terraform=true
            ;;
        --github-action)
            set -x
            debug_on=true
            github_action=true
            ;;
        --in-china)
            set_in_china=true
            ;;
        --svn-checkout)
            checkout_with_svn=true
            svn_url="${2:?empty svn url}"
            shift
            ;;
        --git-clone)
            arg_git_clone=true
            arg_git_clone_url="${2:?empty git clone url}"
            shift
            ;;
        --git-clone-branch)
            arg_git_clone_branch="${2:?empty git clone branch}"
            shift
            ;;
        --get-balance)
            arg_get_balance=true
            exec_single_job=true
            ;;
        --disable-inject)
            arg_disable_inject=true
            ;;
        --renew-cert | -r)
            arg_renew_cert=true
            exec_single_job=true
            ;;
        --code-style)
            arg_code_style=true
            exec_single_job=true
            ;;
        --code-quality)
            arg_code_quality=true
            exec_single_job=true
            ;;
        --build-langs)
            arg_build_langs=true
            exec_single_job=true
            ;;
        --build-docker)
            arg_build_image=true
            exec_single_job=true
            build_cmd=docker
            ;;
        --build-podman)
            arg_build_image=true
            exec_single_job=true
            build_cmd=podman
            build_cmd_opt='--force-rm --format=docker'
            ;;
        --push-image)
            arg_push_image=true
            exec_single_job=true
            ;;
        --deploy-functions)
            arg_deploy_functions=true
            exec_single_job=true
            ;;
        --create-helm)
            arg_create_helm=true
            exec_single_job=true
            helm_dir="$2"
            shift
            ;;
        --deploy-k8s)
            arg_deploy_k8s=true
            exec_single_job=true
            ;;
        --deploy-flyway)
            arg_deploy_flyway=true
            exec_single_job=true
            ;;
        --deploy-rsync-ssh)
            arg_deploy_rsync_ssh=true
            exec_single_job=true
            ;;
        --deploy-rsync)
            arg_deploy_rsync=true
            exec_single_job=true
            ;;
        --deploy-ftp)
            arg_deploy_ftp=true
            exec_single_job=true
            ;;
        --deploy-sftp)
            arg_deploy_sftp=true
            exec_single_job=true
            ;;
        --test-unit)
            arg_test_unit=true
            exec_single_job=true
            ;;
        --test-function)
            arg_test_function=true
            exec_single_job=true
            ;;
        *)
            _usage
            exit 1
            ;;
        esac
        shift
    done
    if ${debug_on:-false}; then
        unset quiet_flag
    else
        quiet_flag='--quiet'
    fi
}

main() {
    set -e ## 出现错误自动退出
    # set -u ## 变量未定义报错 # set -Eeuo pipefail
    SECONDS=0
    _msg step "[deploy] BEGIN"
    ## Process parameters / 处理传入的参数
    _set_args "$@"

    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_path_conf="${me_path}/conf"
    me_path_bin="${me_path}/bin"
    me_path_data="${me_path}/data" ## deploy.sh data folder
    me_path_data_bin="${me_path}/data/bin"
    me_path_builds="${me_path}/builds"
    me_log="${me_path_data}/${me_name}.log"
    me_conf="${me_path_data}/deploy.json"           ## deploy to app server 发布到目标服务器的配置信息
    me_env="${me_path_data}/deploy.env"             ## deploy.sh ENV 发布配置信息(密)
    me_dockerfile="${me_path_conf}/dockerfile"      ## deploy.sh dependent dockerfile
    me_data_dockerfile="${me_path_data}/dockerfile" ## deploy.sh dependent dockerfile
    ## create path data/bin  /  创建目录 data/bin
    [ -d "${me_path_data_bin}" ] || mkdir -p "${me_path_data_bin}"
    ## 准备配置文件
    [[ -f "$me_conf" ]] || cp -v "${me_path_conf}/example-deploy.json" "$me_conf"
    [[ -f "$me_env" ]] || cp -v "${me_path_conf}/example-deploy.env" "$me_env"
    ## 设定 PATH
    declare -a paths_append=(
        "/usr/local/sbin"
        "/snap/bin"
        "$me_path_bin"
        "$me_path_data_bin"
        "$HOME/.local/bin"
        "$HOME/.acme.sh"
        "$me_path_data/.acme.sh"
        "$HOME/.config/composer/vendor/bin"
    )
    for p in "${paths_append[@]}"; do
        if [[ -d "$p" && "$PATH" != *":$p:"* ]]; then
            PATH="${PATH:+"$PATH:"}$p"
        fi
    done

    export PATH

    run_cmd="$build_cmd run $ENV_ADD_HOST --interactive --rm -u $(id -u):$(id -g)"
    run_cmd_root="$build_cmd run $ENV_ADD_HOST --interactive --rm"
    if ${debug_on:-false}; then
        build_cmd_opt="${build_cmd_opt:+"$build_cmd_opt "}--progress plain $ENV_ADD_HOST $quiet_flag"
    else
        build_cmd_opt="${build_cmd_opt:+"$build_cmd_opt "}$ENV_ADD_HOST $quiet_flag"
    fi
    ## check OS version/type/install command/install software / 检查系统版本/类型/安装命令/安装软件
    _detect_os

    ## git clone repo / 克隆 git 仓库
    _clone_git_repo

    ## svn checkout repo / 克隆 svn 仓库
    _checkout_svn_repo

    ## run deploy.sh by hand / 手动执行 deploy.sh 时假定的 gitlab 配置
    _setup_gitlab_vars

    ## source ENV, get global variables / 获取 ENV_ 开头的所有全局变量
    source "$me_env"

    if [ -f "$HOME/.kube/$env_namespace/config" ]; then
        kubectl_opt="kubectl --kubeconfig $HOME/.kube/$env_namespace/config"
        helm_opt="helm --kubeconfig $HOME/.kube/$env_namespace/config"
    else
        kubectl_opt="kubectl --kubeconfig $HOME/.kube/config"
        helm_opt="helm --kubeconfig $HOME/.kube/config"
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
    ${ENV_INSTALL_DOCKER:-false} && _install_docker
    ${ENV_INSTALL_PODMAN:-false} && _install_podman
    ${ENV_INSTALL_CRON:-false} && _install_cron

    ## clean up disk space / 清理磁盘空间
    _clean_disk

    ## create k8s / 创建 kubernetes 集群
    _create_k8s

    ## setup ssh-config/acme.sh/aws/kube/aliyun/python-gitlab/cloudflare/rsync
    _set_deploy_conf

    ## get balance of aliyun / 获取 aliyun 账户现金余额
    # echo "MAN_GET_BALANCE: ${MAN_GET_BALANCE:-false}"
    if [[ "${MAN_GET_BALANCE:-false}" == true ]] || ${arg_get_balance:-false}; then
        _get_balance_aliyun
    fi

    ## renew cert with acme.sh / 使用 acme.sh 重新申请证书
    # echo "MAN_RENEW_CERT: ${MAN_RENEW_CERT:-false}"
    if [[ "${MAN_RENEW_CERT:-false}" == true ]] || ${github_action:-false} || ${arg_renew_cert:-false}; then
        exec_single_job=true
        _renew_cert
    fi

    ## probe program lang / 探测项目的程序语言
    _probe_langs

    ## preprocess project config files / 预处理业务项目配置文件，覆盖配置文件等特殊处理
    _inject_files

    ## probe deploy method / 探测文件并确定发布方式
    _probe_deploy_method

    ## code style check / 代码格式检查
    code_style_sh="$me_path_bin/style.${project_lang}.sh"

    ## code build / 代码编译打包
    build_langs_sh="$me_path_bin/build.${project_lang}.sh"

    ################################################################################
    ## exec single task / 执行单个任务，适用于 gitlab-ci/jenkins 等自动化部署工具的单个 job 任务执行
    if ${exec_single_job:-false}; then
        _msg green "exec single jobs..."
        ${arg_code_quality:-false} && _check_quality_sonar
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
        ${arg_deploy_functions:-false} && _deploy_functions_aliyun
        ${arg_create_helm:-false} && _create_helm_chart "${helm_dir}"
        ${arg_deploy_k8s:-false} && _deploy_k8s
        ${arg_deploy_rsync_ssh:-false} && _deploy_rsync_ssh
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
        _check_quality_sonar
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
    # _generate_apidoc

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
    ${exec_deploy_k8s:-false} && _deploy_k8s
    ## deploy functions aliyun
    ${exec_deploy_functions:-true} && _deploy_functions_aliyun
    ## deploy rsync server
    ${exec_deploy_rsync:-false} && _deploy_rsync
    ## deploy ftp server
    ${exec_deploy_ftp:-false} && _deploy_ftp
    ## deploy sftp server
    ${exec_deploy_sftp:-false} && _deploy_sftp
    ## deploy with rsync / 使用 rsync 发布
    ${exec_deploy_rsync_ssh:-true} && _deploy_rsync_ssh

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
        _scan_zap
    else
        echo '<skip>'
    fi

    _msg step "[security] vulmap scan"
    echo "MAN_SCAN_VULMAP: ${MAN_SCAN_VULMAP:-false}"
    if [[ "${MAN_SCAN_VULMAP:-false}" == true ]]; then
        _scan_vulmap
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
