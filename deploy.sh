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
    case "$1" in
    red | error | erro)
        color_on='\033[0;31m' # Red
        ;;
    green | info)
        color_on='\033[0;32m' # Green
        ;;
    yellow | warning | warn)
        color_on='\033[0;33m' # Yellow
        ;;
    blue)
        color_on='\033[0;34m' # Blue
        ;;
    purple | question | ques)
        color_on='\033[0;35m' # Purple
        ;;
    cyan)
        color_on='\033[0;36m' # Cyan
        ;;
    time)
        color_on="[$(date +%Y%m%d-%T-%u)], "
        color_off=''
        ;;
    step | timestep)
        color_on="\033[33m[$(date +%Y%m%d-%T-%u)] step-$((STEP + 1)), \033[0m"
        STEP=$((STEP + 1))
        color_off=''
        ;;
    esac
    shift
    echo -e "${color_on}$*${color_off}"
}

echo_info() { echo -e "\033[32m$*\033[0m"; }        ## green
echo_warn() { echo -e "\033[33m$*\033[0m"; }        ## yellow
echo_erro() { echo -e "\033[31m$*\033[0m"; }        ## red
echo_ques() { echo -e "\033[35m$*\033[0m"; }        ## purple
echo_time() { echo "[$(date +%Y%m%d-%T-%u)], $*"; } ## time
echo_time_step() { echo -e "\033[33m[$(date +%Y%m%d-%T-%u)] step-$((STEP + 1)),\033[0m $*" && STEP=$((STEP + 1)); }

## year month day - time - %u day of week (1..7); 1 is Monday - %j day of year (001..366) - %W week number of year, with Monday as first day of week (00..53)

## install phpunit
_test_unit() {
    echo_time_step "unit test..."
    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_UNIT_TEST ，1 启用[default]，0 禁用
    echo "PIPELINE_UNIT_TEST: ${PIPELINE_UNIT_TEST:-0}"
    [[ "${PIPELINE_UNIT_TEST:-0}" -eq 0 ]] && return 0

    if [[ -f "$gitlab_project_dir"/tests/unit_test.sh ]]; then
        echo "Found $gitlab_project_dir/tests/unit_test.sh"
        bash "$gitlab_project_dir"/tests/unit_test.sh
    elif [[ -f "$script_path_data"/tests/unit_test.sh ]]; then
        echo "Found $script_path_data/tests/unit_test.sh"
        bash "$script_path_data"/tests/unit_test.sh
    else
        echo_ques "not found tests/unit_test.sh, skip unit test."
    fi
    echo_time "end unit test."
}

## install jdk/ant/jmeter
_test_function() {
    echo_time_step "function test..."
    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_FUNCTION_TEST ，1 启用[default]，0 禁用
    echo "PIPELINE_FUNCTION_TEST: ${PIPELINE_FUNCTION_TEST:-1}"
    [[ "${PIPELINE_FUNCTION_TEST:-0}" -eq 0 ]] && return 0

    if [ -f "$gitlab_project_dir"/tests/func_test.sh ]; then
        echo "Found $gitlab_project_dir/tests/func_test.sh"
        bash "$gitlab_project_dir"/tests/func_test.sh
    elif [ -f "$script_path_data"/tests/func_test.sh ]; then
        echo "Found $script_path_data/tests/func_test.sh"
        bash "$script_path_data"/tests/func_test.sh
    else
        echo_ques "not found tests/func_test.sh, skip function test."
    fi
    echo_time "end function test."
}

_code_quality_sonar() {
    echo_time_step "code quality [sonarqube scanner]..."
    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_SONAR ，1 启用，0 禁用[default]
    echo "PIPELINE_SONAR: ${PIPELINE_SONAR:-0}"
    [[ "${PIPELINE_SONAR:-0}" -eq 0 ]] && return 0

    sonar_url="${ENV_SONAR_URL:?empty}"
    sonar_conf="$gitlab_project_dir/sonar-project.properties"
    if ! curl "$sonar_url" >/dev/null 2>&1; then
        echo_warn "Could not found sonarqube server, exit."
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
    echo_time "end code quality [sonarqube scanner]."
    exit
}

_scan_ZAP() {
    echo_time_step "[TODO] scan [ZAP]..."
    # docker pull owasp/zap2docker-stable
}

_scan_vulmap() {
    echo_time_step "[TODO] scan [vulmap]..."
}

_deploy_flyway_docker() {
    echo_time_step "deploy SQL [flyway]..."
    flyway_conf_volume="${gitlab_project_dir}/flyway_conf:/flyway/conf"
    flyway_sql_volume="${gitlab_project_dir}/flyway_sql:/flyway/sql"
    flyway_docker_run="docker run --rm -v ${flyway_conf_volume} -v ${flyway_sql_volume} flyway/flyway"

    ## ssh port-forward mysql 3306 to localhost / 判断是否需要通过 ssh 端口转发建立数据库远程连接
    [ -f "$script_path_bin/ssh-port-forward.sh" ] && source "$script_path_bin/ssh-port-forward.sh" port
    ## exec flyway
    if $flyway_docker_run info | grep '^|' | grep -vE 'Category.*Version|Versioned.*Success|Versioned.*Deleted|DELETE.*Success'; then
        $flyway_docker_run repair
        $flyway_docker_run migrate || deploy_result=1
        $flyway_docker_run info | tail -n 10
    else
        echo "Nothing to do."
    fi
    if [ ${deploy_result:-0} = 0 ]; then
        echo_info "Result = OK"
    else
        echo_erro "Result = FAIL"
    fi
    echo_time "end deploy database [flyway]."
}

