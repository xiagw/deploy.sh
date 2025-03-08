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
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        # Basic options
        -h | --help) _usage && exit 0 ;;
        -v | --version) echo "Version: 5.0.0" && exit 0 ;;
        -d | --debug) DEBUG_ON=true && set -x ;;
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

    if ${DEBUG_ON:-false}; then
        unset G_QUIET
    else
        export G_QUIET='--quiet'
    fi
    ## 检查是否有命令参数则部分设1，
    all_zero=true
    for key in "${!arg_flags[@]}"; do
        if [[ "${arg_flags[$key]}" -eq 1 ]]; then
            all_zero=false
            break
        fi
    done
    ## 没有任何参数则全部设置为1
    if $all_zero; then
        for key in "${!arg_flags[@]}"; do
            arg_flags[$key]=1
        done
    fi
}

# 配置 Docker/Podman 构建环境
config_build_env() {
    local docker_cmd build_args=""

    # 选择构建工具（Docker 或 Podman）
    docker_cmd=$(command -v podman || command -v docker || echo docker)

    # 如果需要构建镜像，进行更严格的工具选择
    if [ "${arg_flags["build_image"]}" -eq 1 ]; then
        if command -v docker >/dev/null 2>&1; then
            docker_cmd=$(command -v docker)
        elif command -v podman >/dev/null 2>&1; then
            docker_cmd=$(command -v podman)
            build_args="--force-rm --format=docker"
        else
            _msg error "Neither docker nor podman found"
            return 1
        fi
    fi

    # 设置基本的 Docker 运行命令
    DOCKER="${docker_cmd}"
    DOCKER_RUN0="${docker_cmd} run ${ENV_ADD_HOST} --interactive --rm"
    DOCKER_RUN="${docker_cmd} run ${ENV_ADD_HOST} --interactive --rm -u 1000:1000"

    # 构建参数配置
    build_args+=" ${ENV_ADD_HOST} ${G_QUIET} --build-arg IN_CHINA=${ENV_IN_CHINA:-false}"

    # Docker 镜像源配置
    if [ -n "${ENV_DOCKER_MIRROR}" ]; then
        build_args+=" --build-arg MVN_IMAGE=${ENV_DOCKER_MIRROR}"
        build_args+=" --build-arg JDK_IMAGE=${ENV_DOCKER_MIRROR}"
    fi

    # 调试模式配置
    if ${DEBUG_ON:-false}; then
        build_args+=" --progress plain"
    fi

    # Java 项目特殊配置
    if [ "$repo_lang" = java ]; then
        build_args+=" --build-arg MVN_PROFILE=${G_REPO_BRANCH}"
        if ${DEBUG_ON:-false}; then
            build_args+=" --build-arg MVN_DEBUG=on"
        fi
    fi

    # 导出环境变量
    BUILD_ARG="${build_args}"
    export DOCKER DOCKER_RUN0 DOCKER_RUN BUILD_ARG
}

