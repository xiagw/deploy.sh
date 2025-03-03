#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=1090,1091
################################################################################
#
# Description: deploy.sh is a CI/CD program.
# Author: xiagw <fxiaxiaoyu@gmail.com>
# License: GNU/GPL, see http://www.gnu.org/copyleft/gpl.html
# Create Date: 2019-04-03
#
################################################################################

## year month day - time - %u day of week (1..7); 1 is Monday - %j day of year (001..366) - %W week number of year, with Monday as first day of week (00..53)

# 解决 Encountered 1 file(s) that should have been pointers, but weren't
# git lfs migrate import --everything$(awk '/filter=lfs/ {printf " --include='\''%s'\''", $1}' .gitattributes)

config_deploy_vars() {
    ## Set repository directory from GitLab CI variable CI_PROJECT_DIR or fallback to PWD
    G_REPO_DIR=${CI_PROJECT_DIR:-$PWD}

    ## Extract repository name from Gitea/GitHub or GitLab CI variables
    ## 使用 GITHUB_REPOSITORY 变量获取仓库名 (格式: owner/repo)
    if [[ -n "${GITHUB_REPOSITORY}" ]]; then
        G_REPO_NAME=${GITHUB_REPOSITORY##*/}
    else
        ## Fallback to GitLab CI variable CI_PROJECT_NAME or directory name
        G_REPO_NAME=${CI_PROJECT_NAME:-${G_REPO_DIR##*/}}
    fi

    ## Set repository namespace from Gitea/GitHub or GitLab CI variables
    ## 使用 GITHUB_REPOSITORY_OWNER 变量获取命名空间 (owner/group/org)
    if [[ -n "${GITHUB_REPOSITORY_OWNER}" ]]; then
        G_REPO_NS=${GITHUB_REPOSITORY_OWNER}
    else
        ## Fallback to GitLab CI namespace or 'root'
        G_REPO_NS=${CI_PROJECT_NAMESPACE:-root}
    fi

    ## Construct repository path and slug from CI variables or constructed values
    G_REPO_GROUP_PATH=${CI_PROJECT_PATH:-$G_REPO_NS/$G_REPO_NAME}
    G_REPO_GROUP_PATH_SLUG=${CI_PROJECT_PATH_SLUG:-${G_REPO_GROUP_PATH//[.\/]/-}}

    ## Get current git branch name
    G_REPO_BRANCH=$(get_git_branch)

    ## Get abbreviated git commit hash
    G_REPO_SHORT_SHA=$(get_git_commit_sha)

    ## Set Kubernetes namespace to match git branch name
    G_NAMESPACE=$G_REPO_BRANCH

    ## Docker image tag format: <git-commit-sha>-<unix-timestamp-with-milliseconds>
    G_IMAGE_TAG="${G_REPO_SHORT_SHA}-$(date +%s%3N)"

    # Handle crontab execution
    if ${run_with_crontab:-false}; then
        check_crontab_execution "$G_DATA" "$CI_PROJECT_ID" "$G_REPO_SHORT_SHA" || exit 0
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
    --gitea                  Use Gitea with GITHUB_* variables.
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
    --deploy-rsync-ssh       Deploy using rsync over SSH.
    --deploy-rsync           Deploy to rsync server.
    --deploy-ftp             Deploy to FTP server.
    --deploy-sftp            Deploy to SFTP server.

    # Testing and quality
    --test-unit              Run unit tests.
    --test-function          Run functional tests.
    --code-style             Check code style.
    --code-quality           Check code quality.
    --security-zap           Run ZAP security scan.
    --security-vulmap        Run Vulmap security scan.

    # Kubernetes operations
    --create-helm DIR        Create Helm chart in specified directory.
    --create-k8s             Create K8s cluster with Terraform.

    # Miscellaneous
    --disable-inject         Disable file injection.
    -r, --renew-cert         Renew all the certs.
EOF
}

parse_command_args() {
    ## Enable debug mode if CI_DEBUG_TRACE is true
    [[ ${CI_DEBUG_TRACE:-false} == true ]] && DEBUG_ON=true
    DOCKER=$(command -v podman || command -v docker || echo docker)

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        # Basic options
        -h | --help) _usage && exit 0 ;;
        -v | --version) echo "Version: 1.0" && exit 0 ;;
        -d | --debug) DEBUG_ON=true ;;
        --cron | --loop) run_with_crontab=true ;;
        --github-action) DEBUG_ON=true && GITHUB_ACTION=true ;;
        --in-china) sed -i -e '/ENV_IN_CHINA=/s/false/true/' "$G_ENV" ;;
        ## gitea variables
        --gitea)
            # Check if ENV_GITEA_SERVER is defined, otherwise use a default or GITHUB_SERVER_URL
            if [[ -z "${ENV_GITEA_SERVER}" ]]; then
                # Try to use GITHUB_SERVER_URL if available, otherwise use a default
                if [[ -n "${GITHUB_SERVER_URL}" ]]; then
                    ENV_GITEA_SERVER="${GITHUB_SERVER_URL#*://}"
                else
                    ENV_GITEA_SERVER="gitea.example.com"
                    _msg warn "ENV_GITEA_SERVER not defined, using default: ${ENV_GITEA_SERVER}"
                fi
            fi
            arg_git_clone_url="ssh://git@${ENV_GITEA_SERVER}/${GITHUB_REPOSITORY}.git"
            arg_git_clone_branch="${GITHUB_REF_NAME}"
            ;;
        # Repository operations
        --git-clone) arg_git_clone_url="${2:?empty git clone url}" && shift ;;
        --git-clone-branch) arg_git_clone_branch="${2:?empty git clone branch}" && shift ;;
        --svn-checkout) arg_svn_checkout_url="${2:?empty svn url}" && shift ;;
        # Build and push
        --build-langs) arg_build_langs=true && exec_single_job=true ;;
        --build-docker)
            arg_build_image=true
            exec_single_job=true
            DOCKER=$(command -v docker || return 1)
            ;;
        --build-podman)
            arg_build_image=true
            exec_single_job=true
            DOCKER=$(command -v podman || return 1)
            DOCKER_OPT='--force-rm --format=docker'
            echo "$DOCKER $DOCKER_OPT" >/dev/null
            ;;
        --push-image) arg_push_image=true && exec_single_job=true ;;
        # Deployment
        --deploy-k8s) arg_deploy_method=helm && exec_single_job=true ;;
        --deploy-aliyun-func) arg_deploy_method=aliyun_func && exec_single_job=true ;;
        --deploy-aliyun-oss) arg_deploy_method=aliyun_oss && exec_single_job=true ;;
        --deploy-rsync-ssh) arg_deploy_method=rsync_ssh && exec_single_job=true ;;
        --deploy-rsync) arg_deploy_method=rsync && exec_single_job=true ;;
        --deploy-ftp) arg_deploy_method=ftp && exec_single_job=true ;;
        --deploy-sftp) arg_deploy_method=sftp && exec_single_job=true ;;
        # Testing and quality
        --test-unit) arg_test_unit=true && exec_single_job=true ;;
        --apidoc) arg_apidoc=true && exec_single_job=true ;;
        --test-function) arg_test_func=true && exec_single_job=true ;;
        --code-style) arg_code_style=true && exec_single_job=true ;;
        --code-quality) arg_code_quality=true && exec_single_job=true ;;
        --security-zap) arg_security_zap=true ;;
        --security-vulmap) arg_security_vulmap=true ;;
        # Kubernetes operations
        --create-helm)
            arg_create_helm=true
            exec_single_job=true
            disable_inject_action=true
            helm_dir="$2"
            shift
            ;;
        --create-k8s) create_k8s_with_terraform=true ;;
        # Miscellaneous
        --disable-inject) disable_inject_on_env=true ;;
        -r | --renew-cert) arg_renew_cert=true && exec_single_job=true ;;
        *) _usage && exit 1 ;;
        esac
        shift
    done

    ## Set quiet mode unless debug is enabled
    ${DEBUG_ON:-false} && unset G_QUIET || G_QUIET='--quiet'

    ## Enable shell debugging if DEBUG_ON is true
    if ${DEBUG_ON:-false}; then set -x; else true; fi
}

