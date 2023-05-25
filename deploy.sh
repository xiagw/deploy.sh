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

set -e ## 出现错误自动退出
# set -u ## 变量未定义报错

_msg() {
    local color_on
    local color_off='\033[0m' # Text Reset
    case "${1:-none}" in
    red | error | erro) color_on='\033[0;31m' ;;       # Red
    green | info) color_on='\033[0;32m' ;;             # Green
    yellow | warning | warn) color_on='\033[0;33m' ;;  # Yellow
    blue) color_on='\033[0;34m' ;;                     # Blue
    purple | question | ques) color_on='\033[0;35m' ;; # Purple
    cyan) color_on='\033[0;36m' ;;                     # Cyan
    time)
        color_on="[+] $(date +%Y%m%d-%T-%u), "
        color_off=''
        ;;
    step | timestep)
        color_on="\033[0;36m[$((${STEP:-0} + 1))] $(date +%Y%m%d-%T-%u), \033[0m"
        STEP=$((${STEP:-0} + 1))
        color_off=' ... start'
        ;;
    stepend | end)
        color_on="[+] $(date +%Y%m%d-%T-%u), "
        color_off=' ... end'
        ;;
    *)
        color_on=
        color_off=
        ;;
    esac
    if [ "$#" -gt 1 ]; then
        shift
    fi
    echo -e "${color_on}$*${color_off}"
}

## year month day - time - %u day of week (1..7); 1 is Monday - %j day of year (001..366) - %W week number of year, with Monday as first day of week (00..53)

_log() {
    echo "$(date +%Y%m%d-%T-%u), $*" | tee -a $me_log
}

## install phpunit
_test_unit() {
    _msg step "[test] unit test"
    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_UNIT_TEST ，1 启用[default]，0 禁用
    echo "PIPELINE_UNIT_TEST: ${PIPELINE_UNIT_TEST:-0}"
    if [[ "${PIPELINE_UNIT_TEST:-0}" -eq 0 ]]; then
        echo "<skip>"
        return 0
    fi

    if [[ -f "$gitlab_project_dir"/tests/unit_test.sh ]]; then
        echo "Found $gitlab_project_dir/tests/unit_test.sh"
        bash "$gitlab_project_dir"/tests/unit_test.sh
    elif [[ -f "$me_path_data"/tests/unit_test.sh ]]; then
        echo "Found $me_path_data/tests/unit_test.sh"
        bash "$me_path_data"/tests/unit_test.sh
    else
        _msg purple "not found tests/unit_test.sh, skip unit test."
    fi
    _msg stepend "[test] unit test"
}

## install jdk/ant/jmeter
_test_function() {
    _msg step "[test] function test"
    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_FUNCTION_TEST ，1 启用[default]，0 禁用
    echo "PIPELINE_FUNCTION_TEST: ${PIPELINE_FUNCTION_TEST:-1}"
    if [[ "${PIPELINE_FUNCTION_TEST:-0}" -eq 0 ]]; then
        echo "<skip>"
        return 0
    fi
    if [ -f "$gitlab_project_dir"/tests/func_test.sh ]; then
        echo "Found $gitlab_project_dir/tests/func_test.sh"
        bash "$gitlab_project_dir"/tests/func_test.sh
    elif [ -f "$me_path_data"/tests/func_test.sh ]; then
        echo "Found $me_path_data/tests/func_test.sh"
        bash "$me_path_data"/tests/func_test.sh
    else
        echo "Not found tests/func_test.sh, skip function test."
    fi
    _msg stepend "[test] function test"
}

_check_quality_sonar() {
    _msg step "[quality] check code with sonarqube"
    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_SONAR ，1 启用，0 禁用[default]
    echo "PIPELINE_SONAR: ${PIPELINE_SONAR:-0}"
    if [[ "${PIPELINE_SONAR:-0}" -eq 0 ]]; then
        echo "<skip>"
        return 0
    fi
    local sonar_url="${ENV_SONAR_URL:?empty}"
    local sonar_conf="$gitlab_project_dir/sonar-project.properties"
    if ! curl --silent --head --fail "$sonar_url" >/dev/null 2>&1; then
        _msg warning "Could not found sonarqube server, exit."
        return
    fi

    if [[ ! -f "$sonar_conf" ]]; then
        _msg info "Creating $sonar_conf"
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
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    $docker_run -e SONAR_TOKEN="${ENV_SONAR_TOKEN:?empty}" -v "$gitlab_project_dir":/usr/src sonarsource/sonar-scanner-cli
    # $docker_run -v $(pwd):/root/src --link sonarqube newtmitch/sonar-scanner
    # --add-host="sonar.entry.one:192.168.145.12"
    _msg stepend "[quality] check code with sonarqube"
    exit 0
}

_check_style() {
    _msg step "[style] check code style"
    echo "PIPELINE_CODE_STYLE: ${PIPELINE_CODE_STYLE:-0}"
    if [[ "${PIPELINE_CODE_STYLE:-0}" -eq 1 && -f "$code_style_sh" ]]; then
        source "$code_style_sh"
    else
        echo '<skip>'
    fi
}

_scan_zap() {
    _msg step "[security] run ZAP scan"
    echo "PIPELINE_SCAN_ZAP: ${PIPELINE_SCAN_ZAP:-0}"
    if [[ "${PIPELINE_SCAN_ZAP:-0}" -ne 1 ]]; then
        echo '<skip>'
        return
    fi

    local target_url="${ENV_TARGET_URL}"
    local zap_docker_image="${ENV_ZAP_IMAGE:-owasp/zap2docker-stable}"
    local zap_options="${ENV_ZAP_OPT:-"-t ${target_url} -r report.html"}"
    local zap_report_file
    zap_report_file="zap_report_$(date +%Y%m%d_%H%M%S).html"

    # docker pull "$zap_docker_image"
    docker run -t --rm -v "$(pwd):/zap/wrk" "$zap_docker_image" zap-full-scan.sh $zap_options
    if [[ $? -eq 0 ]]; then
        mv "$zap_report_file" "zap_report_latest.html"
        _msg green "ZAP scan completed. Report saved to zap_report_latest.html"
    else
        _msg error "ZAP scan failed."
    fi
    _msg stepend "[security] run ZAP scan"
}
# _security_scan_zap "http://example.com" "my/zap-image" "-t http://example.com -r report.html -x report.xml"

_scan_vulmap() {
    _msg step "[security] vulmap scan"
    echo "PIPELINE_SCAN_VULMAP: ${PIPELINE_SCAN_VULMAP:-0}"
    if [[ "${PIPELINE_SCAN_VULMAP:-0}" -ne 1 ]]; then
        echo '<skip>'
        return
    fi
    # https://github.com/zhzyker/vulmap
    # docker run --rm -ti vulmap/vulmap  python vulmap.py -u https://www.example.com
    # Load environment variables from config file
    source $me_path_data/config.cfg
    # Run vulmap scan
    docker run --rm -v "${PWD}:/work" vulmap \
        -u "${ENV_TARGET_URL}" \
        -o "/work/vulmap_report.html"

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

    docker run --rm -v "$path:/repo" -v "$config_file:/config.toml" zricethezav/gitleaks:v7.5.0 gitleaks --path=/repo --config=/config.toml
}

