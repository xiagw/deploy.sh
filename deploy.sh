#!/usr/bin/env bash

# set -x #debug mode = true # set +x #debug mode = false
set -e ## 出现错误自动退出
# set -u ## 变量未定义报错
################################################################################
#
# Description: Gitlab deploy, rsync file, import sql, deploy k8s
# Author: xiagw <fxiaxiaoyu@gmail.com>
# License: GNU/GPL, see http://www.gnu.org/copyleft/gpl.html
# Date: 2019-04-03
#
################################################################################

# install gitlab-runner, https://docs.gitlab.com/runner/install/linux-manually.html
# http://www.ttlsa.com/auto/gitlab-cicd-variables-zh-document/

echo_info() { echo -e "\033[32m$*\033[0m"; }    ## green
echo_warn() { echo -e "\033[33m$*\033[0m"; }    ## yellow
echo_err() { echo -e "\033[31m$*\033[0m"; }     ## red
echo_ques() { echo -e "\033[35m$*\033[0m"; }    ## brown
echo_time() { echo "[$(date +%F-%T-%w)], $*"; } ## time
echo_time_step() {
    echo -e "[$(date +%F-%T-%w)], \033[33mstep-$((STEP + 1))\033[0m, $*"
    STEP=$((STEP + 1))
}
# https://zhuanlan.zhihu.com/p/48048906
# https://www.jianshu.com/p/bf0ffe8e615a
# https://www.cnblogs.com/lsgxeva/p/7994474.html
# https://eslint.bootcss.com
# http://eslint.cn/docs/user-guide/getting-started
format_check_node() {
    echo_time_step "[TODO] eslint format check."
}

format_check_python() {
    echo_time_step "[TODO] vsc-extension-hadolint."
}

## https://github.com/squizlabs/PHP_CodeSniffer
## install ESlint: yarn global add eslint ("$HOME/".yarn/bin/eslint)
format_check_php() {
    echo_time_step "starting PHP Code Sniffer, < standard=PSR12 >."
    if ! docker images | grep 'deploy/phpcs'; then
        DOCKER_BUILDKIT=1 docker build -t deploy/phpcs -f "$script_dir/docker/Dockerfile.phpcs" "$script_dir/docker" >/dev/null
    fi
    phpcs_result=0
    for i in $($git_diff | awk '/\.php$/{if (NR>0){print $0}}'); do
        if [ -f "$CI_PROJECT_DIR/$i" ]; then
            if ! $docker_run -v "$CI_PROJECT_DIR":/project deploy/phpcs phpcs -n --standard=PSR12 --colors --report="${phpcs_report:-full}" "/project/$i"; then
                phpcs_result=$((phpcs_result + 1))
            fi
        else
            echo_warn "$CI_PROJECT_DIR/$i NOT EXIST."
        fi
    done
    if [ "$phpcs_result" -ne "0" ]; then
        exit $phpcs_result
    fi
}

# https://github.com/alibaba/p3c/wiki/FAQ
format_check_java() {
    echo_time_step "[TODO] Java code format check."
}

format_check_dockerfile() {
    echo_time_step "[TODO] vsc-extension-hadolint."
}

code_format_check() {
    [[ "${project_lang}" == php ]] && format_check_php
    [[ "${project_lang}" == node ]] && format_check_node
    [[ "${project_lang}" == java ]] && format_check_java
    [[ "${project_lang}" == python ]] && format_check_python
    [[ "${project_docker}" == 1 ]] && format_check_dockerfile
}

## install phpunit
unit_test() {
    echo_time_step "unit test."
}

## install sonar-scanner to system user: "gitlab-runner"
sonar_scan() {
    echo_time_step "sonar scanner."
    sonar_url="${ENV_SONAR_URL:?empty}"
    if ! curl "$sonar_url" >/dev/null 2>&1; then
        echo_warn "Could not found sonarqube server."
        return
    fi
    # $docker_run -v $(pwd):/root/src --link sonarqube newtmitch/sonar-scanner
    if [[ ! -f "$CI_PROJECT_DIR/sonar-project.properties" ]]; then
        echo "sonar.host.url=$sonar_url
            sonar.projectKey=$CI_PROJECT_NAME
            sonar.projectName=$CI_PROJECT_NAME
            sonar.java.binaries=.
            sonar.sourceEncoding=UTF-8
            sonar.exclusions=\
            docs/**/*,\
            log/**/*,\
            test/**/*
            sonar.projectVersion=1.0
            sonar.import_unknown_files=true" >"$CI_PROJECT_DIR/sonar-project.properties"
    fi
    $docker_run -v "$CI_PROJECT_DIR":/usr/src sonarsource/sonar-scanner-cli
    # --add-host="sonar.entry.one:192.168.145.12"
}

ZAP_scan() {
    echo_time_step "[TODO] ZAP scan"
    # docker pull owasp/zap2docker-stable
}

vulmap_scan() {
    echo_time_step "[TODO] vulmap scan"
}

## install jdk/ant/jmeter
function_test() {
    echo_time_step "function test"
    command -v jmeter >/dev/null || echo_warn "command not exists: jmeter"
    # jmeter -load
}

