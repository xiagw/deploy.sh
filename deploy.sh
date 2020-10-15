#!/bin/bash
# shellcheck disable=SC1090,SC1091,SC2091
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

echo_i() { echo -e "\033[32m$*\033[0m"; }    ## green
echo_w() { echo -e "\033[33m$*\033[0m"; }    ## yellow
echo_e() { echo -e "\033[31m$*\033[0m"; }    ## red
echo_q() { echo -e "\033[35m$*\033[0m"; }    ## brown
echo_t() { echo "[$(date +%F-%T-%w)], $*"; } ## time
echo_s() {
    echo -e "[$(date +%F-%T-%w)], \033[33mstep-$((STEP + 1))\033[0m, $*"
    STEP=$((STEP + 1))
}
# https://zhuanlan.zhihu.com/p/48048906
# https://www.jianshu.com/p/bf0ffe8e615a
# https://www.cnblogs.com/lsgxeva/p/7994474.html
# https://eslint.bootcss.com
# http://eslint.cn/docs/user-guide/getting-started
eslint_check() {
    echo_s "[TODO] eslint format check."
}

dockerfile_check() {
    echo_s "[TODO] vsc-extension-hadolint."
}

## https://github.com/squizlabs/PHP_CodeSniffer
## install ESlint: yarn global add eslint ("$HOME/".yarn/bin/eslint)
php_format_check() {
    echo_s "starting PHP Code Sniffer, < standard=PSR12 >."
    if ! docker images | grep 'deploy/phpcs'; then
        docker build -t deploy/phpcs -f "$script_dir/Dockerfile.phpcs" "$script_dir" >/dev/null
    fi
    phpcsResult=0
    for i in $($gitDiff | awk '/\.php$/{if (NR>0){print $0}}'); do
        if [ -f "$CI_PROJECT_DIR/$i" ]; then
            if ! $runDocker -v "$CI_PROJECT_DIR":/project deploy/phpcs phpcs -n --standard=PSR12 --colors --report="${phpcsReport:-full}" "/project/$i"; then
                phpcsResult=$((phpcsResult + 1))
            fi
        else
            echo_w "$CI_PROJECT_DIR/$i NOT EXIST."
        fi
    done
    if [ "$phpcsResult" -ne "0" ]; then
        exit $phpcsResult
    fi
}

# https://github.com/alibaba/p3c/wiki/FAQ
java_format_check() {
    echo_s "[TODO] Java code format check."
}

## install phpunit
unit_test() {
    [[ "${enableUnitTest:-1}" -eq 0 ]] && return
    echo_s "[TODO] unit test."
}

## install sonar-scanner to system user: "gitlab-runner"
sonar_scan() {
    echo_s "sonar scanner."
    sonarUrl="${ENV_SONAR_URL:?empty}"
    if ! curl "$sonarUrl" >/dev/null 2>&1; then
        echo_w "Could not found sonarqube server."
        return
    fi
    # $runDocker -v $(pwd):/root/src --link sonarqube newtmitch/sonar-scanner
    if [[ ! -f "$CI_PROJECT_DIR/sonar-project.properties" ]]; then
        echo "sonar.host.url=$sonarUrl
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
    $runDocker -v "$CI_PROJECT_DIR":/usr/src sonarsource/sonar-scanner-cli
    # --add-host="sonar.entry.one:192.168.145.12"
}

ZAP_scan() {
    echo_s "[TODO] ZAP scan"
    # docker pull owasp/zap2docker-stable
}

## install jdk/ant/jmeter
function_test() {
    echo_w "[TODO]."
}

flyway_migrate() {
    echo_w "[TODO]."
}

