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

    ## Set Kubernetes namespace based on git branch mapping
    case "${G_REPO_BRANCH}" in
    dev) G_NAMESPACE="develop" ;;
    test | sit) G_NAMESPACE="testing" ;;
    uat) G_NAMESPACE="release" ;;
    prod | master) G_NAMESPACE="main" ;;
    *) G_NAMESPACE="${G_REPO_BRANCH}" ;;
    esac

    ## Docker image tag format: <git-commit-sha>-<unix-timestamp-with-milliseconds>
    # G_IMAGE_TAG="${G_REPO_SHORT_SHA}-$(date +%s%3N)"
    G_IMAGE_TAG="$(date +%s%3N)"
    ## 1. ENV_DOCKER_RANDOM=false, $ENV_DOCKER_REGISTRY/$G_REPO_NAME:$G_IMAGE_TAG
    ## 2. ENV_DOCKER_RANDOM=true,  $ENV_DOCKER_REGISTRY/$RANDOM:$G_IMAGE_TAG
    if [[ "${ENV_DOCKER_RANDOM:-false}" = true ]]; then
        local chars chars_rand
        chars=({a..o})
        ## 随机选取a-o当中的两个字母组合成字符串（可组合总数225个）
        chars_rand="${chars[$((RANDOM % ${#chars[@]}))]}${chars[$((RANDOM % ${#chars[@]}))]}"
        ENV_DOCKER_REGISTRY="${ENV_DOCKER_REGISTRY}/${chars_rand}"
    fi
    # DOCKER_REGISTRY_BASE="${ENV_DOCKER_REGISTRY%/*}/aa"

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
    -g, --git-clone URL          Clone git repo URL to builds/REPO_NAME.
    -b, --git-branch NAME  Specify git branch (default: main).
    -s, --svn-checkout URL       Checkout SVN repository.

    # Build operations
    -B, --build [push|keep]       Build project (push: push to registry, keep: keep image locally).
    -x, --build-base [args]       Execute function build_base_image with optional arguments.

    # Deployment
    -k, --deploy-k8s             Deploy to Kubernetes.
    -f, --deploy-functions       Deploy to Aliyun Functions.
    -R, --deploy-rsync-ssh       Deploy using rsync over SSH.
    -y, --deploy-rsync           Deploy to rsync server.
    -F, --deploy-ftp             Deploy to FTP server.
    -S, --deploy-sftp            Deploy to SFTP server.

    # Testing and quality
    -u, --test-unit              Run unit tests.
    -t, --test-function          Run functional tests.
    -C, --code-style             Check code style.
    -Q, --code-quality           Check code quality.
    -z, --security-zap           Run ZAP security scan.
    -m, --security-vulmap        Run Vulmap security scan.

    # Kubernetes operations
    -H, --create-helm DIR        Create Helm chart in specified directory.
    -K, --create-k8s             Create K8s cluster with Terraform.
    -P, --kube-pvc NAME             Create PVC with specified name.

    # Miscellaneous
    -D, --disable-inject         Disable file injection.
    -r, --renew-cert            Renew all the certs.
    --clean-tags REPO           Clean old tags from Docker registry.
                               REPO: Repository to clean (e.g., registry.example.com/myapp)
    -c, --copy-image SRC [DEST] [KEEP]  Copy Docker image from source to target registry.
                            SRC: Source image (e.g., nginx:latest)
                            DEST: Target registry (e.g., registry.example.com/ns)
                            KEEP: Keep original tag format (true/false, default: true)
                            Examples:
                              -c nginx:latest registry.example.com/ns
                              -c nginx:latest registry.example.com/ns false
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
        # Repository operations
        -g | --git-clone) arg_git_clone_url="${2:?empty git clone url}" && shift ;;
        -b | --git-branch) arg_git_clone_branch="${2:?empty git clone branch}" && shift ;;
        -s | --svn-checkout) arg_svn_checkout_url="${2:?empty svn url}" && shift ;;
        # Build operations
        -x | --build-base) arg_flags["build_base"]=1 ;;
        -B | --build)
            arg_flags["build_all"]=1
            image_retain="${2:-remove}"
            [[ -z "$2" ]] || shift
            ;;
        # Deployment
        -k | --deploy-k8s) arg_flags["deploy_k8s"]=1 deploy_method=deploy_k8s ;;
        -f | --deploy-functions) arg_flags["deploy_aliyun_func"]=1 deploy_method=deploy_aliyun_func ;;
        -R | --deploy-rsync-ssh) arg_flags["deploy_rsync_ssh"]=1 deploy_method=deploy_rsync_ssh ;;
        -y | --deploy-rsync) arg_flags["deploy_rsync"]=1 deploy_method=deploy_rsync ;;
        -F | --deploy-ftp) arg_flags["deploy_ftp"]=1 deploy_method=deploy_ftp ;;
        -S | --deploy-sftp) arg_flags["deploy_sftp"]=1 deploy_method=deploy_sftp ;;
        -c | --copy-image)
            arg_flags["copy_image"]=1
            arg_src="${2:?ERROR: example: nginx:stable-alpine}"
            arg_target="${3}"
            arg_keep_tag="${4:-true}"
            [ -z "$2" ] || shift
            [ -z "$3" ] || shift
            [ -z "$4" ] || shift
            ;;
        # Testing and quality
        -u | --test-unit) arg_flags["test_unit"]=1 ;;
        -t | --test-function) arg_flags["test_func"]=1 ;;
        -C | --code-style) arg_flags["code_style"]=1 ;;
        -Q | --code-quality) arg_flags["code_quality"]=1 ;;
        -z | --security-zap) arg_flags["security_zap"]=1 ;;
        -m | --security-vulmap) arg_flags["security_vulmap"]=1 ;;
        # Kubernetes operations
        -H | --create-helm) arg_create_helm=true && helm_dir="$2" && shift ;;
        -K | --create-k8s) create_k8s_with_terraform=true ;;
        -P | --kube-pvc) arg_flags["kube_pvc"]=1 sub_path_name="${2:? pvc name required}" namespace="${3:-$G_NAMESPACE}" && shift 2 ;;
        # Miscellaneous
        -D | --disable-inject) arg_disable_inject=true ;;
        -r | --renew-cert) arg_renew_cert=true ;;
        --clean-tags) arg_clean_tags="${2:?ERROR: repository parameter is required}" && shift ;;
        *) _usage && exit 1 ;;
        esac
        shift
    done

    ${DEBUG_ON:-false} || export G_QUIET='--quiet'
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
    local lang="$1"

    # 选择构建工具（Docker 或 Podman）
    G_DOCK=$(command -v podman || command -v docker || echo docker)

    # 设置基本的 Docker 运行命令
    G_RUN="${G_DOCK} run --interactive --rm"
    # 添加所有 add-host 参数
    for host in "${ENV_ADD_HOST[@]}"; do
        G_RUN+=" --add-host=${host}"
        G_ARGS+=" --add-host=${host}"
    done

    # 构建参数配置
    G_ARGS+=" ${G_QUIET} --build-arg IN_CHINA=${ENV_IN_CHINA:-false}"

    # 调试模式配置
    if ${DEBUG_ON:-false}; then
        G_ARGS+=" --progress plain"
    fi

    if [ -n "${ENV_DOCKER_MIRROR}" ]; then
        G_ARGS+=" --build-arg MIRROR=${ENV_DOCKER_MIRROR}/"
    fi
    # Java 项目特殊配置
    case "${lang}" in
    java:*)
        G_ARGS+=" --build-arg MVN_PROFILE=${G_REPO_BRANCH}"
        if ${DEBUG_ON:-false}; then
            G_ARGS+=" --build-arg MVN_DEBUG=on"
        fi

        # Set Maven and JDK versions based on lang
        case "${lang:-}" in
        java:1.7:* | java:7:*) MVN_VERSION="3.6-jdk-7" && JDK_VERSION="7" ;;
        java:11:*) MVN_VERSION="3.9-amazoncorretto-11" && JDK_VERSION="11-base" ;;
        java:17:*) MVN_VERSION="3.9-amazoncorretto-17" && JDK_VERSION="17-base" ;;
        java:21:*) MVN_VERSION="3.9-amazoncorretto-21" && JDK_VERSION="21-base" ;;
        java:23:*) MVN_VERSION="3.9-amazoncorretto-23" && JDK_VERSION="23-base" ;;
        *) MVN_VERSION="3.8-amazoncorretto-8" && JDK_VERSION="8-base" ;; # Default
        esac

        # Add build arguments
        G_ARGS+=" --build-arg MVN_VERSION=${MVN_VERSION}"
        G_ARGS+=" --build-arg JDK_VERSION=${JDK_VERSION}"
        # Check for additional installations
        for install in FFMPEG FONTS LIBREOFFICE; do
            if grep -qi "INSTALL_${install}=true" "${G_REPO_DIR}"/{README,readme}* 2>/dev/null; then
                G_ARGS+=" --build-arg INSTALL_${install}=true"
            fi
        done
        ;;
    node:*)
        local ver="${lang#*:}"
        ver="${ver%:*}"
        G_ARGS+=" --build-arg NODE_VERSION=${ver:-20}"
        ;;
    esac

    # 导出环境变量
    # echo "$G_DOCK $G_RUN $G_ARGS" && exit
    export G_DOCK G_RUN G_ARGS
}