flyway_use_local() {
    [[ "${enableSonar:-0}" -eq 1 ]] && return 0
    [[ "${disableFlyway:-0}" -eq 1 ]] && return 0

    echo_time_step "flyway migrate..."

    flywayHome="${ENV_FLYWAY_PATH:-${script_dir}/flyway}"

    if [ "${ENV_FLYWAY_USER_ROOT}" = 'true' ]; then
        flywayConfPath="$flywayHome/conf:/flyway/conf"
    else
        flywayConfPath="$flywayHome/conf/${CI_COMMIT_REF_NAME}.${CI_PROJECT_NAME}:/flyway/conf"
    fi

    flywaySqlPath="${CI_PROJECT_DIR}/docs/sql:/flyway/sql"

    ## exec flyway
    if docker run --rm -v "${flywaySqlPath}" -v "${flywayConfPath}" flyway/flyway info | grep -i pending; then
        docker run --rm -v "${flywaySqlPath}" -v "${flywayConfPath}" flyway/flyway repair
        docker run --rm -v "${flywaySqlPath}" -v "${flywayConfPath}" flyway/flyway migrate && deploy_result=0 || deploy_result=1
        docker run --rm -v "${flywaySqlPath}" -v "${flywayConfPath}" flyway/flyway info
    else
        echo "Nothing to do."
    fi

    echo_time "end flyway migrate"
}