flyway_migrate_k8s() {
    flyway_last_sql="$(if [ -d "${ENV_GIT_SQL_FOLDER}" ]; then git --no-pager log --name-only --no-merges --oneline "${ENV_GIT_SQL_FOLDER}" | grep -m1 "^${ENV_GIT_SQL_FOLDER}" || true; fi)"
    flyway_nfs_path="$ENV_FLYWAY_NFS_FOLDER"
    if [ -z "$db_name" ]; then
        flyway_db="${CI_PROJECT_NAME//-/_}"
    else
        flyway_db="$db_name"
    fi
    flyway_path_db="$flyway_nfs_path/sql-${CI_COMMIT_REF_NAME}/$flyway_db"

    if [[ ! -f "$flyway_path_db/${flyway_last_sql##*/}" && -n $flyway_last_sql ]]; then
        echo_w "found new sql, enable flyway."
    else
        return 0
    fi
    if $gitDiff | grep -qv "${ENV_GIT_SQL_FOLDER}.*\.sql$"; then
        echo_w "found other file, enable deploy k8s."
    else
        echo_w "skip deploy k8s."
        project_lang=0
        project_docker=0
        exec_deploy_rsync=0
    fi

    echo_s "flyway migrate..."
    flyway_helm_dir="$script_dir/helm/flyway"
    flyway_job='job-flyway'
    flyway_base_sql='V1.0__Base_structure.sql'
    flyway_path_conf="$flyway_nfs_path/conf-${CI_COMMIT_REF_NAME}/$flyway_db"

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
        echo_e "首次运行，仅仅执行了 'flyway baseline', 请重新运行此job."
        deploy_result=1
    fi
    ## delete old job
    helm -n "$CI_COMMIT_REF_NAME" delete $flyway_job || true
    ## create new job
    helm -n "$CI_COMMIT_REF_NAME" upgrade --install --history-max 1 \
        -f "$flyway_helm_dir/values.yaml" \
        --set baseLine=$set_baseline \
        --set nfs.confPath="/flyway/conf-${CI_COMMIT_REF_NAME}/$flyway_db" \
        --set nfs.sqlPath="/flyway/sql-${CI_COMMIT_REF_NAME}/$flyway_db" \
        $flyway_job "$flyway_helm_dir/" >/dev/null
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
    echo_t "end flyway migrate"
}

# https://github.com/nodesource/distributions#debinstall
node_build_volume() {
    srcConfig="src/config/${CI_COMMIT_REF_NAME}.env.js src/api/${CI_COMMIT_REF_NAME}.config.js"
    for ff in $srcConfig; do
        if [ -f "${CI_PROJECT_DIR}/$ff" ]; then
            cp -vf "${CI_PROJECT_DIR}/$ff" "${ff/${CI_COMMIT_REF_NAME}./}"
        fi
    done

    # if [[ ! -d node_modules ]] || git diff --name-only HEAD~1 package.json | grep package.json; then
    if ! docker images | grep 'deploy/node'; then
        docker build -t deploy/node -f "$script_dir/node/Dockerfile" "$script_dir/node" >/dev/null
    fi
    DOCKER_BUILDKIT=1 $runDocker -v "${CI_PROJECT_DIR}":/app -w /app deploy/node bash -c "yarn install; yarn run build"
}

node_docker_build() {
    echo_s "node docker build."
    \cp -f "$script_dir/node/Dockerfile" "${CI_PROJECT_DIR}/Dockerfile"
    DOCKER_BUILDKIT=1 docker build "${CI_PROJECT_DIR}" -t "${dockerTag}"
}

node_docker_push() {
    echo_s "node docker push."
    docker push "${dockerTag}"
}

php_composer_volume() {
    echo_s "php composer install..."
    if ! docker images | grep 'deploy/composer'; then
        docker build -t deploy/composer --build-arg CHANGE_SOURCE=true -f "$script_dir/Dockerfile.composer" "$script_dir/dockerfile" >/dev/null
    fi
    if [[ "${composerUpdate:-0}" -eq 1 ]] || git diff --name-only HEAD~2 composer.json | grep composer.json; then
        p=update
    fi
    if [[ ! -d vendor || "${composerInstall:-0}" -eq 1 ]]; then
        p=install
    fi
    if [[ -n "$p" ]]; then
        $runDocker -v "$PWD:/app" -w /app deploy/composer composer $p
    fi
}

php_docker_build() {
    echo_s "php docker build..."
    pushTag="${ENV_DOCKER_REGISTRY:?empty}/${ENV_DOCKER_REPO}:${CI_PROJECT_NAME}-${CI_COMMIT_REF_NAME}"
    echo_s "starting docker build..."
    \cp "$script_dir/Dockerfile.swoft" "${CI_PROJECT_DIR}/Dockerfile"
    DOCKER_BUILDKIT=1 docker build --tag "${pushTag}" --build-arg CHANGE_SOURCE=true -q "${CI_PROJECT_DIR}" >/dev/null
    echo_t "end docker build."
}

php_docker_push() {
    echo_s "starting docker push..."
    docker push "${pushTag}"
    echo_t "end docker push."
}

