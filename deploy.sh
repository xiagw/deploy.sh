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
echo_time_step() {
    ## year mon day - time - %u day of week (1..7); 1 is Monday - %j day of year (001..366) - %W   week number of year, with Monday as first day of week (00..53)
    echo -e "\033[33m[$(date +%Y%m%d-%T-%u)] step-$((STEP + 1)),\033[0m $*"
    STEP=$((STEP + 1))
}
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
    echo_time_step "starting PHP Code Sniffer, < standard=PSR12 >..."
    if ! docker images | grep 'deploy/phpcs'; then
        DOCKER_BUILDKIT=1 docker build -t deploy/phpcs -f "$path_dockerfile/Dockerfile.phpcs" "$path_dockerfile" >/dev/null
    fi
    phpcs_result=0
    for i in $($git_diff | awk '/\.php$/{if (NR>0){print $0}}'); do
        if [ -f "$gitlab_project_dir/$i" ]; then
            if ! $docker_run -v "$gitlab_project_dir":/project deploy/phpcs phpcs -n --standard=PSR12 --colors --report="${phpcs_report:-full}" "/project/$i"; then
                phpcs_result=$((phpcs_result + 1))
            fi
        else
            echo_warn "$gitlab_project_dir/$i not exists."
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
}

## install jdk/ant/jmeter
func_test_function() {
    echo_time_step "function test..."
    if [ -f "$gitlab_project_dir"/tests/func_test.sh ]; then
        bash "$gitlab_project_dir"/tests/func_test.sh
    fi
    echo_time "end function test."
}

## install sonar-scanner to system user: "gitlab-runner"
func_code_quality() {
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
    $docker_run -e SONAR_TOKEN="${ENV_SONAR_TOKEN:?empty}" -v "$gitlab_project_dir":/usr/src sonarsource/sonar-scanner-cli
    # $docker_run -v $(pwd):/root/src --link sonarqube newtmitch/sonar-scanner
    # --add-host="sonar.entry.one:192.168.145.12"
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
    [ -f "$script_path/bin/special.sh" ] && source "$script_path/bin/special.sh" port
    ## exec flyway
    if $flyway_docker_run info | grep '^|' | grep -vE 'Category.*Version|Versioned.*Success|Versioned.*Deleted|DELETE.*Success'; then
        $flyway_docker_run repair
        $flyway_docker_run migrate && deploy_result=0 || deploy_result=1
        $flyway_docker_run info | tail -n 10
        ## 断开数据库远程连接
    else
        echo "Nothing to do."
    fi
    echo_time "end flyway migrate."
    if [ ${deploy_result:-0} = 0 ]; then
        echo_info "Result = OK"
    else
        echo_erro "Result = FAIL"
    fi
}

func_deploy_flyway_docker() {
    ## docker build flyway
    image_tag_flyway="${ENV_DOCKER_REGISTRY:?undefine}/${ENV_DOCKER_REPO:?undefine}:${gitlab_project_name}-flyway"
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
    # if [[ ! -d node_modules ]] || git diff --name-only HEAD~1 package.json | grep package.json; then
    if ! docker images | grep 'deploy/node' >/dev/null; then
        DOCKER_BUILDKIT=1 docker build -t deploy/node -f "$path_dockerfile/Dockerfile.node" "$path_dockerfile" >/dev/null
    fi
    if [[ -f "$script_path/bin/custome.docker.build.sh" ]]; then
        source "$script_path/bin/custome.docker.build.sh"
    else
        $docker_run -v "${gitlab_project_dir}":/app -w /app deploy/node bash -c "yarn install; yarn run build"
    fi
    echo_time "end node build."
}

