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

echo_msg() {
    color_off='\033[0m' # Text Reset
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
    stepend)
        color_on="[+] $(date +%Y%m%d-%T-%u), "
        color_off=' ... end'
        ;;
    step | timestep)
        color_on="\033[0;33m[$((${STEP:-0} + 1))] $(date +%Y%m%d-%T-%u), \033[0m"
        STEP=$((${STEP:-0} + 1))
        color_off=' ... start'
        ;;
    *)
        color_on=''
        color_off=''
        need_shift=0
        ;;
    esac
    [ "${need_shift:-1}" -eq 1 ] && shift
    need_shift=1
    echo -e "${color_on}$*${color_off}"
}

## year month day - time - %u day of week (1..7); 1 is Monday - %j day of year (001..366) - %W week number of year, with Monday as first day of week (00..53)

## install phpunit
_test_unit() {
    echo_msg step "[test] unit test"
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
        echo_msg purple "not found tests/unit_test.sh, skip unit test."
    fi
    echo_msg stepend "[test] unit test"
}

## install jdk/ant/jmeter
_test_function() {
    echo_msg step "[test] function test"
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
    echo_msg stepend "[test] function test"
}

_code_quality_sonar() {
    echo_msg step "[quality] check code with sonarqube"
    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_SONAR ，1 启用，0 禁用[default]
    echo "PIPELINE_SONAR: ${PIPELINE_SONAR:-0}"
    if [[ "${PIPELINE_SONAR:-0}" -eq 0 ]]; then
        echo "<skip>"
        return 0
    fi
    sonar_url="${ENV_SONAR_URL:?empty}"
    sonar_conf="$gitlab_project_dir/sonar-project.properties"
    if ! curl "$sonar_url" >/dev/null 2>&1; then
        echo_msg warning "Could not found sonarqube server, exit."
        return
    fi

    if [[ ! -f "$sonar_conf" ]]; then
        echo "Not found $sonar_conf, create it"
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
    echo_msg stepend "[quality] check code with sonarqube"
    exit 0
}

_scan_ZAP() {
    echo_msg step "[ZAP] scan"
    echo '<skip>'
    # docker pull owasp/zap2docker-stable
}

_scan_vulmap() {
    echo_msg step "[vulmap] scan"
    echo '<skip>'
    # https://github.com/zhzyker/vulmap
    # docker run --rm -ti vulmap/vulmap  python vulmap.py -u https://www.example.com
}

_deploy_flyway_docker() {
    echo_msg step "[flyway] deploy database SQL files"
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
        echo "Nothing to do."
    fi
    if [ ${deploy_result:-0} = 0 ]; then
        echo_msg green "Result = OK"
    else
        echo_msg error "Result = FAIL"
    fi
    echo_msg stepend "[flyway] deploy database SQL files"
}

_deploy_flyway_helm_job() {
    [[ "${ENV_FLYWAY_HELM_JOB:-0}" -ne 1 ]] && return
    echo_msg step "[flyway] deploy database SQL with helm job"
    echo "$image_tag_flyway"
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    DOCKER_BUILDKIT=1 docker build ${quiet_flag} --tag "${image_tag_flyway}" -f "${gitlab_project_dir}/Dockerfile.flyway" "${gitlab_project_dir}/"
    docker run --rm "$image_tag_flyway" || deploy_result=1
    if [ ${deploy_result:-0} = 0 ]; then
        echo_msg green "Result = OK"
    else
        echo_msg error "Result = FAIL"
    fi
    echo_msg stepend "[flyway] deploy database SQL with helm job"
}

# python-gitlab list all projects / 列出所有项目
# gitlab -v -o yaml -f path_with_namespace project list --all |awk -F': ' '{print $2}' |sort >p.txt
# 解决 Encountered 1 file(s) that should have been pointers, but weren't
# git lfs migrate import --everything$(awk '/filter=lfs/ {printf " --include='\''%s'\''", $1}' .gitattributes)

_docker_login() {
    local lock_docker_login="$me_path_data/.lock.docker.login.${ENV_DOCKER_LOGIN_TYPE:-none}"
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    if [[ "${ENV_DOCKER_LOGIN_TYPE:-none}" == 'aws' ]]; then
        # time_last="$(if [[ -f "$lock_docker_login" ]]; then cat "$lock_docker_login"; else echo 0; fi)"
        time_last="$(stat -t -c %Y "$lock_docker_login")"
        ## Compare the last login time, log in again after 12 hours / 比较上一次登陆时间，超过12小时则再次登录
        [[ "$(date +%s -d '12 hours ago')" -lt "${time_last:-0}" ]] && return 0
        echo_msg time "[login] docker login [${ENV_DOCKER_LOGIN_TYPE:-none}]..."
        str_docker_login="docker login --username AWS --password-stdin ${ENV_DOCKER_REGISTRY%%/*}"
        aws ecr get-login-password --profile="${ENV_AWS_PROFILE}" --region "${ENV_REGION_ID:?undefine}" | $str_docker_login >/dev/null
    else
        if [[ "${demo_mode:-0}" == 1 ]]; then
            echo_msg purple "demo mode, skip docker login."
            return 0
        fi
        [[ -f "$lock_docker_login" ]] && return 0
        echo "${ENV_DOCKER_PASSWORD}" | docker login --username="${ENV_DOCKER_USERNAME}" --password-stdin "${ENV_DOCKER_REGISTRY%%/*}"
    fi
    touch "$lock_docker_login"
}