generate_env_file() {
    p1="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16)"
    db1="${CI_PROJECT_NAME//-/_}"
    f1="$1"
    cp -f "$script_dir/.env.tpl" "$f1"

    if [ "${CI_COMMIT_REF_NAME}" = 'develop' ]; then
        sed -i -e "s/TPL_PROJECT/$db1/" -e "s/TPL_SECRET/$p1/" -e "s/TPL_DBHOST/pxc1-pxc.dbs.svc/" -e "s/TPL_CACHEHOST/redis1-master.dbs.svc/" "$f1"
        kubectl -n dbs exec -i -c database svc/pxc1-pxc -- env LANG=C.UTF-8 mysql -e "grant all on $db1.* to $db1 identified by '$p1'"
    elif [ "${CI_COMMIT_REF_NAME}" = 'testing' ]; then
        sed -i -e "s/TPL_PROJECT/$db1/" -e "s/TPL_SECRET/$p1/" -e "s/TPL_DBHOST/pxc2-pxc.dbs.svc/" -e "s/TPL_CACHEHOST/redis2-master.dbs.svc/" "$f1"
        kubectl -n dbs exec -i -c database svc/pxc2-pxc -- env LANG=C.UTF-8 mysql -e "grant all on $db1.* to $db1 identified by '$p1'"
    elif [ "${CI_COMMIT_REF_NAME}" = 'master' ]; then
        sed -i -e "s/TPL_PROJECT/$db1/" -e "s/TPL_SECRET/$p1/" -e "s/TPL_DBHOST/pxc-pxc.dbs.svc/" -e "s/TPL_CACHEHOST/redisha-haproxy.dbs.svc/" "$f1"
        kubectl -n dbs exec -i -c database svc/pxc-pxc -- env LANG=C.UTF-8 mysql -e "grant all on $db1.* to $db1 identified by '$p1'"
    else
        return 1
    fi
}
# 列出所有项目
# gitlab -v -o yaml -f path_with_namespace project list --all |awk -F': ' '{print $2}' |sort >p.txt
# 解决 Encountered 1 file(s) that should have been pointers, but weren't
# git lfs migrate import --everything$(awk '/filter=lfs/ {printf " --include='\''%s'\''", $1}' .gitattributes)

java_docker_build() {
    echo_s "java docker build."
    ## gitlab-CI/CD setup variables MVN_DEBUG=1 enable debug message
    echo_w "If you want to view debug msg, set MVN_DEBUG=1 on pipeline."
    [[ "${MVN_DEBUG:-0}" == 1 ]] && unset MVN_DEBUG || MVN_DEBUG='-q'

    env_file="$script_dir/.env.${CI_PROJECT_NAME}.${CI_COMMIT_REF_NAME}"
    if [ ! -f "$env_file" ]; then
        ## generate mysql username/password
        # [ -x generate_env_file.sh ] && bash generate_env_file.sh
        [ -f "$script_dir/.env.tpl" ] && generate_env_file "$env_file"
    fi
    [ -f "$env_file" ] && cp -f "$env_file" "${CI_PROJECT_DIR}/.env"

    cp -f "$script_dir/docker/.dockerignore" "${CI_PROJECT_DIR}/"
    cp -f "$script_dir/docker/settings.xml" "${CI_PROJECT_DIR}/"
    cp -f "$script_dir/docker/Dockerfile.bitnami.tomcat" "${CI_PROJECT_DIR}/Dockerfile"

    # shellcheck disable=2013
    for target in $(awk '/^FROM.*as/ {print $4}' Dockerfile | grep -v 'BUILDER'); do
        [ "${ENV_DOCKER_TAG_ADD:-0}" = 1 ] && dockerTagLoop="${dockerTag}-$target" || dockerTagLoop="${dockerTag}"
        DOCKER_BUILDKIT=1 docker build "${CI_PROJECT_DIR}" --quiet --add-host="$ENV_MYNEXUS" \
            -t "${dockerTagLoop}" --target "$target" \
            --build-arg GIT_BRANCH="${CI_COMMIT_REF_NAME}" \
            --build-arg MVN_DEBUG="${MVN_DEBUG}" >/dev/null
    done
    echo_t "end docker build."
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
        local timeComp
        timeComp="$(date +%s -d '12 hours ago')"
        if [ "$timeComp" -gt "${timeSave:-0}" ]; then
            echo_t "docker login..."
            dockerLogin="docker login --username AWS --password-stdin ${ENV_DOCKER_REGISTRY}"
            aws ecr get-login-password --profile="${ENV_AWS_PROFILE}" --region "${ENV_REGION_ID:?undefine}" | $dockerLogin >/dev/null
            date +%s >"$lock_file"
        fi
        ;;
    'aliyun')
        echo "[TODO]."
        ;;
    'qcloud')
        echo "[TODO]."
        ;;
    esac
}

java_docker_push() {
    echo_s "docker push to ECR."
    docker_login
    # shellcheck disable=2013
    for target in $(awk '/^FROM.*as/ {print $4}' Dockerfile | grep -v 'BUILDER'); do
        [ "${ENV_DOCKER_TAG_ADD:-0}" = 1 ] && dockerTagLoop="${dockerTag}-$target" || dockerTagLoop="${dockerTag}"
        docker images "${dockerTagLoop}" --format "table {{.ID}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
        docker push "${dockerTagLoop}" >/dev/null
    done
    echo_t "end docker push."
}