_deploy_flyway_helm_job() {
    ## docker build flyway
    echo "$image_tag_flyway"
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    DOCKER_BUILDKIT=1 docker build ${quiet_flag} --tag "${image_tag_flyway}" -f "${gitlab_project_dir}/Dockerfile.flyway" "${gitlab_project_dir}/"
    docker run --rm "$image_tag_flyway" || deploy_result=1
    if [ ${deploy_result:-0} = 0 ]; then
        echo_info "Result = OK"
    else
        echo_erro "Result = FAIL"
    fi
}

# python-gitlab list all projects / 列出所有项目
# gitlab -v -o yaml -f path_with_namespace project list --all |awk -F': ' '{print $2}' |sort >p.txt
# 解决 Encountered 1 file(s) that should have been pointers, but weren't
# git lfs migrate import --everything$(awk '/filter=lfs/ {printf " --include='\''%s'\''", $1}' .gitattributes)

_docker_login() {
    local lock_docker_login="$script_path_data/.lock.docker.login.${ENV_DOCKER_LOGIN_TYPE:-none}"
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    if [[ "${ENV_DOCKER_LOGIN_TYPE:-none}" == 'aws' ]]; then
        # time_last="$(if [[ -f "$lock_docker_login" ]]; then cat "$lock_docker_login"; else echo 0; fi)"
        time_last="$(stat -t -c %Y "$lock_docker_login")"
        ## Compare the last login time, log in again after 12 hours / 比较上一次登陆时间，超过12小时则再次登录
        [[ "$(date +%s -d '12 hours ago')" -lt "${time_last:-0}" ]] && return 0
        echo_time "docker login [${ENV_DOCKER_LOGIN_TYPE:-none}]..."
        str_docker_login="docker login --username AWS --password-stdin ${ENV_DOCKER_REGISTRY%%/*}"
        aws ecr get-login-password --profile="${ENV_AWS_PROFILE}" --region "${ENV_REGION_ID:?undefine}" | $str_docker_login >/dev/null
    else
        if [[ "${demo_mode:-0}" == 1 ]]; then
            echo_ques "Demo mode, skip docker login."
            return 0
        fi
        [[ -f "$lock_docker_login" ]] && return 0
        echo "${ENV_DOCKER_PASSWORD}" | docker login --username="${ENV_DOCKER_USERNAME}" --password-stdin "${ENV_DOCKER_REGISTRY%%/*}"
    fi
    touch "$lock_docker_login"
}

_build_image_docker() {
    echo_time_step "build image [docker]..."
    _docker_login

    ## Docker build from template image / 是否从模板构建
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    ## When the image does not exist, build the image / 判断模版是否存在,模版不存在，构建模板
    # if [ -n "$build_image_from" ]; then
    #     docker images | grep -q "${build_image_from%%:*}.*${build_image_from##*:}" ||
    #         DOCKER_BUILDKIT=1 docker build ${quiet_flag} --tag "${build_image_from}" --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE}" \
    #             -f "${gitlab_project_dir}/Dockerfile.${build_image_from##*:}" "${gitlab_project_dir}"
    # fi

    ## docker build flyway image / 构建 flyway 模板
    if [[ "$ENV_FLYWAY_HELM_JOB" -eq 1 ]]; then
        DOCKER_BUILDKIT=1 docker build ${quiet_flag} --tag "${image_tag_flyway}" -f "${gitlab_project_dir}/Dockerfile.flyway" "${gitlab_project_dir}/"
    fi
    ## docker build
    [ -d "${gitlab_project_dir}"/flyway_conf ] && rm -rf "${gitlab_project_dir}"/flyway_conf
    [ -d "${gitlab_project_dir}"/flyway_sql ] && rm -rf "${gitlab_project_dir}"/flyway_sql
    DOCKER_BUILDKIT=1 docker build ${quiet_flag} --tag "${ENV_DOCKER_REGISTRY}:${image_tag}" \
        --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE:-false}" "${gitlab_project_dir}"
    echo_time "end docker build image."
}

_build_image_podman() {
    echo_time_step "[TODO] build image [podman]..."
}

_push_image() {
    echo_time_step "push image [docker]..."
    _docker_login
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    if [[ "$demo_mode" == 1 ]]; then
        echo_ques "Demo mode, skip push image."
        return 0
    fi
    docker push ${quiet_flag} "${ENV_DOCKER_REGISTRY}:${image_tag}" || echo_erro "got an error here, probably caused by network..."
    if [[ "$ENV_FLYWAY_HELM_JOB" -eq 1 ]]; then
        docker push ${quiet_flag} "$image_tag_flyway"
    fi
    echo_time "end docker push image."
}