_build_image_docker() {
    echo_msg step "[container] build image with docker"
    _docker_login
    ## Docker build from template image / 是否从模板构建
    [[ "${github_action:-0}" -eq 1 ]] && return 0

    ## docker build flyway image / 构建 flyway 模板
    if [[ "$ENV_FLYWAY_HELM_JOB" -eq 1 ]]; then
        DOCKER_BUILDKIT=1 docker build ${quiet_flag} --tag "${image_tag_flyway}" -f "${gitlab_project_dir}/Dockerfile.flyway" "${gitlab_project_dir}/"
    fi
    ## docker build
    [ -d "${gitlab_project_dir}"/flyway_conf ] && rm -rf "${gitlab_project_dir}"/flyway_conf
    [ -d "${gitlab_project_dir}"/flyway_sql ] && rm -rf "${gitlab_project_dir}"/flyway_sql
    DOCKER_BUILDKIT=1 docker build ${quiet_flag} --tag "${ENV_DOCKER_REGISTRY}:${image_tag}" \
        --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE:-false}" \
        --build-arg MVN_PROFILE="${gitlab_project_branch}" "${gitlab_project_dir}"
    ## docker push to ttl.sh
    # image_uuid="ttl.sh/$(uuidgen):1h"
    # echo "If you want to push the image to ttl.sh, please execute the following command on gitlab-runner:"
    # echo "#    docker tag ${ENV_DOCKER_REGISTRY}:${image_tag} ${image_uuid}"
    # echo "#    docker push $image_uuid"
    # echo "Then execute the following command on remote server:"
    # echo "#    docker pull $image_uuid"
    # echo "#    docker tag $image_uuid deploy/<your_app>"
    echo_msg stepend "[container] build image with docker"
}

_build_image_podman() {
    echo_msg step "[container] build image with podman"
    echo '<skip>'
    # echo_msg stepend "[TODO] [podman] build image"
}

_push_image() {
    echo_msg step "[container] push image with docker"
    _docker_login
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    if [[ "$demo_mode" == 1 ]]; then
        echo_msg purple "Demo mode, skip push image."
        return 0
    fi
    if docker push ${quiet_flag} "${ENV_DOCKER_REGISTRY}:${image_tag}"; then
        echo_msg "safe remove the above image with 'docker rmi'"
    else
        echo_msg error "got an error here, probably caused by network..."
    fi
    if [[ "$ENV_FLYWAY_HELM_JOB" -eq 1 ]]; then
        docker push ${quiet_flag} "$image_tag_flyway" || echo_msg error "got an error here, probably caused by network..."
    fi
    echo_msg stepend "[container] push image"
}

_deploy_k8s() {
    echo_msg step "[deploy] deploy with helm"
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
        echo_msg purple "Not found helm files"
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
    echo_msg stepend "[deploy] deploy with helm"
}

_deploy_rsync_ssh() {
    echo_msg step "[deploy] deploy files with rsync+ssh"
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
        echo_msg time "${ssh_host:?if stop here, check $me_conf}"
        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=10 -p ${ssh_port:-22}"
        ## rsync exclude some files / rsync 排除某些文件
        if [[ -f "${gitlab_project_dir}/rsync.exclude" ]]; then
            rsync_exclude="${gitlab_project_dir}/rsync.exclude"
        else
            rsync_exclude="${me_path_conf}/rsync.exclude"
        fi
        ## node/java use rsync --delete / node/java 使用 rsync --delete
        [[ "${project_lang}" =~ (node|other) ]] && rsync_delete='--delete'
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
            command -v aliyun &>/dev/null || {
                echo_msg warning "command not exist: aliyun"
                exit 1
            }
            aliyun oss cp "${rsync_src}" "$rsync_dest" --recursive --force
            ## 如果使用 rclone， 则需要安装和配置
            # rclone sync "${gitlab_project_dir}/" "$rsync_dest/"
            return
        fi
        $ssh_opt -n "${ssh_host}" "[[ -d $rsync_dest ]] || mkdir -p $rsync_dest"
        echo "Deploy to ${ssh_host}:${rsync_dest}"
        ## rsync to remote server / rsync 到远程服务器
        ${rsync_opt} -e "$ssh_opt" "${rsync_src}" "${ssh_host}:${rsync_dest}"
        if [ -f "$me_path_data_bin/custom.deploy.sh" ]; then
            echo_msg time "custom deploy..."
            bash "$me_path_data_bin/custom.deploy.sh" ${ssh_host} ${rsync_dest}
            echo_msg time "end custom deploy."
        fi
        if [[ $exec_deploy_single_host -eq 1 ]]; then
            echo_msg step "deploy to singl host with docker-compose"
            $ssh_opt -n "$ssh_host" "cd ~/docker/laradock && docker compose up -d $gitlab_project_name"
        fi
    done < <(grep "^${gitlab_project_path}\s\+${env_namespace}" "$me_conf")
    echo_msg stepend "[deploy] deploy files"
}