java_deploy_k8s() {
    echo_s "deploy to k8s."
    if [ ! -f "$script_dir/.lock.namespace.$CI_COMMIT_REF_NAME" ]; then
        kubectl create namespace "$CI_COMMIT_REF_NAME" || true
        touch "$script_dir/.lock.namespace.$CI_COMMIT_REF_NAME"
    fi
    kubeOpt="kubectl -n $CI_COMMIT_REF_NAME"
    helm_dir_project="$script_dir/helm/${ENV_HELM_DIR}"
    # shellcheck disable=2013
    for target in $(awk '/^FROM.*as/ {print $4}' Dockerfile | grep -v 'BUILDER'); do
        if [ "${ENV_DOCKER_TAG_ADD:-0}" = 1 ]; then
            dockerTagLoop="${CI_PROJECT_NAME}-${CI_COMMIT_SHORT_SHA}-$target"
            workNameLoop="${CI_PROJECT_NAME}-$target"
        else
            dockerTagLoop="${CI_PROJECT_NAME}-${CI_COMMIT_SHORT_SHA}"
            workNameLoop="${CI_PROJECT_NAME}"
        fi
        helm -n "$CI_COMMIT_REF_NAME" upgrade --install --history-max 1 "${workNameLoop}" "$helm_dir_project/" \
            --set nameOverride="$workNameLoop" \
            --set image.registry="${ENV_DOCKER_REGISTRY}" \
            --set image.repository="${ENV_DOCKER_REPO}" \
            --set image.tag="${dockerTagLoop}" \
            --set resources.requests.cpu=200m \
            --set resources.requests.memory=256Mi \
            --set persistence.enabled=false \
            --set persistence.nfsServer="${ENV_NFS_SERVER:?undefine var}" \
            --set service.port=8080 \
            --set service.externalTrafficPolicy=Local \
            --set service.type=ClusterIP \
            --set replicaCount="${ENV_HELM_REPLICS:-1}" \
            --set livenessProbe="${ENV_PROBE_URL:?undefine}" >/dev/null
        ## 等待就绪
        if ! $kubeOpt rollout status deployment "${workNameLoop}"; then
            errPod="$($kubeOpt get pods -l app="${CI_PROJECT_NAME}" | awk '/'"${CI_PROJECT_NAME}"'.*0\/1/ {print $1}')"
            echo_e "---------------cut---------------"
            $kubeOpt describe "pod/${errPod}" | tail
            echo_e "---------------cut---------------"
            $kubeOpt logs "pod/${errPod}" | tail -n 100
            echo_e "---------------cut---------------"
            deploy_result=1
        fi
    done

    # shellcheck disable=2086
    $kubeOpt get replicasets.apps | grep '0         0         0' | awk '{print $1}' | xargs $kubeOpt delete replicasets.apps >/dev/null 2>&1 || true
}

docker_build_generic() {
    echo_s "docker build only."
    DOCKER_BUILDKIT=1 docker build -t "$dockerTag" "${CI_PROJECT_DIR}"
}

docker_push_generic() {
    echo_s "docker push only."
    docker_login
    docker push "$dockerTag"
}

deploy_k8s_generic() {
    echo_s "deploy k8s."
    if ! test -f "$script_dir/.lock.namespace.$CI_COMMIT_REF_NAME"; then
        kubectl create namespace "$CI_COMMIT_REF_NAME" || true
        touch "$script_dir/.lock.namespace.$CI_COMMIT_REF_NAME"
    fi
    kubeOpt="kubectl -n $CI_COMMIT_REF_NAME"
    helmDir="$script_dir/helm/bitnami/bitnami/nginx"
    (
        cd "$helmDir"
        git checkout master
        git checkout -- .
        git pull --prune
    )
    helm -n "$CI_COMMIT_REF_NAME" upgrade --install --history-max 1 "${CI_PROJECT_NAME}" "$helmDir/"
}