main() {
    set -e ## 出现错误自动退出
    # set -u ## 变量未定义报错 # set -Eeuo pipefail
    if [[ ${CI_DEBUG_TRACE:-false} == true ]]; then
        set -x
    fi
    SECONDS=0
    ## Prefix G_ is GLOBAL_
    G_NAME="$(basename "${BASH_SOURCE[0]}")"
    G_PATH="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    G_LIB="${G_PATH}/lib"
    G_DATA="${G_PATH}/data"
    G_LOG="${G_DATA}/${G_NAME}.log"
    G_CONF="${G_DATA}/deploy.json"
    G_ENV="${G_DATA}/deploy.env"

    # Source required modules
    source "$G_LIB/config.sh"
    source "$G_LIB/common.sh"
    source "$G_LIB/notify.sh"
    source "$G_LIB/system.sh"
    source "$G_LIB/analysis.sh"
    source "$G_LIB/kubernetes.sh"
    source "$G_LIB/deployment.sh"
    source "$G_LIB/test.sh"
    source "$G_LIB/docker.sh"
    source "$G_LIB/repo.sh"
    source "$G_LIB/style.sh"
    source "$G_LIB/build.sh"

    _msg step "[deploy] BEGIN"

    ## Process parameters / 处理传入的参数
    parse_command_args "$@"

    config_deploy_depend file

    config_deploy_depend path

    ## check OS version/type/install command/install software / 检查系统版本/类型/安装命令/安装软件
    system_check

    # Remove the wrapper function and its call
    if [ -n "${arg_git_clone_url}" ]; then
        setup_git_repo "${arg_git_clone_url:-}" "${arg_git_clone_branch:-main}"
    fi

    ## svn checkout repo / 克隆 svn 仓库
    if [ -n "${arg_svn_checkout_url}" ]; then
        setup_svn_repo "${arg_svn_checkout_url:-}"
    fi

    ## run deploy.sh by hand / 手动执行 deploy.sh 时假定的 gitlab 配置
    config_deploy_vars

    ## source ENV, get global variables / 获取 ENV_ 开头的所有全局变量
    source "$G_ENV"

    # Cloud Service Tools
    ([ "${ENV_DOCKER_LOGIN_TYPE:-}" = aws ] || ${ENV_INSTALL_AWS:-false}) && _install_aws
    ${ENV_INSTALL_ALIYUN:-false} && _install_aliyun_cli

    # Basic Tools
    ${ENV_INSTALL_JQ:-false} && { command -v jq &>/dev/null || _install_packages "$(is_china)" jq; }
    ${ENV_INSTALL_CRON:-false} && { command -v crontab &>/dev/null || _install_packages "$(is_china)" cron; }

    # Infrastructure Tools
    ${ENV_INSTALL_TERRAFORM:-false} && _install_terraform
    ${ENV_INSTALL_KUBECTL:-false} && _install_kubectl
    ${ENV_INSTALL_HELM:-false} && _install_helm

    # Integration Tools
    ${ENV_INSTALL_PYTHON_ELEMENT:-false} && _install_python_element "$@" "$(is_china)"
    ${ENV_INSTALL_PYTHON_GITLAB:-false} && _install_python_gitlab "$@" "$(is_china)"
    ${ENV_INSTALL_JMETER:-false} && _install_jmeter
    ${ENV_INSTALL_FLARECTL:-false} && _install_flarectl

    # Container Tools
    ${ENV_INSTALL_DOCKER:-false} && _install_docker "$(is_china && echo "--mirror Aliyun" || echo "")"
    ${ENV_INSTALL_PODMAN:-false} && _install_podman

    ## clean up disk space / 清理磁盘空间
    system_clean_disk

    ## create k8s / 创建 kubernetes 集群
    ${create_k8s_with_terraform:-false} && kube_setup_terraform

    # Set up kubectl and helm 位置不能前移
    kube_config_init "$G_NAMESPACE"

    ## setup ssh-config/acme.sh/aws/kube/aliyun/python-gitlab/cloudflare/rsync
    config_deploy_depend env >/dev/null

    ## renew cert with acme.sh / 使用 acme.sh 重新申请证书
    system_cert_renew "${arg_renew_cert:-false}"

    ## probe program lang / 探测项目的程序语言
    _msg step "[language] probe program language"
    repo_lang=$(repo_language_detect)
    _msg info "Detected program language: ${repo_lang}"
    # 设置构建参数
    DOCKER_RUN0="$DOCKER run $ENV_ADD_HOST --interactive --rm -u 0:0"
    DOCKER_RUN="$DOCKER run $ENV_ADD_HOST --interactive --rm -u 1000:1000"
    DOCKER_OPT="${DOCKER_OPT:+"$DOCKER_OPT "}$ENV_ADD_HOST $G_QUIET"
    ${DEBUG_ON:-false} && DOCKER_OPT+=" --progress plain"
    BUILD_ARG="${BUILD_ARG:+"$BUILD_ARG "}--build-arg IN_CHINA=${ENV_IN_CHINA:-false}"
    [ -n "${ENV_DOCKER_MIRROR}" ] && BUILD_ARG+=" --build-arg MVN_IMAGE=${ENV_DOCKER_MIRROR} --build-arg JDK_IMAGE=${ENV_DOCKER_MIRROR}"
    if [ "$repo_lang" = java ]; then
        BUILD_ARG+=" --build-arg MVN_PROFILE=${G_REPO_BRANCH}"
        ${DEBUG_ON:-false} && BUILD_ARG+=" --build-arg MVN_DEBUG=on"
    fi

    ## preprocess project config files / 预处理业务项目配置文件，覆盖配置文件等特殊处理
    # Skip injection if disabled
    repo_inject_file "$repo_lang" "${disable_inject_action:-false}" "${disable_inject_on_env:-false}"

    ## probe deploy method / 探测文件并确定发布方式
    [ -z "$arg_deploy_method" ] && arg_deploy_method=$(handle_deploy probe)

    ################################################################################
    ## exec single task / 执行单个任务，适用于 gitlab-ci/jenkins 等自动化部署工具的单个 job 任务执行
    if ${exec_single_job:-false}; then
        _msg green "exec single jobs..."
        ${arg_code_quality:-false} && analysis_sonarqube
        ${arg_code_style:-false} && style_check "$repo_lang"
        ${arg_test_unit:-false} && handle_test unit
        ${arg_apidoc:-false} && generate_apidoc
        ${arg_build_langs:-false} && build_lang "$repo_lang"
        ${arg_build_image:-false} && build_image "$G_QUIET" "$G_IMAGE_TAG"
        ${arg_push_image:-false} && push_image
        ${arg_create_helm:-false} && create_helm_chart "${helm_dir}"
        ${arg_deploy_helm:-false} && handle_deploy "$arg_deploy_method" "$repo_lang" "$G_REPO_GROUP_PATH_SLUG" "$G_CONF" "$G_LOG"
        ${arg_test_func:-false} && handle_test func
        ${arg_security_zap:-false} && analysis_zap
        ${arg_security_vulmap:-false} && analysis_vulmap
        _msg green "exec single jobs...end"
        ${GITHUB_ACTION:-false} || return 0
    fi
    ################################################################################

    ## default exec all tasks / 单个任务未启动时默认执行所有任务
    analysis_sonarqube
    ## check code style
    style_check "$repo_lang"
    ## unit test
    handle_test unit
    ## generate api docs / 利用 apidoc 产生 api 文档
    ${arg_apidoc:-false} && generate_apidoc
    ## build
    build_lang "$repo_lang" "$arg_deploy_method"
    ## build docker image
    build_image
    push_image
    ## deploy
    handle_deploy "$arg_deploy_method" "$repo_lang"
    ## 功能测试
    handle_test func
    ## 安全扫描
    analysis_zap
    analysis_vulmap

    ## deploy notify info / 发布通知信息
    handle_notify

    _msg time "[deploy] END."

    ## deploy result:  0 成功， 1 失败
    return "${deploy_result:-0}"
}

main "$@"