_deploy_flyway_docker() {
    _msg step "[database] deploy SQL files with flyway"
    echo "PIPELINE_FLYWAY: ${PIPELINE_FLYWAY:-0}"
    if [[ "${PIPELINE_FLYWAY:-0}" -ne 1 || "${exec_deploy_flyway:-0}" -ne 1 ]]; then
        echo '<skip>'
        return
    fi
    flyway_conf_volume="${gitlab_project_dir}/flyway_conf:/flyway/conf"
    flyway_sql_volume="${gitlab_project_dir}/flyway_sql:/flyway/sql"
    flyway_docker_run="docker run --rm -v ${flyway_conf_volume} -v ${flyway_sql_volume} flyway/flyway"

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
        _msg green "Result = OK"
    else
        _msg error "Result = FAIL"
    fi
    _msg stepend "[database] deploy SQL files with flyway"
}

_deploy_flyway_helm_job() {
    [[ "${ENV_FLYWAY_HELM_JOB:-0}" -ne 1 ]] && return
    _msg step "[database] deploy SQL with flyway helm job"
    echo "$image_tag_flyway"
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    DOCKER_BUILDKIT=1 docker build ${quiet_flag} --tag "${image_tag_flyway}" -f "${gitlab_project_dir}/Dockerfile.flyway" "${gitlab_project_dir}/"
    docker run --rm "$image_tag_flyway" || deploy_result=1
    if [ ${deploy_result:-0} = 0 ]; then
        _msg green "Result = OK"
    else
        _msg error "Result = FAIL"
    fi
    _msg stepend "[database] deploy SQL with flyway helm job"
}

# python-gitlab list all projects / 列出所有项目
# gitlab -v -o yaml -f path_with_namespace project list --all |awk -F': ' '{print $2}' |sort >p.txt
# 解决 Encountered 1 file(s) that should have been pointers, but weren't
# git lfs migrate import --everything$(awk '/filter=lfs/ {printf " --include='\''%s'\''", $1}' .gitattributes)