_deploy_k8s() {
    echo_time_step "deploy k8s [helm]..."
    if [[ "${ENV_REMOVE_PROJ_PREFIX:-false}" == 'true' ]]; then
        echo "remove project prefix."
        helm_release=${gitlab_project_name#*-}
    else
        helm_release=${gitlab_project_name}
    fi
    ## Convert to lower case / 转换为小写
    helm_release="${helm_release,,}"
    ## finding helm files folder / 查找 helm 文件目录
    if [ -d "${script_path_data}/helm/${gitlab_project_name}" ]; then
        path_helm="${script_path_data}/helm/${gitlab_project_name}"
        echo "Found $path_helm"
    elif [ -d "$gitlab_project_dir/helm" ]; then
        path_helm="$gitlab_project_dir/helm"
        echo "Found $path_helm"
    fi

    if [[ "$ENV_BRANCH_GITOPS" =~ $gitlab_project_branch ]]; then
        ## update gitops files / 更新 gitops 文件
        file_gitops="$script_path_data"/gitops_${gitlab_project_branch}/helm/${gitlab_project_name}/values.yaml
        if [ -f "$file_gitops" ]; then
            echo "Found $file_gitops"
            echo_time_step "update gitops files [helm]..."
            echo_ques "Note: only update 'gitops', skip deploy to k8s."
            sed -i \
                -e "s@repository:.*@repository:\ \"${ENV_DOCKER_REGISTRY_GITOPS:-registry}/${ENV_DOCKER_REPO_GITOPS:-repo}\"@" \
                -e "s@tag:.*@tag:\ \"${image_tag}\"@" \
                "$file_gitops"
            (
                cd "$script_path_data/gitops_$gitlab_project_branch"
                if [ -f "$ENV_GITOPS_SSH_KEY" ]; then
                    GIT_SSH_COMMAND="ssh -i $ENV_GITOPS_SSH_KEY" git pull
                    git add .
                    git commit -m "gitops files $gitlab_project_name"
                    GIT_SSH_COMMAND="ssh -i $ENV_GITOPS_SSH_KEY" git push origin "$gitlab_project_branch"
                else
                    git pull
                    git add .
                    git commit -m "gitops files $gitlab_project_name"
                    git push origin "$gitlab_project_branch"
                fi

            )
        else
            echo_ques "Not found: $file_gitops, skip update gitops files."
        fi
        [[ "${ENV_ENABLE_HELM_AFTER_GITOPS:-1}" -eq 0 ]] && return 0
    fi

    if [ -z "$path_helm" ]; then
        echo_ques "Not found helm files, skip deploy k8s."
        ## Custom deployment method / 自定义部署方式
        [ -f "$script_path_bin/custom-deploy.sh" ] && source "$script_path_bin/custom-deploy.sh" "$env_namespace"
    else
        set -x
        $helm_opt upgrade "${helm_release}" "$path_helm/" --install --history-max 1 \
            --namespace "${env_namespace}" --create-namespace \
            --set image.repository="${ENV_DOCKER_REGISTRY}" \
            --set image.tag="${image_tag}" \
            --set image.pullPolicy='Always' >/dev/null
        [[ "${debug_on:-0}" -ne 1 ]] && set +x
        ## Clean up rs 0 0 / 清理 rs 0 0
        $kubectl_opt -n "${env_namespace}" get rs | awk '/.*0\s+0\s+0/ {print $1}' | xargs $kubectl_opt -n "${env_namespace}" delete rs >/dev/null 2>&1 || true
        $kubectl_opt -n "${env_namespace}" get pod | grep Evicted | awk '{print $1}' | xargs $kubectl_opt -n "${env_namespace}" delete pod 2>/dev/null || true
        sleep 3
        $kubectl_opt -n "${env_namespace}" rollout status deployment "${helm_release}" || deploy_result=1
    fi

    ## install flyway jobs / 安装 flyway 任务
    if [[ "$ENV_FLYWAY_HELM_JOB" == 1 && -d "${script_path_conf}"/helm/flyway ]]; then
        $helm_opt upgrade flyway "${script_path_conf}/helm/flyway/" --install --history-max 1 \
            --namespace "${env_namespace}" --create-namespace \
            --set image.repository="${ENV_DOCKER_REGISTRY}" \
            --set image.tag="${gitlab_project_name}-flyway-${gitlab_commit_short_sha}" \
            --set image.pullPolicy='Always' >/dev/null
    fi
    echo_time "end deploy k8s [helm]."
}

_deploy_rsync_ssh() {
    echo_time_step "deploy code file [rsync+ssh]..."
    ## read conf, get project,branch,jar/war etc. / 读取配置文件，获取 项目/分支名/war包目录
    # grep "^${gitlab_project_path}\s\+${env_namespace}" "$script_conf" | while read -r line; do
    # for line in $(grep "^${gitlab_project_path}\s\+${env_namespace}" "$script_conf"); do
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
        echo "${ssh_host:?if stop here, check runner/conf/deploy.conf}"
        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=10 -p ${ssh_port:-22}"
        ## rsync exclude some files / rsync 排除某些文件
        if [[ -f "${gitlab_project_dir}/rsync.exclude" ]]; then
            rsync_exclude="${gitlab_project_dir}/rsync.exclude"
        else
            rsync_exclude="${script_path_conf}/rsync.exclude"
        fi
        ## node/java use rsync --delete / node/java 使用 rsync --delete
        [[ "${project_lang}" =~ (node|java|other) ]] && rsync_delete='--delete'
        rsync_opt="rsync -acvzt --exclude=.svn --exclude=.git --timeout=10 --no-times --exclude-from=${rsync_exclude} $rsync_delete"

        ## rsync source folder / rsync 源目录
        if [[ "$rsync_src" == 'null' || -z "$rsync_src" ]]; then
            # shellcheck disable=2154
            rsync_src="${gitlab_project_dir}/$path_for_rsync"
        elif [[ "$rsync_src" =~ \.[jw]ar$ ]]; then
            find_file="$(find "${gitlab_project_dir}" -name "$rsync_src" -print0 | head -n 1)"
            if [[ "$find_file" =~ \.[jw]ar$ ]]; then
                rsync_src="$find_file"
            else
                echo "Not found: ${find_file}"
                return 1
            fi
        fi
        ## rsycn dest folder / rsync 目标目录
        if [[ "$rsync_dest" == 'null' || -z "$rsync_dest" ]]; then
            rsync_dest="${ENV_PATH_DEST_PRE}/${env_namespace}.${gitlab_project_name}/"
        fi
        ## deploy to aliyun oss / 发布到 aliyun oss 存储
        if [[ "${rsync_dest}" =~ 'oss://' ]]; then
            command -v aliyun >/dev/null || echo_warn "command not exist: aliyun"
            aliyun oss cp "${rsync_src}/" "$rsync_dest/" --recursive --force
            ## 如果使用 rclone， 则需要安装和配置
            # rclone sync "${gitlab_project_dir}/" "$rsync_dest/"
            return
        fi
        $ssh_opt -n "${ssh_host}" "[[ -d $rsync_dest ]] || mkdir -p $rsync_dest"
        ## rsync to remote server / rsync 到远程服务器
        echo "deploy to ${ssh_host}:${rsync_dest}"
        ${rsync_opt} -e "$ssh_opt" "${rsync_src}" "${ssh_host}:${rsync_dest}"
    done < <(grep "^${gitlab_project_path}\s\+${env_namespace}" "$script_conf")
    echo_time "end deploy code file [rsync+ssh]."
}

_deploy_rsync() {
    echo_time_step "[TODO] deploy code file [rsyncd]..."
}

_deploy_ftp() {
    echo_time_step "[TODO] deploy code file [ftp]..."
}

_deploy_sftp() {
    echo_time_step "[TODO] deploy code file [sftp]..."
}

_deploy_notify_msg() {
    msg_describe="${msg_describe:-$(git --no-pager log --no-merges --oneline -1 || true)}"

    msg_body="
[Gitlab Deploy]
Project = ${gitlab_project_path}
Branche = ${gitlab_project_branch}
Pipeline = ${gitlab_pipeline_id}/JobID=$gitlab_job_id
Describe = [${gitlab_commit_short_sha}]/${msg_describe}
Who = ${gitlab_user_id}/${gitlab_username}
Result = $([ "${deploy_result:-0}" = 0 ] && echo OK || echo FAIL)
$(if [ -n "${test_result}" ]; then echo "Test_Result: ${test_result}" else :; fi)
"
}

_deploy_notify() {
    echo_time_step "deploy notify message [chat/email]..."

    _deploy_notify_msg

    if [[ "${ENV_NOTIFY_WEIXIN:-0}" -eq 1 ]]; then
        weixin_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${ENV_WEIXIN_KEY:?undefine var}"
        curl -s "$weixin_api" -H 'Content-Type: application/json' \
            -d "
        {
            \"msgtype\": \"text\",
            \"text\": {
                \"content\": \"$msg_body\"
            }
        }"
    elif [[ "${ENV_NOTIFY_TELEGRAM:-0}" -eq 1 ]]; then
        telegram_api_msg="https://api.telegram.org/bot${ENV_API_KEY_TG:?undefine var}/sendMessage"
        # telegram_api_doc="https://api.telegram.org/bot${ENV_API_KEY_TG:?undefine var}/sendDocument"
        msg_body="$(echo "$msg_body" | sed -e ':a;N;$!ba;s/\n/%0a/g' -e 's/&/%26/g')"
        $curl_opt -sS -o /dev/null -X POST -d "chat_id=${ENV_TG_GROUP_ID:?undefine var}&text=$msg_body" "$telegram_api_msg"
    elif [[ "${PIPELINE_TEMP_PASS:-0}" -eq 1 ]]; then
        python3 "$script_path_bin/element-up.py" "$msg_body"
    elif [[ "${ENV_NOTIFY_ELEMENT:-0}" -eq 1 && "${PIPELINE_TEMP_PASS:-0}" -ne 1 ]]; then
        python3 "$script_path_bin/element.py" "$msg_body"
    elif [[ "${ENV_NOTIFY_EMAIL:-0}" -eq 1 ]]; then
        # mogaal/sendemail: lightweight, command line SMTP email client
        # https://github.com/mogaal/sendemail
        "$script_path_bin/sendEmail" \
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
        echo_warn "skip message send."
    fi
}

