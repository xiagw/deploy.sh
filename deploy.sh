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
    ## 优先级: CI_PROJECT_DIR (GitLab CI) > PWD (当前工作目录)
    G_REPO_DIR=${CI_PROJECT_DIR:-$PWD}

    ## 提取仓库名称
    ## 优先级: GITHUB_REPOSITORY (GitHub/Gitea Actions) > CI_PROJECT_NAME (GitLab CI) > 目录名
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

    ## 生成Docker镜像标签
    ## 格式: Unix时间戳（毫秒级）
    ## 注意: 之前支持包含Git提交哈希的格式，现已简化为仅时间戳
    # G_IMAGE_TAG="${G_REPO_SHORT_SHA}-$(date +%s%3N)"  # 旧格式（已注释）
    G_IMAGE_TAG="$(date +%s%3N)"

    ## Docker镜像仓库路径配置
    ## 如果启用 ENV_DOCKER_RANDOM=true，会在仓库路径中添加随机字符前缀
    ## 格式说明:
    ##   1. ENV_DOCKER_RANDOM=false: $ENV_DOCKER_REGISTRY/$G_REPO_NAME:$G_IMAGE_TAG
    ##   2. ENV_DOCKER_RANDOM=true:  $ENV_DOCKER_REGISTRY/$RANDOM_CHARS/$G_REPO_NAME:$G_IMAGE_TAG
    if [[ "${ENV_DOCKER_RANDOM:-false}" = true ]]; then
        local chars chars_rand
        chars=({a..o})  # 字符集: a到o（共15个字符）
        ## 随机选取两个字符组合（可组合总数: 15*15=225个）
        chars_rand="${chars[$((RANDOM % ${#chars[@]}))]}${chars[$((RANDOM % ${#chars[@]}))]}"
        ENV_DOCKER_REGISTRY="${ENV_DOCKER_REGISTRY}/${chars_rand}"
    fi

    ## 处理定时任务执行
    ## 如果通过 crontab 执行，检查是否应该跳过本次执行（避免重复执行）
    if ${run_with_crontab:-false}; then
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