flyway_use_helm() {
    flyway_last_sql="$(if [ -d "${ENV_GIT_SQL_FOLDER}" ]; then git --no-pager log --name-only --no-merges --oneline "${ENV_GIT_SQL_FOLDER}" | grep -m1 "^${ENV_GIT_SQL_FOLDER}" || true; fi)"
    ## used AWS EFS
    flyway_path_nfs="$ENV_FLYWAY_NFS_FOLDER"
    if [ -z "$db_name" ]; then
        flyway_db="${CI_PROJECT_NAME//-/_}"
    else
        flyway_db="$db_name"
    fi
    flyway_path_db="$flyway_path_nfs/sql-${CI_COMMIT_REF_NAME}/$flyway_db"

    if [[ ! -f "$flyway_path_db/${flyway_last_sql##*/}" && -n $flyway_last_sql ]]; then
        echo_warn "found new sql, enable flyway."
    else
        return 0
    fi
    if $git_diff | grep -qv "${ENV_GIT_SQL_FOLDER}.*\.sql$"; then
        echo_warn "found other file, enable deploy k8s."
    else
        echo_warn "skip deploy k8s."
        project_lang=0
        project_docker=0
        exec_deploy_rsync=0
    fi

    echo_time_step "flyway migrate (k8s)..."
    flyway_path_helm="$script_dir/helm/flyway"
    flyway_job='job-flyway'
    flyway_base_sql='V1.0__Base_structure.sql'
    flyway_path_conf="$flyway_path_nfs/conf-${CI_COMMIT_REF_NAME}/$flyway_db"

    ## flyway.conf change database name to current project name.
    if [ ! -f "$flyway_path_conf/flyway.conf" ]; then
        [ -d "$flyway_path_conf" ] || mkdir -p "$flyway_path_conf"
        cp "$flyway_path_conf/../flyway.conf" "$flyway_path_conf/flyway.conf"
        sed -i "/^flyway.url/s@3306/.*@3306/${flyway_db}@" "$flyway_path_conf/flyway.conf"
    fi
    ## did you run 'flyway baseline'?
    if [[ -f "$flyway_path_db/$flyway_base_sql" ]]; then
        ## copy sql file from git to nfs
        if [[ -d "${CI_PROJECT_DIR}/$ENV_GIT_SQL_FOLDER" ]]; then
            rsync -av --delete --exclude="$flyway_base_sql" "${CI_PROJECT_DIR}/$ENV_GIT_SQL_FOLDER/" "$flyway_path_db/"
        fi
        set_baseline=false
    else
        mkdir -p "$flyway_path_db"
        touch "$flyway_path_db/$flyway_base_sql"
        set_baseline=true
        echo_err "First run，only 'flyway baseline' was executed, please rerun this job."
        echo_err "首次运行，仅仅执行了 'flyway baseline', 请重新运行此job."
        deploy_result=1
    fi
    ## delete old job
    helm -n "$CI_COMMIT_REF_NAME" delete $flyway_job || true
    ## create new job
    helm -n "$CI_COMMIT_REF_NAME" upgrade --install --history-max 1 \
        -f "$flyway_path_helm/values.yaml" \
        --set baseLine=$set_baseline \
        --set nfs.confPath="/flyway/conf-${CI_COMMIT_REF_NAME}/$flyway_db" \
        --set nfs.sqlPath="/flyway/sql-${CI_COMMIT_REF_NAME}/$flyway_db" \
        $flyway_job "$flyway_path_helm/" >/dev/null
    ## wait result
    until [[ "$SECONDS" -gt 60 || "$flyway_result" -eq 1 ]]; do
        [[ $(kubectl -n "$CI_COMMIT_REF_NAME" get jobs $flyway_job -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}') == "True" ]] && flyway_result=0
        [[ $(kubectl -n "$CI_COMMIT_REF_NAME" get jobs $flyway_job -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}') == "True" ]] && flyway_result=1
        sleep 2
        SECONDS=$((SECONDS + 2))
    done
    ## get logs
    pods=$(kubectl -n "$CI_COMMIT_REF_NAME" get pods --selector=job-name=$flyway_job --output=jsonpath='{.items[*].metadata.name}')
    for p in $pods; do
        kubectl -n "$CI_COMMIT_REF_NAME" logs "pod/$p"
    done
    ## set result
    if [[ "$flyway_result" -eq 1 ]]; then
        deploy_result=1
    fi
    echo_time "end flyway migrate"
}

# https://github.com/nodesource/distributions#debinstall
node_build_volume() {
    echo_time_step "node yarn build."
    config_env_path="$(find "${CI_PROJECT_DIR}" -maxdepth 1 -name "${CI_COMMIT_REF_NAME}.*")"
    for file in $config_env_path; do
        \cp -vf "$file" "${file/${CI_COMMIT_REF_NAME}/}"
    done
    if [[ -d "${CI_PROJECT_DIR}/config" ]]; then
        config_env_path="$(find "${CI_PROJECT_DIR}/config" -maxdepth 1 -name "${CI_COMMIT_REF_NAME}.*")"
        for file in $config_env_path; do
            \cp -vf "$file" "${file/${CI_COMMIT_REF_NAME}./}"
        done
    fi
    rm -f package-lock.json
    # if [[ ! -d node_modules ]] || git diff --name-only HEAD~1 package.json | grep package.json; then
    if ! docker images | grep 'deploy/node' >/dev/null; then
        DOCKER_BUILDKIT=1 docker build -t deploy/node -f "$script_dir/dockerfile/Dockerfile.node" "$script_dir/dockerfile" >/dev/null
    fi
    if [[ -f "$script_dir/bin/custome.docker.build.sh" ]]; then
        source "$script_dir/bin/custome.docker.build.sh"
    else
        $docker_run -v "${CI_PROJECT_DIR}":/app -w /app deploy/node bash -c "yarn install; yarn run build"
    fi
}

node_docker_build() {
    echo_time_step "node docker build."
    \cp -f "$script_dir/node/Dockerfile" "${CI_PROJECT_DIR}/Dockerfile"
    DOCKER_BUILDKIT=1 docker build -t "${docker_tag}" "${CI_PROJECT_DIR}"
}

node_docker_push() {
    echo_time_step "node docker push."
    docker push "${docker_tag}"
}

php_composer_volume() {
    echo_time_step "php composer install..."
    echo "PIPELINE_COMPOSER_UPDATE: ${PIPELINE_COMPOSER_UPDATE:-0}"
    echo "PIPELINE_COMPOSER_INSTALL: ${PIPELINE_COMPOSER_INSTALL:-0}"
    if ! docker images | grep 'deploy/composer' >/dev/null; then
        DOCKER_BUILDKIT=1 docker build -t deploy/composer --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE}" -f "$script_dir/dockerfile/Dockerfile.composer" "$script_dir/dockerfile" >/dev/null
    fi
    if [[ "${PIPELINE_COMPOSER_UPDATE:-0}" -eq 1 ]] || git diff --name-only HEAD~2 composer.json | grep composer.json; then
        p=update
    fi
    if [[ ! -d vendor || "${PIPELINE_COMPOSER_INSTALL:-0}" -eq 1 ]]; then
        p=install
    fi
    if [[ -n "$p" ]]; then
        $docker_run -v "$PWD:/app" -w /app deploy/composer composer $p || true
        # $docker_run -v "$PWD:/app" -w /app deploy/composer composer update || true
    fi
}

php_docker_build() {
    echo_time_step "php docker build..."
    push_tag="${ENV_DOCKER_REGISTRY:?empty}/${ENV_DOCKER_REPO}:${CI_PROJECT_NAME}-${CI_COMMIT_REF_NAME}"
    echo_time_step "starting docker build..."
    \cp "$script_dir/Dockerfile.swoft" "${CI_PROJECT_DIR}/Dockerfile"
    DOCKER_BUILDKIT=1 docker build --tag "${push_tag}" --build-arg CHANGE_SOURCE=true -q "${CI_PROJECT_DIR}" >/dev/null
    echo_time "end docker build."
}

php_docker_push() {
    echo_time_step "starting docker push..."
    docker push "${push_tag}"
    echo_time "end docker push."
}

kube_create_namespace() {
    if [ ! -f "$script_dir/.lock.namespace.$CI_COMMIT_REF_NAME" ]; then
        kubectl create namespace "$CI_COMMIT_REF_NAME" || true
        touch "$script_dir/.lock.namespace.$CI_COMMIT_REF_NAME"
    fi
}

# 列出所有项目
# gitlab -v -o yaml -f path_with_namespace project list --all |awk -F': ' '{print $2}' |sort >p.txt
# 解决 Encountered 1 file(s) that should have been pointers, but weren't
# git lfs migrate import --everything$(awk '/filter=lfs/ {printf " --include='\''%s'\''", $1}' .gitattributes)

docker_build_java() {
    echo_time_step "java docker build."
    ## gitlab-CI/CD setup variables MVN_DEBUG=1 enable debug message
    echo_warn "If you want to view debug msg, set MVN_DEBUG=1 on pipeline."
    [[ "${MVN_DEBUG:-0}" == 1 ]] && unset MVN_DEBUG || MVN_DEBUG='-q'
    ## if you have no apollo config center, use local .env
    env_file="$script_dir/.env.${CI_PROJECT_NAME}.${CI_COMMIT_REF_NAME}"
    if [ ! -f "$env_file" ]; then
        ## generate mysql username/password
        # [ -x generate_env_file.sh ] && bash generate_env_file.sh
        [ -f "$script_dir/.env.tpl" ] && generate_env_file "$env_file"
    fi
    [ -f "$env_file" ] && cp -f "$env_file" "${CI_PROJECT_DIR}/.env"

    cp -f "$script_dir/docker/.dockerignore" "${CI_PROJECT_DIR}/"
    cp -f "$script_dir/docker/settings.xml" "${CI_PROJECT_DIR}/"
    if [ -f "${CI_PROJECT_DIR}/Dockerfile.useLocal" ]; then
        mv Dockerfile.useLocal Dockerfile
    else
        cp -f "$script_dir/docker/Dockerfile.bitnami.tomcat" "${CI_PROJECT_DIR}/Dockerfile"
    fi
    if [[ "$(grep -c '^FROM.*' Dockerfile || true)" -ge 2 ]]; then
        # shellcheck disable=2013
        for target in $(awk '/^FROM\s/ {print $4}' Dockerfile | grep -v 'BUILDER'); do
            [ "${ENV_DOCKER_TAG_ADD:-0}" = 1 ] && docker_tag_loop="${docker_tag}-$target" || docker_tag_loop="${docker_tag}"
            DOCKER_BUILDKIT=1 docker build "${CI_PROJECT_DIR}" --quiet --add-host="$ENV_MYNEXUS" -t "${docker_tag_loop}" \
                --target "$target" --build-arg GIT_BRANCH="${CI_COMMIT_REF_NAME}" --build-arg MVN_DEBUG="${MVN_DEBUG}" >/dev/null
        done
    else
        DOCKER_BUILDKIT=1 docker build "${CI_PROJECT_DIR}" --quiet --add-host="$ENV_MYNEXUS" -t "${docker_tag}" \
            --build-arg GIT_BRANCH="${CI_COMMIT_REF_NAME}" --build-arg MVN_DEBUG="${MVN_DEBUG}" >/dev/null
    fi
    echo_time "end docker build."
}

docker_login() {
    case "$ENV_DOCKER_LOGIN" in
    'aws')
        ## 比较上一次登陆时间，超过12小时则再次登录
        local lock_file
        lock_file="$script_dir/.aws.ecr.login.${ENV_AWS_PROFILE:?undefine}"
        touch "$lock_file"
        local timeSave
        timeSave="$(cat "$lock_file")"
        local time_compare
        time_compare="$(date +%s -d '12 hours ago')"
        if [ "$time_compare" -gt "${timeSave:-0}" ]; then
            echo_time "docker login..."
            docker_login="docker login --username AWS --password-stdin ${ENV_DOCKER_REGISTRY}"
            aws ecr get-login-password --profile="${ENV_AWS_PROFILE}" --region "${ENV_REGION_ID:?undefine}" | $docker_login >/dev/null
            date +%s >"$lock_file"
        fi
        ;;
    'aliyun')
        echo "aliyun docker login"
        echo "${ENV_DOCKER_PASSWORD}" | docker login --username="${ENV_DOCKER_USERNAME}" --password-stdin "${ENV_DOCKER_REGISTRY}"
        ;;
    'qcloud')
        echo "qcloud docker login"
        echo "${ENV_DOCKER_PASSWORD}" | docker login --username="${ENV_DOCKER_USERNAME}" --password-stdin "${ENV_DOCKER_REGISTRY}"
        ;;
    esac
}