_renew_cert() {
    echo_time_step "renew cert [dns api]..."
    acme_home="${HOME}/.acme.sh"
    acme_cmd="${acme_home}/acme.sh"
    acme_cert="${acme_home}/${ENV_CERT_INSTALL:-dest}"
    conf_dns_cloudflare="${script_path_data}/.cloudflare.conf"
    conf_dns_aliyun="${script_path_data}/.aliyun.dnsapi.conf"
    conf_dns_qcloud="${script_path_data}/.qcloud.dnspod.conf"

    ## install acme.sh / 安装 acme.sh
    [[ -x "${acme_cmd}" ]] || curl https://get.acme.sh | sh -s email=deploy@deploy.sh

    [ -d "$acme_cert" ] || mkdir -p "$acme_cert"
    ## support multiple account.conf.[x] / 支持多账号,只有一个则 account.conf.1
    if [[ "$(find "${acme_home}" -name 'account.conf*' | wc -l)" == 1 ]]; then
        cp -vf "${acme_home}/"account.conf "${acme_home}/"account.conf.1
    fi

    ## According to multiple different account files, loop renewal / 根据多个不同的账号文件,循环续签
    for account in "${acme_home}/"account.conf.*; do
        [ -f "$account" ] || continue
        if [ -f "$conf_dns_cloudflare" ]; then
            command -v flarectl || return 1
            source "$conf_dns_cloudflare" "${account##*.}"
            domain_name="$(flarectl zone list | awk '/active/ {print $3}')"
            dnsType='dns_cf'
        elif [ -f "$conf_dns_aliyun" ]; then
            command -v aliyun || return 1
            source "$conf_dns_aliyun" "${account##*.}"
            aliyun configure set --profile "deploy${account##*.}" --mode AK --region "${Ali_region:-none}" --access-key-id "${Ali_Key:-none}" --access-key-secret "${Ali_Secret:-none}"
            domain_name="$(aliyun domain QueryDomainList --output cols=DomainName rows=Data.Domain --PageNum 1 --PageSize 100 | sed '1,2d')"
            dnsType='dns_ali'
        elif [ -f "$conf_dns_qcloud" ]; then
            echo_warn "[TODO] use dnspod api."
        fi
        \cp -vf "$account" "${acme_home}/account.conf"
        ## single account may have multiple domains / 单个账号可能有多个域名
        for domain in ${domain_name}; do
            if [ -d "${acme_home}/$domain" ]; then
                "${acme_cmd}" --renew -d "${domain}" || true
            else
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
    echo_time "end renew cert."
    # [[ "${github_action:-0}" -eq 1 ]] || exit
}

