#!/usr/bin/env bash

################################################################################
#
# Description: Gitlab deploy, rsync file, import sql, deploy k8s
# Author: xiagw <fxiaxiaoyu@gmail.com>
# License: GNU/GPL, see http://www.gnu.org/copyleft/gpl.html
# Date: 2019-04-03
#
################################################################################

set -e ## 出现错误自动退出
# set -u ## 变量未定义报错

# install gitlab-runner, https://docs.gitlab.com/runner/install/linux-manually.html
# http://www.ttlsa.com/auto/gitlab-cicd-variables-zh-document/

echo_info() { echo -e "\033[32m$*\033[0m"; }        ## green
echo_warn() { echo -e "\033[33m$*\033[0m"; }        ## yellow
echo_erro() { echo -e "\033[31m$*\033[0m"; }        ## red
echo_ques() { echo -e "\033[35m$*\033[0m"; }        ## brown
echo_time() { echo "[$(date +%Y%m%d-%T-%u)], $*"; } ## time
## year mon day - time - %u day of week (1..7); 1 is Monday - %j day of year (001..366) - %W   week number of year, with Monday as first day of week (00..53)
echo_time_step() { echo -e "\033[33m[$(date +%Y%m%d-%T-%u)] step-$((STEP + 1)),\033[0m $*" && STEP=$((STEP + 1)); }
# https://zhuanlan.zhihu.com/p/48048906
# https://www.jianshu.com/p/bf0ffe8e615a
# https://www.cnblogs.com/lsgxeva/p/7994474.html
# https://eslint.bootcss.com
# http://eslint.cn/docs/user-guide/getting-started
code_style_node() {
    echo_time_step "[TODO] eslint code style check..."
}

code_style_python() {
    echo_time_step "[TODO] vsc-extension-python..."
}

## https://github.com/squizlabs/PHP_CodeSniffer
## install ESlint: yarn global add eslint ("$HOME/".yarn/bin/eslint)
code_style_php() {
    echo_time_step 'starting PHP Code Sniffer, < standard=PSR12 >...'
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    if ! docker images | grep 'deploy/phpcs'; then
        DOCKER_BUILDKIT=1 docker build -t deploy/phpcs -f "$script_dockerfile/Dockerfile.phpcs" "$script_dockerfile" >/dev/null
    fi
    phpcs_result=0
    for i in $($git_diff | awk '/\.php$/{if (NR>0){print $0}}'); do
        if [ ! -f "$gitlab_project_dir/$i" ]; then
            echo_warn "$gitlab_project_dir/$i not exists."
            continue
        fi
        if ! $docker_run -v "$gitlab_project_dir":/project deploy/phpcs phpcs -n --standard=PSR12 --colors --report="${phpcs_report:-full}" "/project/$i"; then
            phpcs_result=$((phpcs_result + 1))
        fi
    done
    if [ "$phpcs_result" -ne "0" ]; then
        exit $phpcs_result
    fi
}

# https://github.com/alibaba/p3c/wiki/FAQ
code_style_java() {
    echo_time_step "[TODO] Java code style check..."
}

code_style_dockerfile() {
    echo_time_step "[TODO] vsc-extension-hadolint..."
}

func_code_style() {
    [[ "${project_lang}" == php ]] && code_style_php
    [[ "${project_lang}" == node ]] && code_style_node
    [[ "${project_lang}" == java ]] && code_style_java
    [[ "${project_lang}" == python ]] && code_style_python
    [[ "${project_docker}" == 1 ]] && code_style_dockerfile
}

## install phpunit
func_test_unit() {
    echo_time_step "unit test..."
    if [[ -f "$gitlab_project_dir"/tests/unit_test.sh ]]; then
        bash "$gitlab_project_dir"/tests/unit_test.sh
    fi
    echo_time "end unit test."
}

## install jdk/ant/jmeter
func_test_function() {
    echo_time_step "function test..."
    if [ -f "$gitlab_project_dir"/tests/func_test.sh ]; then
        bash "$gitlab_project_dir"/tests/func_test.sh
    fi
    echo_time "end function test."
}

func_code_quality_sonar() {
    echo_time_step "sonar scanner..."
    sonar_url="${ENV_SONAR_URL:?empty}"
    sonar_conf="$gitlab_project_dir/sonar-project.properties"
    if ! curl "$sonar_url" >/dev/null 2>&1; then
        echo_warn "Could not found sonarqube server, exit."
        return
    fi

    if [[ ! -f "$sonar_conf" ]]; then
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
    echo_time "end sonar scanner."
    exit
}

scan_ZAP() {
    echo_time_step "[TODO] ZAP scan..."
    # docker pull owasp/zap2docker-stable
}

scan_vulmap() {
    echo_time_step "[TODO] vulmap scan..."
}

func_deploy_flyway() {
    echo_time_step "flyway migrate..."
    flyway_conf_volume="${gitlab_project_dir}/flyway_conf:/flyway/conf"
    flyway_sql_volume="${gitlab_project_dir}/flyway_sql:/flyway/sql"
    flyway_docker_run="docker run --rm -v ${flyway_conf_volume} -v ${flyway_sql_volume} flyway/flyway"

    ## 判断是否需要建立数据库远程连接
    [ -f "$script_path_bin/special.sh" ] && source "$script_path_bin/special.sh" port
    ## exec flyway
    if $flyway_docker_run info | grep '^|' | grep -vE 'Category.*Version|Versioned.*Success|Versioned.*Deleted|DELETE.*Success'; then
        $flyway_docker_run repair
        $flyway_docker_run migrate && deploy_result=0 || deploy_result=1
        $flyway_docker_run info | tail -n 10
        ## 断开数据库远程连接
    else
        echo "Nothing to do."
    fi
    if [ ${deploy_result:-0} = 0 ]; then
        echo_info "Result = OK"
    else
        echo_erro "Result = FAIL"
    fi
    echo_time "end flyway migrate."
}