_docker_login() {
    local lock_docker_login="$me_path_data/.lock.docker.login.${ENV_DOCKER_LOGIN_TYPE:-none}"
    local time_last
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    case "${ENV_DOCKER_LOGIN_TYPE:-none}" in
    aws)
        time_last="$(stat -t -c %Y "$lock_docker_login" 2>/dev/null || echo 0)"
        ## Compare the last login time, log in again after 12 hours / 比较上一次登陆时间，超过12小时则再次登录
        if [[ "$(date +%s -d '12 hours ago')" -lt "${time_last:-0}" ]]; then
            return 0
        fi
        _msg time "[login] docker login [${ENV_DOCKER_LOGIN_TYPE:-none}]..."
        aws ecr get-login-password --profile="${ENV_AWS_PROFILE}" --region "${ENV_REGION_ID:?undefine}" | docker login --username AWS --password-stdin ${ENV_DOCKER_REGISTRY%%/*} >/dev/null
        ;;
    *)
        if [[ "${demo_mode:-0}" == 1 ]]; then
            _msg purple "demo mode, skip docker login."
            return 0
        fi
        if [[ -f "$lock_docker_login" ]]; then
            return 0
        fi
        echo "${ENV_DOCKER_PASSWORD}" | docker login --username="${ENV_DOCKER_USERNAME}" --password-stdin "${ENV_DOCKER_REGISTRY%%/*}"
        ;;
    esac
    touch "$lock_docker_login"
}

_build_image_docker() {
    _msg step "[container] build image with docker"
    _docker_login
    ## Docker build from template image / 是否从模板构建
    [[ "${github_action:-0}" -eq 1 ]] && return 0

    ## docker build flyway image / 构建 flyway 模板
    if [[ "$ENV_FLYWAY_HELM_JOB" -eq 1 ]]; then
        DOCKER_BUILDKIT=1 docker build $ENV_ADD_HOST ${quiet_flag} --tag "${image_tag_flyway}" -f "${gitlab_project_dir}/Dockerfile.flyway" "${gitlab_project_dir}/"
    fi
    ## docker build
    [ -d "${gitlab_project_dir}"/flyway_conf ] && rm -rf "${gitlab_project_dir}"/flyway_conf
    [ -d "${gitlab_project_dir}"/flyway_sql ] && rm -rf "${gitlab_project_dir}"/flyway_sql
    DOCKER_BUILDKIT=1 docker build $ENV_ADD_HOST $quiet_flag --tag "${ENV_DOCKER_REGISTRY}:${image_tag}" \
        --build-arg IN_CHINA="${ENV_IN_CHINA:-false}" \
        --build-arg USE_JEMALLOC="${USE_JEMALLOC:-false}" \
        --build-arg MVN_PROFILE="${gitlab_project_branch}" "${gitlab_project_dir}"
    ## docker push to ttl.sh
    # image_uuid="ttl.sh/$(uuidgen):1h"
    # echo "If you want to push the image to ttl.sh, please execute the following command on gitlab-runner:"
    # echo "#    docker tag ${ENV_DOCKER_REGISTRY}:${image_tag} ${image_uuid}"
    # echo "#    docker push $image_uuid"
    # echo "Then execute the following command on remote server:"
    # echo "#    docker pull $image_uuid"
    # echo "#    docker tag $image_uuid deploy/<your_app>"
    _msg stepend "[container] build image with docker"
}

_build_image_podman() {
    _msg step "[container] build image with podman"
    local image_name="$1"
    local image_tag="$2"
    local dockerfile_path="$3"
    local podman_registry="$4"

    # Build image
    podman build -f "$dockerfile_path" -t "$image_name:$image_tag" .

    # Tag image for remote registry
    podman tag "$image_name:$image_tag" "$podman_registry/$image_name:$image_tag"

    # Push image to remote registry
    podman push "$podman_registry/$image_name:$image_tag"
}

_push_image() {
    _msg step "[container] push image with docker"
    _docker_login
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    if [[ "$demo_mode" == 1 ]]; then
        _msg purple "Demo mode, skip push image."
        return 0
    fi
    if docker push ${quiet_flag} "${ENV_DOCKER_REGISTRY}:${image_tag}"; then
        _msg "safe remove the above image with 'docker rmi'"
    else
        _msg error "got an error here, probably caused by network..."
    fi
    if [[ "$ENV_FLYWAY_HELM_JOB" -eq 1 ]]; then
        docker push ${quiet_flag} "$image_tag_flyway" || _msg error "got an error here, probably caused by network..."
    fi
    _msg stepend "[container] push image with docker"
}

_deploy_k8s() {
    _msg step "[deploy] deploy with helm"
    if [[ "${ENV_REMOVE_PROJ_PREFIX:-false}" == 'true' ]]; then
        echo "remove project name prefix"
        helm_release=${gitlab_project_name#*-}
    else
        helm_release=${gitlab_project_name}
    fi
    ## Convert to lower case / 转换为小写
    helm_release="${helm_release,,}"
    ## finding helm files folder / 查找 helm 文件目录
    if [ -d "$gitlab_project_dir/helm" ]; then
        path_helm="$gitlab_project_dir/helm"
    elif [ -d "$gitlab_project_dir/docs/helm" ]; then
        path_helm="$gitlab_project_dir/docs/helm"
    elif [ -d "${me_path_data}/helm/${gitlab_project_name}.${gitlab_project_branch}" ]; then
        path_helm="${me_path_data}/helm/${gitlab_project_name}.${gitlab_project_branch}"
    elif [ -d "${me_path_data}/helm/${gitlab_project_name}" ]; then
        path_helm="${me_path_data}/helm/${gitlab_project_name}"
    fi

    ## helm install / helm 安装
    if [ -z "$path_helm" ]; then
        _msg purple "Not found helm files"
        echo "Try to generate helm files with bin/helm-new.sh"
        path_helm="${me_path_data}/helm/${helm_release}"
        bash "$me_path_bin/helm-new.sh" ${helm_release}
    fi
    echo "Found helm files: $path_helm"
    cat <<EOF
$helm_opt upgrade ${helm_release} $path_helm/ \
--install --history-max 1 \
--namespace ${env_namespace} --create-namespace \
--set image.repository=${ENV_DOCKER_REGISTRY} \
--set image.tag=${image_tag} \
--set image.pullPolicy=Always \
--timeout 120s
EOF
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    $helm_opt upgrade "${helm_release}" "$path_helm/" --install --history-max 1 \
        --namespace "${env_namespace}" --create-namespace \
        --set image.repository="${ENV_DOCKER_REGISTRY}" \
        --set image.tag="${image_tag}" \
        --set image.pullPolicy='Always' \
        --timeout 120s >/dev/null
    ## Clean up rs 0 0 / 清理 rs 0 0
    $kubectl_opt -n "${env_namespace}" get rs | awk '/.*0\s+0\s+0/ {print $1}' | xargs $kubectl_opt -n "${env_namespace}" delete rs &>/dev/null || true
    $kubectl_opt -n "${env_namespace}" get pod | grep Evicted | awk '{print $1}' | xargs $kubectl_opt -n "${env_namespace}" delete pod 2>/dev/null || true
    sleep 3
    $kubectl_opt -n "${env_namespace}" rollout status deployment "${helm_release}" --timeout 120s || deploy_result=1

    ## helm install flyway jobs / helm 安装 flyway 任务
    if [[ "$ENV_FLYWAY_HELM_JOB" == 1 && -d "${me_path_conf}"/helm/flyway ]]; then
        $helm_opt upgrade flyway "${me_path_conf}/helm/flyway/" --install --history-max 1 \
            --namespace "${env_namespace}" --create-namespace \
            --set image.repository="${ENV_DOCKER_REGISTRY}" \
            --set image.tag="${gitlab_project_name}-flyway-${gitlab_commit_short_sha}" \
            --set image.pullPolicy='Always' >/dev/null
    fi
    _msg stepend "[deploy] deploy with helm"
}

_deploy_rsync_ssh() {
    _msg step "[deploy] with rsync+ssh"
    ## rsync exclude some files / rsync 排除某些文件
    if [[ -f "${gitlab_project_dir}/rsync.exclude" ]]; then
        rsync_exclude="${gitlab_project_dir}/rsync.exclude"
    else
        rsync_exclude="${me_path_conf}/rsync.exclude"
    fi
    ## read conf, get project,branch,jar/war etc. / 读取配置文件，获取 项目/分支名/war包目录
    while read -r line; do
        # shellcheck disable=2116
        read -ra array <<<"$(echo "$line")"
        # git_branch=${array[1]}
        ssh_host=${array[2]}
        ssh_port=${array[3]}
        rsync_src=${array[4]}
        rsync_dest=${array[5]} ## 从配置文件读取目标路径
        # db_user=${array[6]}
        # db_host=${array[7]}
        # db_name=${array[8]}
        ## Prevent empty variable / 防止出现空变量（若有空变量则自动退出）
        _msg time "ssh host is: ${ssh_host:?if stop here, check $me_conf}"
        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=10 -p ${ssh_port:-22}"

        ## node/java use rsync --delete / node/java 使用 rsync --delete
        [[ "${project_lang}" =~ (node) ]] && rsync_delete='--delete'
        rsync_opt="rsync -acvzt --exclude=.svn --exclude=.git --timeout=10 --no-times --exclude-from=${rsync_exclude} $rsync_delete"

        ## rsync source folder / rsync 源目录
        ## define path_for_rsync in langs/build.*.sh / 在 langs/build.*.sh 中定义 path_for_rsync
        ## default: path_for_rsync=''
        # shellcheck disable=2154
        rsync_src="${gitlab_project_dir}/$path_for_rsync/"

        ## rsycn dest folder / rsync 目标目录
        if [[ "$rsync_dest" == 'null' || -z "$rsync_dest" ]]; then
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
        $ssh_opt -n "${ssh_host}" "[[ -d $rsync_dest ]] || mkdir -p $rsync_dest"
        echo "to ${ssh_host}:${rsync_dest}"
        ## rsync to remote server / rsync 到远程服务器
        ${rsync_opt} -e "$ssh_opt" "${rsync_src}" "${ssh_host}:${rsync_dest}"
        if [ -f "$me_path_data_bin/custom.deploy.sh" ]; then
            _msg time "custom deploy..."
            bash "$me_path_data_bin/custom.deploy.sh" ${ssh_host} ${rsync_dest}
            _msg time "end custom deploy."
        fi
        if [[ $exec_deploy_single_host -eq 1 ]]; then
            _msg step "deploy to singl host with docker-compose"
            $ssh_opt -n "$ssh_host" "cd $HOME/docker/laradock && docker compose up -d $gitlab_project_name"
        fi
    done < <(grep "^${gitlab_project_path}\s\+${env_namespace}" "$me_conf")
    _msg stepend "[deploy] deploy files"
}

_deploy_aliyun_oss() {
    _msg step "[deploy] deploy files to aliyun oss"
    # Check if deployment is enabled
    if [[ "${DEPLOYMENT_ENABLED:-0}" -ne 1 ]]; then
        echo '<skip>'
        return
    fi

    # Read config file
    source $me_path_conf/aliyun.oss.conf

    # Check if OSS CLI is installed
    if ! command -v ossutil >/dev/null 2>&1; then
        echo 'ossutil is not installed. Please install it before deploying to Aliyun OSS.'
        return
    fi

    # Deploy files to Aliyun OSS
    _msg step "[oss] deploy files to Aliyun OSS"
    _msg time "Start time: $(date +'%F %T')"
    ossutil cp -r "${LOCAL_DIR}" "oss://${BUCKET_NAME}/${REMOTE_DIR}" --config="${OSS_CONFIG_FILE}"
    if [[ $? -eq 0 ]]; then
        _msg green "Result = OK"
    else
        _msg error "Result = FAIL"
    fi
    _msg time "End time: $(date +'%F %T')"
    _msg stepend "[oss] deploy files to Aliyun OSS"
}

_deploy_rsync() {
    _msg step "[deploy] deploy files to rsyncd server"
    # Load configuration from file
    CONFIG_FILE="$me_path_data/rsyncd.conf"
    source "$CONFIG_FILE"

    # Deploy files with rsync
    RSYNC_OPTIONS="-avz"
    rsync $RSYNC_OPTIONS --exclude-from="$EXCLUDE_FILE" "$SOURCE_DIR/" "$RSYNC_USER@$RSYNC_HOST::$TARGET_DIR"
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
    _msg stepend "[deploy] deploy files to ftp server"
}

_deploy_sftp() {
    _msg step "[deploy] deploy files to sftp server"
}

_deploy_notify_msg() {
    msg_describe="${msg_describe:-$(git --no-pager log --no-merges --oneline -1 || true)}"

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
}

_notify_zoom() {
    # Send message to Zoom channel
    # ENV_ZOOM_CHANNEL="https://api.zoom.us/v2/im/chat/messages"
    #
    curl -X POST -H "Content-Type: application/json" -d '{"text": "'"${msg_body}"'"}' "${ENV_ZOOM_CHANNEL}"
}

_notify_feishu() {
    # Send message to Feishu
    # ENV_WEBHOOK_URL="https://open.feishu.cn/open-apis/bot/v2/hook/your-webhook-url"
    curl -X POST -H "Content-Type: application/json" -d '{"text": "'"$msg_body"'"}' "$ENV_WEBHOOK_URL"
}

_notify_wechat_work() {
    # Send message to weixin_work
    local wechat_key=$1
    wechat_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$wechat_key"
    curl -s -H 'Content-Type: application/json' \
        -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$msg_body\"}}" \
        "$wechat_api"
}

_deploy_notify() {
    _msg step "[notify] message for result"
    _deploy_notify_msg
    if [[ "${ENV_NOTIFY_WECHAT:-0}" -eq 1 ]]; then
        ## work chat / 发送至 企业微信
        _msg time "to wechat work"
        _notify_wechat_work ${ENV_WEIXIN_KEY}
    elif [[ "${ENV_NOTIFY_TELEGRAM:-0}" -eq 1 ]]; then
        ## Telegram / 发送至 Telegram
        _msg time "to Telegram"
        telegram_api_msg="https://api.telegram.org/bot${ENV_API_KEY_TG:? ERR: empty api key}/sendMessage"
        # telegram_api_doc="https://api.telegram.org/bot${ENV_API_KEY_TG:? ERR: empty api key}/sendDocument"
        msg_body="$(echo "$msg_body" | sed -e ':a;N;$!ba;s/\n/%0a/g' -e 's/&/%26/g')"
        curl -L -sS -o /dev/null -X POST -d "chat_id=${ENV_TG_GROUP_ID:? ERR: empty api key}&text=$msg_body" "$telegram_api_msg"
    elif [[ "${ENV_NOTIFY_ELEMENT:-0}" -eq 1 && "${PIPELINE_TEMP_PASS:-0}" -ne 1 ]]; then
        ## element / 发送至 element
        _msg time "to Element"
        python3 "$me_path_data_bin/element.py" "$msg_body"
    elif [[ "${ENV_NOTIFY_EMAIL:-0}" -eq 1 ]]; then
        ## email / 发送至 email
        # mogaal/sendemail: lightweight, command line SMTP email client
        # https://github.com/mogaal/sendemail
        _msg time "to Email"
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
    else
        _msg "<skip>"
    fi
}

_reload_nginx_gitlab() {
    if [ -f "$file_reload_nginx" ]; then
        _msg info "found .reload.nginx"
    else
        _msg warn "not found .reload.nginx"
        return 0
    fi
    for id in "${ENV_NGINX_PROJECT_ID[@]}"; do
        _msg "gitlab create pipeline, project id is $id"
        gitlab project-pipeline create --ref main --project-id $id
    done
    rm -f "$file_reload_nginx"
}

_renew_cert() {
    if [[ "${github_action:-0}" -eq 1 || "${arg_renew_cert:-0}" -eq 1 || "${PIPELINE_RENEW_CERT:-0}" -eq 1 ]]; then
        echo "PIPELINE_RENEW_CERT: ${PIPELINE_RENEW_CERT:-0}"
    else
        return 0
    fi
    _msg step "[cert] renew cert with acme.sh using dns+api"
    acme_home="${HOME}/.acme.sh"
    acme_cmd="${acme_home}/acme.sh"
    acme_cert="${acme_home}/${ENV_CERT_INSTALL:-dest}"
    file_reload_nginx="${acme_home}/.reload.nginx"
    ## content: export CF_Key="sdfsdfsdfljlbjkljlkjsdfoiwje" export CF_Email="xxxx@sss.com"
    conf_dns_cloudflare="${me_path_data}/.cloudflare.conf"
    ## export Ali_Key="sdfsdfsdfljlbjkljlkjsdfoiwje" export Ali_Secret="jlsdflanljkljlfdsaklkjflsa"
    conf_dns_aliyun="${me_path_data}/.aliyun.dnsapi.conf"
    ## content: DP_Id="1234" DP_Key="sADDsdasdgdsf"
    conf_dns_qcloud="${me_path_data}/.qcloud.dnspod.conf"

    ## install acme.sh / 安装 acme.sh
    [[ -x "${acme_cmd}" ]] || curl https://get.acme.sh | sh -s email=deploy@deploy.sh --home ${me_path_data}/.acmd.sh

    [ -d "$acme_cert" ] || mkdir -p "$acme_cert"
    ## support multiple account.conf.[x] / 支持多账号,只有一个则 account.conf.1
    if [[ "$(find "${acme_home}" -name 'account.conf*' | wc -l)" == 1 ]]; then
        cp -vf "${acme_home}/"account.conf "${acme_home}/"account.conf.1
    fi

    ## According to multiple different account files, loop renewal / 根据多个不同的账号文件,循环续签
    for account in "${acme_home}/"account.conf.*; do
        if [ ! -f "$account" ]; then
            continue
        fi
        if [ -f "$conf_dns_cloudflare" ]; then
            if ! command -v flarectl >/dev/null 2>&1; then
                _msg warning "command not found: flarectl "
                return 1
            fi
            source "$conf_dns_cloudflare" "${account##*.}"
            domains="$(flarectl zone list | awk '/active/ {print $3}')"
            dnsType='dns_cf'
        elif [ -f "$conf_dns_aliyun" ]; then
            _install_aliyun_cli

            source "$conf_dns_aliyun" "${account##*.}"
            aliyun configure set --profile "deploy${account##*.}" --mode AK --region "${Ali_region:-none}" --access-key-id "${Ali_Key:-none}" --access-key-secret "${Ali_Secret:-none}"
            domains="$(aliyun --profile "deploy${account##*.}" domain QueryDomainList --output cols=DomainName rows=Data.Domain --PageNum 1 --PageSize 100 | sed -e '1,2d' -e '/^$/d')"
            dnsType='dns_ali'
        elif [ -f "$conf_dns_qcloud" ]; then
            _msg warning "[TODO] use dnspod api."
        fi
        \cp -vf "$account" "${acme_home}/account.conf"
        ## single account may have multiple domains / 单个账号可能有多个域名
        for domain in ${domains}; do
            if [ -d "${acme_home}/$domain" ]; then
                ## renew cert / 续签证书
                "${acme_cmd}" --renew -d "${domain}" --renew-hook "touch $file_reload_nginx" || true
            else
                ## create cert / 创建证书
                "${acme_cmd}" --issue --dns $dnsType -d "$domain" -d "*.$domain"
            fi
            "${acme_cmd}" --install-cert -d "$domain" --key-file "$acme_cert/$domain".key --fullchain-file "$acme_cert/$domain".crt
        done
    done

    _reload_nginx_gitlab

    ## Custom deployment method / 自定义部署方式
    if [[ -f "${acme_home}/custom.acme.sh" ]]; then
        echo "Found ${acme_home}/custom.acme.sh"
        bash "${acme_home}/custom.acme.sh"
    fi

    _msg stepend "[cert] renew cert with acme.sh using dns+api"

    [[ "${exec_single:-0}" -gt 0 ]] && exit 0

    return 0
}

_get_balance_aliyun() {
    [[ "${github_action:-0}" -eq 1 ]] && return 0

    if [[ "${PIPELINE_GET_BALANCE:-0}" -eq 1 || "${arg_get_balance:-0}" -eq 1 ]]; then
        echo "PIPELINE_GET_BALANCE: ${PIPELINE_GET_BALANCE:-0}"
    else
        return 0
    fi

    _msg step "check balance of aliyun"
    local alarm_balance=${ENV_ALARM_BALANCE_ALIYUN:-3000}
    for p in $(jq -r '.profiles[].name' "$HOME"/.aliyun/config.json); do
        if [[ $ENV_TAKE_ALIYUN_PROFILE =~ $p ]]; then
            echo "Aliyun profile is: $p"
        else
            continue
        fi
        # if [[ $ENV_SKIP_ALIYUN_PROFILE =~ $p ]]; then
        #     continue
        # fi
        local amount
        amount="$(aliyun -p "$p" bssopenapi QueryAccountBalance 2>/dev/null | jq -r .Data.AvailableAmount | sed 's/,//')"
        if [[ -z "$amount" ]]; then
            continue
        fi
        _msg red "Current balance: $amount"
        if [[ $(echo "$amount < $alarm_balance" | bc) -eq 1 ]]; then
            msg_body="Aliyun账号:$p 当前余额 $amount, 需要充值。"
            _notify_wechat_work $ENV_WECHAT_KEY_ALARM
        fi
    done
    echo
    _msg stepend "check balance of aliyun"
    if [[ "${exec_single:-0}" -gt 0 ]]; then
        exit 0
    fi
}

_install_python_gitlab() {
    python3 -m pip list 2>/dev/null | grep -q python-gitlab && return
    _msg info "installing python3 gitlab api..."
    python3 -m pip install --user --upgrade python-gitlab
    if python3 -m pip install --user --upgrade python-gitlab; then
        _msg info "python-gitlab is installed successfully"
    else
        _msg error "failed to install python-gitlab"
    fi
}

_install_python_element() {
    python3 -m pip list 2>/dev/null | grep -q matrix-nio && return
    _msg info "installing python3 element api..."
    if python3 -m pip install --user --upgrade matrix-nio; then
        _msg info "matrix-nio is installed successfully"
    else
        _msg error "failed to install matrix-nio"
    fi
}

_install_aliyun_cli() {
    command -v aliyun >/dev/null && return
    _msg info "install aliyun cli..."
    curl -Lo /tmp/aliyun.tgz https://aliyuncli.alicdn.com/aliyun-cli-linux-latest-amd64.tgz
    tar -C /tmp -zxf /tmp/aliyun.tgz
    # install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    install -m 0755 /tmp/aliyun "${me_path_data_bin}/aliyun"
}

_install_jq_cli() {
    command -v jq >/dev/null && return
    _msg info "install jq cli..."
    [[ $UID -eq 0 ]] || pre_sudo=sudo
    $pre_sudo apt-get install -y jq
}

_install_terraform() {
    command -v terraform >/dev/null && return
    _msg info "installing terraform..."
    [[ $UID -eq 0 ]] || use_sudo=sudo
    $use_sudo apt-get update -qq && $use_sudo apt-get install -qq -y gnupg software-properties-common curl
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor | $use_sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null 2>&1
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" |
        $use_sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null 2>&1
    $use_sudo apt-get update -qq && $use_sudo apt-get install -qq -y terraform
    # terraform version
    _msg info "terraform installed successfully!"
}

_install_aws() {
    command -v aws >/dev/null && return
    _msg info "installing aws cli..."
    curl -Lo "/tmp/awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    unzip -qq /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install --bin-dir "${me_path_data_bin}" --install-dir "${me_path_data}" --update
    rm -rf /tmp/aws
    ## install eksctl / 安装 eksctl
    curl -L "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    mv /tmp/eksctl "${me_path_data_bin}/"
    chmod +x "${me_path_data_bin}/eksctl"
}

_install_kubectl() {
    command -v kubectl >/dev/null && return
    _msg info "installing kubectl..."
    kube_ver="$(curl -L --silent https://storage.googleapis.com/kubernetes-release/release/stable.txt)"
    kube_url="https://storage.googleapis.com/kubernetes-release/release/${kube_ver}/bin/linux/amd64/kubectl"
    if ! curl -Lo "${me_path_data_bin}/kubectl" "$kube_url"; then
        _msg error "failed to download kubectl"
        return 1
    fi
    chmod +x "${me_path_data_bin}/kubectl"
}

_install_helm() {
    command -v helm >/dev/null && return
    _msg info "installing helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
}

_install_jmeter() {
    command -v jmeter >/dev/null && return
    _msg info "install jmeter..."
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
        $exec_sudo apt-get update -y
        $exec_sudo apt-get install -y tzdata
        rm -rf /tmp/preseed.cfg
        unset DEBIAN_FRONTEND DEBCONF_NONINTERACTIVE_SEEN TIME_ZOME
        ## install jdk
        $exec_sudo apt-get install -y openjdk-16-jdk
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

_install_flarectl() {
    command -v flarectl >/dev/null && return
    _msg info "installing flarectl"
    local ver='0.52.0'
    local download_url="https://github.com/cloudflare/cloudflare-go/releases/download/v${ver}/flarectl_${ver}_linux_amd64.tar.xz"

    if ! curl -sSL "${download_url}" | tar xJf - -C "${me_path_data_bin}/" flarectl; then
        _msg error "failed to download and install flarectl"
        return 1
    fi
    _msg success "flarectl installed successfully"
}

_detect_os() {
    if [[ "$UID" != 0 ]]; then
        exec_sudo=sudo
    fi
    if [[ -e /etc/os-release ]]; then
        OS="$(source /etc/os-release && echo ${ID})"
    elif [[ -e /etc/centos-release ]]; then
        OS=centos
    elif [[ -e /etc/arch-release ]]; then
        OS=arch
    else
        echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2 or Arch Linux system"
        _msg error "Unsupported. exit."
        return 1
    fi

    case "$OS" in
    debian | ubuntu | linuxmint)
        ## fix gitlab-runner exit error / 修复 gitlab-runner 退出错误
        [[ -f "$HOME"/.bash_logout ]] && mv -f "$HOME"/.bash_logout "$HOME"/.bash_logout.bak
        command -v git >/dev/null || install_pkg="git"
        git lfs version >/dev/null 2>&1 || install_pkg="$install_pkg git-lfs"
        command -v curl >/dev/null || install_pkg="$install_pkg curl"
        command -v unzip >/dev/null || install_pkg="$install_pkg unzip"
        command -v rsync >/dev/null || install_pkg="$install_pkg rsync"
        command -v pip3 >/dev/null || install_pkg="$install_pkg python3-pip"
        # command -v shc >/dev/null || $exec_sudo apt-get install -qq -y shc

        if [[ -n "$install_pkg" ]]; then
            $exec_sudo apt-get update -qq
            $exec_sudo apt-get install -qq -y apt-utils
            # shellcheck disable=SC2086
            $exec_sudo apt-get install -qq -y $install_pkg >/dev/null
        fi
        ;;
    centos | amzn | rhel | fedora)
        rpm -q epel-release >/dev/null || {
            if [ "$OS" = amzn ]; then
                $exec_sudo amazon-linux-extras install -y epel >/dev/null
            else
                $exec_sudo yum install -y epel-release >/dev/null
            fi
        }
        command -v git >/dev/null || install_pkg=git2u
        git lfs version >/dev/null 2>&1 || install_pkg="$install_pkg git-lfs"
        command -v curl >/dev/null || install_pkg="$install_pkg curl"
        command -v unzip >/dev/null || install_pkg="$install_pkg unzip"
        command -v rsync >/dev/null || install_pkg="$install_pkg rsync"
        [[ -n "$install_pkg" ]] && $exec_sudo yum install -y $install_pkg >/dev/null
        # id | grep -q docker || $exec_sudo usermod -aG docker "$USER"
        ;;
    alpine)
        command -v openssl >/dev/null || install_pkg=openssl
        command -v git >/dev/null || install_pkg=git
        git lfs version >/dev/null 2>&1 || install_pkg="$install_pkg git-lfs"
        command -v curl >/dev/null || install_pkg="$install_pkg curl"
        command -v unzip >/dev/null || install_pkg="$install_pkg unzip"
        command -v rsync >/dev/null || install_pkg="$install_pkg rsync"
        [[ -n "$install_pkg" ]] && $exec_sudo apk add $install_pkg >/dev/null

        ;;
    *)
        echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2 or Arch Linux system"
        _msg error "Unsupported. exit."
        return 1
        ;;
    esac
    if ! command -v docker &>/dev/null; then
        [[ "${ENV_IN_CHINA:-false}" == 'true' ]] && install_arg='-s --mirror Aliyun'
        curl -fsSL https://get.docker.com | bash $install_arg
    fi
}

_clean_disk() {
    # Check disk usage and exit if below the threshold
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print int($5)}')
    local clean_disk_threshold=${ENV_CLEAN_DISK:-80}
    if ((disk_usage < clean_disk_threshold)); then
        return 0
    fi

    # Log disk usage and clean up docker images
    _log "$(df /)"
    _msg warning "Disk space is less than ${clean_disk_threshold}%, removing docker images..."
    docker images "${ENV_DOCKER_REGISTRY}" -q | sort -u | xargs -r docker rmi -f >/dev/null || true
    docker system prune -f >/dev/null || true
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
        $docker_run -v "${gitlab_project_dir}":/app -w /app deploy/node bash -c "apidoc -i app/ -o public/apidoc/"
    fi
}

_inject_files() {
    _msg step "[inject] from runner/data/project_conf/"
    ## backend (PHP/Java/Python) project_conf files
    ## 方便运维人员替换项目内文件，例如 PHP 数据库配置等信息 .env 文件，例如 Java 数据库配置信息 yml 文件
    path_project_conf="${me_path_data}/project_conf/${gitlab_project_name}/${env_namespace}"
    if [ -d "$path_project_conf" ]; then
        _msg warning "found custom config files, sync it."
        rsync -av "$path_project_conf"/ "${gitlab_project_dir}"/
    fi

    ## frontend (VUE) .env file
    if [[ "$project_lang" == node ]]; then
        config_env_path="$(find "${gitlab_project_dir}" -maxdepth 2 -name "${env_namespace}.*")"
        for file in $config_env_path; do
            [[ -f "$file" ]] || continue
            echo "Found $file"
            if [[ "$file" =~ 'config' ]]; then
                rsync -av "$file" "${file/${env_namespace}./}" # vue2.x
            else
                rsync -av "$file" "${file/${env_namespace}/}" # vue3.x
            fi
        done
        copy_flyway_file=0
    fi

    ## from deploy.env， 使用全局模板文件替换项目文件
    # ENV_ENABLE_INJECT=1, 覆盖 [default action]
    # ENV_ENABLE_INJECT=2, 不覆盖 [使用项目自身的文件]
    # ENV_ENABLE_INJECT=3, 删除 Dockerfile [不使用 docker build]
    # ENV_ENABLE_INJECT=4, 创建 docker-compose.yml [使用 docker-compose 发布]
    echo ENV_ENABLE_INJECT: ${ENV_ENABLE_INJECT:-1}
    case ${ENV_ENABLE_INJECT:-1} in
    1)
        ## Java, shared template files Dockerfile, run.sh, settings.xml
        if [[ "$project_lang" == java ]]; then
            local dockerfile_url="https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/Dockerfile.java"
            curl -fsSLo "${gitlab_project_dir}/Dockerfile" $dockerfile_url
            if [[ -f "${me_path_data}/dockerfile/settings.xml" ]]; then
                rsync -a "${me_path_data}/dockerfile/settings.xml" "${gitlab_project_dir}/"
            elif [[ "$ENV_IN_CHINA" == 'true' ]]; then
                local settings_url="https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/settings.xml"
                curl -fsSLo "${gitlab_project_dir}/settings.xml" $settings_url
            fi
        fi
        if [[ -f "${me_path_data}/dockerfile/Dockerfile.${project_lang}" ]]; then
            echo "Overwriting from data/dockerfile/Dockerfile.${project_lang}"
            rsync -a "${me_path_data}/dockerfile/Dockerfile.${project_lang}" "${gitlab_project_dir}/Dockerfile"
        fi
        ;;
    2)
        echo 'Not overwriting Dockerfile'
        ;;
    3)
        echo 'Removing Dockerfile (disabling docker build)'
        rm -f "${gitlab_project_dir}/Dockerfile"
        ;;
    4)
        echo "Generating docker-compose.yml (enabling deployment with docker-compose)"
        echo '## deploy with docker-compose' >>"${gitlab_project_dir}/docker-compose.yml"
        ;;
    esac
    ## docker ignore file / 使用全局模板文件替换项目文件
    [[ -f "${gitlab_project_dir}/Dockerfile" && ! -f "${gitlab_project_dir}/.dockerignore" ]] &&
        rsync -av "${me_path_conf}/.dockerignore" "${gitlab_project_dir}/"

    ## flyway files sql & conf
    for sql in ${ENV_FLYWAY_SQL:-docs/sql} flyway_sql doc/sql sql; do
        path_flyway_sql_proj="${gitlab_project_dir}/${sql}"
        if [[ -d "${path_flyway_sql_proj}" ]]; then
            exec_deploy_flyway=1
            copy_flyway_file=1
            break
        fi
    done
    if [[ -z "${exec_deploy_flyway}" ]]; then
        exec_deploy_flyway=0
        copy_flyway_file=0
    fi

    if [[ "${copy_flyway_file:-0}" -eq 1 ]]; then
        path_flyway_conf="$gitlab_project_dir/flyway_conf"
        path_flyway_sql="$gitlab_project_dir/flyway_sql"
        [[ -d "$path_flyway_sql_proj" && ! -d "$path_flyway_sql" ]] && rsync -a "$path_flyway_sql_proj/" "$path_flyway_sql/"
        [[ -d "$path_flyway_conf" ]] || mkdir -p "$path_flyway_conf"
        [[ -d "$path_flyway_sql" ]] || mkdir -p "$path_flyway_sql"
        [[ -f "${gitlab_project_dir}/Dockerfile.flyway" ]] || rsync -av "${me_dockerfile}/Dockerfile.flyway" "${gitlab_project_dir}/"
    fi
}

_set_deploy_conf() {
    path_conf_ssh="${me_path_data}/.ssh"
    path_conf_acme="${me_path_data}/.acme.sh"
    path_conf_aws="${me_path_data}/.aws"
    path_conf_kube="${me_path_data}/.kube"
    path_conf_aliyun="${me_path_data}/.aliyun"
    conf_python_gitlab="${me_path_data}/.python-gitlab.cfg"
    ## ssh config and key files
    if [[ ! -d "${path_conf_ssh}" ]]; then
        mkdir -m 700 "$path_conf_ssh"
        _msg warning "Generate ssh key file for gitlab-runner: $path_conf_ssh/id_ed25519"
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
    [[ ! -f "${HOME}/.python-gitlab.cfg" && -f "${conf_python_gitlab}" ]] && ln -sf "${conf_python_gitlab}" "$HOME/"
    return 0
}

_setup_gitlab_vars() {
    gitlab_project_dir=${CI_PROJECT_DIR:-$PWD}
    gitlab_project_name=${CI_PROJECT_NAME:-${gitlab_project_dir##*/}}
    # read -rp "Enter gitlab project namespace: " -e -i 'root' gitlab_project_namespace
    gitlab_project_namespace=${CI_PROJECT_NAMESPACE:-root}
    # read -rp "Enter gitlab project path: [root/git-repo] " -e -i 'root/xxx' gitlab_project_path
    gitlab_project_path=${CI_PROJECT_PATH:-$gitlab_project_namespace/$gitlab_project_name}
    # read -t 5 -rp "Enter branch name: " -e -i 'develop' gitlab_project_branch
    gitlab_project_branch=${CI_COMMIT_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}
    gitlab_project_branch=${gitlab_project_branch:-develop}
    gitlab_commit_short_sha=${CI_COMMIT_SHORT_SHA:-$(git rev-parse --short HEAD || true)}
    if [[ -z "$gitlab_commit_short_sha" ]]; then
        if [[ "${github_action:-0}" -eq 1 ]]; then
            gitlab_commit_short_sha=${gitlab_commit_short_sha:-1234567}
        elif [[ "${debug_on:-0}" -eq 1 ]]; then
            read -rp "Enter commit short hash: " -e -i '1234567' gitlab_commit_short_sha
        else
            _msg red "Error: gitlab_commit_short_sha is not set"
            return 1
        fi
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

    if [[ $run_crontab -eq 1 ]]; then
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
    _msg step "[langs] probe language"
    for f in pom.xml composer.json package.json requirements.txt README.md readme.md README.txt readme.txt; do
        [[ -f "${gitlab_project_dir}"/${f} ]] || continue
        case $f in
        composer.json)
            echo "Found composer.json"
            project_lang=php
            ;;
        package.json)
            echo "Found package.json"
            project_lang=node
            ;;
        pom.xml)
            echo "Found pom.xml"
            project_lang=java
            ;;
        requirements.txt)
            echo "Found requirements.txt"
            project_lang=python
            ;;
        *)
            project_lang=${project_lang:-$(awk -F= '/^project_lang/ {print $2}' "${gitlab_project_dir}"/${f} | head -n 1)}
            project_lang=${project_lang// /}
            project_lang=${project_lang,,}
            project_lang=${project_lang:-unknown}
            ;;
        esac
    done
    echo "Probe lang: ${project_lang:-unknown}"
}