build_php_composer() {
    echo_time_step "php composer install..."
    if [ "${ENV_IMAGE_FROM_DOCKERFILE}" = 'Dockerfile' ]; then
        image_composer=$(awk '/FROM/ {print $2}' | tail -n 1)
    else
        image_composer="deploy/composer"
    fi
    if ! docker images | grep -q "deploy/composer"; then
        DOCKER_BUILDKIT=1 docker build --quiet -t "deploy/composer" --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE}" \
            -f "$path_dockerfile/Dockerfile.composer" "$path_dockerfile"
    fi

    [[ "${PIPELINE_COMPOSER_INSTALL:-0}" -eq 1 ]] && COMPOSER_INSTALL=true
    echo "PIPELINE_COMPOSER_INSTALL: ${PIPELINE_COMPOSER_INSTALL:-0}"
    echo "COMPOSER_INSTALL=${COMPOSER_INSTALL:-false}"
    if [[ "${COMPOSER_INSTALL:-false}" == 'true' ]]; then
        rm -f "${gitlab_project_dir}"/composer.lock
        # rm -rf "${gitlab_project_dir}"/vendor
        $docker_run -v "$gitlab_project_dir:/app" --env COMPOSER_INSTALL=${COMPOSER_INSTALL} -w /app "$image_composer" composer install -q || true
    fi
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
    source "$script_env"
    ## 比较上一次登陆时间，超过12小时则再次登录
    lock_docker_login="$script_path/conf/.lock.docker.login.${ENV_DOCKER_LOGIN_TYPE}"
    [ -f "$lock_docker_login" ] || touch "$lock_docker_login"
    time_save="$(cat "$lock_docker_login")"
    if [[ "$(date +%s -d '12 hours ago')" -lt "${time_save:-0}" ]]; then
        return 0
    fi
    echo_time "docker login $ENV_DOCKER_LOGIN_TYPE ..."
    if [[ "$ENV_DOCKER_LOGIN_TYPE" == 'aws' ]]; then
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
    if [ -n "$image_from" ]; then
        docker_build_tmpl=0
        ## 判断模版是否存在
        docker images | grep -q "${image_from%%:*}.*${image_from##*:}" || docker_build_tmpl=$((docker_build_tmpl + 1))
        if [[ "$docker_build_tmpl" -gt 0 ]]; then
            # 模版不存在，构建模板
            DOCKER_BUILDKIT=1 docker build -q --tag "${image_from}" --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE}" \
                -f "${gitlab_project_dir}/Dockerfile.${image_from##*:}" "${gitlab_project_dir}"
        fi
    fi

    ## docker build flyway
    if [[ $ENV_HELM_FLYWAY == 1 ]]; then
        image_tag_flyway="${ENV_DOCKER_REGISTRY:?undefine}/${ENV_DOCKER_REPO:?undefine}:${gitlab_project_name}-flyway"
        DOCKER_BUILDKIT=1 docker build -q --tag "${image_tag_flyway}" -f "${gitlab_project_dir}/Dockerfile.flyway" "${gitlab_project_dir}/" >/dev/null
    fi
    ## docker build
    [[ "${PIPELINE_YARN_INSTALL:-0}" -eq 1 ]] && YARN_INSTALL=true
    echo "PIPELINE_YARN_INSTALL: ${PIPELINE_YARN_INSTALL:-0}"
    echo "YARN_INSTALL: ${YARN_INSTALL:-false}"
    DOCKER_BUILDKIT=1 docker build -q --tag "${image_registry}" \
        --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE:-false}" \
        --build-arg YARN_INSTALL="${YARN_INSTALL}" \
        "${gitlab_project_dir}" >/dev/null
    echo_time "end docker build."
}

docker_push() {
    echo_time_step "docker push only..."
    docker_login
    # echo "$image_registry"
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
    helm_release="${helm_release,,}"
    if [ -d "$script_path/conf/helm/${gitlab_project_name}" ]; then
        path_helm="$script_path/conf/helm/${gitlab_project_name}"
    else
        if [ -d "$gitlab_project_dir/helm" ]; then
            path_helm="$gitlab_project_dir/helm"
        else
            path_helm=none
        fi
    fi

    image_tag="${gitlab_project_name}-${gitlab_commit_short_sha}"
    source "$script_env"
    if [ "$path_helm" = none ]; then
        echo_warn "helm files not exists, ignore helm install."
        [ -f "$script_path/bin/special.sh" ] && source "$script_path/bin/special.sh" "$branch_name"
    else
        set -x
        helm upgrade "${helm_release}" "$path_helm/" --install --history-max 1 \
            --namespace "${branch_name}" --create-namespace \
            --set image.repository="${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}" \
            --set image.tag="${image_tag}" \
            --set image.pullPolicy='Always' >/dev/null
        [[ "$debug_on" -ne 1 ]] && set +x
    fi
    if [[ $ENV_HELM_FLYWAY == 1 ]]; then
        helm upgrade flyway "$script_path/conf/helm/flyway/" --install --history-max 1 \
            --namespace "${branch_name}" --create-namespace \
            --set image.repository="${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}" \
            --set image.tag="${gitlab_project_name}-flyway" \
            --set image.pullPolicy='Always' >/dev/null
    fi
    kubectl -n "${branch_name}" get rs | awk '/.*0\s+0\s+0/ {print $1}' |
        xargs kubectl -n "${branch_name}" delete rs >/dev/null 2>&1 || true
    kubectl -n "${branch_name}" get pod | grep Evicted | awk '{print $1}' | xargs kubectl delete pod || true
    sleep 3
    if ! kubectl -n "${branch_name}" rollout status deployment "${helm_release}"; then
        deploy_result=1
    fi
    echo_time "end deploy k8s."
}