_deploy_aliyun_oss() {
    echo_msg step "[deploy] deploy files to aliyun oss"
}

_deploy_rsync() {
    echo_msg step "[deploy] deploy files to rsyncd server"
}

_deploy_ftp() {
    echo_msg step "[deploy] deploy files to ftp server"
    return
    upload_file="${gitlab_project_dir}/ftp.tgz"
    tar czvf "${upload_file}" -C "${gitlab_project_dir}" .
    ftp -v -n "${ssh_host}" <<EOF
user your_name your_pass
passive on
binary
delete $upload_file
put $upload_file
passive off
bye
EOF
    echo_msg stepend "[deploy] deploy files to ftp server"
}

_deploy_sftp() {
    echo_msg step "[deploy] deploy files to sftp server"
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

_deploy_notify() {
    echo_msg step "[notify] message for result"
    _deploy_notify_msg
    if [[ "${ENV_NOTIFY_WEIXIN:-0}" -eq 1 ]]; then
        ## work chat / 发送至 企业微信
        echo_msg time "to work wxchat"
        weixin_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${ENV_WEIXIN_KEY:? ERR: empty api key}"
        curl -s "$weixin_api" -H 'Content-Type: application/json' \
            -d "
        {
            \"msgtype\": \"text\",
            \"text\": {
                \"content\": \"$msg_body\"
            }
        }"
    elif [[ "${ENV_NOTIFY_TELEGRAM:-0}" -eq 1 ]]; then
        ## Telegram / 发送至 Telegram
        echo_msg time "to Telegram"
        telegram_api_msg="https://api.telegram.org/bot${ENV_API_KEY_TG:? ERR: empty api key}/sendMessage"
        # telegram_api_doc="https://api.telegram.org/bot${ENV_API_KEY_TG:? ERR: empty api key}/sendDocument"
        msg_body="$(echo "$msg_body" | sed -e ':a;N;$!ba;s/\n/%0a/g' -e 's/&/%26/g')"
        $curl_opt -sS -o /dev/null -X POST -d "chat_id=${ENV_TG_GROUP_ID:? ERR: empty api key}&text=$msg_body" "$telegram_api_msg"
    elif [[ "${ENV_NOTIFY_ELEMENT:-0}" -eq 1 && "${PIPELINE_TEMP_PASS:-0}" -ne 1 ]]; then
        ## element / 发送至 element
        echo_msg time "to Element"
        python3 "$me_path_data_bin/element.py" "$msg_body"
    elif [[ "${ENV_NOTIFY_EMAIL:-0}" -eq 1 ]]; then
        ## email / 发送至 email
        # mogaal/sendemail: lightweight, command line SMTP email client
        # https://github.com/mogaal/sendemail
        echo_msg time "to Email"
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
        echo_msg "<skip>"
    fi
}