_probe_deploy_method() {
    _msg step "[probe] probe deploy method"
    for f in Dockerfile docker-compose.yml; do
        [[ -f "${gitlab_project_dir}"/${f} ]] || continue
        case $f in
        docker-compose.yml)
            echo "Found docker-compose.yml"
            exec_build_image=0
            exec_push_image=0
            exec_deploy_k8s=0
            exec_deploy_single_host=1
            ;;
        Dockerfile)
            echo "Found Dockerfile"
            echo "Enable build with docker"
            echo "Enable deploy with helm"
            exec_build_langs=0
            exec_build_image=1
            exec_push_image=1
            exec_deploy_k8s=1
            exec_deploy_rsync_ssh=0
            ;;
        esac
    done
}

_checkout_svn_repo() {
    [[ "${arg_svn_checkout:-0}" -eq 1 ]] || return 0
    if [[ ! -d "$me_path_builds" ]]; then
        echo "Not found $me_path_builds, create it..."
        mkdir -p "$me_path_builds"
    fi
    local svn_repo_name
    svn_repo_name=$(echo "$arg_svn_checkout_url" | awk -F '/' '{print $NF}')
    local svn_repo_dir="${me_path_builds}/${svn_repo_name}"
    if [ -d "$svn_repo_dir" ]; then
        echo "\"$svn_repo_dir\" exists"
        cd "$svn_repo_dir" && svn update
    else
        echo "checkout svn repo: $arg_svn_checkout_url"
        svn checkout "$arg_svn_checkout_url" "$svn_repo_dir" || {
            echo "Failed to checkout svn repo: $arg_svn_checkout_url"
            exit 1
        }
    fi
}