deploy_rsync() {
    echo_s "rsync code file to server."
    ## 读取配置文件，获取 项目/分支名/war包目录
    grep "^${CI_PROJECT_PATH}\s\+${CI_COMMIT_REF_NAME}" "$script_conf" | while read -r line; do
        read -ra array <<<"$(echo $line)"
        ssh_host=${array[2]}
        ssh_port=${array[3]}
        rsync_path_src=${array[4]}
        rsync_path_dest=${array[5]} ## 从配置文件读取目标路径
        db_name=${array[7]}
        ## 防止出现空变量（若有空变量则自动退出）
        if [[ -z ${ssh_host} ]]; then
            echo "if error here, check file: ${script_name}.conf"
            return 1
        fi
        sshOpt="ssh -i ${script_ssh_key} -o StrictHostKeyChecking=no -oConnectTimeout=20 -p ${ssh_port}"
        [[ -f "$script_ssh_conf" ]] && sshOpt="$sshOpt -F $script_ssh_conf"
        if [[ -f "${CI_PROJECT_DIR}/rsync.exclude" ]]; then
            rsyncConf="${CI_PROJECT_DIR}/rsync.exclude"
        else
            rsyncConf="${script_dir}/rsync.exclude"
        fi
        [[ "${project_lang}" == 'node' || "${project_lang}" == 'java' ]] && rsyncDelete='--delete'
        rsyncOpt="rsync -acvzt --exclude=.svn --exclude=.git --timeout=20 --no-times --exclude-from=${rsyncConf} $rsyncDelete"

        ## 源文件夹
        if [[ "${project_lang}" == 'node' ]]; then
            rsync_path_src="${CI_PROJECT_DIR}/dist/"
        else
            if echo "$rsync_path_src" | grep '\.[jw]ar$' || true; then
                find_file="$(find "${CI_PROJECT_DIR}" -name "$rsync_path_src" -print0 | head -n 1)"
                if [ -z "$find_file" ]; then
                    echo "file not found: ${rsync_path_src}"
                    return 1
                else
                    rsync_path_src="$(find "${CI_PROJECT_DIR}" -name "$rsync_path_src" -print0 | head -n 1)"
                fi
            fi
            if [[ "$rsync_path_src" == 'null' || -z "$rsync_path_src" ]]; then
                rsync_path_src="${CI_PROJECT_DIR}/"
            fi
        fi
        ## 目标文件夹
        if [[ "$rsync_path_dest" == 'null' || -z "$rsync_path_src" ]]; then
            rsync_path_dest="${ENV_PATH_DEST_PRE}/${CI_COMMIT_REF_NAME}.${CI_PROJECT_NAME}/"
        fi
        ## 发布到 aliyun oss 存储
        if [[ "${rsync_path_dest}" =~ '^oss://' ]]; then
            command -v aliyun >/dev/null || echo_e "command aliyun not exist."
            # bucktName="${rsync_path_dest#oss://}"
            # bucktName="${bucktName%%/*}"
            aliyun oss cp -rf "${CI_PROJECT_DIR}/" "$rsync_path_dest/"
            return
        fi
        ## 判断目标服务器/目标目录 是否存在？不存在则登录到目标服务器建立目标路径
        $sshOpt "${ssh_host}" "test -d $rsync_path_dest || mkdir -p $rsync_path_dest"
        ## 复制文件到目标服务器的目标目录
        ${rsyncOpt} -e "$sshOpt" "${rsync_path_src}" "${ssh_host}:${rsync_path_dest}"
        ## rsync 项目私密配置文件，例如数据库配置，密钥文件等
        # configDir="${script_dir}/.config.${CI_COMMIT_REF_NAME}.${CI_PROJECT_NAME}/"
        # if [ -d "$configDir" ]; then
        #     rsync -acvzt -e "$sshOpt" "$configDir" "${ssh_host%@*}@${ip}:${rsync_path_dest}"
        # fi
    done
}

get_msg_deploy() {
    mriid="$(gitlab project-merge-request list --project-id "$CI_PROJECT_ID" --page 1 --per-page 1 | awk '/^iid/ {print $2}')"
    ## sudo -H python3 -m pip install PyYaml
    [ -z "$describeMsg" ] && describeMsg="$(gitlab -v project-merge-request get --project-id "$CI_PROJECT_ID" --iid "$mriid" | sed -e '/^description/,/^diff-refs/!d' -e 's/description: //' -e 's/diff-refs.*//')"
    [ -z "$describeMsg" ] && describeMsg="$(git --no-pager log --no-merges --oneline -1)"
    gitUserName="$(gitlab -v user get --id "${GITLAB_USER_ID}" | awk '/^name:/ {print $2}')"

    msgBody="[Gitlab Deploy]
Project = ${CI_PROJECT_PATH}/${CI_COMMIT_REF_NAME}
Pipeline = ${CI_PIPELINE_ID}/Job_ID-$CI_JOB_ID
Description = [${CI_COMMIT_SHORT_SHA}]/${describeMsg}/${GITLAB_USER_ID}-${gitUserName}
Deploy_Result = $([ 0 = "${deploy_result:-0}" ] && echo SUCCESS || echo FAILURE)
"
}