func_deploy_flyway_docker() {
    ## docker build flyway
    image_tag_flyway="${ENV_DOCKER_REGISTRY:?undefine}/${ENV_DOCKER_REPO:?undefine}:${gitlab_project_name}-flyway"
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    DOCKER_BUILDKIT=1 docker build -q --tag "${image_tag_flyway}" -f "${gitlab_project_dir}/Dockerfile.flyway" "${gitlab_project_dir}/" >/dev/null
    docker run --rm "$image_tag_flyway"
    if [ ${deploy_result:-0} = 0 ]; then
        echo_info "Result = OK"
    else
        echo_erro "Result = FAIL"
    fi
}

# https://github.com/nodesource/distributions#debinstall
build_node_yarn() {
    echo_time_step "node yarn build..."
    rm -f package-lock.json
    build_image_from='deploy/node'
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    if ! docker images | grep "$build_image_from" >/dev/null; then
        DOCKER_BUILDKIT=1 docker build -t deploy/node -f "$script_dockerfile/Dockerfile.nodebuild" "$script_dockerfile" >/dev/null
    fi
    $docker_run -v "${gitlab_project_dir}":/app -w /app "$build_image_from" bash -c "if [[ ${YARN_INSTALL:-false} == 'true' ]]; then yarn install; fi; yarn run build"
    echo_time "end node yarn build."
}

build_php_composer() {
    echo_time_step "php composer install..."
    build_image_from=${build_image_from:-deploy/composer}
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    if ! docker images | grep -q "deploy/composer"; then
        DOCKER_BUILDKIT=1 docker build --quiet --tag "deploy/composer" --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE}" \
            -f "$script_dockerfile/Dockerfile.composer" "$script_dockerfile"
    fi
    rm -rf "${gitlab_project_dir}"/vendor
    $docker_run -v "$gitlab_project_dir:/app" -w /app "$build_image_from" bash -c "composer install -q" || true
    echo_time "end php composer install."
}

build_java_maven() {
    echo_time_step "java maven build..."
}

build_python_pip() {
    echo_time_step "python install..."
}

# 列出所有项目
# gitlab -v -o yaml -f path_with_namespace project list --all |awk -F': ' '{print $2}' |sort >p.txt
# 解决 Encountered 1 file(s) that should have been pointers, but weren't
# git lfs migrate import --everything$(awk '/filter=lfs/ {printf " --include='\''%s'\''", $1}' .gitattributes)

docker_login() {
    ## 比较上一次登陆时间，超过12小时则再次登录
    lock_docker_login="$script_path_conf/.lock.docker.login.${ENV_DOCKER_LOGIN_TYPE:-none}"
    time_save="$(if test -f "$lock_docker_login"; then cat "$lock_docker_login"; else :; fi)"
    if [[ "$(date +%s -d '12 hours ago')" -lt "${time_save:-0}" ]]; then
        return 0
    fi
    echo_time "docker login ${ENV_DOCKER_LOGIN_TYPE:-none} ..."
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    if [[ "${ENV_DOCKER_LOGIN_TYPE:-none}" == 'aws' ]]; then
        str_docker_login="docker login --username AWS --password-stdin ${ENV_DOCKER_REGISTRY}"
        aws ecr get-login-password --profile="${ENV_AWS_PROFILE}" --region "${ENV_REGION_ID:?undefine}" | $str_docker_login >/dev/null
    else
        echo "${ENV_DOCKER_PASSWORD}" | docker login --username="${ENV_DOCKER_USERNAME}" --password-stdin "${ENV_DOCKER_REGISTRY}"
    fi
    date +%s >"$lock_docker_login"
}

build_docker() {
    echo_time_step "docker build only..."
    docker_login

    ## Docker build from, 是否从模板构建
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    if [ -n "$image_from" ]; then
        ## 判断模版是否存在,模版不存在，构建模板
        docker images | grep -q "${image_from%%:*}.*${image_from##*:}" ||
            DOCKER_BUILDKIT=1 docker build -q --tag "${image_from}" --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE}" \
                -f "${gitlab_project_dir}/Dockerfile.${image_from##*:}" "${gitlab_project_dir}"
    fi

    ## docker build flyway
    if [[ $ENV_HELM_FLYWAY == 1 ]]; then
        image_tag_flyway="${ENV_DOCKER_REGISTRY:?undefine}/${ENV_DOCKER_REPO:?undefine}:${gitlab_project_name}-flyway"
        DOCKER_BUILDKIT=1 docker build -q --tag "${image_tag_flyway}" -f "${gitlab_project_dir}/Dockerfile.flyway" "${gitlab_project_dir}/" >/dev/null
    fi
    ## docker build
    DOCKER_BUILDKIT=1 docker build -q --tag "${image_registry}" --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE:-false}" "${gitlab_project_dir}" >/dev/null
    echo_time "end docker build."
    # --build-arg COMPOSER_INSTALL="${COMPOSER_INSTALL:-true}" \
}

docker_push() {
    echo_time_step "docker push only..."
    docker_login
    # echo "$image_registry"
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    docker push -q "$image_registry" || echo_erro "error here, maybe caused by GFW."
    if [[ $ENV_HELM_FLYWAY == 1 ]]; then
        docker push -q "$image_tag_flyway"
    fi
    echo_time "end docker push."
}