docker_push_java() {
    echo_time_step "docker push to ECR."
    docker_login
    if [[ "$(grep -c '^FROM.*' Dockerfile || true)" -ge 2 ]]; then
        # shellcheck disable=2013
        for target in $(awk '/^FROM\s/ {print $4}' Dockerfile | grep -v 'BUILDER'); do
            [ "${ENV_DOCKER_TAG_ADD:-0}" = 1 ] && docker_tag_loop="${docker_tag}-$target" || docker_tag_loop="${docker_tag}"
            docker images "${docker_tag_loop}" --format "table {{.ID}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
            docker push "${docker_tag_loop}" >/dev/null
        done
    else
        docker images "${docker_tag}" --format "table {{.ID}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
        docker push "${docker_tag}" >/dev/null
    fi
    echo_time "end docker push."
}

java_deploy_k8s() {
    echo_time_step "deploy to k8s."
    kube_create_namespace
    helm_dir_project="$script_dir/helm/${ENV_HELM_DIR}"
    # shellcheck disable=2013
    for target in $(awk '/^FROM\s/ {print $4}' Dockerfile | grep -v 'BUILDER'); do
        if [ "${ENV_DOCKER_TAG_ADD:-0}" = 1 ]; then
            docker_tag_loop="${CI_PROJECT_NAME}-${CI_COMMIT_SHORT_SHA}-$target"
            work_name_loop="${CI_PROJECT_NAME}-$target"
        else
            docker_tag_loop="${CI_PROJECT_NAME}-${CI_COMMIT_SHORT_SHA}"
            work_name_loop="${CI_PROJECT_NAME}"
        fi
        helm -n "$CI_COMMIT_REF_NAME" upgrade --install --history-max 1 "${work_name_loop}" "$helm_dir_project/" \
            --set nameOverride="$work_name_loop" \
            --set image.registry="${ENV_DOCKER_REGISTRY}" \
            --set image.repository="${ENV_DOCKER_REPO}" \
            --set image.tag="${docker_tag_loop}" \
            --set resources.requests.cpu=200m \
            --set resources.requests.memory=512Mi \
            --set persistence.enabled=false \
            --set persistence.nfsServer="${ENV_NFS_SERVER:?undefine var}" \
            --set service.port=8080 \
            --set service.externalTrafficPolicy=Local \
            --set service.type=ClusterIP \
            --set replicaCount="${ENV_HELM_REPLICS:-1}" \
            --set livenessProbe="${ENV_PROBE_URL:?undefine}" >/dev/null
        ## 等待就绪
        if ! kubectl -n "$CI_COMMIT_REF_NAME" rollout status deployment "${work_name_loop}"; then
            errPod="$(kubectl -n "$CI_COMMIT_REF_NAME" get pods -l app="${CI_PROJECT_NAME}" | awk '/'"${CI_PROJECT_NAME}"'.*0\/1/ {print $1}')"
            echo_err "---------------cut---------------"
            kubectl -n "$CI_COMMIT_REF_NAME" describe "pod/${errPod}" | tail
            echo_err "---------------cut---------------"
            kubectl -n "$CI_COMMIT_REF_NAME" logs "pod/${errPod}" | tail -n 100
            echo_err "---------------cut---------------"
            deploy_result=1
        fi
    done

    kubectl -n "$CI_COMMIT_REF_NAME" get replicasets.apps | grep '0         0         0' | awk '{print $1}' | xargs kubectl -n "$CI_COMMIT_REF_NAME" delete replicasets.apps >/dev/null 2>&1 || true
}

docker_build_generic() {
    echo_time_step "docker build only."
    DOCKER_BUILDKIT=1 docker build -t "$docker_tag" "${CI_PROJECT_DIR}"
}