func_deploy_rsync() {
    echo_time_step "rsync code file to remote server..."
    ## 读取配置文件，获取 项目/分支名/war包目录
    grep "^${gitlab_project_path}\s\+${branch_name}" "$script_conf" || {
        echo_erro "if stop here, check GIT repository: pms/runner/conf/deploy.conf"
        return 1
    }
    grep "^${gitlab_project_path}\s\+${branch_name}" "$script_conf" | while read -r line; do
        # for line in $(grep "^${gitlab_project_path}\s\+${branch_name}" "$script_conf"); do
        # shellcheck disable=2116
        read -ra array <<<"$(echo "$line")"
        ssh_host=${array[2]}
        ssh_port=${array[3]}
        rsync_src=${array[4]}
        rsync_dest=${array[5]} ## 从配置文件读取目标路径
        # db_user=${array[6]}
        # db_host=${array[7]}
        # db_name=${array[8]}
        echo "${ssh_host}"
        ## 防止出现空变量（若有空变量则自动退出）
        if [[ -z ${ssh_host} ]]; then
            echo "if stop here, check conf/deploy.conf"
            return 1
        fi
        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=20 -p ${ssh_port:-22}"
        ## rsync exclude some files
        if [[ -f "${gitlab_project_dir}/rsync.exclude" ]]; then
            rsync_conf="${gitlab_project_dir}/rsync.exclude"
        else
            rsync_conf="${conf_rsync_exclude}"
        fi
        ## node/java use rsync --delete
        [[ "${project_lang}" == 'node' || "${project_lang}" == 'java' ]] && rsync_delete='--delete'
        rsync_opt="rsync -acvzt --exclude=.svn --exclude=.git --timeout=20 --no-times --exclude-from=${rsync_conf} $rsync_delete"

        ## 源文件夹
        if [[ "${project_lang}" == 'node' ]]; then
            rsync_src="${gitlab_project_dir}/dist/"
        elif [[ "${project_lang}" == 'react' ]]; then
            rsync_src="${gitlab_project_dir}/build/"
        elif [[ "$rsync_src" == 'null' || -z "$rsync_src" ]]; then
            rsync_src="${gitlab_project_dir}/"
        elif [[ "$rsync_src" =~ \.[jw]ar$ ]]; then
            find_file="$(find "${gitlab_project_dir}" -name "$rsync_src" -print0 | head -n 1)"
            if [ -z "$find_file" ]; then
                echo "file not found: ${find_file}"
                return 1
            elif [[ "$find_file" =~ \.[jw]ar$ ]]; then
                rsync_src="$find_file"
            else
                echo "file type error:${find_file}"
                return 1
            fi
        fi
        ## 目标文件夹
        if [[ "$rsync_dest" == 'null' || -z "$rsync_dest" ]]; then
            rsync_dest="${ENV_PATH_DEST_PRE}/${branch_name}.${gitlab_project_name}/"
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
    # [ -z "$msg_describe" ] && msg_describe="$(gitlab -v project-merge-request get --project-id "$gitlab_project_id" --iid "$mr_iid" | sed -e '/^description/,/^diff-refs/!d' -e 's/description: //' -e 's/diff-refs.*//')"
    [ -z "$msg_describe" ] && msg_describe="$(git --no-pager log --no-merges --oneline -1)"
    git_username="$(gitlab -v user get --id "${GITLAB_USER_ID}" | awk '/^name:/ {print $2}')"

    msg_body="
[Gitlab Deploy]
Project = ${gitlab_project_path}
Branche = ${gitlab_project_branch}
Pipeline = ${gitlab_pipeline_id}/JobID-$gitlab_job_id
Describe = [${gitlab_commit_short_sha}]/${msg_describe}
Who = ${GITLAB_USER_ID}/${git_username}
Result = $([ "${deploy_result:-0}" = 0 ] && echo OK || echo FAIL)
$(if [ -n "${test_result}" ]; then echo "Test_Result: ${test_result}" else :; fi)
"
}