deploy_k8s() {
    echo_time_step "deploy k8s..."
    if [[ ${ENV_REMOVE_PROJ_PREFIX:-false} == 'true' ]]; then
        helm_release=${gitlab_project_name#*-}
    else
        helm_release=${gitlab_project_name}
    fi
    ## 转换为小写， Convert to lower case
    helm_release="${helm_release,,}"
    ## helm files folder
    if [ -d "${script_path_conf}/helm/${gitlab_project_name}" ]; then
        path_helm="${script_path_conf}/helm/${gitlab_project_name}"
    elif [ -d "$gitlab_project_dir/helm" ]; then
        path_helm="$gitlab_project_dir/helm"
    fi

    image_tag="${gitlab_project_name}-${gitlab_commit_short_sha}"
    if [ -z "$path_helm" ]; then
        echo_warn "helm files not found."
        ## Custom deployment method
        [ -f "$script_path_bin/special.sh" ] && source "$script_path_bin/special.sh" "$env_namespace"
    else
        set -x
        $helm_opt upgrade "${helm_release}" "$path_helm/" --install --history-max 1 \
            --namespace "${env_namespace}" --create-namespace \
            --set image.repository="${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}" \
            --set image.tag="${image_tag}" \
            --set image.pullPolicy='Always' >/dev/null
        [[ "${debug_on:-0}" -ne 1 ]] && set +x
        ## Clean up
        $kubectl_opt -n "${env_namespace}" get rs | awk '/.*0\s+0\s+0/ {print $1}' | xargs $kubectl_opt -n "${env_namespace}" delete rs >/dev/null 2>&1 || true
        $kubectl_opt -n "${env_namespace}" get pod | grep Evicted | awk '{print $1}' | xargs $kubectl_opt -n "${env_namespace}" delete pod 2>/dev/null || true
        sleep 3
        ## Get deployment results and set var: deploy_result
        $kubectl_opt -n "${env_namespace}" rollout status deployment "${helm_release}" || deploy_result=1
    fi

    ## update helm file for argocd
    file_helm_values="$script_path_conf"/gitops/helm/${gitlab_project_name}/values.yaml
    if [ -f "$file_helm_values" ]; then
        echo_time_step "update helm files..."
        sed -i \
            -e "s@repository:.*@repository:\ \"${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}\"@" \
            -e "s@tag:.*@tag:\ \"${image_tag}\"@" \
            "$file_helm_values"
    fi

    ## helm install flyway jobs
    if [[ $ENV_HELM_FLYWAY == 1 && -d "${script_path_conf}/helm/flyway/" ]]; then
        $helm_opt upgrade flyway "${script_path_conf}/helm/flyway/" --install --history-max 1 \
            --namespace "${env_namespace}" --create-namespace \
            --set image.repository="${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}" \
            --set image.tag="${gitlab_project_name}-flyway" \
            --set image.pullPolicy='Always' >/dev/null
    fi
    echo_time "end deploy k8s."
}

func_deploy_rsync() {
    echo_time_step "rsync code file to remote server..."
    ## 读取配置文件，获取 项目/分支名/war包目录
    # for line in $(grep "^${gitlab_project_path}\s\+${env_namespace}" "$script_conf"); do
    grep "^${gitlab_project_path}\s\+${env_namespace}" "$script_conf" | while read -r line; do
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

        ## 防止出现空变量（若有空变量则自动退出）
        echo "${ssh_host:?if stop here, check runner/conf/deploy.conf}"
        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=20 -p ${ssh_port:-22}"
        ## rsync exclude some files
        if [[ -f "${gitlab_project_dir}/rsync.exclude" ]]; then
            rsync_conf="${gitlab_project_dir}/rsync.exclude"
        else
            rsync_conf="${script_path_conf}/rsync.exclude"
        fi
        ## node/java use rsync --delete
        [[ "${project_lang}" =~ (node|react|java|other) ]] && rsync_delete='--delete'
        rsync_opt="rsync -acvzt --exclude=.svn --exclude=.git --timeout=20 --no-times --exclude-from=${rsync_conf} $rsync_delete"

        ## 源文件夹
        if [[ "$rsync_src" == 'null' || -z "$rsync_src" ]]; then
            rsync_src="${gitlab_project_dir}/$path_for_rsync"
        elif [[ "$rsync_src" =~ \.[jw]ar$ ]]; then
            find_file="$(find "${gitlab_project_dir}" -name "$rsync_src" -print0 | head -n 1)"
            if [[ "$find_file" =~ \.[jw]ar$ ]]; then
                rsync_src="$find_file"
            else
                echo "file not found: ${find_file}"
                return 1
            fi
        fi
        ## 目标文件夹
        if [[ "$rsync_dest" == 'null' || -z "$rsync_dest" ]]; then
            rsync_dest="${ENV_PATH_DEST_PRE}/${env_namespace}.${gitlab_project_name}/"
        fi
        ## 发布到 aliyun oss 存储
        if [[ "${rsync_dest}" =~ 'oss://' ]]; then
            command -v aliyun >/dev/null || echo_warn "command not exist: aliyun"
            aliyun oss cp "${rsync_src}/" "$rsync_dest/" --recursive --force
            # rclone sync "${gitlab_project_dir}/" "$rsync_dest/"
            return
        fi
        ## 判断目标服务器/目标目录 是否存在？不存在则登录到目标服务器建立目标路径
        $ssh_opt -n "${ssh_host}" "test -d $rsync_dest || mkdir -p $rsync_dest"
        ## 复制文件到目标服务器的目标目录
        echo "deploy to ${ssh_host}:${rsync_dest}"
        ${rsync_opt} -e "$ssh_opt" "${rsync_src}" "${ssh_host}:${rsync_dest}"
    done
    echo_time "end rsync file."
}

func_deploy_notify_msg() {
    # mr_iid="$(gitlab project-merge-request list --project-id "$gitlab_project_id" --page 1 --per-page 1 | awk '/^iid/ {print $2}')"
    ## $exec_sudo -H python3 -m pip install PyYaml
    # msg_describe="${msg_describe:-$(gitlab -v project-merge-request get --project-id "$gitlab_project_id" --iid "$mr_iid" | sed -e '/^description/,/^diff-refs/!d' -e 's/description: //' -e 's/diff-refs.*//')}"
    msg_describe="${msg_describe:-$(git --no-pager log --no-merges --oneline -1 || true)}"
    git_username="$(gitlab -v user get --id "${gitlab_user_id}" | awk '/^name:/ {print $2}')"

    msg_body="
[Gitlab Deploy]
Project = ${gitlab_project_path}
Branche = ${gitlab_project_branch}
Pipeline = ${gitlab_pipeline_id}/JobID-$gitlab_job_id
Describe = [${gitlab_commit_short_sha}]/${msg_describe}
Who = ${gitlab_user_id}/${git_username}
Result = $([ "${deploy_result:-0}" = 0 ] && echo OK || echo FAIL)
$(if [ -n "${test_result}" ]; then echo "Test_Result: ${test_result}" else :; fi)
"
}

func_deploy_notify() {
    echo_time_step "deploy notify message..."
    func_deploy_notify_msg
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
        tgApiMsg="https://api.telegram.org/bot${ENV_API_KEY_TG:?undefine var}/sendMessage"
        # tgApiUrlDoc="https://api.telegram.org/bot${ENV_API_KEY_TG:?undefine var}/sendDocument"
        msg_body="$(echo "$msg_body" | sed -e ':a;N;$!ba;s/\n/%0a/g' -e 's/&/%26/g')"
        $curl_opt -sS -o /dev/null -X POST -d "chat_id=${ENV_TG_GROUP_ID:?undefine var}&text=$msg_body" "$tgApiMsg"
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
        echo_warn "No message send."
    fi
}

func_renew_cert() {
    echo_time_step "renew cert (dns api)..."
    acme_home="${HOME}/.acme.sh"
    acme_cmd="${acme_home}/acme.sh"
    acme_cert="${acme_home}/dest"
    conf_dns_cloudflare="${script_path_conf}/.cloudflare.conf"
    conf_dns_aliyun="${script_path_conf}/.aliyun.dnsapi.conf"
    conf_dns_qcloud="${script_path_conf}/.qcloud.dnspod.conf"

    ## install acme.sh
    if [[ ! -x "${acme_cmd}" ]]; then
        $curl_opt https://get.acme.sh | sh
    fi
    [ -d "$acme_cert" ] || mkdir "$acme_cert"
    ## 支持多份 account.conf.[x] 配置。只有一个 account 则 copy 成 1
    if [[ "$(find "${acme_home}" -name 'account.conf*' | wc -l)" == 1 ]]; then
        cp "${acme_home}/"account.conf "${acme_home}/"account.conf.1
    fi

    ## 根据多个不同的账号文件，循环处理 renew
    for account in "${acme_home}/"account.conf.*; do
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
        ## 单个 account 可能有多个 domain
        for domain in ${domain_name}; do
            if [ -d "${acme_home}/$domain" ]; then
                "${acme_cmd}" --renew -d "${domain}" || true
            else
                "${acme_cmd}" --issue --dns $dnsType -d "$domain" -d "*.$domain"
            fi
            "${acme_cmd}" --install-cert -d "$domain" --key-file "$acme_cert/$domain".key --fullchain-file "$acme_cert/$domain".crt
        done
    done

    ## Custom deployment method
    if [ -f "${acme_home}"/custom.acme.sh ]; then
        bash "${acme_home}"/custom.acme.sh
    fi
    echo_time "end renew cert."
    exit
}

install_python_gitlab() {
    python3 -m pip list 2>/dev/null | grep -q python-gitlab || python3 -m pip install --user --upgrade python-gitlab
}

install_python_element() {
    python3 -m pip list 2>/dev/null | grep -q matrix-nio || python3 -m pip install --user --upgrade matrix-nio
}

install_aws() {
    command -v aws >/dev/null && return
    $curl_opt -o "awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    unzip -qq awscliv2.zip
    ./aws/install --bin-dir "${script_path_bin}" --install-dir "${script_data}" --update
    ## install eksctl
    $curl_opt "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    mv /tmp/eksctl "${script_path_bin}/"
}

install_kubectl() {
    command -v kubectl >/dev/null && return
    kube_ver="$($curl_opt --silent https://storage.googleapis.com/kubernetes-release/release/stable.txt)"
    kube_url="https://storage.googleapis.com/kubernetes-release/release/${kube_ver}/bin/linux/amd64/kubectl"
    $curl_opt -o "${script_path_bin}/kubectl" "$kube_url"
    chmod +x "${script_path_bin}/kubectl"
}

install_helm() {
    command -v helm >/dev/null || $curl_opt https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
}

install_jmeter() {
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
        cd "$script_data"
        unzip "$path_temp"/jmeter.zip
        ln -sf apache-jmeter-${ver_jmeter} jmeter
    )
    rm -rf "$path_temp"
}

