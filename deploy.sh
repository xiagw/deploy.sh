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
    --build-image          Build image with Docker/Podman.
    --push-image            Push image to registry.

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

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        # Basic options
        -h | --help) _usage && exit 0 ;;
        -v | --version) echo "Version: 5.0.0" && exit 0 ;;
        -d | --debug) DEBUG_ON=true ;;
        --cron | --loop) run_with_crontab=true ;;
        --github-action) DEBUG_ON=true && export GH_ACTION=true ;;
        --in-china) arg_in_china=true ;;
        ## gitea variables
        --gitea) arg_gitea=true ;;
        # Repository operations
        --git-clone) arg_git_clone_url="${2:?empty git clone url}" && shift ;;
        --git-clone-branch) arg_git_clone_branch="${2:?empty git clone branch}" && shift ;;
        --svn-checkout) arg_svn_checkout_url="${2:?empty svn url}" && shift ;;
        # Build and push
        --build-langs) arg_flags["build_langs"]=1 ;;
        --build-image) arg_flags["build_image"]=1 && deploy_method=deploy_k8s ;;
        --push-image) arg_flags["push_image"]=1 && deploy_method=deploy_k8s ;;
        # Deployment
        --deploy-k8s) arg_flags["deploy_k8s"]=1 && deploy_method=deploy_k8s ;;
        --deploy-docker) arg_flags["deploy_docker"]=1 && deploy_method=deploy_docker ;;
        --deploy-aliyun-func) arg_flags["deploy_aliyun_func"]=1 && deploy_method=deploy_aliyun_func ;;
        --deploy-aliyun-oss) arg_flags["deploy_aliyun_oss"]=1 && deploy_method=deploy_aliyun_oss ;;
        --deploy-rsync-ssh) arg_flags["deploy_rsync_ssh"]=1 && deploy_method=deploy_rsync_ssh ;;
        --deploy-rsync) arg_flags["deploy_rsync"]=1 && deploy_method=deploy_rsync ;;
        --deploy-ftp) arg_flags["deploy_ftp"]=1 && deploy_method=deploy_ftp ;;
        --deploy-sftp) arg_flags["deploy_sftp"]=1 && deploy_method=deploy_sftp ;;
        # Testing and quality
        --test-unit) arg_flags["test_unit"]=1 ;;
        --apidoc) arg_flags["apidoc"]=1 ;;
        --test-function) arg_flags["test_func"]=1 ;;
        --code-style) arg_flags["code_style"]=1 ;;
        --code-quality) arg_flags["code_quality"]=1 ;;
        --security-zap) arg_flags["security_zap"]=1 ;;
        --security-vulmap) arg_flags["security_vulmap"]=1 ;;
        # Kubernetes operations
        --create-helm)
            arg_create_helm=true
            disable_inject_action=true
            helm_dir="$2"
            shift
            ;;
        --create-k8s) create_k8s_with_terraform=true ;;
        # Miscellaneous
        --disable-inject) disable_inject_on_env=true ;;
        -r | --renew-cert) arg_renew_cert=true ;;
        *) _usage && exit 1 ;;
        esac
        shift
    done

    ## 检查是否有参数则部分设1，没有任何参数则全部设置为1
    all_zero=true
    for key in "${!arg_flags[@]}"; do
        if [[ "${arg_flags[$key]}" -eq 1 ]]; then
            all_zero=false
            break
        fi
    done

    if $all_zero; then
        for key in "${!arg_flags[@]}"; do
            arg_flags[$key]=1
        done
    fi

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

    ## 声明关联数组用于跟踪参数使用情况
    declare -A arg_flags=(
        ["build_langs"]=0
        ["build_image"]=0
        ["push_image"]=0
        ["deploy_k8s"]=0
        ["deploy_docker"]=0
        ["deploy_aliyun_func"]=0
        ["deploy_aliyun_oss"]=0
        ["deploy_rsync_ssh"]=0
        ["deploy_rsync"]=0
        ["deploy_ftp"]=0
        ["deploy_sftp"]=0
        ["test_unit"]=0
        ["apidoc"]=0
        ["test_func"]=0
        ["code_style"]=0
        ["code_quality"]=0
        ["security_zap"]=0
        ["security_vulmap"]=0
    )
    ## 解析和处理命令行参数
    parse_command_args "$@"

    ## 加载所需的模块文件
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

    ## 复制示例配置文件（deploy.json、deploy.env）到data目录
    config_deploy_depend file

    ## 添加必要的二进制文件目录到PATH环境变量
    config_deploy_depend path

    ## 检测操作系统版本、类型，安装必要的命令和软件
    system_check

    ## 处理 --gitea 参数
    if ${arg_gitea:-false}; then
        if [[ -z "${ENV_GITEA_SERVER}" ]]; then
            if [[ -n "${GITHUB_SERVER_URL}" ]]; then
                ENV_GITEA_SERVER="${GITHUB_SERVER_URL#*://}"
            fi
        fi
        if [[ "${ENV_GITEA_SERVER}" =~ gitea.example.com ]]; then
            _msg error "ENV_GITEA_SERVER cannot contain 'example' as it is a default value placeholder"
            return 1
        fi
        arg_git_clone_url="ssh://git@${ENV_GITEA_SERVER}/${GITHUB_REPOSITORY}.git"
        arg_git_clone_branch="${GITHUB_REF_NAME}"
    fi
    ## Git仓库克隆
    if [ -n "${arg_git_clone_url}" ]; then
        setup_git_repo "${arg_git_clone_url:-}" "${arg_git_clone_branch:-main}"
    fi

    ## SVN仓库检出
    if [ -n "${arg_svn_checkout_url}" ]; then
        setup_svn_repo "${arg_svn_checkout_url:-}"
    fi

    ## 设置手动执行deploy.sh时的GitLab默认配置
    config_deploy_vars

    ## 导入所有以ENV_开头的全局变量
    source "$G_ENV"

    ## 处理 --in-china 参数
    ${arg_in_china:-false} && sed -i -e '/ENV_IN_CHINA=/s/false/true/' "$G_ENV"
    ${arg_create_helm:-false} && create_helm_chart "${helm_dir}"

    ## 基础工具安装
    command -v jq &>/dev/null || _install_packages "$(is_china)" jq

    ## 云服务工具安装
    ([ "${ENV_DOCKER_LOGIN_TYPE:-}" = aws ] || ${ENV_INSTALL_AWS:-false}) && _install_aws
    ${ENV_INSTALL_ALIYUN:-false} && _install_aliyun_cli

    ## 基础设施工具安装
    ${ENV_INSTALL_TERRAFORM:-false} && _install_terraform
    ${ENV_INSTALL_KUBECTL:-false} && _install_kubectl
    ${ENV_INSTALL_HELM:-false} && _install_helm

    ## 集成工具安装
    ${ENV_INSTALL_PYTHON_ELEMENT:-false} && _install_python_element "$@" "$(is_china)"
    ${ENV_INSTALL_PYTHON_GITLAB:-false} && _install_python_gitlab "$@" "$(is_china)"
    ${ENV_INSTALL_JMETER:-false} && _install_jmeter
    ${ENV_INSTALL_FLARECTL:-false} && _install_flarectl

    ## 容器工具安装
    ${ENV_INSTALL_DOCKER:-false} && _install_docker "$(is_china && echo "--mirror Aliyun" || echo "")"
    ${ENV_INSTALL_PODMAN:-false} && _install_podman

    ## 系统维护：清理磁盘空间
    system_clean_disk

    ## Kubernetes集群创建
    ${create_k8s_with_terraform:-false} && kube_setup_terraform

    ## 注意：Kubernetes配置初始化，此步骤位置不可调整
    kube_config_init "$G_NAMESPACE"

    ## 设置ssh-config/acme.sh/aws/kube/aliyun/python-gitlab/cloudflare/rsync
    config_deploy_depend env >/dev/null

    ## 使用acme.sh更新SSL证书
    system_cert_renew "${arg_renew_cert:-false}"

    ## 探测项目的程序语言
    _msg step "[language] probe program language"
    repo_lang=$(repo_language_detect)
    _msg info "Detected program language: ${repo_lang}"

    ## 处理构建工具选择
    DOCKER=$(command -v podman || command -v docker || echo docker)
    if [ "${arg_flags["build_image"]}" -eq 1 ]; then
        if command -v docker >/dev/null 2>&1; then
            DOCKER=$(command -v docker)
        elif command -v podman >/dev/null 2>&1; then
            DOCKER=$(command -v podman)
            BUILD_ARG="--force-rm --format=docker"
        else
            _msg error "Neither docker nor podman found"
            return 1
        fi
    fi
    # 设置构建参数
    DOCKER_RUN0="$DOCKER run $ENV_ADD_HOST --interactive --rm -u 0:0"
    DOCKER_RUN="$DOCKER run $ENV_ADD_HOST --interactive --rm -u 1000:1000"
    BUILD_ARG+=" $ENV_ADD_HOST $G_QUIET --build-arg IN_CHINA=${ENV_IN_CHINA:-false}"
    if [ -n "${ENV_DOCKER_MIRROR}" ]; then
        BUILD_ARG+=" --build-arg MVN_IMAGE=${ENV_DOCKER_MIRROR} --build-arg JDK_IMAGE=${ENV_DOCKER_MIRROR}"
    fi
    if ${DEBUG_ON:-false}; then
        BUILD_ARG+=" --progress plain"
    fi
    if [ "$repo_lang" = java ]; then
        BUILD_ARG+=" --build-arg MVN_PROFILE=${G_REPO_BRANCH}"
        if ${DEBUG_ON:-false}; then
            BUILD_ARG+=" --build-arg MVN_DEBUG=on"
        fi
    fi
    export DOCKER_RUN0 DOCKER_RUN BUILD_ARG

    ## preprocess project config files / 预处理业务项目配置文件，覆盖配置文件等特殊处理
    # Skip injection if disabled
    repo_inject_file "$repo_lang" "${disable_inject_action:-false}" "${disable_inject_on_env:-false}"

    ################################################################################
    ## 根据 arg_flags 执行相应的任务
    _msg green "executing tasks..."

    # 代码质量和风格检查
    [[ ${arg_flags["code_quality"]} -eq 1 ]] && analysis_sonarqube
    [[ ${arg_flags["code_style"]} -eq 1 ]] && style_check "$repo_lang"

    # 单元测试
    [[ ${arg_flags["test_unit"]} -eq 1 ]] && handle_test unit

    # API文档生成
    [[ ${arg_flags["apidoc"]} -eq 1 ]] && generate_apidoc

    ## probe deploy method / 探测文件并确定发布方式
    if [ -z "${deploy_method}" ]; then
        deploy_method=$(handle_deploy probe)
    fi
    if [[ "${deploy_method}" =~ ^(deploy_k8s|deploy_docker)$ ]]; then
        arg_flags["build_langs"]=0
    fi
    if [[ "${deploy_method}" =~ ^(deploy_rsync_ssh)$ ]]; then
        arg_flags["build_image"]=0
        arg_flags["push_image"]=0
    fi
    # 构建相关任务
    [[ ${arg_flags["build_langs"]} -eq 1 ]] && build_lang "$repo_lang"
    [[ ${arg_flags["build_image"]} -eq 1 ]] && build_image "$G_QUIET" "$G_IMAGE_TAG"
    [[ ${arg_flags["push_image"]} -eq 1 ]] && push_image

    # 部署相关任务
    $all_zero && handle_deploy "$deploy_method" "$repo_lang" "$G_REPO_GROUP_PATH_SLUG" "$G_CONF" "$G_LOG"

    # 测试和安全扫描
    [[ ${arg_flags["test_func"]} -eq 1 ]] && handle_test func
    [[ ${arg_flags["security_zap"]} -eq 1 ]] && analysis_zap
    [[ ${arg_flags["security_vulmap"]} -eq 1 ]] && analysis_vulmap

    _msg green "tasks execution completed"
    ################################################################################

    ## deploy notify info / 发布通知信息
    handle_notify

    _msg time "[deploy] END."

    ## deploy result:  0 成功， 1 失败
    return "${deploy_result:-0}"
}

main "$@"