func_deploy_notify() {
    echo_time_step "send message to chatApp..."
    func_deploy_notify_msg
    if [[ 1 -eq "${ENV_NOTIFY_WEIXIN:-0}" ]]; then
        weixin_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${ENV_WEIXIN_KEY:?undefine var}"
        curl -s "$weixin_api" -H 'Content-Type: application/json' \
            -d "
        {
            \"msgtype\": \"text\",
            \"text\": {
                \"content\": \"$msg_body\"
            }
        }"
    elif [[ 1 -eq "${ENV_NOTIFY_TELEGRAM:-0}" ]]; then
        tgApiMsg="https://api.telegram.org/bot${ENV_API_KEY_TG:?undefine var}/sendMessage"
        # tgApiUrlDoc="https://api.telegram.org/bot${ENV_API_KEY_TG:?undefine var}/sendDocument"
        msg_body="$(echo "$msg_body" | sed -e ':a;N;$!ba;s/\n/%0a/g' -e 's/&/%26/g')"
        if [ -n "$ENV_HTTP_PROXY" ]; then
            curl_opt="curl -x$ENV_HTTP_PROXY -sS -o /dev/null -X POST"
        else
            curl_opt="curl -sS -o /dev/null -X POST"
        fi
        $curl_opt -d "chat_id=${ENV_TG_GROUP_ID:?undefine var}&text=$msg_body" "$tgApiMsg"
    elif [[ 1 -eq "${PIPELINE_TEMP_PASS:-0}" ]]; then
        python3 "$script_path/bin/element-up.py" "$msg_body"
    elif [[ 1 -eq "${ENV_NOTIFY_ELEMENT:-0}" && "${PIPELINE_TEMP_PASS:-0}" -ne 1 ]]; then
        python3 "$script_path/bin/element.py" "$msg_body"
    elif [[ 1 -eq "${ENV_NOTIFY_EMAIL:-0}" ]]; then
        # mogaal/sendemail: lightweight, command line SMTP email client
        # https://github.com/mogaal/sendemail
        "$script_path/bin/sendEmail" \
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
    conf_dns_cloudflare="${script_path}/conf/.cloudflare.cfg"
    conf_dns_aliyun="${script_path}/conf/.aliyun.dnsapi.conf"
    conf_dns_qcloud="${script_path}/conf/.qcloud.dnspod.conf"

    ## install acme.sh
    if [[ ! -x "${acme_cmd}" ]]; then
        curl https://get.acme.sh | sh
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

    ## 如果有自定义的程序需要执行
    if [ -f "${acme_home}"/custom.acme.sh ]; then
        bash "${acme_home}"/custom.acme.sh
    fi
}

install_python_gitlab() {
    command -v gitlab >/dev/null && return
    python3 -m pip install --user --upgrade python-gitlab
}

install_python_element() {
    python3 -m pip install --user --upgrade matrix-nio
}

install_aws() {
    command -v aws >/dev/null && return
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -qq awscliv2.zip
    $exec_sudo ./aws/install
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    $exec_sudo mv /tmp/eksctl /usr/local/bin/
}

install_kubectl() {
    command -v kubectl >/dev/null && return
    kube_ver="$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)"
    kube_url="https://storage.googleapis.com/kubernetes-release/release/${kube_ver}/bin/linux/amd64/kubectl"
    if [ -z "$ENV_HTTP_PROXY" ]; then
        curl_opt="curl -Lo"
    else
        curl_opt="curl -x$ENV_HTTP_PROXY -Lo"
    fi
    $curl_opt "${script_path}/bin/kubectl" "$kube_url"
    chmod +x "${script_path}/bin/kubectl"
}

install_helm() {
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
}

install_jmeter() {
    ver_jmeter='5.4.1'
    dir_temp=$(mktemp -d)
    curl -Lo "$dir_temp"/jmeter.zip https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-${ver_jmeter}.zip
    (
        cd "$script_data"
        unzip "$dir_temp"/jmeter.zip
        ln -sf apache-jmeter-${ver_jmeter} jmeter
    )
    rm -rf "$dir_temp"
}