func_check_os() {
    if [[ $UID == 0 ]]; then
        exec_sudo=
    else
        exec_sudo=sudo
    fi

    if [[ -e /etc/debian_version ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS="${ID}" # debian or ubuntu
    elif [[ -e /etc/fedora-release ]]; then
        # shellcheck disable=SC1091
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
    debian | ubuntu)
        ## fix gitlab-runner exit error.
        test -f "$HOME"/.bash_logout && mv -f "$HOME"/.bash_logout "$HOME"/.bash_logout.bak
        command -v git >/dev/null || install_pkg="git"
        git lfs version >/dev/null 2>&1 || install_pkg="$install_pkg git-lfs"
        command -v curl >/dev/null || install_pkg="$install_pkg curl"
        command -v unzip >/dev/null || install_pkg="$install_pkg unzip"
        command -v rsync >/dev/null || install_pkg="$install_pkg rsync"
        command -v pip3 >/dev/null || install_pkg="$install_pkg python3-pip"
        # command -v shc >/dev/null || $exec_sudo apt-get install -qq -y shc
        if [[ -n "$install_pkg" ]]; then
            $exec_sudo apt-get update -qq
            $exec_sudo apt-get install -qq -y apt-utils >/dev/null
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
        command -v git >/dev/null || $exec_sudo yum install -y git2u >/dev/null
        git lfs version >/dev/null 2>&1 || $exec_sudo yum install -y git-lfs >/dev/null
        command -v curl >/dev/null || $exec_sudo yum install -y curl >/dev/null
        command -v rsync >/dev/null || $exec_sudo yum install -y rsync >/dev/null
        # command -v docker >/dev/null || sh "$script_path_bin/get-docker.sh"
        # id | grep -q docker || $exec_sudo usermod -aG docker "$USER"
        ;;
    *)
        echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2 or Arch Linux system"
        echo "Not support. exit."
        exit 1
        ;;
    esac
}