main() {
    set -Eeo pipefail
    if [[ ${CI_DEBUG_TRACE:-false} == true ]]; then
        set -x
        DEBUG_ON=true
    fi
    SECONDS=0
    ## G_ prefix indicates GLOBAL variables that are used across multiple functions
    G_NAME="$(basename "${BASH_SOURCE[0]}")"
    G_PATH="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    G_LIB="${G_PATH}/lib"
    G_DATA="${G_PATH}/data"
    G_LOG="${G_DATA}/${G_NAME}.log"
    G_CONF="${G_DATA}/deploy.yaml" # 默认使用YAML格式
    G_ENV="${G_DATA}/deploy.env"

    ## 声明关联数组用于跟踪参数使用情况
    declare -A arg_flags=(
        ["build_all"]=0
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
        ["copy_image"]=0
        ["kube_pvc"]=0
    )
    ## 解析和处理命令行参数
    parse_command_args "$@"

    ## 按顺序加载模块
    for module in common config system repo test analysis style build deployment kubernetes notify; do
        if [[ -f "$G_LIB/${module}.sh" ]]; then
            source "$G_LIB/${module}.sh"
        else
            _msg error "Module ${module}.sh not found"
        fi
    done

    _msg time "BEGIN"

    ## 复制示例配置文件（deploy.json、deploy.env）到data目录 添加必要的二进制文件目录到PATH环境变量
    config_deploy_depend file

    # 在完成初始化后再执行 build_base
    if [[ ${arg_flags["build_base"]} -eq 1 ]]; then
        select_image_tags
        return
    fi

    ## 检测操作系统版本、类型，安装必要的命令和软件
    if [[ ${arg_flags["kube_pvc"]} -eq 1 ]]; then
        system_check >/dev/null
    else
        system_check
    fi

    ## 导入所有以ENV_开头的全局变量（位置不要随意变动）
    source "$G_ENV"

    ## Clone Git repository and handle --gitea flag
    ## - In Gitea: Use GITHUB_* variables
    ## - If git-clone-url is provided: Clone from specified URL
    ## - Default branch: main
    if [ -n "${arg_git_clone_url}" ] || ${GITEA_ACTIONS:-false}; then
        setup_git_repo "${GITEA_ACTIONS:-false}" "${arg_git_clone_url:-}" "${arg_git_clone_branch:-main}"
    fi

    ## SVN仓库检出
    if [ -n "${arg_svn_checkout_url:-}" ]; then
        setup_svn_repo
    fi

    ## 设置手动执行deploy.sh时的GitLab默认配置（位置不要随意变动）
    config_deploy_vars

    ## 处理 --in-china 参数
    ${arg_in_china:-false} && sed -i -e '/ENV_IN_CHINA=/s/false/true/' "$G_ENV"
    ## Create Helm chart directory if --create-helm flag is set
    ## This is an independent operation that will exit after completion
    ${arg_create_helm:-false} && create_helm_chart "${helm_dir}" && return

    ## Docker image copy operation
    if [[ ${arg_flags["copy_image"]} -eq 1 && -n "${arg_src}" ]]; then
        [ -z "$arg_target" ] && arg_target="$(awk -F= '/^ENV_DOCKER_MIRROR=/ {print $2}' "${G_ENV}" | tr -d "'")"
        [ -z "$arg_target" ] && return 1
        copy_docker_image "${arg_src}" "${arg_target}" "${arg_keep_tag}"
        return
    fi

    ## 安装所需的系统工具
    system_install_tools "$@"

    ## 系统维护：清理磁盘空间
    system_clean_disk

    ## Kubernetes集群创建
    ${create_k8s_with_terraform:-false} && kube_setup_terraform

    ## 注意：Kubernetes配置初始化，此步骤位置不可调整
    kube_config_init "$G_NAMESPACE"

    if [[ ${arg_flags["kube_pvc"]} -eq 1 && -n "${sub_path_name}" ]]; then
        kube_create_pv_pvc "${sub_path_name}" "${namespace}"
        return
    fi

    ## 设置ssh-config/acme.sh/aws/kube/aliyun/python-gitlab/cloudflare/rsync
    config_deploy_depend env >/dev/null

    ## 使用acme.sh更新SSL证书
    if [[ ${arg_renew_cert:-false} = true ]]; then
        system_cert_renew
        return
    fi

    ## 清理旧的Docker标签
    if [[ -n "${arg_clean_tags:-}" ]]; then
        clean_old_tags "${arg_clean_tags}"
        return
    fi

    ## 探测项目的程序语言
    _msg step "[lang] Probe program language"
    ## get_lang=lang:ver:docker
    get_lang=$(repo_language_detect)
    ## repo_lang=lang
    repo_lang=${get_lang%%:*}
    ## 解析语言类型和 docker 标识
    echo "  ${get_lang}"

    ## 处理构建工具选择
    config_build_env "${get_lang}"
    ## preprocess project config files / 预处理业务项目配置文件，覆盖配置文件等特殊处理
    # arg_disable_inject: 命令参数强制不注入文件
    repo_inject_file "${repo_lang}" "${arg_disable_inject:-false}"
    get_lang=$(repo_language_detect)
    ## 解析 docker 标识
    echo "  ${get_lang}"

    ## Task Execution Phase
    ## Mode:
    ## - Auto: All tasks will be executed if no specific flags are set
    ## - Single: Only specified tasks will be executed based on arg_flags
    ################################################################################
    ## 全自动执行，或根据 arg_flags 执行相应的任务
    if $all_zero; then
        _msg green "[auto mode: all tasks will be executed]"
    else
        _msg green "[single job: only specified tasks will be executed]"
        for key in "${!arg_flags[@]}"; do
            [[ ${arg_flags[$key]} -eq 1 ]] && echo "  ${key}"
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
    if [[ ${arg_flags["build_all"]} -eq 1 ]]; then
        unset EXIT_MAIN
        build_all "$get_lang" "${image_retain}"
        [[ "${EXIT_MAIN:-false}" == "true" ]] && return 0
    fi

    # 发布，最优雅的写法
    deploy_sum=0
    for key in "${!arg_flags[@]}"; do
        if [[ $key == deploy_* ]]; then
            deploy_sum=$((deploy_sum + arg_flags[$key]))
        fi
    done
    if [[ $deploy_sum -gt 0 ]] || $all_zero; then
        handle_deploy "${deploy_method:-}" "$repo_lang" "$G_REPO_GROUP_PATH_SLUG" "$G_CONF" "$G_LOG" "$G_IMAGE_TAG"
    fi

    # 测试和安全扫描
    [[ ${arg_flags["test_func"]} -eq 1 ]] && handle_test func
    [[ ${arg_flags["security_zap"]} -eq 1 ]] && analysis_zap
    [[ ${arg_flags["security_vulmap"]} -eq 1 ]] && analysis_vulmap

    _msg green "tasks execution completed"
    ################################################################################

    ## deploy notify info / 发布通知信息
    handle_notify

    _msg time "END."

    return "${deploy_result:-0}"
}

main "$@"

## Exit codes:
## - 0: Deployment successful
## - 1: Deployment failed

## Configure external service dependencies:
## - Authentication: ssh-config
## - SSL: acme.sh
## - Cloud Providers: aws, aliyun
## - Container Orchestration: kubernetes
## - Version Control: python-gitlab
## - DNS: cloudflare
## - File Transfer: rsync