docker_push_generic() {
    echo_time_step "docker push only."
    docker_login
    docker push "$docker_tag"
}

deploy_k8s_generic() {
    echo_time_step "deploy k8s."
    kube_create_namespace
    path_helm="$script_dir/helm/bitnami/bitnami/nginx"
    (
        cd "$path_helm"
        git checkout master
        git checkout -- .
        git pull --prune
    )
    helm -n "$CI_COMMIT_REF_NAME" upgrade --install --history-max 1 "${CI_PROJECT_NAME}" "$path_helm/"
}

deploy_rsync() {
    echo_time_step "rsync code file to remote server."
    ## 读取配置文件，获取 项目/分支名/war包目录
    grep "^${CI_PROJECT_PATH}\s\+${CI_COMMIT_REF_NAME}" "$script_conf" || {
        echo_err "if stop here, check .deploy.conf"
        return 1
    }
    grep "^${CI_PROJECT_PATH}\s\+${CI_COMMIT_REF_NAME}" "$script_conf" | while read -r line; do
        # for line in $(grep "^${CI_PROJECT_PATH}\s\+${CI_COMMIT_REF_NAME}" "$script_conf"); do
        # shellcheck disable=2116
        read -ra array <<<"$(echo "$line")"
        ssh_host=${array[2]}
        ssh_port=${array[3]}
        rsync_src=${array[4]}
        rsync_dest=${array[5]} ## 从配置文件读取目标路径
        # db_user=${array[6]}
        # db_host=${array[7]}
        db_name=${array[8]}
        ## 防止出现空变量（若有空变量则自动退出）
        if [[ -z ${ssh_host} ]]; then
            echo "if stop here, check .deploy.conf"
            return 1
        fi
        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=20 -p ${ssh_port:-22}"
        if [[ -f "${CI_PROJECT_DIR}/rsync.exclude" ]]; then
            rsync_conf="${CI_PROJECT_DIR}/rsync.exclude"
        else
            rsync_conf="${script_dir}/rsync.exclude"
        fi
        [[ "${project_lang}" == 'node' || "${project_lang}" == 'java' ]] && rsync_delete='--delete'
        rsync_opt="rsync -acvzt --exclude=.svn --exclude=.git --timeout=20 --no-times --exclude-from=${rsync_conf} $rsync_delete"

        ## 源文件夹
        if [[ "${project_lang}" == 'node' ]]; then
            rsync_src="${CI_PROJECT_DIR}/dist/"
        elif [[ "$rsync_src" == 'null' || -z "$rsync_src" ]]; then
            rsync_src="${CI_PROJECT_DIR}/"
        elif [[ "$rsync_src" =~ \.[jw]ar$ ]]; then
            find_file="$(find "${CI_PROJECT_DIR}" -name "$rsync_src" -print0 | head -n 1)"
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
        if [[ "$rsync_dest" == 'null' || -z "$rsync_src" ]]; then
            rsync_dest="${ENV_PATH_DEST_PRE}/${CI_COMMIT_REF_NAME}.${CI_PROJECT_NAME}/"
        fi
        ## 发布到 aliyun oss 存储
        if [[ "${rsync_dest}" =~ '^oss://' ]]; then
            command -v aliyun >/dev/null || echo_warn "command not exist: aliyun"
            # bucktName="${rsync_dest#oss://}"
            # bucktName="${bucktName%%/*}"
            aliyun oss cp -rf "${CI_PROJECT_DIR}/" "$rsync_dest/"
            return
        fi
        ## 判断目标服务器/目标目录 是否存在？不存在则登录到目标服务器建立目标路径
        $ssh_opt "${ssh_host}" "test -d $rsync_dest || mkdir -p $rsync_dest"
        ## 复制文件到目标服务器的目标目录
        ${rsync_opt} -e "$ssh_opt" "${rsync_src}" "${ssh_host}:${rsync_dest}"
        ## 复制项目密码/密钥等配置文件，例如数据库配置，密钥文件等
        secret_dir="${script_dir}/.secret.${CI_COMMIT_REF_NAME}.${CI_PROJECT_NAME}/"
        if [ -d "$secret_dir" ]; then
            rsync -rlcvzt -e "$ssh_opt" "$secret_dir" "${ssh_host}:${rsync_dest}"
        fi
    done
}

get_msg_deploy() {
    # mr_iid="$(gitlab project-merge-request list --project-id "$CI_PROJECT_ID" --page 1 --per-page 1 | awk '/^iid/ {print $2}')"
    ## sudo -H python3 -m pip install PyYaml
    # [ -z "$msg_describe" ] && msg_describe="$(gitlab -v project-merge-request get --project-id "$CI_PROJECT_ID" --iid "$mr_iid" | sed -e '/^description/,/^diff-refs/!d' -e 's/description: //' -e 's/diff-refs.*//')"
    [ -z "$msg_describe" ] && msg_describe="$(git --no-pager log --no-merges --oneline -1)"
    git_username="$(gitlab -v user get --id "${GITLAB_USER_ID}" | awk '/^name:/ {print $2}')"

    msg_body="[Gitlab Deploy]
Project = ${CI_PROJECT_PATH}/${CI_COMMIT_REF_NAME}
Pipeline = ${CI_PIPELINE_ID}/Job-id-$CI_JOB_ID
Describe = [${CI_COMMIT_SHORT_SHA}]/${msg_describe}
Who = ${GITLAB_USER_ID}-${git_username}
Result = $([ 0 = "${deploy_result:-0}" ] && echo OK || echo FAIL)
"
}