send_msg_chatapp() {
    echo_s "send message to chatApp."
    if [[ 1 -eq "${ENV_NOTIFY_WEIXIN:-0}" ]]; then
        wxApi="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${ENV_WEIXIN_KEY:?undefine var}"
        curl -s "$wxApi" \
            -H 'Content-Type: application/json' \
            -d "
        {
            \"msgtype\": \"text\",
            \"text\": {
                \"content\": \"$msgBody\"
            }
        }"
    elif [[ 1 -eq "${ENV_NOTIFY_TELEGRAM:-0}" ]]; then
        tgApiMsg="https://api.telegram.org/bot${ENV_API_KEY_TG:?undefine var}/sendMessage"
        # tgApiUrlDoc="https://api.telegram.org/bot${ENV_API_KEY_TG:?undefine var}/sendDocument"
        msgBody="$(echo "$msgBody" | sed -e ':a;N;$!ba;s/\n/%0a/g' -e 's/&/%26/g')"
        if [ -n "$ENV_HTTP_PROXY" ]; then
            curlOpt="curl -x$ENV_HTTP_PROXY -sS -o /dev/null -X POST"
        else
            curlOpt="curl -sS -o /dev/null -X POST"
        fi
        $curlOpt -d "chat_id=${ENV_TG_GROUP_ID:?undefine var}&text=$msgBody" "$tgApiMsg"
    elif [[ 1 -eq "${PIPELINE_TEMP_PASS:-0}" ]]; then
        python3 "$script_dir/bin/element-up.py" "$msgBody"
    elif [[ 1 -eq "${ENV_NOTIFY_ELEMENT:-0}" && "${PIPELINE_TEMP_PASS:-0}" -ne 1 ]]; then
        python3 "$script_dir/bin/element.py" "$msgBody"
    elif [[ 1 -eq "${ENV_NOTIFY_EMAIL:-0}" ]]; then
        echo_w "TODO."
    else
        echo "No message send."
    fi
}