check_os() {
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

    if [[ "$OS" =~ (debian|ubuntu) ]]; then
        ## fix gitlab-runner exit error.
        if [[ -e "$HOME"/.bash_logout ]]; then
            mv -f "$HOME"/.bash_logout "$HOME"/.bash_logout.bak
        fi
        command -v git >/dev/null || $exec_sudo apt install -y git
        git lfs version >/dev/null || $exec_sudo apt install -y git-lfs
        command -v unzip >/dev/null || $exec_sudo apt install -y unzip
        command -v rsync >/dev/null || $exec_sudo apt install -y rsync
        # command -v docker >/dev/null || bash "$script_path/bin/get-docker.sh"
        id | grep -q docker || $exec_sudo usermod -aG docker "$USER"
        command -v pip3 >/dev/null || $exec_sudo apt install -y python3-pip
        command -v java >/dev/null || $exec_sudo apt install -y openjdk-8-jdk
        command -v jmeter >/dev/null || install_jmeter
        # command -v shc >/dev/null || $exec_sudo apt install -y shc
    elif [[ "$OS" == 'centos' ]]; then
        rpm -q epel-release >/dev/null || $exec_sudo yum install -y epel-release
        command -v git >/dev/null || $exec_sudo yum install -y git2u
        git lfs version >/dev/null || $exec_sudo yum install -y git-lfs
        command -v rsync >/dev/null || $exec_sudo yum install -y rsync
        # command -v docker >/dev/null || sh "$script_path/bin/get-docker.sh"
        id | grep -q docker || $exec_sudo usermod -aG docker "$USER"
    elif [[ "$OS" == 'amzn' ]]; then
        rpm -q epel-release >/dev/null || $exec_sudo amazon-linux-extras install -y epel
        command -v git >/dev/null || $exec_sudo yum install -y git2u
        git lfs version >/dev/null || $exec_sudo yum install -y git-lfs
        command -v rsync >/dev/null || $exec_sudo yum install -y rsync
        # command -v docker >/dev/null || $exec_sudo amazon-linux-extras install -y docker
        id | grep -q docker || $exec_sudo usermod -aG docker "$USER"
    fi
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
    curl -qs -Lo "$t1" https://dl.miyuru.lk/geoip/maxmind/country/maxmind.dat.gz
    curl -qs -Lo "$t2" https://dl.miyuru.lk/geoip/maxmind/city/maxmind.dat.gz
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
    echo_time "preprocessing file."
    ## frontend (VUE) .env file
    if [[ $project_lang =~ (node|react) ]]; then
        config_env_path="$(find "${gitlab_project_dir}" -maxdepth 2 -name "${branch_name}.*")"
        for file in $config_env_path; do
            if [[ "$file" =~ 'config/' ]]; then
                rsync -av "$file" "${file/${branch_name}./}" # vue2.x
            else
                rsync -av "$file" "${file/${branch_name}/}" # vue3.x
            fi
        done
        copy_flyway_file=0
    fi
    ## backend (PHP) project_conf files
    path_project_conf="${script_path}/conf/project_conf/${branch_name}.${gitlab_project_name}/"
    [ -d "$path_project_conf" ] && rsync -av "$path_project_conf" "${gitlab_project_dir}/"
    ## docker ignore file
    [ -f "${gitlab_project_dir}/.dockerignore" ] || rsync -av "${script_path}/conf/.dockerignore" "${gitlab_project_dir}/"
    ## cert file for nginx
    if [[ "${gitlab_project_name}" == "$ENV_NGINX_GIT_NAME" && -d "$HOME/.acme.sh/dest/" ]]; then
        rsync -av "$HOME/.acme.sh/dest/" "${gitlab_project_dir}/etc/nginx/conf.d/ssl/"
    fi
    ## Docker build from, 是否从模板构建
    image_from=$(awk '/^FROM/ {print $2}' Dockerfile | grep -q "${image_registry%%:*}" | head -n 1)
    if [ -n "$image_from" ]; then
        file_docker_tmpl="${path_dockerfile}/Dockerfile.${image_from##*:}"
        [ -f "${file_docker_tmpl}" ] && rsync -av "${file_docker_tmpl}" "${gitlab_project_dir}/"
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
        [[ -f "${gitlab_project_dir}/Dockerfile.flyway" ]] || rsync -av "${path_dockerfile}/Dockerfile.flyway" "${gitlab_project_dir}/"
    fi
}

func_config_ssh() {
    path_conf_ssh="${script_path}/conf/.ssh"
    if [[ ! -d "${path_conf_ssh}" ]]; then
        mkdir -m 700 "$path_conf_ssh"
        echo_warn "generate ssh key file for gitlab-runner: $path_conf_ssh/id_ed25519"
        echo_erro "cat $path_conf_ssh/id_ed25519.pub >> [dest_server]:\~/.ssh/authorized_keys"
        ssh-keygen -t ed25519 -N '' -f "$path_conf_ssh/id_ed25519"
        ln -sf "$path_conf_ssh" "$HOME/"
    fi
    for f in "$path_conf_ssh"/*; do
        if [ ! -f "$HOME/.ssh/${f##*/}" ]; then
            chmod 600 "${f}"
            ln -sf "${f}" "$HOME/.ssh/"
        fi
    done
}