_renew_cert() {
    if [[ "${github_action:-0}" -eq 1 || "${arg_renew_cert:-0}" -eq 1 || "${PIPELINE_RENEW_CERT:-0}" -eq 1 ]]; then
        echo "PIPELINE_RENEW_CERT: ${PIPELINE_RENEW_CERT:-0}"
    else
        return 0
    fi
    echo_msg step "[cert] renew cert with acme.sh using dns+api"
    acme_home="${HOME}/.acme.sh"
    acme_cmd="${acme_home}/acme.sh"
    acme_cert="${acme_home}/${ENV_CERT_INSTALL:-dest}"
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
        [ -f "$account" ] || continue
        if [ -f "$conf_dns_cloudflare" ]; then
            if ! command -v flarectl; then
                echo_msg warning "command not found: flarectl "
                return 1
            fi
            source "$conf_dns_cloudflare" "${account##*.}"
            domains="$(flarectl zone list | awk '/active/ {print $3}')"
            dnsType='dns_cf'
        elif [ -f "$conf_dns_aliyun" ]; then
            if ! command -v aliyun; then
                echo_msg warning "command not found: aliyun "
                return 1
            fi
            source "$conf_dns_aliyun" "${account##*.}"
            aliyun configure set --profile "deploy${account##*.}" --mode AK --region "${Ali_region:-none}" --access-key-id "${Ali_Key:-none}" --access-key-secret "${Ali_Secret:-none}"
            domains="$(aliyun --profile "deploy${account##*.}" domain QueryDomainList --output cols=DomainName rows=Data.Domain --PageNum 1 --PageSize 100 | sed -e '1,2d' -e '/^$/d')"
            dnsType='dns_ali'
        elif [ -f "$conf_dns_qcloud" ]; then
            echo_msg warning "[TODO] use dnspod api."
        fi
        \cp -vf "$account" "${acme_home}/account.conf"
        ## single account may have multiple domains / 单个账号可能有多个域名
        for domain in ${domains}; do
            if [ -d "${acme_home}/$domain" ]; then
                ## renew cert / 续签证书
                "${acme_cmd}" --renew -d "${domain}" || true
            else
                ## create cert / 创建证书
                "${acme_cmd}" --issue --dns $dnsType -d "$domain" -d "*.$domain"
            fi
            "${acme_cmd}" --install-cert -d "$domain" --key-file "$acme_cert/$domain".key --fullchain-file "$acme_cert/$domain".crt
        done
    done

    ## Custom deployment method / 自定义部署方式
    if [ -f "${acme_home}"/custom.acme.sh ]; then
        echo "Found ${acme_home}/custom.acme.sh"
        bash "${acme_home}"/custom.acme.sh
    fi
    echo_msg stepend "[cert] renew cert with acme.sh using dns+api"
    [[ "${arg_renew_cert:-0}" -eq 1 || "${PIPELINE_RENEW_CERT:-0}" -eq 1 ]] && exit 0
}

_install_python_gitlab() {
    python3 -m pip list 2>/dev/null | grep -q python-gitlab && return
    echo_msg info "install python3 gitlab api..."
    python3 -m pip install --user --upgrade python-gitlab
}

_install_python_element() {
    python3 -m pip list 2>/dev/null | grep -q matrix-nio && return
    echo_msg info "install python3 element api..."
    python3 -m pip install --user --upgrade matrix-nio
}

_install_aliyun_cli() {
    command -v aliyun >/dev/null && return
    echo_msg info "install aliyun cli..."
    curl -Lo /tmp/aliyun.tgz https://aliyuncli.alicdn.com/aliyun-cli-linux-latest-amd64.tgz
    tar -C /tmp -zxf /tmp/aliyun.tgz
    # install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    install -m 0755 /tmp/aliyun "${me_path_data_bin}/aliyun"
}

_install_terraform() {
    command -v terraform >/dev/null && return
    echo_msg info "install terraform..."
    [[ $UID -eq 0 ]] || use_sudo=sudo
    $use_sudo apt-get update && $use_sudo apt-get install -y gnupg software-properties-common curl
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor | $use_sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" |
        $use_sudo tee /etc/apt/sources.list.d/hashicorp.list
    $use_sudo apt update && $use_sudo apt install -y terraform
    # terraform version
}

_install_aws() {
    command -v aws >/dev/null && return
    echo_msg info "install aws cli..."
    $curl_opt -o "awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    unzip -qq awscliv2.zip
    ./aws/install --bin-dir "${me_path_data_bin}" --install-dir "${me_path_data}" --update
    ## install eksctl / 安装 eksctl
    $curl_opt "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    mv /tmp/eksctl "${me_path_data_bin}/"
}

_install_kubectl() {
    command -v kubectl >/dev/null && return
    echo_msg info "install kubectl..."
    kube_ver="$($curl_opt --silent https://storage.googleapis.com/kubernetes-release/release/stable.txt)"
    kube_url="https://storage.googleapis.com/kubernetes-release/release/${kube_ver}/bin/linux/amd64/kubectl"
    $curl_opt -o "${me_path_data_bin}/kubectl" "$kube_url"
    chmod +x "${me_path_data_bin}/kubectl"
}

_install_helm() {
    command -v helm >/dev/null && return
    echo_msg info "install helm..."
    $curl_opt https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
}

_install_jmeter() {
    command -v jmeter >/dev/null && return
    echo_msg info "install jmeter..."
    ver_jmeter='5.4.1'
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
    $curl_opt --retry -C - -o "$path_temp"/jmeter.zip $url_jmeter
    (
        cd "$me_path_data"
        unzip "$path_temp"/jmeter.zip
        ln -sf apache-jmeter-${ver_jmeter} jmeter
    )
    rm -rf "$path_temp"
}

_install_flarectl() {
    command -v flarectl >/dev/null && return
    echo_msg info "install flarectl"
    local ver='0.52.0'
    path_temp=$(mktemp -d)
    $curl_opt -o "$path_temp"/flarectl.zip https://github.com/cloudflare/cloudflare-go/releases/download/v${ver}/flarectl_${ver}_linux_amd64.tar.xz
    tar xf "$path_temp"/flarectl.zip -C "${me_path_data_bin}/"
}

_detect_os() {
    if [[ "$UID" != 0 ]]; then
        exec_sudo=sudo
    fi
    if [[ -e /etc/debian_version ]]; then
        source /etc/os-release
        OS="${ID}" # debian or ubuntu
    elif [[ -e /etc/fedora-release ]]; then
        source /etc/os-release
        OS="${ID}"
    elif [[ -e /etc/centos-release ]]; then
        OS=centos
    elif [[ -e /etc/arch-release ]]; then
        OS=arch
    elif [[ -e /etc/os-release ]]; then
        source /etc/os-release
        OS="${ID}"
    else
        echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2 or Arch Linux system"
        echo_msg error "Not support. exit."
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
            # shellcheck disable=SC2086
            $exec_sudo apt-get install -qq -y $install_pkg >/dev/null
        fi
        command -v docker >/dev/null || (
            curl -fsSL https://get.docker.com -o get-docker.sh
            bash get-docker.sh
        )
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
        command -v docker >/dev/null || (
            curl -fsSL https://get.docker.com -o get-docker.sh
            bash get-docker.sh
        )
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
        command -v docker >/dev/null || (
            curl -fsSL https://get.docker.com -o get-docker.sh
            bash get-docker.sh
        )
        ;;
    *)
        echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2 or Arch Linux system"
        echo_msg error "Not support. exit."
        return 1
        ;;
    esac
}