func_clean_disk() {
    ## clean cache of docker build
    disk_usage="$(df / | awk 'NR>1 {print $5}')"
    disk_usage="${disk_usage/\%/}"
    if ((disk_usage < 80)); then
        return
    fi
    docker images "${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}" -q | sort | uniq | xargs -I {} docker rmi -f {} || true
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
    for i in ${ENV_NGINX_IPS:?undefine var}; do
        echo "$i"
        rsync -av "${t}/" "root@$i":/etc/nginx/conf.d/
    done
}

func_generate_apidoc() {
    if [[ -f "${gitlab_project_dir}/apidoc.json" ]]; then
        echo_time_step "generate apidoc."
        $docker_run -v "${gitlab_project_dir}":/app -w /app deploy/node bash -c "apidoc -i app/ -o public/apidoc/"
    fi
}

func_file_preprocessing() {
    echo_time "preprocessing file..."
    ## frontend (VUE) .env file
    if [[ $project_lang =~ (node|react) ]]; then
        config_env_path="$(find "${gitlab_project_dir}" -maxdepth 2 -name "${env_namespace}.*")"
        for file in $config_env_path; do
            if [[ "$file" =~ 'config/' ]]; then
                rsync -av "$file" "${file/${env_namespace}./}" # vue2.x
            else
                rsync -av "$file" "${file/${env_namespace}/}" # vue3.x
            fi
        done
        copy_flyway_file=0
    fi
    ## backend (PHP) project_conf files
    path_project_conf="${script_path_conf}/project_conf/${env_namespace}.${gitlab_project_name}/"
    [ -d "$path_project_conf" ] && rsync -av "$path_project_conf" "${gitlab_project_dir}/"
    ## docker ignore file
    [ -f "${gitlab_project_dir}/.dockerignore" ] || rsync -av "${script_path_conf}/.dockerignore" "${gitlab_project_dir}/"
    ## cert file for nginx
    if [[ "${gitlab_project_name}" == "$ENV_NGINX_GIT_NAME" && -d "$HOME/.acme.sh/dest/" ]]; then
        rsync -av "$HOME/.acme.sh/dest/" "${gitlab_project_dir}/etc/nginx/conf.d/ssl/"
    fi
    ## Docker build from, 是否从模板构建
    if [ "${project_docker}" -eq 1 ]; then
        image_from=$(awk '/^FROM/ {print $2}' Dockerfile | grep "${image_registry%%:*}" | head -n 1)
        if [ -n "$image_from" ]; then
            file_docker_tmpl="${script_dockerfile}/Dockerfile.${image_from##*:}"
            [ -f "${file_docker_tmpl}" ] && rsync -av "${file_docker_tmpl}" "${gitlab_project_dir}/"
        fi
    fi
    ## flyway sql/conf files
    [[ ! -d "${gitlab_project_dir}/${ENV_FLYWAY_SQL:-docs/sql}" ]] && copy_flyway_file=0
    if [[ "${copy_flyway_file:-1}" -eq 1 ]]; then
        path_flyway_conf="$gitlab_project_dir/flyway_conf"
        path_flyway_sql="$gitlab_project_dir/flyway_sql"
        path_flyway_sql_proj="$gitlab_project_dir/${ENV_FLYWAY_SQL:-docs/sql}"
        [[ -d "$path_flyway_sql_proj" && ! -d "$path_flyway_sql" ]] && rsync -a "$path_flyway_sql_proj/" "$path_flyway_sql/"
        [[ -d "$path_flyway_conf" ]] || mkdir -p "$path_flyway_conf"
        [[ -d "$path_flyway_sql" ]] || mkdir -p "$path_flyway_sql"
        [[ -f "${gitlab_project_dir}/Dockerfile.flyway" ]] || rsync -av "${script_dockerfile}/Dockerfile.flyway" "${gitlab_project_dir}/"
    fi
    echo_time "end preprocessing file."
}

func_config_files() {
    ## ssh config and key
    path_conf_ssh="${script_path_conf}/.ssh"
    if [[ ! -d "${path_conf_ssh}" ]]; then
        mkdir -m 700 "$path_conf_ssh"
        echo_warn "Generate ssh key file for gitlab-runner: $path_conf_ssh/id_ed25519"
        echo_erro "Please: cat $path_conf_ssh/id_ed25519.pub >> [dest_server]:\~/.ssh/authorized_keys"
        ssh-keygen -t ed25519 -N '' -f "$path_conf_ssh/id_ed25519"
        [ -d "$HOME/.ssh" ] || ln -sf "$path_conf_ssh" "$HOME/"
    fi
    for f in "$path_conf_ssh"/*; do
        if [ ! -f "$HOME/.ssh/${f##*/}" ]; then
            chmod 600 "${f}"
            ln -sf "${f}" "$HOME/.ssh/"
        fi
    done
    ## acme.sh/aws/kube/aliyun/python-gitlab
    path_conf_acme="${script_path_conf}/.acme.sh"
    path_conf_aws="${script_path_conf}/.aws"
    path_conf_kube="${script_path_conf}/.kube"
    path_conf_aliyun="${script_path_conf}/.aliyun"
    conf_python_gitlab="${script_path_conf}/.python-gitlab.cfg"
    [[ ! -d "${HOME}/.acme.sh" && -d "${path_conf_acme}" ]] && ln -sf "${path_conf_acme}" "$HOME/"
    [[ ! -d "${HOME}/.aws" && -d "${path_conf_aws}" ]] && ln -sf "${path_conf_aws}" "$HOME/"
    [[ ! -d "${HOME}/.kube" && -d "${path_conf_kube}" ]] && ln -sf "${path_conf_kube}" "$HOME/"
    [[ ! -d "${HOME}/.aliyun" && -d "${path_conf_aliyun}" ]] && ln -sf "${path_conf_aliyun}" "$HOME/"
    [[ ! -f "${HOME}/.python-gitlab.cfg" && -f "${conf_python_gitlab}" ]] && ln -sf "${conf_python_gitlab}" "$HOME/"
    return 0
}

