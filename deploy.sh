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
        if [ -f "$CI_PROJECT_DIR/$i" ]; then
            if ! $docker_run -v "$CI_PROJECT_DIR":/project deploy/phpcs phpcs -n --standard=PSR12 --colors --report="${phpcs_report:-full}" "/project/$i"; then
                phpcs_result=$((phpcs_result + 1))
            fi
        else
            echo_warn "$CI_PROJECT_DIR/$i not exists."
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

check_code_style() {
    [[ "${project_lang}" == php ]] && code_style_php
    [[ "${project_lang}" == node ]] && code_style_node
    [[ "${project_lang}" == java ]] && code_style_java
    [[ "${project_lang}" == python ]] && code_style_python
    [[ "${project_docker}" == 1 ]] && code_style_dockerfile
}

## install phpunit
test_unit() {
    echo_time_step "[TODO] unit test..."
}

## install sonar-scanner to system user: "gitlab-runner"
scan_sonarqube() {
    echo_time_step "sonar scanner..."
    sonar_url="${ENV_SONAR_URL:?empty}"
    sonar_conf="$CI_PROJECT_DIR/sonar-project.properties"
    if ! curl "$sonar_url" >/dev/null 2>&1; then
        echo_warn "Could not found sonarqube server, exit."
        return
    fi

    if [[ ! -f "$sonar_conf" ]]; then
        cat >"$sonar_conf" <<EOF
sonar.host.url=$sonar_url
sonar.projectKey=${CI_PROJECT_NAMESPACE}_${CI_PROJECT_NAME}
sonar.qualitygate.wait=true
sonar.projectName=$CI_PROJECT_NAME
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
    $docker_run -e SONAR_TOKEN="${ENV_SONAR_TOKEN:?empty}" -v "$CI_PROJECT_DIR":/usr/src sonarsource/sonar-scanner-cli
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

## install jdk/ant/jmeter
test_function() {
    echo_time_step "function test..."
    [ -f "$script_dir/data/tests/test_func.sh" ] && bash "$script_dir/data/tests/test_func.sh"
    echo_time "end function test."
}

deploy_sql_flyway() {
    echo_time_step "flyway migrate..."

    flyway_home="${ENV_FLYWAY_PATH:-${script_dir}/conf/flyway}"

    if [ -d "$flyway_home/conf/${branch_name}.${CI_PROJECT_NAME}" ]; then
        flyway_volume_conf="$flyway_home/conf/${branch_name}.${CI_PROJECT_NAME}:/flyway/conf"
    else
        flyway_volume_conf="$flyway_home/conf:/flyway/conf"
    fi
    flyway_volume_sql="${CI_PROJECT_DIR}/docs/sql:/flyway/sql"
    flyway_docker_run="docker run --rm -v ${flyway_volume_sql} -v ${flyway_volume_conf} flyway/flyway"

    ## 判断是否需要建立数据库远程连接
    [ -f "$script_dir/bin/special.sh" ] && source "$script_dir/bin/special.sh" port
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

# https://github.com/nodesource/distributions#debinstall
node_build_volume() {
    echo_time_step "node yarn build..."
    config_env_path="$(find "${CI_PROJECT_DIR}" -maxdepth 2 -name "${branch_name}.*")"
    for file in $config_env_path; do
        if [[ "$file" =~ 'config' ]]; then
            # vue2.x项目，发布系统自动部署时会把config目录下的环境配置文件复制为env.js
            \cp -vf "$file" "${file/${branch_name}./}"
        else
            # vue3.x项目，发布系统自动部署时会把根目录下的环境配置文件复制为.env文件
            \cp -vf "$file" "${file/${branch_name}/}"
        fi
    done

    rm -f package-lock.json
    # if [[ ! -d node_modules ]] || git diff --name-only HEAD~1 package.json | grep package.json; then
    if ! docker images | grep 'deploy/node' >/dev/null; then
        DOCKER_BUILDKIT=1 docker build -t deploy/node -f "$path_dockerfile/Dockerfile.node" "$path_dockerfile" >/dev/null
    fi
    if [[ -f "$script_dir/bin/custome.docker.build.sh" ]]; then
        source "$script_dir/bin/custome.docker.build.sh"
    else
        $docker_run -v "${CI_PROJECT_DIR}":/app -w /app deploy/node bash -c "yarn install; yarn run build"
    fi
    echo_time "end node build."
}

docker_login() {
    source "$script_env"
    ## 比较上一次登陆时间，超过12小时则再次登录
    lock_docker_login="$script_dir/conf/.lock.docker.login.${ENV_DOCKER_LOGIN}"
    [ -f "$lock_docker_login" ] || touch "$lock_docker_login"
    time_save="$(cat "$lock_docker_login")"
    if [ "$(date +%s -d '12 hours ago')" -gt "${time_save:-0}" ]; then
        echo_time "docker login $ENV_DOCKER_LOGIN ..."
        if [[ "$ENV_DOCKER_LOGIN" == 'aws' ]]; then
            str_docker_login="docker login --username AWS --password-stdin ${ENV_DOCKER_REGISTRY}"
            aws ecr get-login-password --profile="${ENV_AWS_PROFILE}" --region "${ENV_REGION_ID:?undefine}" | $str_docker_login >/dev/null
        else
            echo "${ENV_DOCKER_PASSWORD}" | docker login --username="${ENV_DOCKER_USERNAME}" --password-stdin "${ENV_DOCKER_REGISTRY}"
        fi
        date +%s >"$lock_docker_login"
    fi

}

php_composer_volume() {
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

    echo "PIPELINE_COMPOSER_INSTALL: ${PIPELINE_COMPOSER_INSTALL:-0}"
    echo "PIPELINE_COMPOSER_UPDATE: ${PIPELINE_COMPOSER_UPDATE:-0}"
    [[ "${PIPELINE_COMPOSER_INSTALL:-0}" -eq 1 ]] && COMPOSER_INSTALL=true
    [[ "${PIPELINE_COMPOSER_UPDATE:-0}" -eq 1 ]] && COMPOSER_UPDATE=true
    git diff --name-only HEAD^ composer.json | grep composer.json && COMPOSER_INSTALL=true
    echo "COMPOSER_INSTALL=${COMPOSER_INSTALL:-false}"
    echo "COMPOSER_UPDATE=${COMPOSER_UPDATE:-false}"
    if [ "${COMPOSER_INSTALL:-false}" = true ]; then
        rm -f "${CI_PROJECT_DIR}"/composer.lock
        # rm -rf "${CI_PROJECT_DIR}"/vendor
        $docker_run -v "$CI_PROJECT_DIR:/app" --env COMPOSER_INSTALL=${COMPOSER_INSTALL:-false} -w /app "$image_composer" composer install -q --no-dev -o || true
    fi
    if [ "${COMPOSER_UPDATE:-false}" = true ]; then
        $docker_run -v "$CI_PROJECT_DIR:/app" --env COMPOSER_UPDATE=${COMPOSER_UPDATE:-false} -w /app "$image_composer" composer update -q || true
    fi
    echo_time "end php composer install."
}

# 列出所有项目
# gitlab -v -o yaml -f path_with_namespace project list --all |awk -F': ' '{print $2}' |sort >p.txt
# 解决 Encountered 1 file(s) that should have been pointers, but weren't
# git lfs migrate import --everything$(awk '/filter=lfs/ {printf " --include='\''%s'\''", $1}' .gitattributes)

java_docker_build() {
    echo_time_step "java docker build..."
    ## gitlab-CI/CD setup variables MVN_DEBUG=1 enable debug message
    echo_warn "If you want to view debug msg, set MVN_DEBUG=1 on pipeline."
    [[ "${MVN_DEBUG:-0}" == 1 ]] && unset MVN_DEBUG || MVN_DEBUG='-q'
    ## if you have no apollo config center, use local .env
    env_file="$script_dir/conf/.env.${CI_PROJECT_NAME}.${branch_name}"
    if [ ! -f "$env_file" ]; then
        ## generate mysql username/password
        # [ -x generate_env_file.sh ] && bash generate_env_file.sh
        [ -f "$script_dir/conf/.env.tpl" ] && generate_env_file "$env_file"
    fi
    [ -f "$env_file" ] && cp -f "$env_file" "${CI_PROJECT_DIR}/.env"

    cp -f "$script_dir/conf/.dockerignore" "${CI_PROJECT_DIR}/"
    cp -f "$path_dockerfile/settings.xml" "${CI_PROJECT_DIR}/"
    if [ -f "${CI_PROJECT_DIR}/Dockerfile.useLocal" ]; then
        mv Dockerfile.useLocal Dockerfile
    else
        cp -f "$path_dockerfile/Dockerfile.bitnami.tomcat" "${CI_PROJECT_DIR}/Dockerfile"
    fi
    if [[ "$(grep -c '^FROM.*' Dockerfile || true)" -ge 2 ]]; then
        # shellcheck disable=2013
        for target in $(awk '/^FROM\s/ {print $4}' Dockerfile | grep -v 'BUILDER'); do
            [ "${ENV_DOCKER_TAG_ADD:-0}" = 1 ] && docker_tag_loop="${image_registry}-$target" || docker_tag_loop="${image_registry}"
            DOCKER_BUILDKIT=1 docker build "${CI_PROJECT_DIR}" --quiet --add-host="$ENV_MYNEXUS" -t "${docker_tag_loop}" \
                --target "$target" --build-arg GIT_BRANCH="${branch_name}" --build-arg MVN_DEBUG="${MVN_DEBUG}" >/dev/null
        done
    else
        DOCKER_BUILDKIT=1 docker build "${CI_PROJECT_DIR}" --quiet --add-host="$ENV_MYNEXUS" -t "${image_registry}" \
            --build-arg GIT_BRANCH="${branch_name}" --build-arg MVN_DEBUG="${MVN_DEBUG}" >/dev/null
    fi
    echo_time "end docker build."
}

java_docker_push() {
    echo_time_step "docker push to ECR..."
    docker_login
    if [[ "$(grep -c '^FROM.*' Dockerfile || true)" -ge 2 ]]; then
        # shellcheck disable=2013
        for target in $(awk '/^FROM\s/ {print $4}' Dockerfile | grep -v 'BUILDER'); do
            [ "${ENV_DOCKER_TAG_ADD:-0}" = 1 ] && docker_tag_loop="${image_registry}-$target" || docker_tag_loop="${image_registry}"
            docker images "${docker_tag_loop}" --format "table {{.ID}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
            docker push -q "${docker_tag_loop}" || echo_erro "error here, maybe caused by GFW."
        done
    else
        docker images "${image_registry}" --format "table {{.ID}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
        docker push -q "${image_registry}" || echo_erro "error here, maybe caused by GFW."
    fi
    echo_time "end docker push."
}

java_deploy_k8s() {
    echo_time_step "deploy to k8s..."
    helm_dir_project="$script_dir/conf/helm/${ENV_HELM_DIR}"
    # shellcheck disable=2013
    for target in $(awk '/^FROM\s/ {print $4}' Dockerfile | grep -v 'BUILDER'); do
        source "$script_env"
        if [ "${ENV_DOCKER_TAG_ADD:-0}" = 1 ]; then
            docker_tag_loop="${CI_PROJECT_NAME}-${CI_COMMIT_SHORT_SHA}-$target"
            work_name_loop="${CI_PROJECT_NAME}-$target"
        else
            docker_tag_loop="${CI_PROJECT_NAME}-${CI_COMMIT_SHORT_SHA}"
            work_name_loop="${CI_PROJECT_NAME}"
        fi
        helm upgrade "${work_name_loop}" "$helm_dir_project/" \
            --install -n "${branch_name}" --create-namespace --history-max 1 \
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
        if ! kubectl -n "${branch_name}" rollout status deployment "${work_name_loop}"; then
            errPod="$(kubectl -n "${branch_name}" get pods -l app="${CI_PROJECT_NAME}" | awk '/'"${CI_PROJECT_NAME}"'.*0\/1/ {print $1}')"
            echo_erro "---------------cut---------------"
            kubectl -n "${branch_name}" describe "pod/${errPod}" | tail
            echo_erro "---------------cut---------------"
            kubectl -n "${branch_name}" logs "pod/${errPod}" | tail -n 100
            echo_erro "---------------cut---------------"
            deploy_result=1
        fi
    done

    kubectl -n "$branch_name" get replicasets.apps | awk '/repicasets.apps.*0\s+0\s+0/ {print $1}' | xargs kubectl -n "$branch_name" delete replicasets.apps >/dev/null 2>&1 || true
}

docker_build_generic() {
    echo_time_step "docker build only..."
    docker_login
    ## frontend (VUE) .env file
    if [[ $project_lang == "vue" ]]; then
        config_env_path="$(find "${CI_PROJECT_DIR}" -maxdepth 2 -name "${branch_name}.*")"
        for file in $config_env_path; do
            if [[ "$file" =~ 'config/' ]]; then
                \cp -vf "$file" "${file/${branch_name}./}" # vue2.x
            else
                \cp -vf "$file" "${file/${branch_name}/}" # vue3.x
            fi
        done
    fi
    ## backend (PHP) .env file
    path_secret="${script_dir}/conf/.secret/${branch_name}.${CI_PROJECT_NAME}/"
    [ -d "$path_secret" ] && rsync -rlctv "$path_secret" "${CI_PROJECT_DIR}/"
    ## docker ignore file
    [ -f "${CI_PROJECT_DIR}/.dockerignore" ] || cp -v "${script_dir}/conf/.dockerignore" "${CI_PROJECT_DIR}/"
    ## cert file for nginx
    if [[ "${CI_PROJECT_NAME}" == "$ENV_NGINX_GIT_NAME" && -d "$HOME/.acme.sh/dest/" ]]; then
        rsync -av "$HOME/.acme.sh/dest/" "${CI_PROJECT_DIR}/etc/nginx/conf.d/ssl/"
    fi
    ## Docker build from, 是否从模板构建
    image_from=$(awk '/^FROM/ {print $2}' Dockerfile | grep -q "${image_registry%%:*}" | head -n 1)
    if [ -n "$image_from" ]; then
        docker_build_tmpl=0
        ## 判断模版是否存在
        docker images | grep -q "${image_from%%:*}.*${image_from##*:}" || docker_build_tmpl=$((docker_build_tmpl + 1))
        if [[ "$docker_build_tmpl" -gt 0 ]]; then
            # 模版不存在，构建模板
            cp -f "${path_dockerfile}/Dockerfile.${image_from##*:}" "${CI_PROJECT_DIR}/"
            DOCKER_BUILDKIT=1 docker build -q --tag "${image_from}" --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE}" \
                -f "${CI_PROJECT_DIR}/Dockerfile.${image_from##*:}" "${CI_PROJECT_DIR}"
        fi
    fi

    ## docker build flyway
    if [[ $ENV_HELM_FLYWAY == 1 ]]; then
        image_tag_flyway="${ENV_DOCKER_REGISTRY:?undefine}/${ENV_DOCKER_REPO:?undefine}:${CI_PROJECT_NAME:?undefine var}-flyway"
        path_flyway_conf_proj="${script_dir}/conf/flyway/conf/${branch_name}.${CI_PROJECT_NAME}/"
        path_flyway_conf="$CI_PROJECT_DIR/docs/flyway_conf"
        path_flyway_sql="$CI_PROJECT_DIR/docs/flyway_sql"
        [[ -d "$CI_PROJECT_DIR/docs/sql" && ! -d "$path_flyway_sql" ]] && mv "$CI_PROJECT_DIR/docs/sql" "$path_flyway_sql"
        [[ -d "$path_flyway_sql" ]] || mkdir -p "$path_flyway_sql"
        [[ -d "$path_flyway_conf" ]] || mkdir -p "$path_flyway_conf"
        [[ -d "$path_flyway_conf_proj" ]] && rsync -rlctv "$path_flyway_conf_proj" "${path_flyway_conf}/"
        [ -f "${CI_PROJECT_DIR}/Dockerfile.flyway" ] || cp -f "${path_dockerfile}/Dockerfile.flyway" "${CI_PROJECT_DIR}/"
        DOCKER_BUILDKIT=1 docker build -q --tag "${image_tag_flyway}" -f "${CI_PROJECT_DIR}/Dockerfile.flyway" "${CI_PROJECT_DIR}/" >/dev/null
    fi
    ## docker build
    echo "PIPELINE_YARN_INSTALL: ${PIPELINE_YARN_INSTALL:-false}"
    DOCKER_BUILDKIT=1 docker build -q --tag "${image_registry}" \
        --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE:-false}" \
        --build-arg YARN_INSTALL="${PIPELINE_YARN_INSTALL:-false}" \
        "${CI_PROJECT_DIR}" >/dev/null
    echo_time "end docker build."
}

docker_push_generic() {
    echo_time_step "docker push only..."
    docker_login
    # echo "$image_registry"
    docker push -q "$image_registry" || echo_erro "error here, maybe caused by GFW."
    if [[ $ENV_HELM_FLYWAY == 1 ]]; then
        docker push -q "$image_tag_flyway"
    fi
    echo_time "end docker push."
}

deploy_k8s_generic() {
    echo_time_step "deploy k8s..."
    if [[ ${ENV_REMOVE_PROJ_PREFIX:-false} == true ]]; then
        helm_release=${CI_PROJECT_NAME#*-}
    else
        helm_release=${CI_PROJECT_NAME}
    fi
    helm_release="${helm_release,,}"
    if [ -d "$script_dir/conf/helm/${CI_PROJECT_NAME}" ]; then
        path_helm="$script_dir/conf/helm/${CI_PROJECT_NAME}"
    else
        if [ -d "$CI_PROJECT_PATH/helm" ]; then
            path_helm="$CI_PROJECT_PATH/helm"
        else
            path_helm=none
        fi
    fi

    image_tag="${CI_PROJECT_NAME}-${CI_COMMIT_SHORT_SHA}"
    source "$script_env"
    if [ "$path_helm" = none ]; then
        echo_warn "helm files not exists, ignore helm install."
        [ -f "$script_dir/bin/special.sh" ] && source "$script_dir/bin/special.sh" "$branch_name"
    else
        set -x
        helm upgrade "${helm_release}" "$path_helm/" --install --history-max 1 \
            --namespace "${branch_name}" --create-namespace \
            --set image.repository="${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}" \
            --set image.tag="${image_tag}" \
            --set image.pullPolicy='Always' >/dev/null
        [[ $PIPELINE_DEBUG != 'true' ]] && set +x
    fi
    if [[ $ENV_HELM_FLYWAY == 1 ]]; then
        helm upgrade flyway "$script_dir/conf/helm/flyway/" --install --history-max 1 \
            --namespace "${branch_name}" --create-namespace \
            --set image.repository="${ENV_DOCKER_REGISTRY}/${ENV_DOCKER_REPO}" \
            --set image.tag="${CI_PROJECT_NAME}-flyway" \
            --set image.pullPolicy='Always' >/dev/null
    fi
    kubectl -n "${branch_name}" get rs | awk '/.*0\s+0\s+0/ {print $1}' |
        xargs kubectl -n "${branch_name}" delete rs >/dev/null 2>&1 || true

    echo_time "end deploy k8s."
}

deploy_rsync() {
    echo_time_step "rsync code file to remote server..."
    ## 读取配置文件，获取 项目/分支名/war包目录
    grep "^${CI_PROJECT_PATH}\s\+${branch_name}" "$script_conf" || {
        echo_erro "if stop here, check GIT repository: pms/runner/conf/deploy.conf"
        return 1
    }
    grep "^${CI_PROJECT_PATH}\s\+${branch_name}" "$script_conf" | while read -r line; do
        # for line in $(grep "^${CI_PROJECT_PATH}\s\+${branch_name}" "$script_conf"); do
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
            echo "if stop here, check pms/runner/conf/deploy.conf"
            return 1
        fi
        ssh_opt="ssh -o StrictHostKeyChecking=no -oConnectTimeout=20 -p ${ssh_port:-22}"
        ## rsync exclude some files
        if [[ -f "${CI_PROJECT_DIR}/rsync.exclude" ]]; then
            rsync_conf="${CI_PROJECT_DIR}/rsync.exclude"
        else
            rsync_conf="${conf_rsync_exclude}"
        fi
        ## node/java use rsync --delete
        [[ "${project_lang}" == 'node' || "${project_lang}" == 'java' ]] && rsync_delete='--delete'
        rsync_opt="rsync -acvzt --exclude=.svn --exclude=.git --timeout=20 --no-times --exclude-from=${rsync_conf} $rsync_delete"

        ## 源文件夹
        if [[ "${project_lang}" == 'node' ]]; then
            rsync_src="${CI_PROJECT_DIR}/dist/"
        elif [[ "${project_lang}" == 'react' ]]; then
            rsync_src="${CI_PROJECT_DIR}/build/"
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
        if [[ "$rsync_dest" == 'null' || -z "$rsync_dest" ]]; then
            rsync_dest="${ENV_PATH_DEST_PRE}/${branch_name}.${CI_PROJECT_NAME}/"
        fi
        ## 复制项目密码/密钥等配置文件，例如数据库配置，密钥文件等
        secret_dir="${script_dir}/conf/.secret/${branch_name}.${CI_PROJECT_NAME}/"
        ## 发布到 aliyun oss 存储
        if [[ "${rsync_dest}" =~ 'oss://' ]]; then
            command -v aliyun >/dev/null || echo_warn "command not exist: aliyun"
            aliyun oss cp "${rsync_src}/" "$rsync_dest/" --recursive --force
            # rclone sync "${CI_PROJECT_DIR}/" "$rsync_dest/"
            return
        fi
        ## 判断目标服务器/目标目录 是否存在？不存在则登录到目标服务器建立目标路径
        $ssh_opt -n "${ssh_host}" "test -d $rsync_dest || mkdir -p $rsync_dest"
        [ -d "$secret_dir" ] && rsync -rlcvzt "$secret_dir" "${rsync_src}"
        ## 复制文件到目标服务器的目标目录
        echo "deploy to ${ssh_host}:${rsync_dest}"
        ${rsync_opt} -e "$ssh_opt" "${rsync_src}" "${ssh_host}:${rsync_dest}"
    done
    echo_time "end rsync file."
}

deploy_notify_msg() {
    # mr_iid="$(gitlab project-merge-request list --project-id "$CI_PROJECT_ID" --page 1 --per-page 1 | awk '/^iid/ {print $2}')"
    ## sudo -H python3 -m pip install PyYaml
    # [ -z "$msg_describe" ] && msg_describe="$(gitlab -v project-merge-request get --project-id "$CI_PROJECT_ID" --iid "$mr_iid" | sed -e '/^description/,/^diff-refs/!d' -e 's/description: //' -e 's/diff-refs.*//')"
    [ -z "$msg_describe" ] && msg_describe="$(git --no-pager log --no-merges --oneline -1)"
    git_username="$(gitlab -v user get --id "${GITLAB_USER_ID}" | awk '/^name:/ {print $2}')"

    msg_body="
[Gitlab Deploy]
Project = ${CI_PROJECT_PATH}
Branche = ${CI_COMMIT_REF_NAME}
Pipeline = ${CI_PIPELINE_ID}/JobID-$CI_JOB_ID
Describe = [${CI_COMMIT_SHORT_SHA}]/${msg_describe}
Who = ${GITLAB_USER_ID}/${git_username}
Result = $([ "${deploy_result:-0}" = 0 ] && echo OK || echo FAIL)
$(if [ -n "${test_result}" ]; then echo "Test_Result: ${test_result}" else :; fi)
"
}

deploy_notify() {
    echo_time_step "send message to chatApp..."
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
        echo_warn "No message send."
    fi
}

update_cert() {
    echo_time_step "update ssl cert (dns api)..."
    acme_home="${HOME}/.acme.sh"
    acme_cmd="${acme_home}/acme.sh"
    acme_cert="${acme_home}/dest"
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
        if [ -f "$conf_cloudflare" ]; then
            command -v flarectl || return 1
            source "$conf_cloudflare" "${account##*.}"
            domain_name="$(flarectl zone list | awk '/active/ {print $3}')"
            dnsType='dns_cf'
        elif [ -f "$HOME/.aliyun.dnsapi.conf" ]; then
            command -v aliyun || return 1
            source "$HOME/.aliyun.dnsapi.conf" "${account##*.}"
            aliyun configure set --profile "deploy${account##*.}" --mode AK --region "${Ali_region:-none}" --access-key-id "${Ali_Key:-none}" --access-key-secret "${Ali_Secret:-none}"
            domain_name="$(aliyun domain QueryDomainList --output cols=DomainName rows=Data.Domain --PageNum 1 --PageSize 100 | sed '1,2d')"
            dnsType='dns_ali'
        elif [ -f "$HOME/.qcloud.dnspod.conf" ]; then
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
            "${acme_cmd}" --install-cert -d "$domain" --key-file "$acme_cert/$domain".key \
                --fullchain-file "$acme_cert/$domain".crt
        done
    done
    ## 如果有特殊处理的程序则执行
    if [ -f "${acme_home}/deploy.acme.sh" ]; then
        bash "${acme_home}"/deploy.acme.sh
    fi
}

install_python_gitlab() {
    command -v gitlab >/dev/null && return
    python3 -m pip install --user --upgrade python-gitlab
}

install_python_element() {
    # command -v gitlab >/dev/null && return
    python3 -m pip install --user --upgrade matrix-nio
}

install_aws() {
    command -v aws >/dev/null && return
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -qq awscliv2.zip
    sudo ./aws/install
    ## install eksctl
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin/
}

install_kubectl() {
    command -v kubectl >/dev/null && return
    kube_ver="$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)"
    kube_url="https://storage.googleapis.com/kubernetes-release/release/${kube_ver}/bin/linux/amd64/kubectl"
    if [ -z "$ENV_HTTP_PROXY" ]; then
        curl -Lo "${script_dir}/bin/kubectl" "$kube_url"
    else
        curl -x "$ENV_HTTP_PROXY" -Lo "${script_dir}/bin/kubectl" "$kube_url"
    fi
    chmod +x "${script_dir}/bin/kubectl"
    sudo cp -af "${script_dir}/bin/kubectl" /usr/local/bin/kubectl
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
        command -v jmeter >/dev/null || install_jmeter
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
    if [[ -f "${CI_PROJECT_DIR}/apidoc.json" ]]; then
        echo_time_step "generate apidoc."
        $docker_run -v "${CI_PROJECT_DIR}":/app -w /app deploy/node bash -c "apidoc -i app/ -o public/apidoc/"
    # else
    #     echo_warn "apidoc.json not exists."
    fi
}

main() {
    [[ $PIPELINE_DEBUG == 'true' ]] && set -x
    script_name="$(basename "$0")"
    script_name="${script_name%.sh}"
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    script_data="${script_dir}/data" ## 记录 deploy.sh 的数据文件

    PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/usr/local/sbin:/snap/bin"
    PATH="$PATH:$script_data/jdk/bin:$script_data/jmeter/bin:$script_data/ant/bin:$script_data/maven/bin"
    PATH="$PATH:$script_dir/bin:$HOME/.config/composer/vendor/bin:$HOME/.local/bin"
    export PATH

    ## 检查OS 类型和版本，安装相应命令和软件包
    check_os

    ## 安装依赖命令/工具
    [[ "${ENV_INSTALL_AWS}" == true ]] && install_aws
    [[ "${ENV_INSTALL_KUBECTL}" == true ]] && install_kubectl
    [[ "${ENV_INSTALL_HELM}" == true ]] && install_helm
    [[ "${ENV_INSTALL_PYTHON_ELEMENT}" == true ]] && install_python_element
    [[ "${ENV_INSTALL_PYTHON_GITLAB}" == true ]] && install_python_gitlab

    ## 处理传入的参数
    ## 1，默认情况执行所有任务，
    ## 2，如果传入参数，则通过传递入参执行单个任务。适用于单独的gitlab job，（一个 pipeline 多个独立的 job）
    while [[ "${#}" -ge 0 ]]; do
        case $1 in
        --update-ssl)
            PIPELINE_UPDATE_SSL=1
            ;;
        --docker-build-java)
            exec_java_docker_build=1
            ;;
        --docker-push-java)
            exec_java_docker_push=1
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
            exec_deploy_k8s_node=1
            ;;
        --disable-rsync)
            exec_deploy_rsync=0
            ;;
        --diable-flyway)
            exec_flyway=0
            ;;
        *)
            exec_java_docker_build=1
            exec_java_docker_push=1
            exec_deploy_k8s_java=1
            exec_deploy_k8s_php=1
            # gitlabSingleJob=0
            exec_docker_build_node=1
            exec_docker_push_node=1
            exec_deploy_k8s_node=1
            break
            ;;
        esac
        shift
    done
    ##

    script_log="${script_dir}/data/${script_name}.log" ## 记录 deploy.sh 执行情况
    script_conf="${script_dir}/conf/deploy.conf"       ## 发布到目标服务器的配置信息
    script_env="${script_dir}/conf/deploy.env"         ## 发布配置信息(密)
    path_dockerfile="${script_dir}/conf/dockerfile"    ## dockerfile

    [[ ! -f "$script_conf" ]] && cp "${script_dir}/conf/deploy.conf.example" "$script_conf"
    [[ ! -f "$script_env" ]] && cp "${script_dir}/conf/deploy.env.example" "$script_env"
    [[ ! -f "$script_log" ]] && touch "$script_log"

    conf_dir_ssh="${script_dir}/conf/.ssh"
    if [[ ! -d "${conf_dir_ssh}" ]]; then
        mkdir -m 700 "$conf_dir_ssh"
        echo_warn "generate ssh key file for gitlab-runner: $conf_dir_ssh/id_ed25519"
        echo_erro "cat $conf_dir_ssh/id_ed25519.pub >> [dest_server]:\~/.ssh/authorized_keys"
        ssh-keygen -t ed25519 -N '' -f "$conf_dir_ssh/id_ed25519"
        ln -sf "$conf_dir_ssh" "$HOME/"
    fi
    for f in "$conf_dir_ssh"/*; do
        if [ ! -f "$HOME/.ssh/${f##*/}" ]; then
            chmod 600 "${f}"
            ln -sf "${f}" "$HOME/.ssh/"
        fi
    done
    conf_dir_acme="${script_dir}/conf/.acme.sh"
    conf_dir_aws="${script_dir}/conf/.aws"
    conf_dir_kube="${script_dir}/conf/.kube"
    conf_dir_aliyun="${script_dir}/conf/.aliyun"
    conf_python_gitlab="${script_dir}/conf/.python-gitlab.cfg"
    conf_cloudflare="${script_dir}/conf/.cloudflare.cfg"
    conf_rsync_exclude="${script_dir}/conf/rsync.exclude"
    [[ ! -e "${HOME}/.acme.sh" && -e "${conf_dir_acme}" ]] && ln -sf "${conf_dir_acme}" "$HOME/"
    [[ ! -e "${HOME}/.aws" && -e "${conf_dir_aws}" ]] && ln -sf "${conf_dir_aws}" "$HOME/"
    [[ ! -e "${HOME}/.kube" && -e "${conf_dir_kube}" ]] && ln -sf "${conf_dir_kube}" "$HOME/"
    [[ ! -e "${HOME}/.aliyun" && -e "${conf_dir_aliyun}" ]] && ln -sf "${conf_dir_aliyun}" "$HOME/"
    [[ ! -e "${HOME}/.python-gitlab.cfg" && -e "${conf_python_gitlab}" ]] && ln -sf "${conf_python_gitlab}" "$HOME/"
    ## source ENV, 获取 ENV_ 开头的所有全局变量
    # shellcheck disable=SC1090
    source "$script_env"
    [ -z "${branch_name}" ] && branch_name=$CI_COMMIT_REF_NAME
    ## run docker with current user
    docker_run="docker run --interactive --rm -u $UID:$UID"
    ## run docker with root
    # docker_run_root="docker run --interactive --rm"
    image_registry="${ENV_DOCKER_REGISTRY:?undefine}/${ENV_DOCKER_REPO:?undefine}:${CI_PROJECT_NAME:?undefine var}-${CI_COMMIT_SHORT_SHA}"
    git_diff="git --no-pager diff --name-only HEAD^"

    ## 清理磁盘空间
    clean_disk

    ## acme.sh 更新证书
    if [[ "$PIPELINE_UPDATE_SSL" -eq 1 ]]; then
        update_cert
        return
    fi

    ## 判定项目类型
    if [[ -f "${CI_PROJECT_DIR:?undefine var}/package.json" ]]; then
        if grep -i -q 'Create React' "${CI_PROJECT_DIR}/README.md" "${CI_PROJECT_DIR}/readme.md" >/dev/null 2>&1; then
            project_lang='react'
        else
            project_lang='node'
        fi
    fi
    if [[ -f "${CI_PROJECT_DIR}/composer.json" ]]; then
        project_lang='php'
    fi
    if [[ -f "${CI_PROJECT_DIR}/pom.xml" ]]; then
        project_lang='java'
    fi
    if [[ -f "${CI_PROJECT_DIR}/requirements.txt" ]]; then
        project_lang='python'
    fi
    if grep '^## android' "${CI_PROJECT_DIR}/.gitlab-ci.yml" >/dev/null; then
        project_lang='android'
    fi
    if grep '^## ios' "${CI_PROJECT_DIR}/.gitlab-ci.yml" >/dev/null; then
        project_lang='ios'
    fi
    if [[ -f "${CI_PROJECT_DIR}/Dockerfile" ]]; then
        project_docker=1
    fi
    echo "PIPELINE_DISABLE_DOCKER: ${PIPELINE_DISABLE_DOCKER:-0}"
    if [[ "${PIPELINE_DISABLE_DOCKER:-0}" -eq 1 || "${ENV_DISABLE_DOCKER:-0}" -eq 1 ]]; then
        project_docker=0
    fi
    echo "PIPELINE_SONAR: ${PIPELINE_SONAR:-0}"

    ## use flyway deploy sql file
    echo "PIPELINE_FLYWAY: ${PIPELINE_FLYWAY:-1}"
    ## projcet dir 不存在 docs/sql 文件夹，则返回
    [[ ! -d "${CI_PROJECT_DIR}/docs/sql" ]] && exec_flyway=0
    [[ "${PIPELINE_SONAR:-0}" -eq 1 || "${PIPELINE_FLYWAY:-1}" -eq 0 ]] && exec_flyway=0
    if [[ ${exec_flyway:-1} -eq 1 ]]; then
        deploy_sql_flyway
    fi

    ## 蓝绿发布，灰度发布，金丝雀发布的k8s配置文件

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_SONAR ，1 启用，0 禁用[default]
    if [[ "${PIPELINE_SONAR:-0}" -eq 1 ]]; then
        scan_sonarqube
        return $?
    fi

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_UNIT_TEST ，1 启用[default]，0 禁用
    echo "PIPELINE_UNIT_TEST: ${PIPELINE_UNIT_TEST:-1}"
    if [[ "${PIPELINE_UNIT_TEST:-1}" -eq 1 ]]; then
        test_unit
    fi

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_CODE_STYLE ，1 启用[default]，0 禁用
    echo "PIPELINE_CODE_STYLE: ${PIPELINE_CODE_STYLE:-0}"
    if [[ "${PIPELINE_CODE_STYLE:-0}" -eq 1 ]]; then
        check_code_style
    fi

    case "${project_lang}" in
    'php')
        ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_CODE_STYLE ，1 启用[default]，0 禁用
        if [[ "${project_docker}" -eq 1 ]]; then
            [[ "${exec_docker_build_php:-1}" -eq 1 ]] && docker_build_generic
            [[ "${exec_docker_push_php:-1}" -eq 1 ]] && docker_push_generic
            [[ "$exec_deploy_k8s_php" -eq 1 ]] && deploy_k8s_generic
            if [[ ${ENV_FORCE_RSYNC:-false} == true ]]; then
                echo "ENV_FORCE_RSYNC: ${ENV_FORCE_RSYNC:-false}"
                php_composer_volume
            fi
        else
            php_composer_volume
        fi
        ;;
    'node' | 'react')
        if [[ "${project_docker}" -eq 1 ]]; then
            [[ "$exec_docker_build_node" -eq 1 ]] && docker_build_generic
            [[ "$exec_docker_push_node" -eq 1 ]] && docker_push_generic
            [[ "$exec_deploy_k8s_node" -eq 1 ]] && deploy_k8s_generic
            if [[ ${ENV_FORCE_RSYNC:-false} == true ]]; then
                echo "ENV_FORCE_RSYNC: ${ENV_FORCE_RSYNC:-false}"
                node_build_volume
            fi
        else
            node_build_volume
        fi
        ;;
    'java')
        if [[ "${project_docker}" -eq 1 ]]; then
            [[ "$exec_java_docker_build" -eq 1 ]] && java_docker_build
            [[ "$exec_java_docker_push" -eq 1 ]] && java_docker_push
            [[ "$exec_deploy_k8s_java" -eq 1 ]] && java_deploy_k8s
        fi
        ;;
    'android')
        exec_deploy_rsync=0
        ;;
    'ios')
        exec_deploy_rsync=0
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

    ## generate api docs
    # gen_apidoc

    [[ "${project_docker}" -eq 1 || "$ENV_DISABLE_RSYNC" -eq 1 ]] && exec_deploy_rsync=0
    [[ $ENV_FORCE_RSYNC == true ]] && exec_deploy_rsync=1
    if [[ "${exec_deploy_rsync:-1}" -eq 1 ]]; then
        deploy_rsync
    fi

    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_FUNCTION_TEST ，1 启用[default]，0 禁用
    echo "PIPELINE_FUNCTION_TEST: ${PIPELINE_FUNCTION_TEST:-1}"
    if [[ "${PIPELINE_FUNCTION_TEST:-1}" -eq 1 ]]; then
        test_function
    fi

    ## notify
    ## 发送消息到群组, enable_send_msg， 0 不发， 1 发.
    [[ "${deploy_result}" -eq 1 ]] && enable_send_msg=1
    [[ "$ENV_DISABLE_MSG" = 1 ]] && enable_send_msg=0
    [[ "$ENV_DISABLE_MSG_BRANCH" =~ $CI_COMMIT_REF_NAME ]] && enable_send_msg=0
    if [[ "${enable_send_msg:-1}" == 1 ]]; then
        deploy_notify_msg
        deploy_notify
    else
        echo_warn "disable notify."
    fi

    ## deploy result:  0 成功， 1 失败
    return $deploy_result
}

main "$@"