_clean_disk() {
    ## clean cache of docker build / 清理 docker 构建缓存
    disk_usage="$(df / | awk 'NR>1 {print $5}' | sed 's/%//')"
    if ((disk_usage < 80)); then
        return 0
    fi
    echo_msg warning "Disk space is less than 80%, remove docker images"
    docker images "${ENV_DOCKER_REGISTRY}" -q | sort | uniq | xargs -I {} docker rmi -f {} || true
    docker system prune -f >/dev/null || true
}

# https://github.com/sherpya/geolite2legacy
# https://www.miyuru.lk/geoiplegacy
# https://github.com/leev/ngx_http_geoip2_module
get_maxmind_ip() {
    t="$(mktemp -d)"
    t1="$t/maxmind-Country.dat.gz"
    t2="$t/maxmind-City.dat.gz"
    $curl_opt -qs -o "$t1" https://dl.miyuru.lk/geoip/maxmind/country/maxmind.dat.gz
    $curl_opt -qs -o "$t2" https://dl.miyuru.lk/geoip/maxmind/city/maxmind.dat.gz
    gunzip "$t1" "$t2"
    for ip in ${ENV_NGINX_IPS:?undefine var}; do
        echo "$ip"
        rsync -av "${t}/" "root@$ip":/etc/nginx/conf.d/
    done
}

_generate_apidoc() {
    if [[ -f "${gitlab_project_dir}/apidoc.json" ]]; then
        echo_msg step "[apidoc] generate API Docs with apidoc"
        $docker_run -v "${gitlab_project_dir}":/app -w /app deploy/node bash -c "apidoc -i app/ -o public/apidoc/"
    fi
}