func_setup_var_gitlab() {
    gitlab_project_dir=${CI_PROJECT_DIR:-$PWD}
    gitlab_project_name=${CI_PROJECT_NAME:-${gitlab_project_dir##*/}}
    # read -rp "Enter gitlab project namespace: " -e -i 'root' gitlab_project_namespace
    gitlab_project_namespace=${CI_PROJECT_NAMESPACE:-root}
    # read -rp "Enter gitlab project path: [root/git-repo] " -e -i 'root/xxx' gitlab_project_path
    gitlab_project_path=${CI_PROJECT_PATH:-root/$gitlab_project_name}
    # read -t 5 -rp "Enter branch name: " -e -i 'develop' gitlab_project_branch
    gitlab_project_branch=${CI_COMMIT_REF_NAME:-develop}
    gitlab_commit_short_sha=${CI_COMMIT_SHORT_SHA:-$(git rev-parse --short HEAD || true)}
    [[ -z "$gitlab_commit_short_sha" && "$github_action" -eq 1 ]] && gitlab_commit_short_sha=${gitlab_commit_short_sha:-7d30547}
    [[ -z "$gitlab_commit_short_sha" && "$debug_on" -eq 1 ]] && read -rp "Enter commit short hash: " -e -i 'xxxxxx' gitlab_commit_short_sha
    # read -rp "Enter gitlab project id: " -e -i '1234' gitlab_project_id
    # gitlab_project_id=${CI_PROJECT_ID:-1234}
    # read -t 5 -rp "Enter gitlab pipeline id: " -e -i '3456' gitlab_pipeline_id
    gitlab_pipeline_id=${CI_PIPELINE_ID:-3456}
    # read -rp "Enter gitlab job id: " -e -i '5678' gitlab_job_id
    gitlab_job_id=${CI_JOB_ID:-5678}
    # read -rp "Enter gitlab user id: " -e -i '1' gitlab_user_id
    gitlab_user_id=${GITLAB_USER_ID:-1}
    env_namespace=$gitlab_project_branch
}

func_detect_project_type() {
    echo "PIPELINE_DISABLE_DOCKER: ${PIPELINE_DISABLE_DOCKER:-0}"
    echo "PIPELINE_SONAR: ${PIPELINE_SONAR:-0}"
    if [[ "${PIPELINE_DISABLE_DOCKER:-0}" -eq 1 || "${ENV_DISABLE_DOCKER:-0}" -eq 1 ]]; then
        disable_docker=1
    fi
    if [[ -f "${gitlab_project_dir}/Dockerfile" && "$disable_docker" -ne 1 ]]; then
        project_docker=1
        exec_build_docker=1
        exec_docker_push=1
        exec_deploy_k8s=1
        build_image_from="$(awk '/^FROM/ {print $2}' Dockerfile | grep "${env_image_reg}" | head -n 1)"
    fi

    if [[ -f "${gitlab_project_dir}/package.json" ]]; then
        if grep -i -q 'Create React' "${gitlab_project_dir}/README.md" "${gitlab_project_dir}/readme.md" >/dev/null 2>&1; then
            project_lang='react'
            path_for_rsync='build/'
        else
            project_lang='node'
            path_for_rsync='dist/'
        fi
        if ! grep -q "$(md5sum "${gitlab_project_dir}/package.json" | awk '{print $1}')" "${script_log}"; then
            echo "$gitlab_project_path $env_namespace $(md5sum "${gitlab_project_dir}/package.json")" >>"${script_log}"
            YARN_INSTALL=true
        fi
        [ -d "${gitlab_project_dir}/node_modules" ] || YARN_INSTALL=true
        exec_build_node=1

    fi

    if [[ -f "${gitlab_project_dir}/composer.json" ]]; then
        project_lang='php'
        path_for_rsync=
        if ! grep -q "$(md5sum "${gitlab_project_dir}/composer.json" | awk '{print $1}')" "${script_log}"; then
            echo "$gitlab_project_path $env_namespace $(md5sum "${gitlab_project_dir}/composer.json")" >>"${script_log}"
            exec_build_php=1
        fi
        [ -d "${gitlab_project_dir}/vendor" ] || exec_build_php=1
        exec_build_node=0
    fi

    if [[ -f "${gitlab_project_dir}/pom.xml" ]]; then
        project_lang='java'
        path_for_rsync=
        [[ "$project_docker" -ne 1 || $ENV_FORCE_RSYNC == 'true' ]] && exec_build_java=1
    fi
    if [[ -f "${gitlab_project_dir}/requirements.txt" ]]; then
        project_lang='python'
        path_for_rsync=
        [[ "$project_docker" -ne 1 || $ENV_FORCE_RSYNC == 'true' ]] && exec_build_python=1
    fi
    if grep '^## android' "${gitlab_project_dir}/.gitlab-ci.yml" >/dev/null; then
        project_lang='android'
        exec_deploy_rsync=0
        exec_build_node=0
    fi
    if grep '^## ios' "${gitlab_project_dir}/.gitlab-ci.yml" >/dev/null; then
        project_lang='ios'
        exec_deploy_rsync=0
        exec_build_node=0
    fi
    project_lang=${project_lang:-other}
}

func_detect_project_type2() {
    echo "PIPELINE_DISABLE_DOCKER: ${PIPELINE_DISABLE_DOCKER:-0}"
    echo "PIPELINE_SONAR: ${PIPELINE_SONAR:-0}"
    if [[ "${PIPELINE_DISABLE_DOCKER:-0}" -eq 1 || "${ENV_DISABLE_DOCKER:-0}" -eq 1 ]]; then
        disable_docker=1
    fi
    if [[ -f "${gitlab_project_dir}"/Dockerfile && "$disable_docker" -ne 1 ]]; then
        project_docker=1
        exec_build_docker=1
        exec_docker_push=1
        exec_deploy_k8s=1
    fi
    test -f "${gitlab_project_dir}"/package.json && project_lang=node
    test -f "${gitlab_project_dir}"/composer.json && project_lang=php
    test -f "${gitlab_project_dir}"/pom.xml && project_lang=java
    test -f "${gitlab_project_dir}"/requirements.txt && project_lang=python
    project_lang=${project_lang:-other}

    case $project_lang in
    node)
        if grep -i -q 'Create React' "${gitlab_project_dir}/README.md" "${gitlab_project_dir}/readme.md" >/dev/null 2>&1; then
            project_lang='react'
            path_for_rsync='build/'
        else
            project_lang='node'
            path_for_rsync='dist/'
        fi
        if ! grep -q "$(md5sum "${gitlab_project_dir}/package.json" | awk '{print $1}')" "${script_log}"; then
            echo "$gitlab_project_path $env_namespace $(md5sum "${gitlab_project_dir}/package.json")" >>"${script_log}"
            YARN_INSTALL=true
        fi
        [ -d "${gitlab_project_dir}/node_modules" ] || YARN_INSTALL=true
        if [[ "$project_docker" -ne 1 || $ENV_FORCE_RSYNC == 'true' ]]; then
            exec_build_node=1
        fi
        ;;
    php)
        project_lang='php'
        path_for_rsync=
        if ! grep -q "$(md5sum "${gitlab_project_dir}/composer.json" | awk '{print $1}')" "${script_log}"; then
            echo "$gitlab_project_path $env_namespace $(md5sum "${gitlab_project_dir}/composer.json")" >>"${script_log}"
            COMPOSER_INSTALL=true
        fi
        [ -d "${gitlab_project_dir}/vendor" ] || COMPOSER_INSTALL=true
        if [[ "$project_docker" -ne 1 || $ENV_FORCE_RSYNC == 'true' ]]; then
            exec_build_php=1
            exec_build_node=0
        fi
        ;;
    java)
        project_lang='java'
        path_for_rsync=
        if [[ "$project_docker" -ne 1 || $ENV_FORCE_RSYNC == 'true' ]]; then
            exec_build_java=1
        fi
        ;;
    python)
        project_lang='python'
        path_for_rsync=
        if [[ "$project_docker" -ne 1 || $ENV_FORCE_RSYNC == 'true' ]]; then
            exec_build_python=1
        fi
        ;;
    *)
        # if grep '^## android' "${gitlab_project_dir}/.gitlab-ci.yml" >/dev/null; then
        project_lang='other'
        exec_deploy_rsync=0
        ;;
    esac
}