_clone_git_repo() {
    [[ "${arg_git_clone:-0}" -eq 1 ]] || return 0
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
    [[ "$create_k8s" -eq 1 ]] || return 0
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
    --build-image            Build docker image.
    --push-image             Push docker image.
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

_process_args() {
    ## All tasks are performed by default / 默认执行所有任务
    ## if you want to exec some tasks, use --task1 --task2 / 如果需要执行某些任务，使用 --task1 --task2， 适用于单独的 gitlab job，（一个 pipeline 多个独立的 job）
    exec_single=0
    while [[ "${#}" -ge 0 ]]; do
        case "$1" in
        --debug)
            set -x
            debug_on=1
            quiet_flag=
            ;;
        --cron | --loop)
            run_crontab=1
            ;;
        --create-k8s)
            create_k8s=1
            ;;
        --github-action)
            set -x
            debug_on=1
            quiet_flag=
            github_action=1
            ;;
        --get-balance)
            arg_get_balance=1 && exec_single=$((exec_single + 1))
            ;;
        --renew-cert | -r)
            arg_renew_cert=1 && exec_single=$((exec_single + 1))
            ;;
        --svn-checkout)
            arg_svn_checkout=1
            arg_svn_checkout_url="${2:?empty svn url}"
            shift
            ;;
        --git-clone)
            arg_git_clone=1
            arg_git_clone_url="${2:?empty git clone url}"
            shift
            ;;
        --git-clone-branch)
            arg_git_clone_branch="${2:?empty git clone branch}"
            shift
            ;;
        --code-style)
            arg_code_style=1 && exec_single=$((exec_single + 1))
            ;;
        --code-quality)
            arg_code_quality=1 && exec_single=$((exec_single + 1))
            ;;
        --build-langs)
            arg_build_langs=1 && exec_single=$((exec_single + 1))
            ;;
        --build-image)
            arg_build_image=1 && exec_single=$((exec_single + 1))
            ;;
        --push-image)
            arg_push_image=1 && exec_single=$((exec_single + 1))
            ;;
        --deploy-k8s)
            arg_deploy_k8s=1 && exec_single=$((exec_single + 1))
            ;;
        --deploy-flyway)
            # arg_deploy_flyway=1
            exec_single=$((exec_single + 1))
            ;;
        --deploy-rsync-ssh)
            arg_deploy_rsync_ssh=1 && exec_single=$((exec_single + 1))
            ;;
        --deploy-rsync)
            arg_deploy_rsync=1 && exec_single=$((exec_single + 1))
            ;;
        --deploy-ftp)
            arg_deploy_ftp=1 && exec_single=$((exec_single + 1))
            ;;
        --deploy-sftp)
            arg_deploy_sftp=1 && exec_single=$((exec_single + 1))
            ;;
        --test-unit)
            arg_test_unit=1 && exec_single=$((exec_single + 1))
            ;;
        --test-function)
            arg_test_function=1 && exec_single=$((exec_single + 1))
            ;;
        *)
            if [[ "${#}" -gt 0 ]]; then
                _usage
                exit
            fi
            [[ "${debug_on:-0}" -eq 0 ]] && quiet_flag='--quiet'
            break
            ;;
        esac
        shift
    done
}