_inject_files() {
    echo_msg step "[inject] from runner/data/project_conf/"
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
    ## backend (PHP/Java/Python) project_conf files
    ## 方便运维人员替换项目内文件，例如 PHP 数据库配置等信息 .env 文件，例如 Java 数据库配置信息 yml 文件
    path_project_conf="${me_path_data}/project_conf/${gitlab_project_name}.${env_namespace}"
    if [ -d "$path_project_conf" ]; then
        echo_msg warning "found custom config files, sync it."
        rsync -av "$path_project_conf"/ "${gitlab_project_dir}"/
    fi
    ## from deploy.env， 使用全局模板文件替换项目文件
    # ENV_ENABLE_INJECT=1, 覆盖 [default action]
    # ENV_ENABLE_INJECT=2, 不覆盖 [使用项目自身的文件]
    # ENV_ENABLE_INJECT=3, 删除 Dockerfile [不使用 docker build]
    # ENV_ENABLE_INJECT=4, 创建 docker-compose.yml [使用 docker-compose 发布]
    echo ENV_ENABLE_INJECT: ${ENV_ENABLE_INJECT:-1}
    case ${ENV_ENABLE_INJECT:-1} in
    1)
        ## Java, 公用的模版文件 Dockerfile, run.sh, settings.xml
        if [[ -f "${me_path_data}/dockerfile/Dockerfile.${project_lang}" ]]; then
            echo "Overwritten from data/dockerfile/Dockerfile.${project_lang}"
            rsync -a "${me_path_data}/dockerfile/Dockerfile.${project_lang}" "${gitlab_project_dir}"/Dockerfile
        fi
        if [[ "$project_lang" == java && "$ENV_CHANGE_SOURCE" == true ]]; then
            curl -fsSLo "$gitlab_project_dir"/settings.xml https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/settings.xml
        fi
        ;;
    2)
        echo 'Not overwritten Dockerfile'
        ;;
    3)
        echo 'Remove Dockerfile (disable docker build)'
        rm -f "${gitlab_project_dir}"/Dockerfile
        ;;
    4)
        echo "Generate docker-compose.yml (enable deply with docker-compose)"
        echo '## deploy with docker-compose' >>"${gitlab_project_dir}"/docker-compose.yml
        ;;
    esac
    ## docker ignore file / 使用全局模板文件替换项目文件
    [[ -f "${gitlab_project_dir}/Dockerfile" && ! -f "${gitlab_project_dir}/.dockerignore" ]] &&
        rsync -av "${me_path_conf}/.dockerignore" "${gitlab_project_dir}/"
    ## cert file for nginx
    if [[ "${gitlab_project_name}" == *"$ENV_NGINX_GIT_NAME"* && -d "$me_path_data/.acme.sh/${ENV_CERT_INSTALL:-dest}/" ]]; then
        rsync -av "$me_path_data/.acme.sh/${ENV_CERT_INSTALL:-dest}/" "${gitlab_project_dir}/etc/nginx/conf.d/ssl/"
    fi
    ## flyway files sql & conf
    for sql in ${ENV_FLYWAY_SQL:-docs/sql} flyway_sql doc/sql sql; do
        path_flyway_sql_proj="${gitlab_project_dir}/$sql"
        if [[ -d "${path_flyway_sql_proj}" ]]; then
            exec_deploy_flyway=1
            copy_flyway_file=1
            break
        else
            exec_deploy_flyway=0
            copy_flyway_file=0
        fi
    done
    if [[ "${copy_flyway_file:-0}" -eq 1 ]]; then
        path_flyway_conf="$gitlab_project_dir/flyway_conf"
        path_flyway_sql="$gitlab_project_dir/flyway_sql"
        [[ -d "$path_flyway_sql_proj" && ! -d "$path_flyway_sql" ]] && rsync -a "$path_flyway_sql_proj/" "$path_flyway_sql/"
        [[ -d "$path_flyway_conf" ]] || mkdir -p "$path_flyway_conf"
        [[ -d "$path_flyway_sql" ]] || mkdir -p "$path_flyway_sql"
        [[ -f "${gitlab_project_dir}/Dockerfile.flyway" ]] || rsync -av "${me_dockerfile}/Dockerfile.flyway" "${gitlab_project_dir}/"
    fi
}

_setup_deploy_conf() {
    path_conf_ssh="${me_path_data}/.ssh"
    path_conf_acme="${me_path_data}/.acme.sh"
    path_conf_aws="${me_path_data}/.aws"
    path_conf_kube="${me_path_data}/.kube"
    path_conf_aliyun="${me_path_data}/.aliyun"
    conf_python_gitlab="${me_path_data}/.python-gitlab.cfg"
    ## ssh config and key files
    if [[ ! -d "${path_conf_ssh}" ]]; then
        mkdir -m 700 "$path_conf_ssh"
        echo_msg warning "Generate ssh key file for gitlab-runner: $path_conf_ssh/id_ed25519"
        echo_msg purple "Please: cat $path_conf_ssh/id_ed25519.pub >> [dest_server]:\~/.ssh/authorized_keys"
        ssh-keygen -t ed25519 -N '' -f "$path_conf_ssh/id_ed25519"
        [ -d "$HOME/.ssh" ] || ln -sf "$path_conf_ssh" "$HOME/"
    fi
    for file in "$path_conf_ssh"/*; do
        [ -f "$HOME/.ssh/${file##*/}" ] && continue
        if [ ! -d "$HOME"/.ssh ]; then
            mkdir "$HOME"/.ssh
            chmod 700 "$HOME"/.ssh
        fi
        echo "Link $file to $HOME/.ssh/"
        chmod 600 "${file}"
        ln -sf "${file}" "$HOME/.ssh/"
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
        [[ "${github_action:-0}" -eq 1 ]] && gitlab_commit_short_sha=${gitlab_commit_short_sha:-1234567}
        [[ "${debug_on:-0}" -eq 1 ]] && read -rp "Enter commit short hash: " -e -i 'xxxxxx' gitlab_commit_short_sha
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
        cron_save_file="$(find ${me_path_data} -name "crontab.${gitlab_project_id}.*" | head -n 1)"
        cron_save_id="${cron_save_file##*.}"
        if [[ "${gitlab_commit_short_sha}" == "$cron_save_id" ]]; then
            echo warning "no code change found, <skip>."
            exit 0
        else
            rm -f "${me_path_data}/crontab.${gitlab_project_id}".*
            touch "${me_path_data}/crontab.${gitlab_project_id}.${gitlab_commit_short_sha}"
        fi
    fi
}