func_process_args() {
    [[ "${PIPELINE_DEBUG:-0}" -eq 1 || "$1" =~ (--debug|--github) ]] && debug_on=1
    [[ "$debug_on" -eq 1 ]] && set -x
    ## 1，默认情况执行所有任务，
    ## 2，如果传入参数，则通过传递入参执行单个任务。适用于单独的gitlab job，（一个 pipeline 多个独立的 job）
    while [[ "${#}" -ge 0 ]]; do
        case $1 in
        --debug)
            debug_on=1
            ;;
        --github-action)
            debug_on=1
            github_action=1
            ;;
        --renwe-cert)
            func_renew_cert
            exec_auto=0
            ;;
        --build-docker)
            build_docker
            exec_auto=0
            ;;
        --docker-push)
            docker_push
            exec_auto=0
            ;;
        --deploy-k8s)
            deploy_k8s
            exec_auto=0
            ;;
        --build-php)
            build_php_composer
            exec_auto=0
            ;;
        --build-node)
            build_node_yarn
            exec_auto=0
            ;;
        --build-java)
            build_java_maven
            exec_auto=0
            ;;
        --build-python)
            build_python_pip
            exec_auto=0
            ;;
        --code-style)
            func_code_style
            exec_auto=0
            ;;
        --code-quality)
            func_code_quality_sonar
            exec_auto=0
            ;;
        --deploy-flyway)
            func_deploy_flyway
            exec_auto=0
            ;;
        --deploy-rsync)
            func_deploy_rsync
            exec_auto=0
            ;;
        --deploy-notify)
            func_deploy_notify
            exec_auto=0
            ;;
        --test-unit)
            func_test_unit
            exec_auto=0
            ;;
        --test-function)
            func_test_function
            exec_auto=0
            ;;
        *)
            ## 1，默认情况执行所有任务，
            exec_auto=${exec_auto:-1}
            break
            ;;
        esac
        shift
    done

}