send_msg_chatapp() {
    echo_time_step "send message to chatApp."
    if [[ 1 -eq "${ENV_NOTIFY_WEIXIN:-0}" ]]; then
        weixin_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${ENV_WEIXIN_KEY:?undefine var}"
        curl -s "$weixin_api" \
            -H 'Content-Type: application/json' \
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
        python3 "$script_dir/bin/element-up.py" "$msg_body"
    elif [[ 1 -eq "${ENV_NOTIFY_ELEMENT:-0}" && "${PIPELINE_TEMP_PASS:-0}" -ne 1 ]]; then
        python3 "$script_dir/bin/element.py" "$msg_body"
    elif [[ 1 -eq "${ENV_NOTIFY_EMAIL:-0}" ]]; then
        echo_warn "[TODO] send email to you."
    else
        echo "No message send."
    fi
}

update_cert() {
    echo_time_step "update ssl cert (dns api)."
    acme_home="${HOME}/.acme.sh"
    cmd_run="${acme_home}/acme.sh"
    ## install acme.sh
    if [[ ! -x "${cmd_run}" ]]; then
        curl https://get.acme.sh | sh
    fi
    cert_dir="${acme_home}/dest"
    [ -d "$cert_dir" ] || mkdir "$cert_dir"

    if [[ "$(find "${acme_home}/" -name 'account.conf*' | wc -l)" == 1 ]]; then
        cp "${acme_home}/"account.conf "${acme_home}/"account.conf.1
    fi

    for a in "${acme_home}/"account.conf.*; do
        if [ -f "$script_dir/.cloudflare.conf" ]; then
            command -v flarectl || return 1
            source "$script_dir/.cloudflare.conf" "${a##*.}"
            domain_name="$(flarectl zone list | awk '/active/ {print $3}')"
            dnsType='dns_cf'
        elif [ -f "$script_dir/.aliyun.dnsapi.conf" ]; then
            command -v aliyun || return 1
            source "$script_dir/.aliyun.dnsapi.conf" "${a##*.}"
            domain_name="$(aliyun domain QueryDomainList --output cols=DomainName rows=Data.Domain --PageNum 1 --PageSize 100 | sed '1,2d')"
            dnsType='dns_ali'
        elif [ -f "$script_dir/.qcloud.dnspod.conf" ]; then
            echo_warn "[TODO] use dnspod api."
        fi
        \cp -vf "$a" "${acme_home}/account.conf"

        for d in ${domain_name}; do
            if [ -d "${acme_home}/$d" ]; then
                "${cmd_run}" --renew -d "${d}" || true
            else
                "${cmd_run}" --issue --dns $dnsType -d "$d" -d "*.$d"
            fi
            "${cmd_run}" --install-cert -d "$d" --key-file "$cert_dir/$d".key.pem \
                --fullchain-file "$cert_dir/$d".cert.pem
        done
    done
}

install_aws() {
    if ! command -v aws >/dev/null; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip -qq awscliv2.zip
        sudo ./aws/install
    fi
}

install_python_gitlab() {
    command -v gitlab >/dev/null || python3 -m pip install --user --upgrade python-gitlab
    [ -e "$HOME/".python-gitlab.cfg ] || ln -sf "$script_dir/etc/python-gitlab.cfg" "$HOME/"
}

install_kubectl() {
    command -v kubectl >/dev/null || {
        kube_ver="$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)"
        kube_url="https://storage.googleapis.com/kubernetes-release/release/$kube_ver/bin/linux/amd64/kubectl"
        if [ -z "$ENV_HTTP_PROXY" ]; then
            curl -Lo "$script_dir/bin/kubectl" "$kube_url"
        else
            curl -x "$ENV_HTTP_PROXY" -Lo "$script_dir/bin/kubectl" "$kube_url"
        fi
        chmod +x "$script_dir/bin/kubectl"
    }
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
        exit 1
    fi
    if [[ "$OS" =~ (debian|ubuntu) ]]; then
        ## fix gitlab-runner exit error.
        if [[ -e "$HOME"/.bash_logout ]]; then
            mv -f "$HOME"/.bash_logout "$HOME"/.bash_logout.bak
        fi
        command -v git >/dev/null || sudo apt install -y git
        git lfs version >/dev/null || sudo apt install -y git-lfs
        command -v unzip >/dev/null || sudo apt install -y unzip
        command -v rsync >/dev/null || sudo apt install -y rsync
        # command -v docker >/dev/null || bash "$script_dir/bin/get-docker.sh"
        id | grep -q docker || sudo usermod -aG docker "$USER"
        command -v pip3 >/dev/null || sudo apt install -y python3-pip
        command -v java >/dev/null || sudo apt install -y openjdk-8-jdk
        # command -v shc >/dev/null || sudo apt install -y shc
    elif [[ "$OS" == 'centos' ]]; then
        rpm -q epel-release >/dev/null || sudo yum install -y epel-release
        command -v git >/dev/null || sudo yum install -y git2u
        git lfs version >/dev/null || sudo yum install -y git-lfs
        command -v rsync >/dev/null || sudo yum install -y rsync
        # command -v docker >/dev/null || sh "$script_dir/bin/get-docker.sh"
        id | grep -q docker || sudo usermod -aG docker "$USER"
    elif [[ "$OS" == 'amzn' ]]; then
        rpm -q epel-release >/dev/null || sudo amazon-linux-extras install -y epel
        command -v git >/dev/null || sudo yum install -y git2u
        git lfs version >/dev/null || sudo yum install -y git-lfs
        command -v rsync >/dev/null || sudo yum install -y rsync
        # command -v docker >/dev/null || sudo amazon-linux-extras install -y docker
        id | grep -q docker || sudo usermod -aG docker "$USER"
    fi
}

