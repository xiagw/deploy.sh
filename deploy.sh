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

################################################################################
# 函数: config_deploy_vars
# 描述: 配置部署相关的全局变量，包括仓库信息、分支映射、命名空间等
# 参数: 无
# 返回: 无（设置全局变量）
# 全局变量:
#   - G_REPO_DIR: 仓库目录路径
#   - G_REPO_NAME: 仓库名称
#   - G_REPO_NS: 仓库命名空间
#   - G_REPO_GROUP_PATH: 仓库完整路径（命名空间/仓库名）
#   - G_REPO_GROUP_PATH_SLUG: 仓库路径的URL友好格式
#   - G_REPO_BRANCH: 当前Git分支名
#   - G_REPO_SHORT_SHA: Git提交哈希的简短版本
#   - G_NAMESPACE: Kubernetes命名空间（根据分支映射）
#   - G_IMAGE_TAG: Docker镜像标签（时间戳格式）
################################################################################
config_deploy_vars() {
    ## 设置仓库目录路径
    ## 优先级: -w/--workspace (用户指定) > CI_PROJECT_DIR (GitLab CI) > PWD (当前工作目录)
    G_REPO_DIR="${arg_workspace:-${CI_PROJECT_DIR:-$PWD}}"

    ## 切换到仓库目录，确保后续 git 命令在正确目录执行
    [[ -d "$G_REPO_DIR" ]] || {
        _msg error "Workspace directory not found: $G_REPO_DIR"
        return 1
    }
    cd "$G_REPO_DIR" || return 1

    ## 提取仓库名称
    ## 优先级: GITHUB_REPOSITORY (GitHub/Gitea Actions) > CI_PROJECT_NAME (GitLab CI) > 当前目录名
    ## GITHUB_REPOSITORY 格式: owner/repo，取最后一部分作为仓库名
    if [[ -n "${GITHUB_REPOSITORY}" ]]; then
        G_REPO_NAME=${GITHUB_REPOSITORY##*/}
    else
        ## 回退到 GitLab CI 变量或目录名
        G_REPO_NAME=${CI_PROJECT_NAME:-${G_REPO_DIR##*/}}
    fi

    ## 设置仓库命名空间（组织/组名）
    ## 优先级: GITHUB_REPOSITORY_OWNER (GitHub/Gitea) > CI_PROJECT_NAMESPACE (GitLab CI) > 'root'
    if [[ -n "${GITHUB_REPOSITORY_OWNER}" ]]; then
        G_REPO_NS=${GITHUB_REPOSITORY_OWNER}
    else
        ## 回退到 GitLab CI 命名空间或默认值 'root'
        G_REPO_NS=${CI_PROJECT_NAMESPACE:-root}
    fi

    ## 构建仓库完整路径和URL友好格式
    ## G_REPO_GROUP_PATH: 完整路径，格式为 namespace/repo_name
    ## G_REPO_GROUP_PATH_SLUG: 将点号和斜杠替换为横杠，用于URL或文件名
    G_REPO_GROUP_PATH=${CI_PROJECT_PATH:-$G_REPO_NS/$G_REPO_NAME}
    G_REPO_GROUP_PATH_SLUG=${CI_PROJECT_PATH_SLUG:-${G_REPO_GROUP_PATH//[.\/]/-}}

    ## 获取当前Git分支名称
    G_REPO_BRANCH=$(get_git_branch)

    ## 获取Git提交哈希的简短版本（通常7个字符）
    G_REPO_SHORT_SHA=$(get_git_commit_sha)

    ## 根据Git分支映射到Kubernetes命名空间
    ## 分支到命名空间的映射规则:
    ##   dev      -> develop
    ##   test/sit -> testing
    ##   uat      -> release
    ##   prod/master -> main
    ##   其他     -> 使用分支名本身
    case "${G_REPO_BRANCH}" in
    dev) G_NAMESPACE="develop" ;;
    test | sit) G_NAMESPACE="testing" ;;
    uat) G_NAMESPACE="release" ;;
    prod | master) G_NAMESPACE="main" ;;
    *) G_NAMESPACE="${G_REPO_BRANCH}" ;;
    esac

    ## 设置Docker构建的进度显示模式
    ## 构建输出统一写入日志文件，始终使用 --progress=plain 保证日志完整性
    export G_PROGRESS='--progress=plain'

    ## 生成Docker镜像标签
    ## 格式: Unix时间戳（毫秒级）
    ## 注意: 之前支持包含Git提交哈希的格式，现已简化为仅时间戳
    # G_IMAGE_TAG="${G_REPO_SHORT_SHA}-$(date +%s%3N)"  # 旧格式（已注释）
    G_IMAGE_TAG="t$(date +%s%3N)"

    ## Docker镜像仓库路径配置
    ## 如果启用 ENV_DOCKER_IMAGE_RANDOM=true，会在仓库路径中添加随机字符前缀
    ## 格式说明:
    ##   1. ENV_DOCKER_IMAGE_RANDOM=false: $ENV_DOCKER_REGISTRY/$G_REPO_NAME:$G_IMAGE_TAG
    ##   2. ENV_DOCKER_IMAGE_RANDOM=true:  $ENV_DOCKER_REGISTRY/$RANDOM_CHARS:$G_IMAGE_TAG
    [ -z "$ENV_DOCKER_REGISTRY" ] && ENV_DOCKER_REGISTRY="${ENV_DOCKER_REGISTRY:-example.com/myrepo}"
    if [[ "${ENV_DOCKER_IMAGE_RANDOM:-${ENV_DOCKER_RANDOM:-false}}" = true ]]; then
        local chars
        chars=({a..o}) # 字符集: a到o（共15个字符）
        ## 随机选取两个字符组合（可组合总数: 15*15=225个）
        G_IMAGE_NAME="${chars[$((RANDOM % ${#chars[@]}))]}${chars[$((RANDOM % ${#chars[@]}))]}"
    else
        G_IMAGE_NAME="${G_REPO_NAME}"
        G_IMAGE_NAME="${G_REPO_NAME//-/}"
        G_IMAGE_NAME="${G_IMAGE_NAME//_/}"
        G_IMAGE_NAME="${G_IMAGE_NAME:0:10}"
    fi
    ## 处理定时任务执行
    ## 如果通过 crontab 执行，检查是否应该跳过本次执行（避免重复执行）
    if ${arg_cron:-false}; then
        check_crontab_execution "$G_DATA" "$CI_PROJECT_ID" "$G_REPO_SHORT_SHA" || exit 0
    fi
}