main() {
    ## 处理传入的参数
    func_process_args "$@"

    script_name="$(basename "$0")"
    script_path="$(cd "$(dirname "$0")" && pwd)"
    script_path_conf="${script_path}/conf"
    script_path_bin="${script_path}/bin"
    script_conf="${script_path_conf}/deploy.conf"      ## 发布到目标服务器的配置信息
    script_env="${script_path_conf}/deploy.env"        ## 发布配置信息(密)
    script_data="${script_path}/data"                  ## 记录 deploy.sh 的数据文件
    script_log="${script_data}/${script_name}.log"     ## 记录 deploy.sh 执行情况
    script_dockerfile="${script_path_conf}/dockerfile" ## dockerfile

    [[ ! -f "$script_conf" ]] && cp "${script_path_conf}/deploy.conf.example" "$script_conf"
    [[ ! -f "$script_env" ]] && cp "${script_path_conf}/deploy.env.example" "$script_env"
    [[ ! -f "$script_log" ]] && touch "$script_log"

    PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/usr/local/sbin:/snap/bin"
    PATH="$PATH:$script_data/jdk/bin:$script_data/jmeter/bin:$script_data/ant/bin:$script_data/maven/bin"
    PATH="$PATH:$script_path_bin:$HOME/.config/composer/vendor/bin:$HOME/.local/bin"
    export PATH

    ## run docker with current/root user
    docker_run="docker run --interactive --rm -u $UID:$UID"
    # docker_run_root="docker run --interactive --rm -u 0:0"
    git_diff="git --no-pager diff --name-only HEAD^"
    kubectl_opt="kubectl --kubeconfig $HOME/.kube/config"
    helm_opt="helm --kubeconfig $HOME/.kube/config"

    ## 检查OS 类型和版本，安装基础命令和软件包
    func_check_os

    ## 人工/手动/执行/定义参数
    func_setup_var_gitlab
    ## source ENV, 获取 ENV_ 开头的所有全局变量
    source "$script_env"
    if [ -z "$ENV_HTTP_PROXY" ]; then
        curl_opt="curl -L"
    else
        curl_opt="curl -x$ENV_HTTP_PROXY -L"
    fi

    ## 安装依赖命令/工具
    [[ "${ENV_INSTALL_AWS}" == 'true' ]] && install_aws
    [[ "${ENV_INSTALL_KUBECTL}" == 'true' ]] && install_kubectl
    [[ "${ENV_INSTALL_HELM}" == 'true' ]] && install_helm
    [[ "${ENV_INSTALL_PYTHON_ELEMENT}" == 'true' ]] && install_python_element
    [[ "${ENV_INSTALL_PYTHON_GITLAB}" == 'true' ]] && install_python_gitlab
    [[ "${ENV_INSTALL_JMETER}" == 'true' ]] && install_jmeter

    env_image_reg="${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}"
    env_image_tag="${gitlab_project_name}-${gitlab_commit_short_sha}"
    image_registry="${env_image_reg}:${env_image_tag}"

    ## 清理磁盘空间
    func_clean_disk

    ## setup ssh config/ acme.sh/aws/kube/aliyun/python-gitlab/cloudflare/rsync
    func_config_files

    ## acme.sh 更新证书
    echo "PIPELINE_RENEW_CERT: ${PIPELINE_RENEW_CERT:-0}"
    [[ "$PIPELINE_RENEW_CERT" -eq 1 ]] && func_renew_cert

    ## 判定项目类型
    func_detect_project_type

    ## 文件预处理
    func_file_preprocessing

    ## 全自动执行所有步骤
    [[ "$exec_auto" -ne 1 ]] && return

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_SONAR ，1 启用，0 禁用[default]
    echo "PIPELINE_SONAR: ${PIPELINE_SONAR:-0}"
    [[ "${PIPELINE_SONAR:-0}" -eq 1 ]] && func_code_quality_sonar

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_CODE_STYLE ，1 启用[default]，0 禁用
    echo "PIPELINE_CODE_STYLE: ${PIPELINE_CODE_STYLE:-0}"
    [[ "${PIPELINE_CODE_STYLE:-0}" -eq 1 ]] && func_code_style

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_UNIT_TEST ，1 启用[default]，0 禁用
    echo "PIPELINE_UNIT_TEST: ${PIPELINE_UNIT_TEST:-1}"
    [[ "${PIPELINE_UNIT_TEST:-1}" -eq 1 ]] && func_test_unit

    ## use flyway deploy sql file
    echo "PIPELINE_FLYWAY: ${PIPELINE_FLYWAY:-1}"
    [[ -d "${gitlab_project_dir}/${ENV_FLYWAY_SQL:-docs/sql}" ]] || exec_deploy_flyway=0
    [[ "${PIPELINE_FLYWAY:-1}" -eq 0 ]] && exec_deploy_flyway=0
    [[ "${ENV_HELM_FLYWAY:-0}" -eq 1 ]] && exec_deploy_flyway=0
    [[ ${exec_deploy_flyway:-1} -eq 1 ]] && func_deploy_flyway
    # [[ ${exec_deploy_flyway:-1} -eq 1 ]] && func_deploy_flyway_docker

    ## generate api docs
    # func_generate_apidoc

    ## build/deploy
    [[ "${exec_build_php}" -eq 1 ]] && build_php_composer
    [[ "${exec_build_node}" -eq 1 ]] && build_node_yarn
    [[ "${exec_build_java}" -eq 1 ]] && build_java_maven
    [[ "${exec_build_python}" -eq 1 ]] && build_python_pip
    [[ "${exec_build_docker}" -eq 1 ]] && build_docker
    [[ "${exec_docker_push}" -eq 1 ]] && docker_push
    [[ "${exec_deploy_k8s}" -eq 1 ]] && deploy_k8s

    [[ "${project_docker}" -eq 1 || "$ENV_DISABLE_RSYNC" -eq 1 ]] && exec_deploy_rsync=0
    [[ $ENV_FORCE_RSYNC == 'true' ]] && exec_deploy_rsync=1
    [[ "${exec_deploy_rsync:-1}" -eq 1 ]] && func_deploy_rsync

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_FUNCTION_TEST ，1 启用[default]，0 禁用
    echo "PIPELINE_FUNCTION_TEST: ${PIPELINE_FUNCTION_TEST:-1}"
    [[ "${PIPELINE_FUNCTION_TEST:-1}" -eq 1 ]] && func_test_function

    ## notify
    ## 发送消息到群组, exec_deploy_notify， 0 不发， 1 发.
    [[ "${github_action:-0}" -eq 1 ]] && deploy_result=0
    [[ "${deploy_result}" -eq 1 ]] && exec_deploy_notify=1
    [[ "$ENV_DISABLE_MSG" = 1 ]] && exec_deploy_notify=0
    [[ "$ENV_DISABLE_MSG_BRANCH" =~ $gitlab_project_branch ]] && exec_deploy_notify=0
    [[ "${exec_deploy_notify:-1}" == 1 ]] && func_deploy_notify

    ## deploy result:  0 成功， 1 失败
    return $deploy_result
}

main "$@"