main() {
    [[ "${PIPELINE_DEBUG:-0}" -eq 1 ]] && set -x
    ## Process parameters / 处理传入的参数
    _process_args "$@"

    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_path_conf="${me_path}/conf"
    me_path_bin="${me_path}/bin"
    me_path_data="${me_path}/data" ## deploy.sh data folder
    me_log="${me_path_data}/${me_name}.log"
    me_path_data_bin="${me_path}/data/bin"
    me_path_builds="${me_path}/builds"
    me_conf="${me_path_data}/deploy.conf"      ## deploy to app server 发布到目标服务器的配置信息
    me_env="${me_path_data}/deploy.env"        ## deploy.sh ENV 发布配置信息(密)
    me_dockerfile="${me_path_conf}/dockerfile" ## deploy.sh dependent dockerfile
    ## create deploy.sh/data dir  /  创建 data 目录
    [[ -d $me_path_data ]] || mkdir -p $me_path_data
    ## 准备配置文件
    [[ -f "$me_conf" ]] || cp "${me_path_conf}/example-deploy.conf" "$me_conf"
    [[ -f "$me_env" ]] || cp "${me_path_conf}/example-deploy.env" "$me_env"
    ## 设定 PATH
    declare -a paths_to_append=(
        "/usr/local/sbin"
        "/snap/bin"
        "$me_path_bin"
        "$me_path_data_bin"
        "$HOME/.local/bin"
        "$HOME/.config/composer/vendor/bin"
    )
    for p in "${paths_to_append[@]}"; do
        if [[ -d "$p" && "$PATH" != *":$p:"* ]]; then
            PATH="${PATH:+"$PATH:"}$p"
        fi
    done

    export PATH

    docker_run="docker run $ENV_ADD_HOST --interactive --rm -u $(id -u):$(id -g)"
    # docker_run_root="docker run $ENV_ADD_HOST --interactive --rm -u 0:0"
    kubectl_opt="kubectl --kubeconfig $HOME/.kube/config"
    helm_opt="helm --kubeconfig $HOME/.kube/config"

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
    ## demo mode: default docker login password / docker 登录密码
    if [[ "$ENV_DOCKER_PASSWORD" == 'your_password' && "$ENV_DOCKER_USERNAME" == 'your_username' ]]; then
        _msg purple "Found default username/password, skip docker login / push image / deploy k8s..."
        demo_mode=1
    fi
    image_tag="${gitlab_project_name}-${gitlab_commit_short_sha}-$(date +%s)"
    image_tag_flyway="${ENV_DOCKER_REGISTRY:?undefine}:${gitlab_project_name}-flyway-${gitlab_commit_short_sha}"
    ## install acme.sh/aws/kube/aliyun/python-gitlab/flarectl 安装依赖命令/工具
    [[ "${ENV_INSTALL_AWS}" == 'true' ]] && _install_aws
    [[ "${ENV_INSTALL_ALIYUN}" == 'true' ]] && _install_aliyun_cli
    [[ "${ENV_INSTALL_JQ}" == 'true' ]] && _install_jq_cli
    [[ "${ENV_INSTALL_TERRAFORM}" == 'true' ]] && _install_terraform
    [[ "${ENV_INSTALL_KUBECTL}" == 'true' ]] && _install_kubectl
    [[ "${ENV_INSTALL_HELM}" == 'true' ]] && _install_helm
    [[ "${ENV_INSTALL_PYTHON_ELEMENT}" == 'true' ]] && _install_python_element
    [[ "${ENV_INSTALL_PYTHON_GITLAB}" == 'true' ]] && _install_python_gitlab
    [[ "${ENV_INSTALL_JMETER}" == 'true' ]] && _install_jmeter
    [[ "${ENV_INSTALL_FLARECTL}" == 'true' ]] && _install_flarectl

    ## clean up disk space / 清理磁盘空间
    _clean_disk

    ## create k8s / 创建 kubernetes 集群
    _create_k8s

    ## setup ssh-config/acme.sh/aws/kube/aliyun/python-gitlab/cloudflare/rsync
    _set_deploy_conf

    ## renew cert with acme.sh / 使用 acme.sh 重新申请证书
    _renew_cert

    ## get balance of aliyun / 获取 aliyun 账户现金余额
    _get_balance_aliyun

    ## probe program lang / 探测项目的程序语言
    _probe_langs

    ## preprocess project config files / 预处理业务项目配置文件，覆盖配置文件等特殊处理
    _inject_files

    ## probe deploy method / 探测文件并确定发布方式
    _probe_deploy_method

    ## code style check / 代码格式检查
    code_style_sh="$me_path/langs/style.${project_lang}.sh"

    ## code build / 代码编译打包
    build_langs_sh="$me_path/langs/build.${project_lang}.sh"

    ################################################################################
    ## exec single task / 执行单个任务，适用于 gitlab-ci/jenkins 等自动化部署工具的单个 job 任务执行
    if [[ "${exec_single:-0}" -gt 0 ]]; then
        [[ "${arg_code_quality:-0}" -eq 1 ]] && _check_quality_sonar
        [[ "${arg_code_style:-0}" -eq 1 && -f "$code_style_sh" ]] && source "$code_style_sh"
        [[ "${arg_test_unit:-0}" -eq 1 ]] && _test_unit
        # [[ "${exec_deploy_flyway:-0}" -eq 1 ]] && _deploy_flyway_helm_job
        [[ "${exec_deploy_flyway:-0}" -eq 1 ]] && _deploy_flyway_docker
        [[ "${arg_build_langs:-0}" -eq 1 && -f "$build_langs_sh" ]] && source "$build_langs_sh"
        [[ "${arg_build_image:-0}" -eq 1 ]] && _build_image_docker
        [[ "${arg_push_image:-0}" -eq 1 ]] && _push_image
        [[ "${arg_deploy_k8s:-0}" -eq 1 ]] && _deploy_k8s
        [[ "${arg_deploy_rsync_ssh:-0}" -eq 1 ]] && _deploy_rsync_ssh
        [[ "${arg_deploy_rsync:-0}" -eq 1 ]] && _deploy_rsync
        [[ "${arg_deploy_ftp:-0}" -eq 1 ]] && _deploy_ftp
        [[ "${arg_deploy_sftp:-0}" -eq 1 ]] && _deploy_sftp
        [[ "${arg_test_function:-0}" -eq 1 ]] && _test_function
        return 0
    fi
    ################################################################################

    ## default exec all tasks / 默认执行所有任务
    _check_quality_sonar

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_CODE_STYLE ，1 启用[default]，0 禁用
    _check_style

    ## unit test / 单元测试
    _test_unit

    ## use flyway deploy sql file / 使用 flyway 发布 sql 文件
    # [[ "${exec_deploy_flyway:-0}" -eq 1 ]] && _deploy_flyway_helm_job
    _deploy_flyway_docker

    ## generate api docs / 利用 apidoc 产生 api 文档
    # _generate_apidoc

    ## build
    [[ "${exec_build_langs:-1}" -eq 1 && -f "$build_langs_sh" ]] && source "$build_langs_sh"
    [[ "${exec_build_image:-0}" -eq 1 ]] && _build_image_docker
    # [[ "${exec_build_image:-0}" -eq 1 ]] && _build_image_podman

    ## docker push image
    [[ "${exec_push_image:-0}" -eq 1 ]] && _push_image

    ## deploy k8s
    [[ "${exec_deploy_k8s:-0}" -eq 1 ]] && _deploy_k8s
    ## deploy rsync server
    [[ "${exec_deploy_rsync:-0}" -eq 1 ]] && _deploy_rsync
    ## deploy ftp server
    [[ "${exec_deploy_ftp:-0}" -eq 1 ]] && _deploy_ftp
    ## deploy sftp server
    [[ "${exec_deploy_sftp:-0}" -eq 1 ]] && _deploy_sftp
    ## deploy with rsync / 使用 rsync 发布
    [[ "${ENV_DISABLE_RSYNC:-0}" -eq 1 ]] && exec_deploy_rsync_ssh=0
    [[ "${exec_deploy_rsync_ssh:-1}" -eq 1 ]] && _deploy_rsync_ssh

    ## function test / 功能测试
    _test_function

    ## 安全扫描
    _scan_zap
    _scan_vulmap

    ## deploy notify info / 发布通知信息
    ## 发送消息到群组, exec_deploy_notify， 0 不发， 1 发.
    [[ "${github_action:-0}" -eq 1 ]] && deploy_result=0
    [[ "${deploy_result}" -eq 1 ]] && exec_deploy_notify=1
    [[ "$ENV_DISABLE_MSG" -eq 1 ]] && exec_deploy_notify=0
    [[ "$ENV_DISABLE_MSG_BRANCH" =~ $gitlab_project_branch ]] && exec_deploy_notify=0
    [[ "${exec_deploy_notify:-1}" -eq 1 ]] && _deploy_notify

    echo "==== END ===="
    ## deploy result:  0 成功， 1 失败
    return ${deploy_result:-0}
}

main "$@"