_install_python_gitlab() {
    python3 -m pip list 2>/dev/null | grep -q python-gitlab || python3 -m pip install --user --upgrade python-gitlab
}

_install_python_element() {
    python3 -m pip list 2>/dev/null | grep -q matrix-nio || python3 -m pip install --user --upgrade matrix-nio
}

_install_aws() {
    command -v aws >/dev/null && return
    $curl_opt -o "awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    unzip -qq awscliv2.zip
    ./aws/install --bin-dir "${script_path_bin}" --install-dir "${script_path_data}" --update
    ## install eksctl / 安装 eksctl
    $curl_opt "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    mv /tmp/eksctl "${script_path_bin}/"
}

_install_kubectl() {
    command -v kubectl >/dev/null && return
    kube_ver="$($curl_opt --silent https://storage.googleapis.com/kubernetes-release/release/stable.txt)"
    kube_url="https://storage.googleapis.com/kubernetes-release/release/${kube_ver}/bin/linux/amd64/kubectl"
    $curl_opt -o "${script_path_bin}/kubectl" "$kube_url"
    chmod +x "${script_path_bin}/kubectl"
}

_install_helm() {
    command -v helm >/dev/null || $curl_opt https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
}

_install_jmeter() {
    ver_jmeter='5.4.1'
    path_temp=$(mktemp -d)
    ## 6. Asia, 31. Hong_Kong, 70. Shanghai
    if ! command -v java >/dev/null; then
        {
            echo 6
            echo 70
        } | $exec_sudo apt-get install -y openjdk-16-jdk
    fi
    $curl_opt -o "$path_temp"/jmeter.zip https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${ver_jmeter}.zip
    (
        cd "$script_path_data"
        unzip "$path_temp"/jmeter.zip
        ln -sf apache-jmeter-${ver_jmeter} jmeter
    )
    rm -rf "$path_temp"
}

_install_flarectl() {
    command -v flarectl >/dev/null && return
    ver_flarectl='0.28.0'
    path_temp=$(mktemp -d)
    $curl_opt -o "$path_temp"/flarectl.zip https://github.com/cloudflare/cloudflare-go/releases/download/v${ver_flarectl}/flarectl_${ver_flarectl}_linux_amd64.tar.xz
    tar xf "$path_temp"/flarectl.zip -C "${script_path_bin}/"
}

_detect_os() {
    if [[ $UID == 0 ]]; then
        exec_sudo=
    else
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
    else
        echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2 or Arch Linux system"
        echo "Not support. exit."
        exit 1
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
    *)
        echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2 or Arch Linux system"
        echo "Not support. exit."
        exit 1
        ;;
    esac
}

_clean_disk() {
    ## clean cache of docker build / 清理 docker 构建缓存
    disk_usage="$(df / | awk 'NR>1 {print $5}')"
    disk_usage="${disk_usage/\%/}"
    if ((disk_usage < 80)); then
        return
    fi
    echo "Disk space is less than 80%, run clean_disk"
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
        echo_time_step "generate API Docs [apidoc]..."
        $docker_run -v "${gitlab_project_dir}":/app -w /app deploy/node bash -c "apidoc -i app/ -o public/apidoc/"
    fi
}

_preprocess_file() {
    echo_time "preprocessing [env/config...]..."
    ## frontend (VUE) .env file
    if [[ "$project_lang" =~ (node) ]]; then
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
    path_project_conf="${script_path_data}/project_conf/${env_namespace}.${gitlab_project_name}/"
    [ -d "$path_project_conf" ] && rsync -av "$path_project_conf" "${gitlab_project_dir}/"
    ## docker ignore file
    [ -f "${gitlab_project_dir}/.dockerignore" ] || rsync -av "${script_path_conf}/.dockerignore" "${gitlab_project_dir}/"
    ## cert file for nginx
    if [[ "${gitlab_project_name}" == "$ENV_NGINX_GIT_NAME" && -d "$HOME/.acme.sh/${ENV_CERT_INSTALL:-dest}/" ]]; then
        rsync -av "$HOME/.acme.sh/${ENV_CERT_INSTALL:-dest}/" "${gitlab_project_dir}/etc/nginx/conf.d/ssl/"
    fi
    ## Docker build from / 是否从模板构建
    if [[ "${project_docker}" -eq 1 && -n "$build_image_from" ]]; then
        file_docker_tmpl="${script_dockerfile}/Dockerfile.${build_image_from##*:}"
        [ -f "${file_docker_tmpl}" ] && rsync -av "${file_docker_tmpl}" "${gitlab_project_dir}/"
    fi
    ## flyway files sql & conf
    for sql in ${ENV_FLYWAY_SQL:-docs/sql} flyway_sql doc/sql sql; do
        if [[ -d "${gitlab_project_dir}/$sql" ]]; then
            path_flyway_sql_proj="${gitlab_project_dir}/$sql"
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
        [[ -f "${gitlab_project_dir}/Dockerfile.flyway" ]] || rsync -av "${script_dockerfile}/Dockerfile.flyway" "${gitlab_project_dir}/"
    fi
    echo_time "end preprocessing preprocessing [env/config...]."
}