_probe_langs() {
    echo_msg step "[langs] probe language"
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
    echo_msg step "[probe] probe deploy method"
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
            if [[ "$project_lang" =~ (java) ]]; then
                ## 使用本机目录缓存 maven ，可以加快 docker build 速度
                exec_build_langs=1
            else
                exec_build_langs=0
            fi
            exec_build_image=1
            exec_push_image=1
            exec_deploy_k8s=1
            exec_deploy_rsync_ssh=0
            ;;
        esac
    done
}

_svn_checkout_repo() {
    [[ "${arg_svn_co:-0}" -eq 1 ]] || return 0
    if [[ ! -d "$me_path_builds" ]]; then
        echo "Not found $me_path_builds, create it..."
        mkdir -p builds
    fi
    local path_git_clone="$me_path_builds/${arg_svn_co_url##*/}"
    echo 'Coming soon...'
}

_git_clone_repo() {
    [[ "${arg_git_clone:-0}" -eq 1 ]] || return 0
    if [[ ! -d "$me_path_builds" ]]; then
        echo "Not found $me_path_builds, create it..."
        mkdir -p builds
    fi
    local path_git_clone="$me_path_builds/${arg_git_clone_url##*/}"
    path_git_clone="${path_git_clone%.git}"
    if [ ! -d "$path_git_clone" ]; then
        echo "Clone git repo: $arg_git_clone_url"
        git clone "$arg_git_clone_url" "${path_git_clone}"
    fi
    # echo "\"$path_git_clone\" exists"
    cd "${path_git_clone}" || return 1
    if [[ -n "$arg_git_clone_branch" ]]; then
        git checkout "${arg_git_clone_branch}" || return 1
    fi
}

_create_k8s() {
    [[ "$create_k8s" -eq 1 ]] || return 0
    [ -d "$me_path_data/terraform" ] || return 0
    echo_msg step "[terraform] create k8s"
    cd "$me_path_data/terraform" && terraform init && terraform apply -auto-approve
    exit $?
}