main() {
    # set -Eeuo pipefail
    set -e ## 出现错误自动退出
    if [[ ${CI_DEBUG_TRACE:-false} == true ]]; then
        set -x
        DEBUG_ON=true
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
    source "$G_LIB/analysis.sh"
    source "$G_LIB/build.sh"
    source "$G_LIB/common.sh"
    source "$G_LIB/config.sh"
    source "$G_LIB/deployment.sh"
    source "$G_LIB/kubernetes.sh"
    source "$G_LIB/notify.sh"
    source "$G_LIB/repo.sh"
    source "$G_LIB/style.sh"
    source "$G_LIB/system.sh"
    source "$G_LIB/test.sh"

    _msg step "[deploy] BEGIN"

    ## 复制示例配置文件（deploy.json、deploy.env）到data目录 添加必要的二进制文件目录到PATH环境变量
    config_deploy_depend file

    ## 检测操作系统版本、类型，安装必要的命令和软件
    system_check

    ## 导入所有以ENV_开头的全局变量（位置不要随意变动）
    source "$G_ENV"

    ## Git仓库克隆 处理 --gitea 参数
    if ${arg_gitea:-false} || [ -n "${arg_git_clone_url}" ]; then
        setup_git_repo "${arg_gitea:-false}" "${arg_git_clone_url:-}" "${arg_git_clone_branch:-main}"
    fi

    ## SVN仓库检出
    [ -n "${arg_svn_checkout_url:-}" ] && setup_svn_repo

    ## 设置手动执行deploy.sh时的GitLab默认配置（位置不要随意变动）
    config_deploy_vars

    ## 处理 --in-china 参数
    ${arg_in_china:-false} && sed -i -e '/ENV_IN_CHINA=/s/false/true/' "$G_ENV"
    ${arg_create_helm:-false} && create_helm_chart "${helm_dir}"

    ## 安装所需的系统工具
    system_install_tools "$@"

    ## 系统维护：清理磁盘空间
    system_clean_disk

    ## Kubernetes集群创建
    ${create_k8s_with_terraform:-false} && kube_setup_terraform

    ## 注意：Kubernetes配置初始化，此步骤位置不可调整
    kube_config_init "$G_NAMESPACE"

    ## 设置ssh-config/acme.sh/aws/kube/aliyun/python-gitlab/cloudflare/rsync
    config_deploy_depend env >/dev/null

    ## 使用acme.sh更新SSL证书
    ${arg_renew_cert:-false} && system_cert_renew

    ## 探测项目的程序语言
    _msg step "[lang] probe program language"
    repo_lang_detect=$(repo_language_detect)
    repo_lang=${repo_lang_detect%%:*}
    ## 解析语言类型和 docker 标识
    repo_dockerfile=${repo_lang_detect##*:}
    _msg info "Detected program language: ${repo_lang}"

    ## 处理构建工具选择
    config_build_env || return 1

    ## preprocess project config files / 预处理业务项目配置文件，覆盖配置文件等特殊处理
    # Skip injection if disabled
    repo_inject_file "$repo_lang" "${disable_inject_action:-false}" "${disable_inject_on_env:-false}"
    repo_lang_detect=$(repo_language_detect)
    ## 解析 docker 标识
    repo_dockerfile=${repo_lang_detect##*:}

    ################################################################################
    ## 全自动执行，或根据 arg_flags 执行相应的任务
    if $all_zero; then
        _msg green "executing tasks... [auto mode: all tasks will be executed]"
    else
        _msg green "executing tasks... [single job: only specified tasks will be executed]"
        # 可选：打印将要执行的任务列表
        echo "Tasks to execute:"
        for key in "${!arg_flags[@]}"; do
            [[ ${arg_flags[$key]} -eq 1 ]] && echo "  - ${key}"
        done
    fi

    # 代码质量和风格检查
    [[ ${arg_flags["code_quality"]} -eq 1 ]] && analysis_sonarqube
    [[ ${arg_flags["code_style"]} -eq 1 ]] && style_check "$repo_lang"

    # 单元测试
    [[ ${arg_flags["test_unit"]} -eq 1 ]] && handle_test unit

    # API文档生成
    [[ ${arg_flags["apidoc"]} -eq 1 ]] && generate_apidoc

    # 构建相关任务
    if [[ -z "${repo_dockerfile}" ]]; then
        arg_flags["build_image"]=0
        arg_flags["push_image"]=0
    else
        arg_flags["build_langs"]=0
    fi
    [[ ${arg_flags["build_langs"]} -eq 1 ]] && build_lang "$repo_lang"
    [[ ${arg_flags["build_image"]} -eq 1 ]] && build_image "$G_QUIET" "$G_IMAGE_TAG"
    [[ ${arg_flags["push_image"]} -eq 1 ]] && push_image

    # 发布，最优雅的写法
    deploy_sum=0
    for key in "${!arg_flags[@]}"; do
        [[ $key == deploy_* ]] && ((deploy_sum += arg_flags[$key]))
    done

    if [[ $deploy_sum -gt 0 ]] || $all_zero; then
        handle_deploy "${deploy_method:-}" "$repo_lang" "$G_REPO_GROUP_PATH_SLUG" "$G_CONF" "$G_LOG" || {
            _msg error "Deployment failed"
            deploy_result=1
            # 如果部署失败，跳过后续测试和扫描
            arg_flags["test_func"]=0
            arg_flags["security_zap"]=0
            arg_flags["security_vulmap"]=0
        }
    fi

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