_setup_deploy_conf() {
    path_conf_ssh="${script_path_data}/.ssh"
    path_conf_acme="${script_path_data}/.acme.sh"
    path_conf_aws="${script_path_data}/.aws"
    path_conf_kube="${script_path_data}/.kube"
    path_conf_aliyun="${script_path_data}/.aliyun"
    conf_python_gitlab="${script_path_data}/.python-gitlab.cfg"
    ## ssh config and key files
    if [[ ! -d "${path_conf_ssh}" ]]; then
        mkdir -m 700 "$path_conf_ssh"
        echo_warn "Generate ssh key file for gitlab-runner: $path_conf_ssh/id_ed25519"
        echo_erro "Please: cat $path_conf_ssh/id_ed25519.pub >> [dest_server]:\~/.ssh/authorized_keys"
        ssh-keygen -t ed25519 -N '' -f "$path_conf_ssh/id_ed25519"
        [ -d "$HOME/.ssh" ] || ln -sf "$path_conf_ssh" "$HOME/"
    fi
    for file in "$path_conf_ssh"/*; do
        if [ ! -f "$HOME/.ssh/${file##*/}" ]; then
            echo "link $file to $HOME/.ssh/"
            chmod 600 "${file}"
            ln -sf "${file}" "$HOME/.ssh/"
        fi
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
        [[ "${github_action:-0}" -eq 1 ]] && gitlab_commit_short_sha=${gitlab_commit_short_sha:-7d30547}
        [[ "${debug_on:-0}" -eq 1 ]] && read -rp "Enter commit short hash: " -e -i 'xxxxxx' gitlab_commit_short_sha
    fi
    # read -rp "Enter gitlab project id: " -e -i '1234' gitlab_project_id
    # gitlab_project_id=${CI_PROJECT_ID:-1234}
    # read -t 5 -rp "Enter gitlab pipeline id: " -e -i '3456' gitlab_pipeline_id
    gitlab_pipeline_id=${CI_PIPELINE_ID:-3456}
    # read -rp "Enter gitlab job id: " -e -i '5678' gitlab_job_id
    gitlab_job_id=${CI_JOB_ID:-5678}
    # read -rp "Enter gitlab user id: " -e -i '1' gitlab_user_id
    gitlab_user_id=${GITLAB_USER_ID:-1}
    gitlab_username="$(gitlab -v user get --id "${gitlab_user_id}" | awk '/^name:/ {print $2}' || true)"
    gitlab_username="${gitlab_username:-root}"
    env_namespace=$gitlab_project_branch
}

_detect_langs() {
    for f in Dockerfile composer.json package.json pom.xml requirements.txt README.md readme.md README.txt readme.txt; do
        if [[ -f "${gitlab_project_dir}"/${f} ]]; then
            case $f in
            Dockerfile)
                echo "Found Dockerfile, enable docker build and helm deploy. disable rsync+ssh."
                echo "PIPELINE_DISABLE_DOCKER: ${PIPELINE_DISABLE_DOCKER:-0}"
                if [[ "${PIPELINE_DISABLE_DOCKER:-0}" -eq 1 || "${ENV_DISABLE_DOCKER:-0}" -eq 1 ]]; then
                    echo "Force disable docker build and helm deploy, default enable rsync+ssh."
                    project_docker=0
                    exec_deploy_rsync_ssh=1
                else
                    project_docker=1
                    exec_build_image=1
                    exec_push_image=1
                    exec_deploy_k8s=1
                    exec_deploy_rsync_ssh=0
                    build_image_from="$(awk '/^FROM/ {print $2}' Dockerfile | grep "${ENV_DOCKER_REGISTRY}" | head -n 1)"
                fi
                ;;
            composer.json)
                echo "Found composer.json, detect lang: php"
                project_lang=php
                exec_build_langs=1
                break
                ;;
            package.json)
                echo "Found package.json, detect lang: node"
                project_lang=node
                exec_build_langs=1
                break
                ;;
            pom.xml)
                echo "Found pom.xml, detect lang: java"
                project_lang=java
                exec_build_langs=1
                break
                ;;
            requirements.txt)
                echo "Found requirements.txt, detect lang: python"
                project_lang=python
                break
                ;;
            *)
                project_lang=${project_lang:-$(awk -F= '/^project_lang/ {print $2}' "${gitlab_project_dir}"/${f} | head -n 1)}
                project_lang=${project_lang// /}
                project_lang=${project_lang,,}
                project_lang=${project_lang:-other}
                echo "Detect lang: $project_lang"
                break
                ;;
            esac
        fi
    done
}