################################################################################
# 函数: parse_command_args
# 描述: 解析命令行参数并设置相应的标志变量
# 参数: "$@" - 所有命令行参数
# 返回: 无（设置全局变量 arg_flags 和相关变量）
# 全局变量:
#   - arg_flags: 关联数组，存储各个功能的启用标志（0=禁用, 1=启用）
#   - DEBUG_ON: 调试模式标志
#   - run_with_crontab: 定时任务执行标志
#   - arg_*: 各种命令行参数的值
#   - all_zero: 如果所有标志都为0，则设置为true（表示自动模式）
################################################################################
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
            arg_keep_tag="${4}"
            [ -z "$arg_src" ] || shift
            [ -z "$arg_target" ] || shift
            [ -z "$arg_keep_tag" ] || shift
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

    ## 设置Docker构建的静默模式（非调试模式下启用）
    ${DEBUG_ON:-false} || export G_QUIET='--quiet'

    ## 检查是否有任何功能标志被启用
    ## 如果所有标志都为0，表示用户没有指定任何参数，将启用自动模式（所有任务）
    all_zero=true
    for key in "${!arg_flags[@]}"; do
        if [[ "${arg_flags[$key]}" -eq 1 ]]; then
            all_zero=false
            break
        fi
    done

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
# 描述: 配置Docker/Podman构建环境，根据项目语言设置相应的构建参数
# 参数:
#   $1 - lang: 项目语言标识，格式为 "lang:version:docker" (例如: "java:17:dockerfile")
# 返回: 无（设置全局变量 G_DOCK, G_RUN, G_ARGS）
# 全局变量:
#   - G_DOCK: Docker或Podman命令路径
#   - G_RUN: Docker/Podman运行命令的基础参数
#   - G_ARGS: Docker/Podman构建参数
#   - ENV_ADD_HOST: 需要添加到容器中的主机映射数组
#   - ENV_IN_CHINA: 是否在中国地区（影响镜像源选择）
#   - ENV_DOCKER_MIRROR: Docker镜像镜像源地址
#   - DEBUG_ON: 调试模式标志
################################################################################
config_build_env() {
    local lang="$1"

    ## 选择容器构建工具
    ## 优先级: Podman > Docker > docker (默认)
    ## 如果系统安装了Podman则优先使用，否则使用Docker
    G_DOCK=$(command -v podman || command -v docker || echo docker)

    ## 设置Docker/Podman运行命令的基础参数
    ## --interactive: 保持标准输入打开
    ## --rm: 容器退出后自动删除
    G_RUN="${G_DOCK} run --interactive --rm"

    ## 添加主机映射参数（用于容器内访问外部服务）
    ## ENV_ADD_HOST 数组中的每个条目都会添加到 --add-host 参数中
    for host in "${ENV_ADD_HOST[@]}"; do
        G_RUN+=" --add-host=${host}"
        G_ARGS+=" --add-host=${host}"
    done

    ## 基础构建参数配置
    ## G_QUIET: 静默模式（非调试模式下启用）
    ## IN_CHINA: 是否在中国地区（影响构建时的镜像源选择）
    G_ARGS+=" ${G_QUIET} --build-arg IN_CHINA=${ENV_IN_CHINA:-false}"

    ## 调试模式配置
    ## 在调试模式下显示详细的构建进度信息
    if ${DEBUG_ON:-false}; then
        G_ARGS+=" --progress plain"
    fi

    ## 配置Docker镜像镜像源（如果指定）
    ## 用于加速镜像拉取（特别是在中国地区）
    if [ -n "${ENV_DOCKER_MIRROR}" ]; then
        G_ARGS+=" --build-arg MIRROR=${ENV_DOCKER_MIRROR}/"
    fi

    ## 根据项目语言类型配置特定的构建参数
    case "${lang}" in
    java:*)
        ## Java项目配置
        ## MVN_PROFILE: Maven构建配置文件，使用当前分支名
        G_ARGS+=" --build-arg MVN_PROFILE=${G_REPO_BRANCH}"

        ## 调试模式下启用Maven调试输出
        if ${DEBUG_ON:-false}; then
            G_ARGS+=" --build-arg MVN_DEBUG=on"
        fi

        ## 根据Java版本设置Maven和JDK版本
        ## 支持的Java版本: 7, 8, 11, 17, 21, 23
        case "${lang:-}" in
        java:1.7:* | java:7:*)
            MVN_VERSION="3.6-jdk-7"
            JDK_VERSION="7"
            ;;
        java:11:*)
            MVN_VERSION="3.9-amazoncorretto-11"
            JDK_VERSION="11-base"
            ;;
        java:17:*)
            MVN_VERSION="3.9-amazoncorretto-17"
            JDK_VERSION="17-base"
            ;;
        java:21:*)
            MVN_VERSION="3.9-amazoncorretto-21"
            JDK_VERSION="21-base"
            ;;
        java:23:*)
            MVN_VERSION="3.9-amazoncorretto-23"
            JDK_VERSION="23-base"
            ;;
        *)
            ## 默认使用Java 8
            MVN_VERSION="3.8-amazoncorretto-8"
            JDK_VERSION="8-base"
            ;;
        esac

        ## 添加Maven和JDK版本构建参数
        G_ARGS+=" --build-arg MVN_VERSION=${MVN_VERSION}"
        G_ARGS+=" --build-arg JDK_VERSION=${JDK_VERSION}"

        ## 检查README文件中是否指定了额外的安装需求
        ## 支持的选项: INSTALL_FFMPEG, INSTALL_FONTS, INSTALL_LIBREOFFICE
        for install in FFMPEG FONTS LIBREOFFICE; do
            if grep -qi "INSTALL_${install}=true" "${G_REPO_DIR}"/{README,readme}* 2>/dev/null; then
                G_ARGS+=" --build-arg INSTALL_${install}=true"
            fi
        done
        ;;
    node:*)
        ## Node.js项目配置
        ## 从语言标识中提取Node版本号（格式: node:20:dockerfile）
        local ver="${lang#*:}"  # 移除 "node:" 前缀
        ver="${ver%:*}"          # 移除 ":dockerfile" 后缀
        ## 默认使用Node 20（如果未指定版本）
        G_ARGS+=" --build-arg NODE_VERSION=${ver:-20}"
        ;;
    esac

    ## 导出构建环境变量供其他函数使用
    export G_DOCK G_RUN G_ARGS
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

    ## 如果CI环境启用了调试跟踪，则启用详细输出
    if [[ ${CI_DEBUG_TRACE:-false} == true ]]; then
        set -x
        DEBUG_ON=true
    fi

    ## 记录脚本开始执行的时间（用于计算总执行时间）
    SECONDS=0

    ## ========================================================================
    ## 全局变量初始化
    ## 变量命名规范:
    ##   G_* : 全局变量，在多个函数间共享使用
    ##   ENV_*: 环境配置变量，从 deploy.env 文件加载
    ##   arg_*: 命令行参数变量
    ##   CI_*: CI/CD平台提供的环境变量
    ## ========================================================================

    ## 脚本基本信息
    G_NAME="$(basename "${BASH_SOURCE[0]}")"              # 脚本名称
    G_PATH="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"  # 脚本所在目录的绝对路径
    G_LIB="${G_PATH}/lib"                                  # 功能模块库目录
    G_DATA="${G_PATH}/data"                                # 数据目录（配置文件、日志等）

    ## 日志和配置文件路径
    G_LOG="${G_DATA}/${G_NAME}.log"                        # 日志文件路径
    ## 配置文件路径（优先使用JSON格式，如果不存在则使用YAML格式）
    G_CONF="${G_DATA}/deploy.json"                         # 部署配置文件（JSON格式，优先）
    G_ENV="${G_DATA}/deploy.env"                           # 环境变量配置文件

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
        ["apidoc"]=0
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
    _msg time "BEGIN"

    ## ========================================================================
    ## 配置文件初始化
    ## 复制示例配置文件到data目录（如果不存在）
    ## 添加必要的二进制文件目录到PATH环境变量
    ## ========================================================================
    config_deploy_depend file

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
    ## 加载环境变量配置
    ## 从 deploy.env 文件加载所有以 ENV_ 开头的环境变量
    ## 注意: 此步骤位置不要随意变动，因为后续步骤依赖这些环境变量
    ## ========================================================================
    source "$G_ENV"

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
    ## 配置部署变量
    ## 设置仓库信息、分支映射、命名空间、镜像标签等全局变量
    ## 注意: 此步骤位置不要随意变动，后续步骤依赖这些变量
    ## ========================================================================
    config_deploy_vars

    ## ========================================================================
    ## 查找项目专用配置文件
    ## 支持多级配置查找策略，解决大量项目时的性能和维护问题:
    ##   1. 项目专用配置: data/projects/namespace/project-name.json
    ##   2. 命名空间配置: data/projects/namespace.json
    ##   3. 全局配置: data/deploy.json (向后兼容)
    ## 优势: 避免单文件过大、减少版本冲突、更好的权限控制
    ## ========================================================================
    find_project_config "${G_REPO_GROUP_PATH}"

    ## ========================================================================
    ## 中国地区特殊配置
    ## 如果指定了 --in-china 参数，更新环境配置文件中的 ENV_IN_CHINA 为 true
    ## 这将影响后续的镜像源选择、代理配置等
    ## ========================================================================
    ${arg_in_china:-false} && sed -i -e '/ENV_IN_CHINA=/s/false/true/' "$G_ENV"

    ## ========================================================================
    ## 独立功能: 创建Helm Chart
    ## 如果指定了 --create-helm 参数，创建Helm Chart目录结构
    ## 这是一个独立功能，执行完成后直接返回
    ## ========================================================================
    ${arg_create_helm:-false} && create_helm_chart "${helm_dir}" && return

    ## ========================================================================
    ## 独立功能: 复制Docker镜像
    ## 将Docker镜像从一个registry复制到另一个registry
    ## 如果未指定目标registry，则使用环境配置中的镜像源地址
    ## ========================================================================
    if [[ ${arg_flags["copy_image"]} -eq 1 && -n "${arg_src}" ]]; then
        [ -z "$arg_target" ] && arg_target="$(awk -F= '/^ENV_DOCKER_MIRROR=/ {print $2}' "${G_ENV}" | tr -d "'")"
        [ -z "$arg_target" ] && return 1
        copy_docker_image "${arg_src}" "${arg_target}" "${arg_keep_tag:-true}"
        return
    fi

    ## ========================================================================
    ## 系统工具安装
    ## 根据项目需求安装所需的系统工具和依赖
    ## ========================================================================
    system_install_tools "$@"

    ## ========================================================================
    ## 磁盘空间清理
    ## 如果磁盘空间不足，自动清理临时文件、旧镜像等
    ## ========================================================================
    system_clean_disk

    ## ========================================================================
    ## 独立功能: 使用Terraform创建Kubernetes集群
    ## 如果指定了 --create-k8s 参数，使用Terraform创建K8s集群
    ## ========================================================================
    ${create_k8s_with_terraform:-false} && kube_setup_terraform

    ## ========================================================================
    ## Kubernetes配置初始化
    ## 初始化Kubernetes连接配置，设置kubectl上下文等
    ## 注意: 此步骤位置不可调整，后续K8s操作依赖此配置
    ## ========================================================================
    kube_config_init "$G_NAMESPACE"

    ## ========================================================================
    ## 独立功能: 创建Kubernetes PVC
    ## 如果指定了 --kube-pvc 参数，创建持久化卷声明
    ## ========================================================================
    if [[ ${arg_flags["kube_pvc"]} -eq 1 && -n "${sub_path_name}" ]]; then
        kube_create_pv_pvc "${sub_path_name}" "${namespace}"
        return
    fi

    ## ========================================================================
    ## 部署环境配置
    ## 设置SSH配置、acme.sh、AWS、Kubernetes、阿里云、python-gitlab、
    ## Cloudflare、rsync等工具的配置文件
    ## ========================================================================
    config_deploy_depend env >/dev/null

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
    ## 项目语言探测
    ## 自动探测项目的编程语言、版本和Dockerfile信息
    ## 返回格式: "lang:version:dockerfile" (例如: "java:17:Dockerfile")
    ## ========================================================================
    _msg step "[lang] Probe program language"
    get_lang=$(repo_language_detect)  # 完整语言标识: lang:ver:docker
    repo_lang=${get_lang%%:*}         # 仅语言类型: lang
    echo "${get_lang}"

    ## ========================================================================
    ## 构建环境配置
    ## 根据项目语言配置Docker/Podman构建参数
    ## ========================================================================
    config_build_env "${get_lang}"

    ## ========================================================================
    ## 配置文件注入
    ## 预处理项目配置文件，根据环境注入或覆盖配置
    ## 例如: 根据环境替换数据库连接字符串、API端点等
    ## arg_disable_inject: 如果为true，则跳过文件注入
    ## ========================================================================
    repo_inject_file "${repo_lang}" "${arg_disable_inject:-false}"

    ## 重新探测语言（注入文件后可能需要重新检测）
    get_lang=$(repo_language_detect)
    echo "${get_lang}"

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
    ##   3. API文档生成 (apidoc)
    ##   4. 构建 (build_all)
    ##   5. 部署 (deploy_*)
    ##   6. 功能测试 (test_func)
    ##   7. 安全扫描 (security_zap, security_vulmap)
    ## ========================================================================

    ## 显示执行模式信息
    if $all_zero; then
        _msg green "mode: auto [all tasks will be executed]"
    else
        _msg yellow "mode: spec [only specified tasks will be executed]"
        _msg info "Enabled tasks:"
        for key in "${!arg_flags[@]}"; do
            [[ ${arg_flags[$key]} -eq 1 ]] && echo "  - ${key}"
        done
    fi

    ## ========================================================================
    ## 阶段 1: 代码质量检查
    ## ========================================================================
    [[ ${arg_flags["code_quality"]} -eq 1 ]] && analysis_sonarqube
    [[ ${arg_flags["code_style"]} -eq 1 ]] && style_check "$repo_lang"

    ## ========================================================================
    ## 阶段 2: 单元测试
    ## ========================================================================
    [[ ${arg_flags["test_unit"]} -eq 1 ]] && handle_test unit

    ## ========================================================================
    ## 阶段 3: API文档生成
    ## ========================================================================
    [[ ${arg_flags["apidoc"]} -eq 1 ]] && generate_apidoc

    ## ========================================================================
    ## 阶段 4: 构建
    ## ========================================================================
    if [[ ${arg_flags["build_all"]} -eq 1 ]]; then
        unset EXIT_MAIN
        ## image_retain: 镜像保留策略
        ##   - push: 推送到镜像仓库
        ##   - keep: 本地保留
        ##   - remove: 构建后删除（默认）
        build_all "$get_lang" "${image_retain}"
        ## 如果构建失败并设置了 EXIT_MAIN=true，则提前退出
        [[ "${EXIT_MAIN:-false}" == "true" ]] && return 0
    fi

    ## ========================================================================
    ## 部署阶段
    ## 执行条件:
    ##   - 自动模式 (all_zero=true): 总是执行部署
    ##   - 指定模式: 如果设置了任何部署相关的标志 (deploy_*)，则执行部署
    ## 注意: deploy_method 变量在参数解析时已设置，表示具体的部署方式
    ## ========================================================================
    ## 检查是否有部署任务需要执行
    ## 方法1: 检查 deploy_method 是否已设置（更直接）
    ## 方法2: 检查是否有任何 deploy_* 标志被启用（更全面）
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

    ## ========================================================================
    ## 阶段 6: 功能测试（部署后验证）
    ## ========================================================================
    [[ ${arg_flags["test_func"]} -eq 1 ]] && handle_test func

    ## ========================================================================
    ## 阶段 7: 安全扫描
    ## ========================================================================
    ## OWASP ZAP安全扫描
    [[ ${arg_flags["security_zap"]} -eq 1 ]] && analysis_zap
    ## Vulmap安全扫描
    [[ ${arg_flags["security_vulmap"]} -eq 1 ]] && analysis_vulmap

    _msg green "tasks execution completed"
    ## ========================================================================

    ## ========================================================================
    ## 通知阶段
    ## 发送部署结果通知（邮件、钉钉、企业微信、Slack等）
    ## ========================================================================
    handle_notify

    ## 记录脚本执行结束时间
    _msg time "END."

    ## 返回部署结果状态码
    return "${deploy_result:-0}"
}

main "$@"

## Exit codes:
## - 0: Deployment successful
## - 1: Deployment failed

## Configure external service dependencies:
## - Authentication: .ssh/config
## - SSL: acme.sh
## - Cloud Providers: aws, aliyun
## - Container Orchestration: kubernetes
## - Version Control: GitLab, python-gitlab
## - DNS: Aliyun, cloudflare
## - File Transfer: rsync