################################################################################
# 函数: _usage
# 描述: 显示脚本使用帮助信息
# 参数: 无
# 返回: 无（输出到标准输出）
################################################################################
_usage() {
    cat <<EOF
Usage: $0 [parameters ...]

Parameters:
    -h, --help               Show this help message.
    -v, --version            Show version info.
    -d, --debug              Run in debug mode.
    -l, --loop                 Run as a cron job.
    --dry                      Preview mode: show all commands that would run, execute nothing.

    # Repository operations
    -w, --workspace DIR        Specify workspace directory (default: current directory).
    -g, --git-clone URL        Clone git repo URL to builds/REPO_NAME.
    -b, --git-branch NAME      Specify git branch (default: main).
                               With -g: clone this branch. With -w: switch the
                               workspace to this branch (create from main if missing).
    -s, --svn-checkout URL     Checkout SVN repository.

    # Build operations
    -B, --build [push|keep|remove]  Build project. Default: remove (build local, don't push).
                                push: push to registry afterwards. keep: keep image locally.
                                Override via ENV_IMAGE_RETAIN (push|keep|remove).
    --buildx-mode MODE          Select buildx builder mode: remote|context|kubernetes|auto.
    -x, --build-base            Execute function build_base_image; append --dry for preview mode.
    --gen-dockerfile            Generate Dockerfile.<lang> from detected language.
    --build-buildpacks          Build image with Cloud Native Buildpacks (needs pack CLI).

    # Deployment
    -k, --deploy-k8s             Deploy to Kubernetes.
    -f, --deploy-functions       Deploy to Aliyun Functions.
    -o, --deploy-docker          Deploy with Docker Compose (rsync files + compose up over SSH).
    -O, --deploy-oss             Deploy to Aliyun OSS (source/dest from project config or ENV_OSS_*).
    -R, --deploy-rsync-ssh       Deploy using rsync over SSH.
    -y, --deploy-rsync           Deploy to rsync server (needs ENV_RSYNC_* or rsyncd.conf).
    -F, --deploy-ftp             Deploy to FTP server (needs ENV_FTP_*).
    -S, --deploy-sftp            Deploy to SFTP server (project hosts or ENV_SFTP_*).

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
    -P, --kube-pvc NAME          Create PVC with specified name.
    --create-storage-class       Create CNFS NAS storage class resources (needs ENV_NAS_URL).

    # Miscellaneous
    -D, --disable-inject         Disable file injection.
    -r, --renew-cert            Renew all the certs.
    --clean-tags REPO           Clean old tags from Docker registry.
                               REPO: Repository to clean (e.g., registry.example.com/myapp)
    -c, --copy-image SRC [DEST]     Copy Docker image from source to target registry.
                            SRC: Source image (e.g., nginx:latest)
                            DEST: Target registry (e.g., registry.example.com/ns).
                                 Target must not already exist.
                            Examples:
                              -c nginx:latest registry.example.com/ns

    # Environment configuration
    set KEY=VALUE [KEY2=VALUE2 ...]  Set variable(s) in deploy.env.
                                     Updates existing, uncomments commented, or appends new.
                                     Values with spaces need quotes: set "ENV_FOO='bar baz'"
    get KEY                          Get variable value from deploy.env.
    env                              List all active ENV_ variables in deploy.env.
EOF
}

################################################################################
# 函数: parse_command_args
# 描述: 解析命令行参数并设置相应的标志变量
# 参数: "$@" - 所有命令行参数
# 返回: 无（设置全局变量 arg_flags 和相关变量）
# 全局变量:
#   - arg_flags: 关联数组，存储各个功能的启用标志（0=禁用, 1=启用）
#   - G_DEBUG_ON: 调试模式标志
#   - arg_cron: 定时任务执行标志
#   - arg_*: 各种命令行参数的值
#   - all_zero: 如果所有标志都为0，则设置为true（表示自动模式）
################################################################################
parse_command_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        # Basic options
        -h | --help) _usage && exit 0 ;;
        -v | --version) echo "Version: 5.0.0" && exit 0 ;;
        -d | --debug) G_DEBUG_ON=true && set -x ;;
        -l | --cron | --loop) arg_cron=true ;;
        --dry) export G_DRY_RUN=true ;;
        -L | --lang) export G_MSG_LANG="${2:?usage: zh or en}" && shift ;;
        # Repository operations
        -w | --workspace) arg_workspace="${2:?empty workspace dir}" && shift ;;
        -g | --git-clone) arg_git_clone_url="${2:?empty git clone url}" && shift ;;
        -b | --git-branch) arg_git_clone_branch="${2:?empty git clone branch}" && shift ;;
        -s | --svn-checkout) arg_svn_checkout_url="${2:?empty svn url}" && shift ;;
        # Build operations
        -x | --build-base) arg_flags["build_base"]=1 ;;
        -B | --build)
            arg_flags["build_all"]=1
            arg_image_retain="${2:-remove}"
            [[ -z "$2" ]] || shift
            ;;
        --buildx-mode)
            arg_buildx_mode="${2:?empty buildx mode}"
            shift
            ;;
        --gen-dockerfile) arg_gen_dockerfile=true ;;
        --build-buildpacks) arg_build_buildpacks=true ;;
        # Deployment
        -k | --deploy-k8s) arg_flags["deploy_k8s"]=1 ;;
        -f | --deploy-functions) arg_flags["deploy_aliyun_func"]=1 ;;
        -o | --deploy-docker) arg_flags["deploy_docker"]=1 ;;
        -O | --deploy-oss) arg_flags["deploy_aliyun_oss"]=1 ;;
        -R | --deploy-rsync-ssh) arg_flags["deploy_rsync_ssh"]=1 ;;
        -y | --deploy-rsync) arg_flags["deploy_rsync"]=1 ;;
        -F | --deploy-ftp) arg_flags["deploy_ftp"]=1 ;;
        -S | --deploy-sftp) arg_flags["deploy_sftp"]=1 ;;
        -c | --copy-image)
            arg_flags["copy_image"]=1
            arg_src="${2:?ERROR: example: nginx:stable-alpine}"
            arg_target="${3}"
            [ -z "$arg_src" ] || shift
            [ -z "$arg_target" ] || shift
            ;;
        # Testing and quality
        -u | --test-unit) arg_flags["test_unit"]=1 ;;
        -t | --test-function) arg_flags["test_func"]=1 ;;
        -C | --code-style) arg_flags["code_style"]=1 ;;
        -Q | --code-quality) arg_flags["code_quality"]=1 ;;
        -z | --security-zap) arg_flags["security_zap"]=1 ;;
        -m | --security-vulmap) arg_flags["security_vulmap"]=1 ;;
        # Kubernetes operations
        -H | --create-helm) arg_create_helm=true && arg_helm_dir="$2" && shift ;;
        -K | --create-k8s) create_k8s_with_terraform=true ;;
        -P | --kube-pvc)
            arg_flags["kube_pvc"]=1
            arg_sub_path="${2:? pvc name required}"
            if [[ "${3:-}" != -* && -n "${3:-}" ]]; then
                arg_pvc_namespace="$3"
            else
                arg_pvc_namespace=""
            fi
            shift 2
            ;;
        --create-storage-class) arg_create_storage_class=true ;;
        # Miscellaneous
        -D | --disable-inject) arg_disable_inject=true ;;
        -r | --renew-cert) arg_renew_cert=true ;;
        --clean-tags) arg_clean_tags="${2:?ERROR: repository parameter is required}" && shift ;;
        # Environment configuration
        set)
            shift
            arg_env_set=("$@")
            break
            ;;
        get) arg_env_get="${2:?ERROR: key name required}" && shift ;;
        env | list) arg_env_list=true ;;
        *) _usage && exit 1 ;;
        esac
        shift
    done

    ## 检查是否有任何功能标志被启用
    ## 如果所有标志都为0，表示用户没有指定任何参数，将启用自动模式（所有任务）
    all_zero=true
    for key in "${!arg_flags[@]}"; do
        if [[ "${arg_flags[$key]}" -eq 1 ]]; then
            all_zero=false
            break
        fi
    done

    ## 环境变量操作 (set/get/env) 不属于 CI/CD 任务，不触发自动模式
    if [[ ${#arg_env_set[@]} -gt 0 || -n "${arg_env_get:-}" || "${arg_env_list:-false}" == true ]]; then
        all_zero=false
    fi

    ## 自动模式: 如果没有任何参数，则启用所有功能标志
    ## 这样用户可以直接运行 ./deploy.sh 执行完整的CI/CD流程
    if $all_zero; then
        for key in "${!arg_flags[@]}"; do
            arg_flags[$key]=1
        done
    fi
}

################################################################################
# 函数: config_build_env
# 描述: 配置Docker/Podman构建环境
# 参数: 无
# 返回: 无（设置全局变量 G_DOCK, G_RUN）
# 全局变量:
#   - G_DOCK: Docker或Podman命令路径
#   - G_RUN: Docker/Podman运行命令的基础参数
#   - G_PROGRESS: buildx bake --progress 参数（plain/quiet）
#   - ENV_ADD_HOST: 需要添加到容器中的主机映射数组
################################################################################
config_build_env() {
    if ${ENV_IS_CHINA:-false} || ${CHANGE_SOURCE:-false}; then
        export IS_CHINA=true
    else
        export IS_CHINA=false
    fi
    ## 选择容器构建工具
    ## 优先级: Podman > Docker > docker (默认)
    ## 如果系统安装了Podman则优先使用，否则使用Docker
    if command -v podman &>/dev/null; then
        G_DOCK=$(command -v podman)
    else
        _install_docker
        G_DOCK=$(command -v docker || echo docker)
    fi

    ## 设置Docker/Podman运行命令的基础参数
    ## --interactive: 保持标准输入打开
    ## --rm: 容器退出后自动删除
    G_RUN="${G_DOCK} run --interactive --rm"

    ## 添加主机映射参数（用于容器内访问外部服务）
    ## ENV_ADD_HOST 数组中的每个条目都会添加到 G_RUN 中
    if [ -n "${ENV_ADD_HOST[*]:-}" ]; then
        for host in "${ENV_ADD_HOST[@]}"; do
            G_RUN+=" --add-host=${host}"
        done
    fi

    ## 导出构建环境变量供其他函数使用
    export G_DOCK G_RUN
}

################################################################################
# 函数: main
# 描述: 主函数，执行CI/CD流程的完整生命周期
# 参数: "$@" - 所有命令行参数
# 返回: 部署结果状态码（0=成功, 非0=失败）
# 执行流程:
#   1. 初始化环境和变量
#   2. 解析命令行参数
#   3. 加载功能模块
#   4. 配置依赖和系统环境
#   5. 仓库操作（Git/SVN检出）
#   6. 语言探测和构建环境配置
#   7. 执行任务（测试、构建、部署、安全扫描等）
#   8. 发送通知
################################################################################
main() {
    ## 设置错误处理: 遇到错误立即退出，管道中任何命令失败都会导致脚本退出
    set -Eeo pipefail

    ## 记录脚本开始执行的时间（用于计算总执行时间）
    SECONDS=0

    ## 探测当前项目: 白名单（root/pms、root/devops 等 namespace/path）内的仓库直接执行其 ci.sh，跳过部署流程
    local ci_project_path="${CI_PROJECT_PATH:-${GITHUB_REPOSITORY:-${CI_PROJECT_NAMESPACE:-root}/${CI_PROJECT_NAME:-${CI_PROJECT_DIR##*/}}}}"
    case "${ci_project_path}" in
    root/pms | root/devops)
        if [[ -f "${CI_PROJECT_DIR}/ci.sh" ]]; then
            bash "${CI_PROJECT_DIR}/ci.sh"
            return 0
        fi
        ;;
    esac

    unset G_REPO_DIR G_REPO_NAME G_REPO_NS G_REPO_GROUP_PATH G_REPO_GROUP_PATH_SLUG G_REPO_BRANCH
    unset G_REPO_SHORT_SHA G_NAMESPACE G_IMAGE_TAG G_DOCK G_RUN
    unset IS_CHINA G_DEBUG_ON arg_cron arg_image_retain arg_sub_path
    unset G_DRY_RUN G_MSG_LANG G_DEPLOY_RESULT G_TEST_RESULT
    unset STAGE_NUM STAGE_TOTAL STAGE_START_MS

    ## 如果 GitLab CI 环境启用了调试跟踪，则启用详细输出
    if [[ ${CI_DEBUG_TRACE:-false} == true ]]; then
        set -x
        G_DEBUG_ON=true
        echo "Debug mode enabled: CI_DEBUG_TRACE is $G_DEBUG_ON"
    fi

    ## ========================================================================
    ## 全局变量初始化
    ## 变量命名规范:
    ##   G_* : 全局变量，在多个函数间共享使用
    ##   ENV_*: 环境配置变量，从 deploy.env 文件加载
    ##   arg_*: 命令行参数变量
    ##   CI_*: GitLab CI/CD平台提供的环境变量
    ## ========================================================================

    ## 脚本基本信息
    G_NAME="$(basename "${BASH_SOURCE[0]}")"                 # 脚本名称
    G_PATH="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" # 脚本所在目录的绝对路径
    G_LIB="${G_PATH}/lib"                                    # 功能模块库目录
    G_DATA="${G_PATH}/data"                                  # 数据目录（配置文件、日志等）
    ## 配置文件路径（JSON格式，由 find_project_config 函数设置）
    G_CONF="" # 部署配置文件
    ## 日志和配置文件路径
    G_ENV="${G_DATA}/deploy.env"         # 环境变量配置文件
    G_LOG="${G_DATA}/logs/${G_NAME}.log" # 日志文件路径
    mkdir -p "$(dirname "$G_LOG")"

    ## ========================================================================
    ## 功能标志数组初始化
    ## 使用关联数组跟踪各个功能的启用状态（0=禁用, 1=启用）
    ## 如果用户没有指定任何参数，所有标志将被设置为1（自动模式）
    ## ========================================================================
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
        ["test_func"]=0
        ["code_style"]=0
        ["code_quality"]=0
        ["security_zap"]=0
        ["security_vulmap"]=0
        ["copy_image"]=0
        ["kube_pvc"]=0
    )
    ## ========================================================================
    ## 命令行参数解析
    ## ========================================================================
    parse_command_args "$@"

    ## ========================================================================
    ## 加载功能模块
    ## 按顺序加载所有必需的功能模块，每个模块提供特定的功能
    ## 模块列表:
    ##   - common: 通用工具函数（日志、消息输出等）
    ##   - config: 配置管理
    ##   - system: 系统检查和工具安装
    ##   - repo: 仓库操作（Git/SVN）
    ##   - test: 测试相关功能
    ##   - analysis: 代码分析（SonarQube等）
    ##   - style: 代码风格检查
    ##   - build: 构建相关功能
    ##   - deployment: 部署相关功能
    ##   - kubernetes: Kubernetes相关操作
    ##   - notify: 通知功能
    ## ========================================================================
    for module in common config system repo test analysis style build deployment kubernetes notify; do
        if [[ -f "$G_LIB/${module}.sh" ]]; then
            source "$G_LIB/${module}.sh"
        else
            _msg error "Module ${module}.sh not found"
        fi
    done

    ## 记录脚本开始执行
    ## 阶段横幅累计耗时的锚点: 从此刻起算（脚本开始），勿改为阶段差值，见 _msg stage 注释
    STAGE_START_MS=$(_now_ms)
    export STAGE_START_MS
    _msg anchor "$(_t '▸ 开始' '▸ BEGIN') ${G_NAME}"

    ## dry-run 模式提示
    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] ${G_NAME} run in preview mode, nothing will be executed beyond local ${G_DATA} state"
    fi

    ## ========================================================================
    ## 配置文件初始化 + 加载环境变量
    ## 1. 复制示例配置文件到 data 目录（如果不存在）
    ## 2. 添加必要的二进制文件目录到 PATH 环境变量
    ## 3. 从 deploy.env 加载所有 ENV_* 环境变量
    ## ========================================================================
    config_deploy_init

    source "$G_ENV"

    ## 如果命令行指定了 buildx 模式，则覆盖 deploy.env 中的配置
    [[ -n "${arg_buildx_mode:-}" ]] && export ENV_BUILDX_MODE="${arg_buildx_mode}"

    ## ========================================================================
    ## 环境变量配置操作 (set/get/env)
    ## 这些是独立操作，执行完成后直接返回，不继续 CI/CD 流程
    ## ========================================================================
    if [[ ${#arg_env_set[@]} -gt 0 ]]; then
        for kv in "${arg_env_set[@]}"; do
            env_file_set "$kv"
        done
        return 0
    fi
    if [[ -n "${arg_env_get:-}" ]]; then
        env_file_get "${arg_env_get}"
        return $?
    fi
    if [[ "${arg_env_list:-false}" == true ]]; then
        env_file_list
        return 0
    fi

    ## ========================================================================
    ## 独立功能: 构建基础镜像
    ## 这是一个独立功能，执行完成后直接返回，不继续执行后续流程
    ## ========================================================================
    if [[ ${arg_flags["build_base"]} -eq 1 ]]; then
        select_image_tags
        return
    fi

    ## ========================================================================
    ## 系统环境检查
    ## 检测操作系统版本、类型，安装必要的命令和软件
    ## 如果只是创建PVC，则静默执行系统检查
    ## ========================================================================
    if [[ ${arg_flags["kube_pvc"]} -eq 1 ]]; then
        system_check >/dev/null
    else
        system_check
    fi

    ## ========================================================================
    ## 仓库操作: Git仓库克隆
    ## 支持场景:
    ##   1. Gitea Actions: 使用 GITHUB_* 变量
    ##   2. 手动指定URL: 通过 --git-clone 参数指定
    ##   3. 默认分支: main
    ## ========================================================================
    if [ -n "${arg_git_clone_url}" ] || ${GITEA_ACTIONS:-false}; then
        setup_git_repo "${GITEA_ACTIONS:-false}" "${arg_git_clone_url:-}" "${arg_git_clone_branch:-main}"
    fi

    ## ========================================================================
    ## 仓库操作: SVN仓库检出
    ## 如果通过 --svn-checkout 参数指定了SVN URL，则执行检出操作
    ## ========================================================================
    if [ -n "${arg_svn_checkout_url:-}" ]; then
        setup_svn_repo
    fi

    ## ========================================================================
    ## 仓库操作: 切换已有 workspace 到指定分支
    ## -w workspace + -b branch: 自动 checkout/pull 指定分支
    ## 分支不存在时从默认分支(main)创建；仅用于非克隆场景
    ## (克隆场景的 -b 由 setup_git_repo 处理，Gitea 已按 GITHUB_REF_NAME 检出)
    ## ========================================================================
    if [ -n "${arg_git_clone_branch:-}" ] && [ -z "${arg_git_clone_url:-}" ]; then
        setup_git_branch "${arg_git_clone_branch}" "${arg_workspace:-${CI_PROJECT_DIR:-$PWD}}"
    fi

    ## ========================================================================
    ## 配置部署变量
    ## 设置仓库信息、分支映射、命名空间、镜像标签等全局变量
    ## 注意: 此步骤位置不要随意变动，后续步骤依赖这些变量
    ## ========================================================================
    config_deploy_vars

    ## ========================================================================
    ## 独立功能: 生成语言 Dockerfile
    ## 如果指定了 --gen-dockerfile 参数，按检测到的语言写出 Dockerfile.<lang>
    ## 这是一个独立功能，执行完成后直接返回
    ## ========================================================================
    if [[ ${arg_gen_dockerfile:-false} = true ]]; then
        (cd "$G_REPO_DIR" && generate_lang_dockerfile "$(detect_repo_language | cut -d: -f1)")
        return $?
    fi

    ## ========================================================================
    ## 独立功能: 用 Buildpacks 构建镜像
    ## 如果指定了 --build-buildpacks 参数，用 Cloud Native Buildpacks 打包镜像
    ## 需要 pack CLI；这是一个独立功能，执行完成后直接返回
    ## ========================================================================
    if [[ ${arg_build_buildpacks:-false} = true ]]; then
        detect_repo_language_and_build "$G_REPO_DIR"
        return $?
    fi

    ## ========================================================================
    ## 查找项目专用配置文件
    ## 仅使用项目专用配置，解决大量项目时的性能和维护问题:
    ##   项目专用配置: data/conf/namespace/project-name.json
    ## 优势: 避免单文件过大、减少版本冲突、更好的权限控制
    ## 注意: 如果配置文件不存在，会自动从模板创建，但必须修改后才能继续部署
    ## ========================================================================
    find_project_config "${G_REPO_GROUP_PATH}"

    ## ========================================================================
    ## 中国地区特殊配置
    ## 如果处于中国区环境，启用 deploy.env 中的代理设置
    system_proxy on

    ## ========================================================================
    ## 独立功能: 创建Helm Chart
    ## 如果指定了 --create-helm 参数，创建Helm Chart目录结构
    ## 这是一个独立功能，执行完成后直接返回
    ## ========================================================================
    ${arg_create_helm:-false} && create_helm_chart "${arg_helm_dir}" && return

    ## ========================================================================
    ## 独立功能: 复制Docker镜像
    ## 将Docker镜像从一个registry复制到另一个registry
    ## 如果未指定目标registry，则使用环境配置中的镜像源地址
    ## ========================================================================
    if [[ ${arg_flags["copy_image"]} -eq 1 && -n "${arg_src}" ]]; then
        [ -z "$arg_target" ] && arg_target="${ENV_DOCKER_MIRROR:-}"
        [ -z "$arg_target" ] && return 1
        copy_docker_image "${arg_src}" "${arg_target}"
        return
    fi

    ## ========================================================================
    ## 磁盘空间清理
    ## 如果磁盘空间不足，自动清理临时文件、旧镜像等
    ## ========================================================================
    system_clean_disk

    ## ========================================================================
    ## 系统工具安装
    ## 根据项目需求安装所需的系统工具和依赖
    ## ========================================================================
    system_install_tools "$@"

    ## ========================================================================
    ## 独立功能: 使用Terraform创建Kubernetes集群
    ## 如果指定了 --create-k8s 参数，使用Terraform创建K8s集群
    ## 这是一个独立功能，执行完成后直接返回
    ## ========================================================================
    if ${create_k8s_with_terraform:-false}; then
        kube_setup_terraform
        return $?
    fi

    ## ========================================================================
    ## Kubernetes配置初始化
    ## 初始化Kubernetes连接配置，设置kubectl上下文等
    ## 注意: 此步骤位置不可调整，后续K8s操作依赖此配置
    ## ========================================================================
    kube_config_init "$G_NAMESPACE"

    ## ========================================================================
    ## 独立功能: 创建 CNFS 存储类
    ## 如果指定了 --create-storage-class 参数，创建 CNFS NAS StorageClass 资源
    ## 这是一个独立功能，执行完成后直接返回
    ## ========================================================================
    if [[ ${arg_create_storage_class:-false} = true ]]; then
        kube_create_storage_class
        return $?
    fi

    ## ========================================================================
    ## 独立功能: 创建Kubernetes PVC
    ## 如果指定了 --kube-pvc 参数，创建持久化卷声明
    ## ========================================================================
    if [[ ${arg_flags["kube_pvc"]} -eq 1 && -n "${arg_sub_path}" ]]; then
        kube_create_pv_pvc "${arg_sub_path}" "${arg_pvc_namespace:-${G_NAMESPACE:-default}}"
        return
    fi

    ## ========================================================================
    ## 部署环境配置
    ## 设置SSH配置、acme.sh、AWS、Kubernetes、阿里云、python-gitlab、
    ## Cloudflare、rsync等工具的配置文件
    if ${G_DRY_RUN:-false}; then
        config_deploy_setup >/dev/null 2>&1
        dry_run_note "config_deploy_setup (ssh keys, $HOME symlinks) — skipped in preview"
    else
        config_deploy_setup >/dev/null
    fi

    ## ========================================================================
    ## 独立功能: 更新SSL证书
    ## 如果指定了 --renew-cert 参数，使用acme.sh更新所有SSL证书
    ## ========================================================================
    if [[ ${arg_renew_cert:-false} = true ]]; then
        system_cert_renew
        return
    fi

    ## ========================================================================
    ## 独立功能: 清理旧的Docker标签
    ## 如果指定了 --clean-tags 参数，清理Docker registry中的旧标签
    ## ========================================================================
    if [[ -n "${arg_clean_tags:-}" ]]; then
        clean_old_tags "${arg_clean_tags}"
        return
    fi

    ## ========================================================================
    ## 构建环境配置
    ## 根据项目语言配置Docker/Podman构建参数
    ## ========================================================================
    config_build_env

    ## ========================================================================
    ## 配置文件注入
    ## 预处理项目配置文件，根据环境注入或覆盖配置
    ## 例如: 根据环境替换数据库连接字符串、API端点等
    ## arg_disable_inject: 如果为true，则跳过文件注入
    ## ========================================================================
    repo_inject_file "${arg_disable_inject:-false}"

    ## 重新探测语言（注入文件后可能需要重新检测）
    local detected_lang
    detected_lang=$(detect_repo_language)
    _msg note "detected language: ${detected_lang}"

    ## ========================================================================
    ## 任务执行阶段
    ##
    ## 执行模式说明:
    ##   - Auto (自动模式): 用户没有指定任何参数时，执行所有任务
    ##   - Spec (指定模式): 用户通过参数指定任务时，只执行指定的任务
    ##
    ## 任务执行顺序:
    ##   1. 代码质量检查 (code_quality, code_style)
    ##   2. 单元测试 (test_unit)
    ##   3. 构建 (build_all)
    ##   4. 部署 (deploy_*)
    ##   5. 功能测试 (test_func)
    ##   6. 安全扫描 (security_zap, security_vulmap)
    ## ========================================================================

    ## 部署方法单一来源: 每个 deploy_* 开关在此定义顺序与显示名
    ## 迭代顺序即"多方法时的优先顺序"; 阶段 4 派生 deploy_method 与 spec 任务列表共用
    local -a deploy_display=(
        "deploy_k8s|-k/--deploy-k8s"
        "deploy_rsync_ssh|-R/--deploy-rsync-ssh"
        "deploy_rsync|-y/--deploy-rsync"
        "deploy_ftp|-F/--deploy-ftp"
        "deploy_sftp|-S/--deploy-sftp"
        "deploy_aliyun_func|-f/--deploy-functions"
        "deploy_aliyun_oss|-O/--deploy-oss"
        "deploy_docker|-o/--deploy-docker"
    )
    local -a deploy_order=()
    local deploy_item deploy_key deploy_method="" deploy_sum=0
    for deploy_item in "${deploy_display[@]}"; do
        deploy_order+=("${deploy_item%%|*}")
    done

    ## 检查是否有部署任务需要执行（阶段 4 与阶段计数共用，固定顺序统计）
    for deploy_key in "${deploy_order[@]}"; do
        deploy_sum=$((deploy_sum + arg_flags[$deploy_key]))
    done

    ## deploy_method 从 arg_flags 派生（R-3 单一来源，替代 parse 时双写）
    ## auto 模式保持空 → handle_deploy 走 detect_deployment_method 探测链路
    if ! $all_zero && [[ $deploy_sum -gt 0 ]]; then
        local -a deploy_enabled=()
        for deploy_key in "${deploy_order[@]}"; do
            [[ ${arg_flags[$deploy_key]} -eq 1 ]] && deploy_enabled+=("$deploy_key")
        done
        if ((${#deploy_enabled[@]} > 1)); then
            _msg warn "$(_t '检测到多个部署方式:' 'multiple deploy methods requested:') ${deploy_enabled[*]}"
            _msg warn "$(_t '仅执行首个，多目标部署请走 GitLab 多 job' 'will run the first only; use separate jobs for multi-target deploy.')"
        fi
        deploy_method="${deploy_enabled[0]-}"
    fi

    ## 统计本次启用的阶段总数（stage 横幅序号自动计算）
    export STAGE_NUM=0
    export STAGE_TOTAL=0
    [[ ${arg_flags["code_quality"]} -eq 1 || ${arg_flags["code_style"]} -eq 1 ]] && ((++STAGE_TOTAL))
    [[ ${arg_flags["test_unit"]} -eq 1 ]] && ((++STAGE_TOTAL))
    [[ ${arg_flags["build_all"]} -eq 1 ]] && ((++STAGE_TOTAL))
    [[ $deploy_sum -gt 0 ]] && ((++STAGE_TOTAL))
    [[ ${arg_flags["test_func"]} -eq 1 ]] && ((++STAGE_TOTAL))
    [[ ${arg_flags["security_zap"]} -eq 1 || ${arg_flags["security_vulmap"]} -eq 1 ]] && ((++STAGE_TOTAL))

    ## 显示执行模式信息
    if $all_zero; then
        _msg ok "$(_t '模式: 自动（执行全部任务）' 'mode: auto (all tasks enabled)')"
    else
        _msg warn "$(_t '模式: 指定（仅执行所选任务）' 'mode: spec (only selected tasks)')"
        _msg note "$(_t '已启用任务:' 'Enabled tasks:')"
        ## 固定顺序显示已启用任务（${!arg_flags[@]} 关联数组迭代顺序不稳定）
        ## 格式: 内部key|显示名（CLI参数）
        local -a task_list=(
            "code_quality|-Q/--code-quality"
            "code_style|-C/--code-style"
            "test_unit|-u/--test-unit"
            "build_all|-B/--build"
            "test_func|-t/--test-function"
            "security_zap|-z/--security-zap"
            "security_vulmap|-m/--security-vulmap"
        )
        local item
        for item in "${task_list[@]}"; do
            [[ ${arg_flags[${item%%|*}]} -eq 1 ]] && _msg note "- ${item#*|}"
        done
        for deploy_item in "${deploy_display[@]}"; do
            [[ ${arg_flags[${deploy_item%%|*}]} -eq 1 ]] && _msg note "- ${deploy_item#*|}"
        done
    fi

    ## ========================================================================
    ## 阶段 1: 代码质量检查
    ## ========================================================================
    if [[ ${arg_flags["code_quality"]} -eq 1 || ${arg_flags["code_style"]} -eq 1 ]]; then
        _msg stage "$(_t '代码质量与风格' 'code quality & style')"
    fi
    [[ ${arg_flags["code_quality"]} -eq 1 ]] && analysis_sonarqube
    [[ ${arg_flags["code_style"]} -eq 1 ]] && style_check

    ## ========================================================================
    ## 阶段 2: 单元测试
    ## ========================================================================
    [[ ${arg_flags["test_unit"]} -eq 1 ]] && _msg stage "$(_t '单元测试' 'unit test')" && handle_test unit

    ## ========================================================================
    ## 阶段 3: 构建
    ## ========================================================================
    if [[ ${arg_flags["build_all"]} -eq 1 ]]; then
        _msg stage "$(_t '构建' 'build')"
        ## arg_image_retain: 镜像保留策略（R-2 统一默认 remove）
        ##   - remove: 仅本地构建、不推送，构建结束后删除本地镜像（默认）
        ##   - keep:   仅本地构建，保留本地镜像
        ##   - push:   构建并推送到镜像仓库
        ## ENV_IMAGE_RETAIN 可全局覆盖; auto 模式含部署，默认 push（后续部署需从 registry 拉取）
        local effective_retain="${ENV_IMAGE_RETAIN:-${arg_image_retain:-remove}}"
        if $all_zero && [[ -z "${ENV_IMAGE_RETAIN:-}" ]]; then
            effective_retain=push
        fi
        build_all "$detected_lang" "${effective_retain}"
    fi

    ## ========================================================================
    ## 阶段 4: 部署
    ## 执行条件:
    ##   - 自动模式: 所有 deploy_* 开关置 1（deploy_sum>0），deploy_method 为空 → 探测链路
    ##   - 指定模式: 设置了任何 deploy_* 标志则执行; deploy_method 由 arg_flags 派生（R-3 单一来源）
    ## ========================================================================
    ## 检查是否有部署任务需要执行（deploy_sum 已在模式信息处计算）
    if [[ $deploy_sum -gt 0 ]]; then
        _msg stage "$(_t '部署' 'deployment')"
        handle_deploy "${deploy_method:-}" "${detected_lang%%:*}" "$G_REPO_GROUP_PATH_SLUG" "$G_CONF" "$G_LOG" "$G_IMAGE_TAG"
    fi

    ## ========================================================================
    ## 阶段 5: 功能测试（部署后验证）
    ## ========================================================================
    [[ ${arg_flags["test_func"]} -eq 1 ]] && _msg stage "$(_t '功能测试' 'functional test')" && handle_test func

    ## ========================================================================
    ## 阶段 6: 安全扫描
    ## ========================================================================
    ## OWASP ZAP安全扫描
    if [[ ${arg_flags["security_zap"]} -eq 1 || ${arg_flags["security_vulmap"]} -eq 1 ]]; then
        _msg stage "$(_t '安全扫描' 'security scan')"
    fi
    [[ ${arg_flags["security_zap"]} -eq 1 ]] && analysis_zap
    ## Vulmap安全扫描
    [[ ${arg_flags["security_vulmap"]} -eq 1 ]] && analysis_vulmap

    _msg ok "$(_t '全部任务执行完成' 'tasks execution completed')"
    ## ========================================================================

    ## ========================================================================
    ## 通知阶段
    ## 发送部署结果通知（邮件、钉钉、企业微信、Slack等）
    ## ========================================================================
    handle_notify

    ## 记录脚本执行结束时间
    _msg anchor "$(_t '✓ 完成' '✓ completed') ${G_NAME} · $(_fmt_dur "$SECONDS") · $(_t '全部任务完成' 'all tasks done')"

    ## 返回部署结果状态码
    ## Exit codes:
    ## - 0: Deployment successful
    ## - 1: Deployment failed
    return "${G_DEPLOY_RESULT:-0}"
}

main "$@"

## Configure external service dependencies:
## - Authentication: .ssh/config
## - SSL: acme.sh
## - Cloud Providers: aliyun, huawei, tencent, aws, gcp
## - Container Orchestration: kubernetes
## - Version Control: GitLab, python-gitlab
## - DNS: Aliyun, cloudflare
## - File Transfer: rsync