clean_disk() {
    ## clean cache of docker build
    disk_usage="$(df / | awk 'NR>1 {print $5}')"
    disk_usage="${disk_usage/\%/}"
    if ((disk_usage < 80)); then
        return
    fi
    docker images "${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}" -q | sort | uniq |
        while read -r line; do
            docker rmi -f "$line" >/dev/null || true
        done
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

gen_apidoc() {
    echo_time_step "generate apidoc."
    if [[ -f "${CI_PROJECT_DIR}/apidoc.json" ]]; then
        $docker_run -v "${CI_PROJECT_DIR}":/app -w /app deploy/node bash -c "apidoc -i app/ -o public/apidoc/"
    fi
}
main() {
    script_name="$(basename "$0")"
    script_name="${script_name%.sh}"
    script_dir="$(cd "$(dirname "$0")" && pwd)"

    PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/usr/local/sbin:/snap/bin"
    PATH="$PATH:$script_dir/jdk/bin:$script_dir/jmeter/bin:$script_dir/ant/bin:$script_dir/maven/bin"
    PATH="$PATH:$script_dir/bin:$HOME/.config/composer/vendor/bin:$HOME/.local/bin"
    export PATH

    ## 检查OS 类型和版本，安装相应命令和软件包
    check_os

    [[ "${ENV_INSTALL_AWS}" == true ]] && install_aws
    [[ "${ENV_INSTALL_PYTHON_GITLAB}" == true ]] && install_python_gitlab
    [[ "${ENV_INSTALL_KUBECTL}" == true ]] && install_kubectl

    ## 处理传入的参数
    ## 1，默认情况执行所有任务，
    ## 2，如果传入参，则通过传递入参执行单个任务。。适用于单独的gitlab job，（gitlab 一个 pipeline 多个job）
    while [[ "${#}" -ge 0 ]]; do
        case $1 in
        --update-ssl)
            PIPELINE_UPDATE_SSL=1
            ;;
        --docker-build-java)
            exec_docker_build_java=1
            ;;
        --docker-push-java)
            exec_docker_push_java=1
            ;;
        --deploy-k8s-java)
            exec_deploy_k8s_java=1
            ;;
        --docker-build-php)
            exec_docker_build_php=1
            ;;
        --docker-push-php)
            exec_docker_push_php=1
            ;;
        --deploy-k8s-php)
            exec_deploy_k8s_php=1
            ;;
        --docker-build-node)
            exec_docker_build_node=1
            ;;
        --docker-push-node)
            exec_docker_push_node=1
            ;;
        --deploy-k8s-node)
            exec_node_deploy_k8s=1
            ;;
        --disable-rsync)
            exec_deploy_rsync=0
            ;;
        --diable-flyway)
            exec_flyway=0
            ;;
        *)
            exec_docker_build_java=1
            exec_docker_push_java=1
            exec_deploy_k8s_java=1
            exec_deploy_k8s_php=1
            # gitlabSingleJob=0
            break
            ;;
        esac
        shift
    done
    ##
    script_log="${script_dir}/${script_name}.log"            ## 记录sql文件的执行情况
    script_conf="${script_dir}/.${script_name}.conf"         ## 发布到服务器的配置信息
    script_env="${script_dir}/.${script_name}.env"           ## 发布配置信息(密)
    script_ssh_conf="${script_dir}/.${script_name}.ssh.conf" ## ssh config 信息，跳板机/堡垒机

    [[ ! -f "$script_conf" && -f "${script_dir}/${script_name}.conf" ]] && cp "${script_dir}/${script_name}.conf" "$script_conf"
    [[ ! -f "$script_env" && -f "${script_dir}/${script_name}.env" ]] && cp "${script_dir}/${script_name}.env" "$script_env"
    [[ ! -f "$script_log" ]] && touch "$script_log"

    if [[ -f "${script_dir}/id_rsa" ]]; then
        chmod 600 "${script_dir}/id_rsa"
        ln -sf "${script_dir}/id_rsa" "$HOME/.ssh/"
    fi
    if [[ -f "${script_dir}/id_ed25519" ]]; then
        chmod 600 "${script_dir}/id_ed25519"
        ln -sf "${script_dir}/id_ed25519" "$HOME/.ssh/"
    fi
    if [[ -f "${script_dir}/id_ecdsa" ]]; then
        chmod 600 "${script_dir}/id_ecdsa"
        ln -sf "${script_dir}/id_ecdsa" "$HOME/.ssh/"
    fi
    if [[ -f "${script_ssh_conf}" ]]; then
        chmod 600 "${script_ssh_conf}"
        ln -sf "${script_ssh_conf}" "$HOME/.ssh/config"
    fi
    [[ ! -e "${HOME}/.acme.sh" && -e "${script_dir}/.acme.sh" ]] && ln -sf "${script_dir}/.acme.sh" "$HOME/"
    [[ ! -e "${HOME}/.aws" && -e "${script_dir}/.aws" ]] && ln -sf "${script_dir}/.aws" "$HOME/"
    [[ ! -e "${HOME}/.kube" && -e "${script_dir}/.kube" ]] && ln -sf "${script_dir}/.kube" "$HOME/"
    [[ ! -e "${HOME}/.python-gitlab.cfg" && -e "${script_dir}/.python-gitlab.cfg" ]] && ln -sf "${script_dir}/.python-gitlab.cfg" "$HOME/"
    ## source ENV, 获取 ENV_ 开头的所有全局变量
    # shellcheck disable=SC1090
    source "$script_env"
    ## run docker using current user
    docker_run="docker run --interactive --rm -u $UID:$UID"
    ## run docker using root
    # runDockeRoot="docker run --interactive --rm"
    docker_tag="${ENV_DOCKER_REGISTRY:?undefine}/${ENV_DOCKER_REPO:?undefine}:${CI_PROJECT_NAME:?undefine var}-${CI_COMMIT_SHORT_SHA}"
    git_diff="git --no-pager diff --name-only HEAD^"
    ## 清理磁盘空间
    clean_disk
    ## acme.sh 更新证书
    if [[ "$PIPELINE_UPDATE_SSL" -eq 1 ]]; then
        update_cert
    fi
    ## 判定项目类型
    if [[ -f "${CI_PROJECT_DIR:?undefine var}/package.json" ]]; then
        if [[ -d "${CI_PROJECT_DIR}/ios" || -d "${CI_PROJECT_DIR}/android" ]]; then
            project_lang='react'
        else
            project_lang='node'
        fi
    fi
    [[ -f "${CI_PROJECT_DIR}/composer.json" ]] && project_lang='php'
    [[ -f "${CI_PROJECT_DIR}/pom.xml" ]] && project_lang='java'
    [[ -f "${CI_PROJECT_DIR}/requirements.txt" ]] && project_lang='python'
    [[ -f "${CI_PROJECT_DIR}/Dockerfile" ]] && project_docker=1
    echo "PIPELINE_DISABLE_DOCKER: ${PIPELINE_DISABLE_DOCKER:-0}"
    [[ "${PIPELINE_DISABLE_DOCKER:-0}" -eq 1 || "${ENV_DISABLE_DOCKER:-0}" -eq 1 ]] && project_docker=0
    echo "PIPELINE_SONAR: ${PIPELINE_SONAR:-0}"
    echo "PIPELINE_FLYWAY: ${PIPELINE_FLYWAY:-1}"
    [[ "${PIPELINE_SONAR:-0}" -eq 1 || "${PIPELINE_FLYWAY:-1}" -eq 0 ]] && exec_flyway=0
    [[ ! -d "${CI_PROJECT_DIR}/docs/sql" ]] && exec_flyway=0
    if [[ ${exec_flyway:-1} -eq 1 ]]; then
        if [[ "${project_docker}" -eq 1 ]]; then
            flyway_use_helm
        else
            flyway_use_local
        fi
    fi
    ## 蓝绿发布，灰度发布，金丝雀发布的k8s配置文件

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_SONAR ，1 启用，0 禁用[default]
    if [[ 1 -eq "${PIPELINE_SONAR:-0}" ]]; then
        sonar_scan
        return $?
    fi
    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_UNIT_TEST ，1 启用[default]，0 禁用
    echo "PIPELINE_UNIT_TEST: ${PIPELINE_UNIT_TEST:-1}"
    if [[ "${PIPELINE_UNIT_TEST:-1}" -eq 1 ]]; then
        unit_test
    fi
    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_CODE_FORMAT ，1 启用[default]，0 禁用
    echo "PIPELINE_CODE_FORMAT: ${PIPELINE_CODE_FORMAT:-0}"
    if [[ 1 -eq "${PIPELINE_CODE_FORMAT:-0}" ]]; then
        code_format_check
    fi

    case "${project_lang}" in
    'php')
        ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_CODE_FORMAT ，1 启用[default]，0 禁用
        if [[ 1 -eq "${project_docker}" ]]; then
            [[ 1 -eq "$exec_docker_build_php" ]] && php_docker_build
            [[ 1 -eq "$exec_docker_push_php" ]] && php_docker_push
            [[ 1 -eq "$exec_deploy_k8s_php" ]] && deploy_k8s_generic
        else
            ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_COMPOSER_UPDATE ，1 启用，0 禁用[default]
            ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_COMPOSER_INSTALL ，1 启用，0 禁用[default]
            php_composer_volume
        fi
        ;;
    'node')
        if [[ 1 -eq "${project_docker}" ]]; then
            [[ 1 -eq "$exec_docker_build_node" ]] && node_docker_build
            [[ 1 -eq "$exec_docker_push_node" ]] && node_docker_push
            [[ 1 -eq "$exec_node_deploy_k8s" ]] && deploy_k8s_generic
        else
            node_build_volume
        fi
        ;;
    'java')
        if [[ 1 -eq "${project_docker}" ]]; then
            [[ 1 -eq "$exec_docker_build_java" ]] && docker_build_java
            [[ 1 -eq "$exec_docker_push_java" ]] && docker_push_java
            [[ 1 -eq "$exec_deploy_k8s_java" ]] && java_deploy_k8s
        fi
        ;;
    'react')
        echo_err "manual package"
        return
        ;;
    *)
        ## 各种Build， npm/composer/mvn/docker
        if [[ "$project_docker" -eq 1 ]]; then
            docker_build_generic
            docker_push_generic
            deploy_k8s_generic
        fi
        ;;
    esac

    gen_apidoc

    [[ "${project_docker}" -eq 1 || "$ENV_DISABLE_RSYNC" -eq 1 ]] && exec_deploy_rsync=0
    if [[ "${exec_deploy_rsync:-1}" -eq 1 ]]; then
        deploy_rsync
    fi

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_FUNCTION_TEST ，1 启用[default]，0 禁用
    echo "PIPELINE_FUNCTION_TEST: ${PIPELINE_FUNCTION_TEST:-1}"
    if [[ "${PIPELINE_FUNCTION_TEST:-1}" -eq 1 ]]; then
        function_test
    fi

    ## notify
    ## 发送消息到群组, enable_send_msg， 0 不发， 1 不发.
    [[ "${deploy_result}" -eq 1 ]] && enable_send_msg=1
    [[ "$ENV_DISABLE_MSG" = 1 ]] && enable_send_msg=0
    [[ "$CI_COMMIT_REF_NAME" = "$ENV_DISABLE_MSG_BRANCH" ]] && enable_send_msg=0
    if [[ "${enable_send_msg:-1}" == 1 ]]; then
        get_msg_deploy
        send_msg_chatapp
    fi

    ## deploy_result， 0 成功， 1 失败
    return $deploy_result
}

main "$@"