_git_clone_repo() {
    if [[ ! -d "$script_path_builds" ]]; then
        echo "not found $script_path_builds, create it..."
        mkdir -p builds
    fi
    local path_git_clone="$script_path_builds/${arg_git_clone_url##*/}"
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

_usage() {
    echo "
Usage: $0 [parameters ...]

Parameters:
    -h, --help               Show this help message.
    -v, --version            Show version info.
    -r, --renew-cert         Renew all the certs.
    --git-clone  https://xxx.com/yyy/zzz.git      Clone git repo url, clone to builds/zzz.git
    --git-clone-branch  [dev|main] default \"main\"      git branch name
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
"
}

_process_args() {
    [[ "${PIPELINE_DEBUG:-0}" -eq 1 ]] && set -x
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
        --github-action)
            set -x
            debug_on=1
            quiet_flag=
            github_action=1
            ;;
        --renwe-cert | -r)
            arg_renew_cert=1
            exec_single=$((exec_single + 1))
            ;;
        --git-clone)
            arg_git_clone=1
            arg_git_clone_url="$2"
            shift
            ;;
        --git-clone-branch)
            arg_git_clone_branch="$2"
            shift
            ;;
        --code-style)
            arg_code_style=1
            exec_single=$((exec_single + 1))
            ;;
        --code-quality)
            arg_code_quality=1
            exec_single=$((exec_single + 1))
            ;;
        --build-langs)
            arg_build_langs=1
            exec_single=$((exec_single + 1))
            ;;
        --build-image)
            arg_build_image=1
            exec_single=$((exec_single + 1))
            ;;
        --push-image)
            arg_push_image=1
            exec_single=$((exec_single + 1))
            ;;
        --deploy-k8s)
            arg_deploy_k8s=1
            exec_single=$((exec_single + 1))
            ;;
        --deploy-flyway)
            # arg_deploy_flyway=1
            exec_single=$((exec_single + 1))
            ;;
        --deploy-rsync-ssh)
            arg_deploy_rsync_ssh=1
            exec_single=$((exec_single + 1))
            ;;
        --deploy-rsync)
            arg_deploy_rsync=1
            exec_single=$((exec_single + 1))
            ;;
        --deploy-ftp)
            arg_deploy_ftp=1
            exec_single=$((exec_single + 1))
            ;;
        --deploy-sftp)
            arg_deploy_sftp=1
            exec_single=$((exec_single + 1))
            ;;
        --test-unit)
            arg_test_unit=1
            exec_single=$((exec_single + 1))
            ;;
        --test-function)
            arg_test_function=1
            exec_single=$((exec_single + 1))
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
    ## Process parameters / 处理传入的参数
    _process_args "$@"

    script_name="$(basename "$0")"
    script_path="$(cd "$(dirname "$0")" && pwd)"
    script_path_conf="${script_path}/conf"
    script_path_bin="${script_path}/bin"
    script_path_builds="${script_path}/builds"
    script_path_data="${script_path}/data"              ## deploy.sh data folder
    script_conf="${script_path_conf}/deploy.conf"       ## deploy to app server 发布到目标服务器的配置信息
    script_env="${script_path_conf}/deploy.env"         ## deploy.sh ENV 发布配置信息(密)
    script_log="${script_path_data}/${script_name}.log" ## deploy.sh run loger
    script_dockerfile="${script_path_conf}/dockerfile"  ## deploy.sh dependent dockerfile

    [[ ! -f "$script_conf" ]] && cp "${script_path_conf}/example-deploy.conf" "$script_conf"
    [[ ! -f "$script_env" ]] && cp "${script_path_conf}/example-deploy.env" "$script_env"
    [[ ! -f "$script_log" ]] && touch "$script_log"

    PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/usr/local/sbin:/snap/bin"
    PATH="$PATH:$script_path_data/jdk/bin:$script_path_data/jmeter/bin:$script_path_data/ant/bin:$script_path_data/maven/bin"
    PATH="$PATH:$script_path_bin:$HOME/.config/composer/vendor/bin:$HOME/.local/bin"
    export PATH

    docker_run="docker run --interactive --rm -u 1000:1000"
    # docker_run_root="docker run --interactive --rm -u 0:0"
    kubectl_opt="kubectl --kubeconfig $HOME/.kube/config"
    helm_opt="helm --kubeconfig $HOME/.kube/config"

    ## check OS version/type/install command/install software / 检查系统版本/类型/安装命令/安装软件
    _detect_os

    ## git clone repo / 克隆 git 仓库
    [[ "${arg_git_clone:-0}" -eq 1 ]] && _git_clone_repo

    ## run deploy.sh by hand / 手动执行 deploy.sh
    _setup_gitlab_vars
    ## source ENV, 获取 ENV_ 开头的所有全局变量
    source "$script_env"
    ## curl use proxy / curl 使用代理
    if [ -z "$ENV_HTTP_PROXY" ]; then
        curl_opt="curl -L"
    else
        curl_opt="curl -x$ENV_HTTP_PROXY -L"
    fi
    if [[ "$ENV_DOCKER_PASSWORD" == 'your_password' && "$ENV_DOCKER_USERNAME" == 'your_username' ]]; then
        echo_ques "Found default username/password, skip docker login/push image/deploy k8s..."
        demo_mode=1
    fi
    image_tag="${gitlab_project_name}-${gitlab_commit_short_sha}-$(date +%s)"
    image_tag_flyway="${ENV_DOCKER_REGISTRY:?undefine}:${gitlab_project_name}-flyway-${gitlab_commit_short_sha}"

    ## install acme.sh/aws/kube/aliyun/python-gitlab/flarectl 安装依赖命令/工具
    [[ "${ENV_INSTALL_AWS}" == 'true' ]] && _install_aws
    [[ "${ENV_INSTALL_KUBECTL}" == 'true' ]] && _install_kubectl
    [[ "${ENV_INSTALL_HELM}" == 'true' ]] && _install_helm
    [[ "${ENV_INSTALL_PYTHON_ELEMENT}" == 'true' ]] && _install_python_element
    [[ "${ENV_INSTALL_PYTHON_GITLAB}" == 'true' ]] && _install_python_gitlab
    [[ "${ENV_INSTALL_JMETER}" == 'true' ]] && _install_jmeter
    # [[ "${ENV_INSTALL_ACMESH}" == 'true' ]] && _install_acme_sh
    [[ "${ENV_INSTALL_FLARECTL}" == 'true' ]] && _install_flarectl

    ## clean up disk space / 清理磁盘空间
    _clean_disk

    ## setup ssh config/ acme.sh/aws/kube/aliyun/python-gitlab/cloudflare/rsync
    _setup_deploy_conf

    ## renew cert with acme.sh / 使用 acme.sh 重新申请证书
    echo "PIPELINE_RENEW_CERT: ${PIPELINE_RENEW_CERT:-0}"
    [[ "${github_action:-0}" -eq 1 ]] && exec_renew_cert=1
    [[ "${arg_renew_cert:-0}" -eq 1 ]] && exec_renew_cert=1
    [[ "${PIPELINE_RENEW_CERT:-0}" -eq 1 ]] && exec_renew_cert=1
    if [[ "${exec_renew_cert:-0}" -eq 1 ]]; then
        _renew_cert
        [[ "${arg_renew_cert:-0}" -eq 1 || "${PIPELINE_RENEW_CERT:-0}" -eq 1 ]] && return
    fi

    ## detect program lang / 检测程序语言
    _detect_langs

    ## preprocess project config files / 预处理业务项目配置文件
    _preprocess_file

    code_style_sh="$script_path/langs/style.${project_lang}.sh"
    build_langs_sh="$script_path/langs/build.${project_lang}.sh"

    ## exec single task / 执行单个任务
    if [[ "${exec_single:-0}" -gt 0 ]]; then
        [[ "${arg_code_quality:-0}" -eq 1 ]] && _code_quality_sonar
        [[ "${arg_code_style:-0}" -eq 1 && -f "$code_style_sh" ]] && source "$code_style_sh"
        [[ "${arg_test_unit:-0}" -eq 1 ]] && _test_unit
        if [[ "${ENV_FLYWAY_HELM_JOB:-0}" -eq 1 ]]; then
            [[ "${exec_deploy_flyway:-0}" -eq 1 ]] && _deploy_flyway_helm_job
        else
            [[ "${exec_deploy_flyway:-0}" -eq 1 ]] && _deploy_flyway_docker
        fi
        [[ "${arg_build_langs:-0}" -eq 1 && -f "$build_langs_sh" ]] && source "$build_langs_sh"
        [[ "${arg_build_image:-0}" -eq 1 ]] && _build_image_docker
        [[ "${arg_push_image:-0}" -eq 1 ]] && _push_image
        [[ "${arg_deploy_k8s:-0}" -eq 1 ]] && _deploy_k8s
        [[ "${arg_deploy_rsync_ssh:-0}" -eq 1 ]] && _deploy_rsync_ssh
        [[ "${arg_deploy_rsync:-0}" -eq 1 ]] && _deploy_rsync
        [[ "${arg_deploy_ftp:-0}" -eq 1 ]] && _deploy_ftp
        [[ "${arg_deploy_sftp:-0}" -eq 1 ]] && _deploy_sftp
        [[ "${arg_test_function:-0}" -eq 1 ]] && _test_function
        return
    fi

    ## default exec all tasks / 默认执行所有任务

    _code_quality_sonar

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_CODE_STYLE ，1 启用[default]，0 禁用
    echo_time_step "code style..."
    echo "PIPELINE_CODE_STYLE: ${PIPELINE_CODE_STYLE:-0}"
    [[ "${PIPELINE_CODE_STYLE:-0}" -eq 1 ]] && exec_code_style=1
    [[ "${exec_code_style:-0}" -eq 1 && -f "$code_style_sh" ]] && source "$code_style_sh"

    _test_unit

    ## use flyway deploy sql file / 使用 flyway 发布 sql 文件
    echo "PIPELINE_FLYWAY: ${PIPELINE_FLYWAY:-0}"
    [[ "${PIPELINE_FLYWAY:-0}" -eq 0 ]] && exec_deploy_flyway=0
    if [[ "${ENV_FLYWAY_HELM_JOB:-0}" -eq 1 ]]; then
        [[ "${exec_deploy_flyway:-0}" -eq 1 ]] && _deploy_flyway_helm_job
    else
        [[ "${exec_deploy_flyway:-0}" -eq 1 ]] && _deploy_flyway_docker
    fi

    ## generate api docs
    # _generate_apidoc

    ## build
    [[ "${exec_build_langs:-0}" -eq 1 && -f "$build_langs_sh" ]] && source "$build_langs_sh"

    ## deploy k8s
    [[ "${exec_build_image:-0}" -eq 1 ]] && _build_image_docker
    # [[ "${exec_build_image:-0}" -eq 1 ]] && _build_image_podman
    [[ "${exec_push_image:-0}" -eq 1 ]] && _push_image
    [[ "${exec_deploy_k8s:-0}" -eq 1 ]] && _deploy_k8s

    ## deploy with rsync / 使用 rsync 发布
    [[ "$ENV_DISABLE_RSYNC" -eq 1 ]] && exec_deploy_rsync_ssh=0
    [[ "${exec_deploy_rsync_ssh:-1}" -eq 1 ]] && _deploy_rsync_ssh
    ## rsync server
    [[ "${exec_deploy_rsync:-0}" -eq 1 ]] && _deploy_rsync
    ## ftp server
    [[ "${exec_deploy_ftp:-0}" -eq 1 ]] && _deploy_ftp
    ## sftp server
    [[ "${exec_deploy_sftp:-0}" -eq 1 ]] && _deploy_sftp

    _test_function

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