update_cert() {
    echo_s "update ssl cert (dns api)."
    acme_home="${HOME}/.acme.sh"
    cmd1="${acme_home}/acme.sh"
    ## install acme.sh
    if [[ ! -x "${cmd1}" ]]; then
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
            echo_w "[TODO] use dnspod api."
        fi
        \cp -vf "$a" "${acme_home}/account.conf"

        for d in ${domain_name}; do
            if [ -d "${acme_home}/$d" ]; then
                "${cmd1}" --renew -d "${d}" || true
            else
                "${cmd1}" --issue --dns $dnsType -d "$d" -d "*.$d"
            fi
            "${cmd1}" --install-cert -d "$d" --key-file "$cert_dir/$d".key.pem \
                --fullchain-file "$cert_dir/$d".cert.pem
        done
    done

    rsync -av "$cert_dir/" "$HOME/efs/data/nginx-conf/ssl/"
    rsync -av "$cert_dir/" "$HOME/efs/data/nginx-conf2/ssl/"
    ## bitnami/nginx user 1001
    sudo chown 1001 "$HOME"/efs/data/nginx-conf/ssl/*.key.pem
    sudo chown 1001 "$HOME"/efs/data/nginx-conf2/ssl/*.key.pem

    for i in ${ENV_NGINX_IPS:?empty}; do
        echo "$i"
        rsync -a "$cert_dir/" "root@$i":/etc/nginx/conf.d/ssl/
    done
}

check_os() {
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
        exit 1
    fi
    if [[ "$OS" =~ (debian|ubuntu) ]]; then
        ## fix gitlab-runner exit error.
        if [[ -e "$HOME"/.bash_logout ]]; then
            mv -f "$HOME"/.bash_logout "$HOME"/.bash_logout.bak
        fi
        command -v rsync >/dev/null || sudo apt install -y rsync
        command -v git >/dev/null || sudo apt install -y git
        git lfs version >/dev/null || sudo apt install -y git-lfs
        command -v docker >/dev/null || bash "$script_dir/bin/get-docker.sh"
        id | grep -q docker || sudo usermod -aG docker "$USER"
        command -v pip3 >/dev/null || sudo apt install -y python3-pip
        command -v java >/dev/null || sudo apt install -y openjdk-8-jdk
        command -v shc >/dev/null || sudo apt install -y shc
        if ! command -v aws >/dev/null; then
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip awscliv2.zip
            sudo ./aws/install
        fi
    elif [[ "$OS" == centos ]]; then
        rpm -q epel-release >/dev/null || sudo yum install -y epel-release
        command -v rsync >/dev/null || sudo yum install -y rsync
        command -v git >/dev/null || sudo yum install -y git2u
        git lfs version >/dev/null || sudo yum install -y git-lfs
        command -v docker >/dev/null || sh "$script_dir/bin/get-docker.sh"
        id | grep -q docker || sudo usermod -aG docker "$USER"
    elif [[ "$OS" == 'amzn' ]]; then
        rpm -q epel-release >/dev/null || sudo amazon-linux-extras install -y epel
        command -v rsync >/dev/null || sudo yum install -y rsync
        command -v git >/dev/null || sudo yum install -y git2u
        git lfs version >/dev/null || sudo yum install -y git-lfs
        command -v docker >/dev/null || sudo amazon-linux-extras install -y docker
        id | grep -q docker || sudo usermod -aG docker "$USER"
    fi

    command -v gitlab >/dev/null || python3 -m pip install --user --upgrade python-gitlab
    [ -e "$HOME/".python-gitlab.cfg ] || ln -sf "$script_dir/bin/.python-gitlab.cfg" "$HOME/"
    command -v kubectl >/dev/null || {
        kVer="$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)"
        kUrl="https://storage.googleapis.com/kubernetes-release/release/$kVer/bin/linux/amd64/kubectl"
        if [ -z "$ENV_HTTP_PROXY" ]; then
            curl -Lo "$script_dir/bin/kubectl" "$kUrl"
        else
            curl -x "$ENV_HTTP_PROXY" -Lo "$script_dir/bin/kubectl" "$kUrl"
        fi
        chmod +x "$script_dir/bin/kubectl"
    }
}

clean_disk() {
    ## clean cache of docker build
    diskUsed="$(df / | awk 'NR>1 {print $5}')"
    diskUsed="${diskUsed/\%/}"
    if ((diskUsed < 80)); then
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

main() {
    script_name="$(basename "$0")"
    script_name="${script_name%.sh}"
    script_dir="$(cd "$(dirname "$0")" && pwd)"

    PATH="$HOME/bin:/usr/bin:/usr/sbin:/usr/local/sbin:/usr/local/bin"
    PATH="$PATH:$script_dir/jdk/bin:$script_dir/jmeter/bin:$script_dir/ant/bin:$script_dir/sonar-scanner/bin"
    PATH="$PATH:$script_dir/maven/bin:$HOME/.config/composer/vendor/bin:/snap/bin:$HOME/.local/bin"
    export PATH

    ## 检查OS 类型和版本，安装相应命令和软件包
    check_os

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
    script_log="${script_dir}/${script_name}.log"           ## 记录sql文件的执行情况
    script_conf="${script_dir}/${script_name}.conf"         ## 发布到服务器的配置信息
    script_env="${script_dir}/${script_name}.env"           ## 发布配置信息(密)
    script_ssh_conf="${script_dir}/${script_name}.ssh.conf" ## ssh config 信息，跳板机/堡垒机
    script_ssh_key="${script_dir}/id_rsa.gitlab"            ## ssh key

    [ ! -f "$script_conf" ] && touch "$script_conf"
    [ ! -f "$script_env" ] && touch "$script_env"
    [ ! -f "$script_log" ] && touch "$script_log"

    [[ -e "${script_ssh_conf}" && $(stat -c "%a" "${script_ssh_conf}") != 600 ]] && chmod 600 "${script_ssh_conf}"
    [[ -e "${script_ssh_key}" && $(stat -c "%a" "${script_ssh_key}") != 600 ]] && chmod 600 "${script_ssh_key}"
    [[ ! -e "$HOME/.ssh/id_rsa" ]] && ln -sf "${script_ssh_key}" "$HOME/".ssh/id_rsa
    [[ ! -e "$HOME/.ssh/config" ]] && ln -sf "${script_ssh_conf}" "$HOME/".ssh/config
    [[ ! -e "${HOME}/bin" ]] && ln -sf "${script_dir}/bin" "$HOME/"
    [[ ! -e "${HOME}/.acme.sh" && -e "${script_dir}/.acme.sh" ]] && ln -sf "${script_dir}/.acme.sh" "$HOME/"
    [[ ! -e "${HOME}/.aws" && -e "${script_dir}/.aws" ]] && ln -sf "${script_dir}/.aws" "$HOME/"
    [[ ! -e "${HOME}/.kube" && -e "${script_dir}/.kube" ]] && ln -sf "${script_dir}/.kube" "$HOME/"
    [[ ! -e "${HOME}/.python-gitlab.cfg" && -e "${script_dir}/.python-gitlab.cfg" ]] && ln -sf "${script_dir}/.python-gitlab.cfg" "$HOME/"
    ## source ENV, 获取 ENV_ 开头的所有全局变量
    source "$script_env"
    ## run docker using current user
    runDocker="docker run --interactive --rm -u $UID:$UID"
    ## run docker using root
    # runDockeRoot="docker run --interactive --rm"
    dockerTag="${ENV_DOCKER_REGISTRY:?undefine}/${ENV_DOCKER_REPO:?undefine}:${CI_PROJECT_NAME:?undefine var}-${CI_COMMIT_SHORT_SHA}"
    gitDiff="git --no-pager diff --name-only HEAD^"
    ## 清理磁盘空间
    clean_disk
    ## acme.sh 更新证书
    if [[ "$PIPELINE_UPDATE_SSL" -eq 1 ]]; then
        update_cert
    fi
    ## 判定项目类型
    [[ -f "${CI_PROJECT_DIR:?undefine var}/package.json" ]] && project_lang='node'
    [[ -f "${CI_PROJECT_DIR}/composer.json" ]] && project_lang='php'
    [[ -f "${CI_PROJECT_DIR}/pom.xml" ]] && project_lang='java'
    [[ -f "${CI_PROJECT_DIR}/requirements.txt" ]] && project_lang='python'
    [[ -f "${CI_PROJECT_DIR}/Dockerfile" ]] && project_docker=1
    [[ "${PIPELINE_DISABLE_DOCKER:-0}" -eq 1 ]] && project_docker=0
    [[ "${ENV_DISABLE_DOCKER:-0}" -eq 1 ]] && project_docker=0

    [[ "${PIPELINE_SONAR:-0}" -eq 1 ]] && exec_flyway=0
    [[ "${PIPELINE_FLYWAY:-0}" -eq 0 ]] && exec_flyway=0
    if [[ ${exec_flyway:-1} -eq 1 ]]; then
        if [[ "${project_docker}" -eq 1 ]]; then
            ## sql导入，k8s, flyway
            flyway_migrate_k8s
        else
            ## sql导入，flyway 传统方式
            flyway_migrate
        fi
    fi
    ## 蓝绿发布，灰度发布，金丝雀发布的k8s配置文件

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_SONAR ，1 启用，0 禁用[default]
    if [[ 1 -eq "${PIPELINE_SONAR:-0}" ]]; then
        sonar_scan
        return $?
    fi
    ## 在 gitlab 的 pipeline 配置环境变量 enableUnitTest ，1 启用[default]，0 禁用
    unit_test

    [[ 1 -eq "${PIPELINE_CODE_FORMAT:-1}" && 1 -eq "${project_docker}" ]] && dockerfile_check

    case "${project_lang}" in
    'php')
        ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_CODE_FORMAT ，1 启用[default]，0 禁用
        if [[ 1 -eq "${PIPELINE_CODE_FORMAT:-1}" ]]; then
            php_format_check
        fi
        if [[ 1 -eq "${project_docker}" ]]; then
            [[ 1 -eq "$exec_docker_build_php" ]] && php_docker_build
            [[ 1 -eq "$exec_docker_push_php" ]] && php_docker_push
            [[ 1 -eq "$exec_deploy_k8s_php" ]] && deploy_k8s
        else
            ## 在 gitlab 的 pipeline 配置环境变量 enableComposer ，1 启用，0 禁用[default]
            php_composer_volume
        fi
        ;;
    'node')
        if [[ 1 -eq "${PIPELINE_CODE_FORMAT:-1}" ]]; then
            eslint_check
        fi
        if [[ 1 -eq "${project_docker}" ]]; then
            [[ 1 -eq "$exec_docker_build_node" ]] && node_docker_build
            [[ 1 -eq "$exec_docker_push_node" ]] && node_docker_push
            [[ 1 -eq "$exec_node_deploy_k8s" ]] && deploy_k8s
        else
            node_build_volume
        fi
        ;;
    'java')
        if [[ 1 -eq "${PIPELINE_CODE_FORMAT:-1}" ]]; then
            java_format_check
        fi
        if [[ 1 -eq "${project_docker}" ]]; then
            [[ 1 -eq "$exec_docker_build_java" ]] && java_docker_build
            [[ 1 -eq "$exec_docker_push_java" ]] && java_docker_push
            [[ 1 -eq "$exec_deploy_k8s_java" ]] && java_deploy_k8s
        fi
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

    [[ "${project_docker}" -eq 1 ]] && exec_deploy_rsync=0
    [[ "$ENV_DISABLE_RSYNC" -eq 1 ]] && exec_deploy_rsync=0
    if [[ "${exec_deploy_rsync:-1}" -eq 1 ]]; then
        deploy_rsync
    fi

    ## 在 gitlab 的 pipeline 配置环境变量 enableFuncTest ，1 启用[default]，0 禁用
    function_test

    ## notify
    ## 发送消息到群组, enable_send_msg， 0 不发， 1 不发.
    [[ "${deploy_result}" -eq 1 ]] && enable_send_msg=1
    [[ "$ENV_DISABLE_MSG" = 1 ]] && enable_send_msg=0
    if [[ "${enable_send_msg:-1}" == 1 ]]; then
        get_msg_deploy
        send_msg_chatapp
    fi

    ## deploy_result， 0 成功， 1 失败
    return $deploy_result
}

main "$@"