_usage() {
    echo "
Usage: $0 [parameters ...]

Parameters:
    -h, --help               Show this help message.
    -v, --version            Show version info.
    -r, --renew-cert         Renew all the certs.
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
        --renew-cert | -r)
            arg_renew_cert=1 && exec_single=$((exec_single + 1))
            ;;
        --svn-co)
            arg_svn_co=1
            arg_svn_co_url="${2:?empty svn url}"
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
    me_yml="${me_path_data}/deploy.yml"        ## deploy to app server 发布到目标服务器的配置信息
    me_env="${me_path_data}/deploy.env"        ## deploy.sh ENV 发布配置信息(密)
    me_dockerfile="${me_path_conf}/dockerfile" ## deploy.sh dependent dockerfile

    [[ -f "$me_conf" ]] || cp "${me_path_conf}/example-deploy.conf" "$me_conf"
    [[ -f "$me_yml" ]] || cp "${me_path_conf}/example-deploy.yml" "$me_yml"
    [[ -f "$me_env" ]] || cp "${me_path_conf}/example-deploy.env" "$me_env"

    PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/usr/local/sbin:/snap/bin"
    PATH="$PATH:$me_path_data/jdk/bin:$me_path_data/jmeter/bin:$me_path_data/ant/bin:$me_path_data/maven/bin"
    PATH="$PATH:$me_path_bin:$me_path_data_bin:$HOME/.config/composer/vendor/bin:$HOME/.local/bin"
    export PATH

    docker_run="docker run --interactive --rm -u 1000:1000"
    # docker_run_root="docker run --interactive --rm -u 0:0"
    kubectl_opt="kubectl --kubeconfig $HOME/.kube/config"
    helm_opt="helm --kubeconfig $HOME/.kube/config"

    ## check OS version/type/install command/install software / 检查系统版本/类型/安装命令/安装软件
    _detect_os

    ## git clone repo / 克隆 git 仓库
    _git_clone_repo

    ## svn checkout repo / 克隆 svn 仓库
    _svn_checkout_repo

    ## run deploy.sh by hand / 手动执行 deploy.sh
    _setup_gitlab_vars

    ## source ENV, 获取 ENV_ 开头的所有全局变量
    source "$me_env"
    ## curl use proxy / curl 使用代理
    curl_opt="curl -L"
    ## demo mode: default docker login password / docker 登录密码
    if [[ "$ENV_DOCKER_PASSWORD" == 'your_password' && "$ENV_DOCKER_USERNAME" == 'your_username' ]]; then
        echo_msg purple "Found default username/password, skip docker login / push image / deploy k8s..."
        demo_mode=1
    fi
    image_tag="${gitlab_project_name}-${gitlab_commit_short_sha}-$(date +%s)"
    image_tag_flyway="${ENV_DOCKER_REGISTRY:?undefine}:${gitlab_project_name}-flyway-${gitlab_commit_short_sha}"
    ## install acme.sh/aws/kube/aliyun/python-gitlab/flarectl 安装依赖命令/工具
    [[ "${ENV_INSTALL_AWS}" == 'true' ]] && _install_aws
    [[ "${ENV_INSTALL_ALIYUN}" == 'true' ]] && _install_aliyun_cli
    [[ "${ENV_INSTALL_TERRAFORM}" == 'true' ]] && _install_terraform
    [[ "${ENV_INSTALL_KUBECTL}" == 'true' ]] && _install_kubectl
    [[ "${ENV_INSTALL_HELM}" == 'true' ]] && _install_helm
    [[ "${ENV_INSTALL_PYTHON_ELEMENT}" == 'true' ]] && _install_python_element
    [[ "${ENV_INSTALL_PYTHON_GITLAB}" == 'true' ]] && _install_python_gitlab
    [[ "${ENV_INSTALL_JMETER}" == 'true' ]] && _install_jmeter
    [[ "${ENV_INSTALL_FLARECTL}" == 'true' ]] && _install_flarectl

    ## create k8s
    _create_k8s

    ## clean up disk space / 清理磁盘空间
    _clean_disk

    ## setup ssh config/ acme.sh/aws/kube/aliyun/python-gitlab/cloudflare/rsync
    _setup_deploy_conf

    ## renew cert with acme.sh / 使用 acme.sh 重新申请证书
    _renew_cert

    ## probe program lang / 探测程序语言
    _probe_langs

    ## preprocess project config files / 预处理业务项目配置文件
    _inject_files

    ## probe deploy method / 探测文件确定发布方法
    _probe_deploy_method

    ## code style check / 代码风格检查
    code_style_sh="$me_path/langs/style.${project_lang}.sh"

    ## code build / 代码编译打包
    build_langs_sh="$me_path/langs/build.${project_lang}.sh"

    ################################################################################
    ## exec single task / 执行单个任务，适用于gitlab-ci/jenkins等自动化部署工具的单个job任务执行
    if [[ "${exec_single:-0}" -gt 0 ]]; then
        [[ "${arg_code_quality:-0}" -eq 1 ]] && _code_quality_sonar
        [[ "${arg_code_style:-0}" -eq 1 && -f "$code_style_sh" ]] && source "$code_style_sh"
        [[ "${arg_test_unit:-0}" -eq 1 ]] && _test_unit
        # [[ "${exec_deploy_flyway:-0}" -eq 1 ]] && _deploy_flyway_helm_job
        _deploy_flyway_docker
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
    _code_quality_sonar

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_CODE_STYLE ，1 启用[default]，0 禁用
    echo_msg step "[style] check code style"
    echo "PIPELINE_CODE_STYLE: ${PIPELINE_CODE_STYLE:-0}"
    if [[ "${PIPELINE_CODE_STYLE:-0}" -eq 1 && -f "$code_style_sh" ]]; then
        source "$code_style_sh"
    else
        echo '<skip>'
    fi

    _test_unit

    ## use flyway deploy sql file / 使用 flyway 发布 sql 文件
    # [[ "${exec_deploy_flyway:-0}" -eq 1 ]] && _deploy_flyway_helm_job
    _deploy_flyway_docker

    ## generate api docs
    # _generate_apidoc

    ## build
    [[ "${exec_build_langs:-1}" -eq 1 && -f "$build_langs_sh" ]] && source "$build_langs_sh"
    [[ "${exec_build_image:-0}" -eq 1 ]] && _build_image_docker
    # [[ "${exec_build_image:-0}" -eq 1 ]] && _build_image_podman

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
    [[ "$ENV_DISABLE_RSYNC" -eq 1 ]] && exec_deploy_rsync_ssh=0
    [[ "${exec_deploy_rsync_ssh:-1}" -eq 1 ]] && _deploy_rsync_ssh

    _test_function
    _scan_ZAP
    _scan_vulmap

    ## deploy notify info / 发布通知信息
    ## 发送消息到群组, exec_deploy_notify， 0 不发， 1 发.
    [[ "${github_action:-0}" -eq 1 ]] && deploy_result=0
    [[ "${deploy_result}" -eq 1 ]] && exec_deploy_notify=1
    [[ "$ENV_DISABLE_MSG" -eq 1 ]] && exec_deploy_notify=0
    [[ "$ENV_DISABLE_MSG_BRANCH" =~ $gitlab_project_branch ]] && exec_deploy_notify=0
    [[ "${exec_deploy_notify:-1}" -eq 1 ]] && _deploy_notify

    ## deploy result:  0 成功， 1 失败
    return ${deploy_result:-0}
}

main "$@"