func_setup_config() {
    path_conf_acme="${script_path}/conf/.acme.sh"
    path_conf_aws="${script_path}/conf/.aws"
    path_conf_kube="${script_path}/conf/.kube"
    path_conf_aliyun="${script_path}/conf/.aliyun"
    conf_python_gitlab="${script_path}/conf/.python-gitlab.cfg"
    conf_rsync_exclude="${script_path}/conf/rsync.exclude"
    [[ ! -d "${HOME}/.acme.sh" && -d "${path_conf_acme}" ]] && ln -sf "${path_conf_acme}" "$HOME/"
    [[ ! -d "${HOME}/.aws" && -d "${path_conf_aws}" ]] && ln -sf "${path_conf_aws}" "$HOME/"
    [[ ! -d "${HOME}/.kube" && -d "${path_conf_kube}" ]] && ln -sf "${path_conf_kube}" "$HOME/"
    [[ ! -d "${HOME}/.aliyun" && -d "${path_conf_aliyun}" ]] && ln -sf "${path_conf_aliyun}" "$HOME/"
    [[ ! -f "${HOME}/.python-gitlab.cfg" && -f "${conf_python_gitlab}" ]] && ln -sf "${conf_python_gitlab}" "$HOME/"
    return 0
}

func_setup_var_gitlab() {
    if [ -z "$CI_PROJECT_DIR" ]; then
        gitlab_project_dir="$PWD"
    else
        gitlab_project_dir=$CI_PROJECT_DIR
    fi
    if [ -z "$CI_PROJECT_NAME" ]; then
        gitlab_project_name=${PWD##*/}
    else
        gitlab_project_name=$CI_PROJECT_NAME
    fi
    if [ -z "$CI_PROJECT_NAMESPACE" ]; then
        read -rp "Enter gitlab project namespace: " -e -i 'root' gitlab_project_namespace
    else
        gitlab_project_namespace=$CI_PROJECT_NAMESPACE
    fi
    if [ -z "$CI_PROJECT_PATH" ]; then
        # read -rp "Enter gitlab project path: [root/git-repo] " -e -i 'root/xxx' gitlab_project_path
        gitlab_project_path=root/$gitlab_project_name
    else
        gitlab_project_path=$CI_PROJECT_PATH
    fi
    if [ -z "$CI_COMMIT_REF_NAME" ]; then
        read -rp "Enter branch name: " -e -i 'develop' gitlab_project_branch
    else
        gitlab_project_branch=$CI_COMMIT_REF_NAME
    fi
    if [ -z "$CI_COMMIT_SHORT_SHA" ]; then
        # read -rp "Enter commit short hash: " -e -i 'xxxxxx' gitlab_commit_short_sha
        gitlab_commit_short_sha="$(git rev-parse --short HEAD)"
    else
        gitlab_commit_short_sha=$CI_COMMIT_SHORT_SHA
    fi
    # if [ -z "$CI_PROJECT_ID" ]; then
    #     read -rp "Enter gitlab project id: " -e -i '1234' gitlab_project_id
    # else
    #     gitlab_project_id=$CI_PROJECT_ID
    # fi
    if [ -z "$CI_PIPELINE_ID" ]; then
        read -rp "Enter gitlab pipeline id: " -e -i '3456' gitlab_pipeline_id
    else
        gitlab_pipeline_id=$CI_PIPELINE_ID
    fi
    if [ -z "$CI_JOB_ID" ]; then
        read -rp "Enter gitlab job id: " -e -i '5678' gitlab_job_id
    else
        gitlab_job_id=$CI_JOB_ID
    fi

    branch_name=$gitlab_project_branch
}

func_detect_project_type() {
    echo "PIPELINE_DISABLE_DOCKER: ${PIPELINE_DISABLE_DOCKER:-0}"
    echo "PIPELINE_SONAR: ${PIPELINE_SONAR:-0}"
    if [[ -f "${gitlab_project_dir}/Dockerfile" ]]; then
        project_docker=1
        exec_build_docker=1
        exec_docker_push=1
        exec_deploy_k8s=1
        if [[ "${PIPELINE_DISABLE_DOCKER:-0}" -eq 1 || "${ENV_DISABLE_DOCKER:-0}" -eq 1 ]]; then
            project_docker=0
            exec_build_docker=0
            exec_docker_push=0
            exec_deploy_k8s=0
        fi
    fi
    if [[ -f "${gitlab_project_dir}/package.json" ]]; then
        if grep -i -q 'Create React' "${gitlab_project_dir}/README.md" "${gitlab_project_dir}/readme.md" >/dev/null 2>&1; then
            project_lang='react'
        else
            project_lang='node'
        fi
        if ! grep -q "$(md5sum "${gitlab_project_dir}/package.json" | awk '{print $1}')" "${script_log}"; then
            echo "$gitlab_project_path $branch_name $(md5sum "${gitlab_project_dir}/package.json")" >>"${script_log}"
            YARN_INSTALL=true
        fi
        if [[ "$project_docker" -ne 1 || $ENV_FORCE_RSYNC == 'true' ]]; then
            exec_build_node=1
        fi
    fi
    if [[ -f "${gitlab_project_dir}/composer.json" ]]; then
        project_lang='php'
        if ! grep -q "$(md5sum "${gitlab_project_dir}/composer.json" | awk '{print $1}')" "${script_log}"; then
            echo "$gitlab_project_path $branch_name $(md5sum "${gitlab_project_dir}/composer.json")" >>"${script_log}"
            COMPOSER_INSTALL=true
        fi
        if [[ "$project_docker" -ne 1 || $ENV_FORCE_RSYNC == 'true' ]]; then
            exec_build_php=1
        fi
    fi
    if [[ -f "${gitlab_project_dir}/pom.xml" ]]; then
        project_lang='java'
        if [[ "$project_docker" -ne 1 || $ENV_FORCE_RSYNC == 'true' ]]; then
            exec_build_java=1
        fi
    fi
    if [[ -f "${gitlab_project_dir}/requirements.txt" ]]; then
        project_lang='python'
        if [[ "$project_docker" -ne 1 || $ENV_FORCE_RSYNC == 'true' ]]; then
            exec_build_python=1
        fi
    fi
    if grep '^## android' "${gitlab_project_dir}/.gitlab-ci.yml" >/dev/null; then
        project_lang='android'
        exec_deploy_rsync=0
    fi
    if grep '^## ios' "${gitlab_project_dir}/.gitlab-ci.yml" >/dev/null; then
        project_lang='ios'
        exec_deploy_rsync=0
    fi
}

main() {
    [[ -f ~/ci_debug || $PIPELINE_DEBUG == 'true' ]] && debug_on=1
    [[ "$1" == '--debug' ]] && debug_on=1
    [[ "$debug_on" -eq 1 ]] && set -x
    script_name="$(basename "$0")"
    script_path="$(cd "$(dirname "$0")" && pwd)"
    script_data="${script_path}/data"                   ## 记录 deploy.sh 的数据文件
    script_log="${script_path}/data/${script_name}.log" ## 记录 deploy.sh 执行情况
    script_conf="${script_path}/conf/deploy.conf"       ## 发布到目标服务器的配置信息
    script_env="${script_path}/conf/deploy.env"         ## 发布配置信息(密)
    path_dockerfile="${script_path}/conf/dockerfile"    ## dockerfile

    [[ ! -f "$script_conf" ]] && cp "${script_path}/conf/deploy.conf.example" "$script_conf"
    [[ ! -f "$script_env" ]] && cp "${script_path}/conf/deploy.env.example" "$script_env"
    [[ ! -f "$script_log" ]] && touch "$script_log"

    PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/usr/local/sbin:/snap/bin"
    PATH="$PATH:$script_data/jdk/bin:$script_data/jmeter/bin:$script_data/ant/bin:$script_data/maven/bin"
    PATH="$PATH:$script_path/bin:$HOME/.config/composer/vendor/bin:$HOME/.local/bin"
    export PATH

    if [[ $UID == 0 ]]; then
        exec_sudo=
    else
        exec_sudo=sudo
    fi

    ## 检查OS 类型和版本，安装相应命令和软件包
    check_os

    ## 安装依赖命令/工具
    [[ "${ENV_INSTALL_AWS}" == 'true' ]] && install_aws
    [[ "${ENV_INSTALL_KUBECTL}" == 'true' ]] && install_kubectl
    [[ "${ENV_INSTALL_HELM}" == 'true' ]] && install_helm
    [[ "${ENV_INSTALL_PYTHON_ELEMENT}" == 'true' ]] && install_python_element
    [[ "${ENV_INSTALL_PYTHON_GITLAB}" == 'true' ]] && install_python_gitlab

    ## 人工/手动/执行/定义参数
    func_setup_var_gitlab

    ## source ENV, 获取 ENV_ 开头的所有全局变量
    source "$script_env"

    ## run docker with current/root user
    docker_run="docker run --interactive --rm -u $UID:$UID"
    # docker_run_root="docker run --interactive --rm -u 0:0"
    git_diff="git --no-pager diff --name-only HEAD^"
    image_registry="${ENV_DOCKER_REGISTRY:?undefine}/${ENV_DOCKER_REPO:?undefine}:${gitlab_project_name}-${gitlab_commit_short_sha}"

    ## setup ssh config
    func_config_ssh

    ## setup acme.sh/aws/kube/aliyun/python-gitlab/cloudflare/rsync
    func_setup_config

    ## 清理磁盘空间
    func_clean_disk

    ## acme.sh 更新证书
    echo "PIPELINE_RENEW_CERT: ${PIPELINE_RENEW_CERT:-0}"
    if [[ "$PIPELINE_RENEW_CERT" -eq 1 ]]; then
        func_renew_cert
        return
    fi

    ## 判定项目类型
    func_detect_project_type

    ## 文件预处理
    func_file_preprocessing

    ## 处理传入的参数
    ## 1，默认情况执行所有任务，
    ## 2，如果传入参数，则通过传递入参执行单个任务。适用于单独的gitlab job，（一个 pipeline 多个独立的 job）
    while [[ "${#}" -ge 0 ]]; do
        case $1 in
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
            func_code_quality
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
            [ -z "$exec_auto" ] && exec_auto=1
            break
            ;;
        esac
        shift
    done

    ## 全自动执行所有步骤
    if [[ "$exec_auto" -ne 1 ]]; then
        return
    fi

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_SONAR ，1 启用，0 禁用[default]
    echo "PIPELINE_SONAR: ${PIPELINE_SONAR:-0}"
    if [[ "${PIPELINE_SONAR:-0}" -eq 1 ]]; then
        func_code_quality
        return $?
    fi

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_CODE_STYLE ，1 启用[default]，0 禁用
    echo "PIPELINE_CODE_STYLE: ${PIPELINE_CODE_STYLE:-0}"
    if [[ "${PIPELINE_CODE_STYLE:-0}" -eq 1 ]]; then
        func_code_style
    fi

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_UNIT_TEST ，1 启用[default]，0 禁用
    echo "PIPELINE_UNIT_TEST: ${PIPELINE_UNIT_TEST:-1}"
    if [[ "${PIPELINE_UNIT_TEST:-1}" -eq 1 ]]; then
        func_test_unit
    fi

    ## use flyway deploy sql file
    echo "PIPELINE_FLYWAY: ${PIPELINE_FLYWAY:-1}"
    [[ -d "${gitlab_project_dir}/${ENV_FLYWAY_SQL:-docs/sql}" ]] || exec_deploy_flyway=0
    [[ "${PIPELINE_FLYWAY:-1}" -eq 0 ]] && exec_deploy_flyway=0
    [[ "${ENV_HELM_FLYWAY:-0}" -eq 1 ]] && exec_deploy_flyway=0
    if [[ ${exec_deploy_flyway:-1} -eq 1 ]]; then
        func_deploy_flyway
        # func_deploy_flyway_docker
    fi

    ## generate api docs
    # func_generate_apidoc

    ## build/deploy
    [[ "${exec_build_docker}" -eq 1 ]] && build_docker
    [[ "${exec_docker_push}" -eq 1 ]] && docker_push
    [[ "${exec_deploy_k8s}" -eq 1 ]] && deploy_k8s
    [[ "${exec_build_php}" -eq 1 ]] && build_php_composer
    [[ "${exec_build_node}" -eq 1 ]] && build_node_yarn
    [[ "${exec_build_java}" -eq 1 ]] && build_java_maven
    [[ "${exec_build_python}" -eq 1 ]] && build_python_pip

    [[ "${project_docker}" -eq 1 || "$ENV_DISABLE_RSYNC" -eq 1 ]] && exec_deploy_rsync=0
    [[ $ENV_FORCE_RSYNC == 'true' ]] && exec_deploy_rsync=1
    if [[ "${exec_deploy_rsync:-1}" -eq 1 ]]; then
        func_deploy_rsync
    fi

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_FUNCTION_TEST ，1 启用[default]，0 禁用
    echo "PIPELINE_FUNCTION_TEST: ${PIPELINE_FUNCTION_TEST:-1}"
    if [[ "${PIPELINE_FUNCTION_TEST:-1}" -eq 1 ]]; then
        func_test_function
    fi

    ## notify
    ## 发送消息到群组, exec_deploy_notify， 0 不发， 1 发.
    [[ "${deploy_result}" -eq 1 ]] && exec_deploy_notify=1
    [[ "$ENV_DISABLE_MSG" = 1 ]] && exec_deploy_notify=0
    [[ "$ENV_DISABLE_MSG_BRANCH" =~ $gitlab_project_branch ]] && exec_deploy_notify=0
    if [[ "${exec_deploy_notify:-1}" == 1 ]]; then
        func_deploy_notify
    fi

    ## deploy result:  0 成功， 1 失败
    return $deploy_result
}

main "$@"
