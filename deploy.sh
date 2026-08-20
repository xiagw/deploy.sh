#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=1090,1091,2034
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
    ENV_DOCKER_REGISTRY="${ENV_DOCKER_REGISTRY:-example.com/myrepo}"
    if [[ "${ENV_DOCKER_IMAGE_RANDOM:-${ENV_DOCKER_RANDOM:-false}}" = true ]]; then
        local chars
        chars=({a..o}) # 字符集: a到o（共15个字符）
        ## 随机选取两个字符组合（可组合总数: 15*15=225个）
        G_IMAGE_NAME="${chars[$((RANDOM % ${#chars[@]}))]}${chars[$((RANDOM % ${#chars[@]}))]}"
    else
        G_IMAGE_NAME="${G_REPO_NAME//-/}"
        G_IMAGE_NAME="${G_IMAGE_NAME//_/}"
        G_IMAGE_NAME="${G_IMAGE_NAME:0:10}"
    fi
    ## 处理定时任务执行
    ## 如果通过 crontab 执行，检查是否应该跳过本次执行（避免重复执行）
    if ${arg_cron:-false}; then
        check_crontab_execution "$G_DATA" "${CI_PROJECT_ID:-}" "$G_REPO_SHORT_SHA" || exit 0
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
    -l, --cron, --loop       Run as a cron job.
    --dry                    Preview mode: show all commands that would run, execute nothing.
    -L, --lang LANG          Output language: zh (default) or en.

    # Repository operations
    -w, --workspace DIR        Specify workspace directory (default: current directory).
    -g, --git-clone URL        Clone git repo URL to builds/REPO_NAME.
    -b, --git-branch NAME      Specify git branch (default: main).
                               With -g: clone this branch. With -w: switch the
                               workspace to this branch (create from main if missing).
    -s, --svn-checkout URL     Checkout SVN repository.

    # Build operations
    -B, --build                   Build project (build and push to registry).
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
    -K, --create-k8s             Create K8s cluster with Terraform.
    -P, --kube-pvc NAME          Create PVC with specified name.
    --create-storage-class       Create CNFS NAS storage class resources (needs ENV_NAS_URL).

    # Miscellaneous
    -D, --disable-inject         Disable file injection.
    -r, --renew-cert             Renew all the certs.
    --clean-tags REPO            Clean old tags from Docker registry.
                               REPO: Repository to clean (e.g., registry.example.com/myapp)
    -c, --copy-image SRC [DEST]     Copy Docker image from source to target registry.
                            SRC: Source image (e.g., nginx:latest)
                            DEST: Target registry (e.g., registry.example.com/ns).
                                 Target must not already exist.
                            Examples:
                              -c nginx:latest registry.example.com/ns
EOF
}

################################################################################
# 函数: parse_command_args
# 描述: 解析命令行参数，将用户请求的功能以函数名填入三个执行数组
# 参数: "$@" - 所有命令行参数
# 返回: 无（填充 RUN_REPO/RUN_TASKS/RUN_STAGES/RUN_DEPLOY 及相关 arg_* 变量）
# 全局变量:
#   - RUN_REPO:   仓库准备函数名数组（循环点1: 必须在 config_deploy_vars 之前）
#   - RUN_TASKS:  独立功能函数名数组（循环点2: 在 config_build_env 之后统一执行）
#   - RUN_STAGES: 阶段函数名数组（循环点3: 阶段区）
#   - RUN_DEPLOY: 部署方式 key 数组，供 stage_deploy 按优先级选型（非循环）
#   - G_DEBUG_ON: 调试模式标志
#   - arg_cron: 定时任务执行标志
#   - arg_*: 各种命令行参数的值
################################################################################
parse_command_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        # Basic options
        -h | --help) _usage && exit 0 ;;
        -v | --version) echo "Version: 5.0.0" && exit 0 ;;
        -d | --debug) G_DEBUG_ON=true && set -x && echo "Debug mode enabled" ;;
        -l | --cron | --loop) arg_cron=true ;;
        --dry) export G_DRY_RUN=true ;;
        -L | --lang) _msg_lang_val="${2:?usage: zh or en}" && shift ;;
        # Repository operations
        -w | --workspace) arg_workspace="${2:?empty workspace dir}" && shift ;;
        -g | --git-clone)
            RUN_REPO+=(setup_git_repo)
            arg_git_clone_url="${2:?empty git clone url}"
            shift
            ;;
        -b | --git-branch)
            RUN_REPO+=(setup_git_branch)
            arg_git_clone_branch="${2:?empty git clone branch}"
            shift
            ;;
        -s | --svn-checkout)
            RUN_REPO+=(setup_svn_repo)
            arg_svn_checkout_url="${2:?empty svn url}"
            shift
            ;;
        # Build operations
        -x | --build-base) RUN_TASKS+=(build_base_image_select) ;;
        -B | --build) RUN_STAGES+=(stage_build) ;;
        --buildx-mode)
            arg_buildx_mode="${2:-auto}"
            export ENV_BUILDX_MODE="${arg_buildx_mode}"
            shift
            ;;
        --gen-dockerfile) RUN_TASKS+=(generate_lang_dockerfile) ;;
        --build-buildpacks) RUN_TASKS+=(detect_repo_language_and_build) ;;
        # Deployment
        -k | --deploy-k8s) RUN_DEPLOY+=(deploy_k8s) ;;
        -f | --deploy-functions) RUN_DEPLOY+=(deploy_aliyun_func) ;;
        -o | --deploy-docker) RUN_DEPLOY+=(deploy_docker) ;;
        -O | --deploy-oss) RUN_DEPLOY+=(deploy_aliyun_oss) ;;
        -R | --deploy-rsync-ssh) RUN_DEPLOY+=(deploy_rsync_ssh) ;;
        -y | --deploy-rsync) RUN_DEPLOY+=(deploy_rsync) ;;
        -F | --deploy-ftp) RUN_DEPLOY+=(deploy_ftp) ;;
        -S | --deploy-sftp) RUN_DEPLOY+=(deploy_sftp) ;;
        -c | --copy-image)
            RUN_TASKS+=(copy_docker_image)
            arg_src="${2:?ERROR: example: nginx:stable-alpine}"
            arg_target="${3}"
            [ -z "$arg_src" ] || shift
            [ -z "$arg_target" ] || shift
            ;;
        # Testing and quality
        -u | --test-unit) RUN_STAGES+=(stage_unit_test) ;;
        -t | --test-function) RUN_STAGES+=(stage_functional_test) ;;
        -C | --code-style) RUN_STAGES+=(stage_code_style) ;;
        -Q | --code-quality) RUN_STAGES+=(stage_code_quality) ;;
        -z | --security-zap) RUN_STAGES+=(stage_security_zap) ;;
        -m | --security-vulmap) RUN_STAGES+=(stage_security_vulmap) ;;
        # Kubernetes operations
        -K | --create-k8s) RUN_TASKS+=(kube_setup_terraform) ;;
        -P | --kube-pvc)
            RUN_TASKS+=(kube_create_pv_pvc)
            arg_sub_path="${2:? pvc name required}"
            if [[ "${3:-}" != -* && -n "${3:-}" ]]; then
                arg_pvc_namespace="$3"
            else
                arg_pvc_namespace=""
            fi
            shift 2
            ;;
        --create-storage-class) RUN_TASKS+=(kube_create_storage_class) ;;
        # Miscellaneous
        -D | --disable-inject) arg_disable_inject=true ;;
        -r | --renew-cert) RUN_TASKS+=(system_cert_renew) ;;
        --clean-tags)
            RUN_TASKS+=(clean_old_tags)
            arg_clean_tags="${2:?ERROR: repository parameter is required}"
            shift
            ;;
        *) _usage && exit 1 ;;
        esac
        shift
    done

    ## 任一部署 flag 使 RUN_DEPLOY 非空时，把阶段 stage_deploy 加入 RUN_STAGES（仅一次，
    ## 多个部署方式由 stage_deploy 内部按优先级取一）
    if [[ ${#RUN_DEPLOY[@]} -gt 0 ]]; then
        RUN_STAGES+=(stage_deploy)
    fi

    ## 自动模式: 未请求任何功能时填充全部阶段
    ## 独立功能不进自动模式，避免 -r/-K/--clean-tags 等单独执行时误跑完整流水线
    if [[ ${#RUN_REPO[@]} -eq 0 && ${#RUN_TASKS[@]} -eq 0 && ${#RUN_STAGES[@]} -eq 0 ]]; then
        RUN_STAGES=(stage_code_quality stage_code_style stage_unit_test stage_build stage_deploy stage_functional_test stage_security_zap stage_security_vulmap)
    fi

    ## Gitea Actions: 仓库代码由 runner 注入，无论是否显式传参都要做仓库准备，
    ## 故独立于自动模式之外无条件加入 RUN_REPO
    if [[ "${GITEA_ACTIONS:-false}" == true ]]; then
        RUN_REPO+=(setup_git_repo)
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

## 白名单（root/pms、root/devops 等 namespace/path）内的仓库直接执行其 ci.sh，跳过部署流程
run_project_ci() {
    ## 仅 CI 平台注入的仓库路径参与白名单判断；本地直接运行（无 CI 变量）时跳过
    local ci_project_path="${CI_PROJECT_PATH:-${GITHUB_REPOSITORY:-}}"
    [[ -n "$ci_project_path" ]] || return 0
    case "${ci_project_path}" in
    root/pms | root/devops)
        ## CI_PROJECT_DIR 在非 CI 场景可能为空，避免误检根目录 /ci.sh
        if [[ -n "${CI_PROJECT_DIR:-}" && -f "${CI_PROJECT_DIR}/ci.sh" ]]; then
            bash "${CI_PROJECT_DIR}/ci.sh"
            exit $?
        fi
        ;;
    esac
    return 0
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

    ## 探测当前项目: 白名单内的仓库直接执行其 ci.sh 并退出
    run_project_ci

    ## 清残留: 这些只被 CLI 条件赋值或在退出码/通知中读取，
    ## 父环境残留值会静默改变行为，必须在运行前清空。
    ## IS_CHINA 需保留 unset: system_install_tools（_install_packages->_set_mirror os）
    ## 先于 config_build_env 运行，父环境残留 IS_CHINA 会在 ENV_IS_CHINA=false 时误配中国镜像。
    unset G_DEBUG_ON arg_cron arg_sub_path
    unset IS_CHINA _msg_lang_val G_DRY_RUN G_DEPLOY_RESULT G_TEST_RESULT

    ## 如果 GitLab CI 环境启用了调试跟踪，则启用详细输出
    if [[ ${CI_DEBUG_TRACE:-false} == true ]]; then
        set -x
        G_DEBUG_ON=true
        echo "Debug mode enabled"
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
    ## 执行数组初始化
    ## 由 parse_command_args 按 CLI 请求填充函数名，main 在对应循环点执行数组值:
    ##   RUN_REPO:   仓库准备函数，循环点1（config_deploy_vars 之前，因后者读仓库分支）
    ##   RUN_TASKS:  独立功能函数，循环点2（config_build_env 之后，kube/cert 依赖已就绪）
    ##   RUN_STAGES: 各个阶段函数，循环点3（阶段区）
    ##   RUN_DEPLOY: 部署方式 key，供 stage_deploy 按优先级选型（非循环）
    ## 三个执行数组全空时自动模式填充全部阶段，见 parse_command_args
    ## ========================================================================
    declare -a RUN_REPO=() RUN_TASKS=() RUN_STAGES=() RUN_DEPLOY=()

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
            return 1
        fi
    done

    ## 记录脚本开始执行
    ## 阶段横幅累计耗时的锚点: 从此刻起算（脚本开始），勿改为阶段差值，见 _msg stage 注释
    _stage_start_ms="$(_now_ms)"
    _msg anchor "$(_t '▸ 开始' '▸ BEGIN') ${G_NAME}"

    ## ========================================================================
    ## 配置文件初始化 + 加载环境变量
    ## 复制示例配置文件到 data 目录（如不存在）、添加二进制目录到 PATH、
    ## source deploy.env 加载 ENV_* 变量，均在 config_deploy_init 内完成
    ## ========================================================================
    config_deploy_init

    ## ========================================================================
    ## 系统环境检查
    ## 检测操作系统版本、类型，安装必要的命令和软件
    ## ========================================================================
    system_check

    ## ========================================================================
    ## 独立功能: 仓库准备（RUN_REPO 循环点1）
    ## 位置: 必须在 config_deploy_vars 之前——后者经 get_git_branch 读取仓库分支，
    ##       setup_git_branch 切换的是 G_REPO_DIR（repo.sh:408）内的分支
    ## ========================================================================
    for fn in "${RUN_REPO[@]}"; do "$fn"; done

    ## ========================================================================
    ## 配置部署变量
    ## 设置仓库信息、分支映射、命名空间、镜像标签等全局变量
    ## ========================================================================
    config_deploy_vars

    ## ========================================================================
    ## 查找项目专用配置文件
    ## 仅使用项目专用配置，解决大量项目时的性能和维护问题:
    ##   项目专用配置: data/conf/namespace/project-name.json
    ## 优势: 避免单文件过大、减少版本冲突、更好的权限控制
    ## 注意: 如果配置文件不存在，会自动从模板创建，不修改则执行自动部署，修改后执行定义部署
    ## ========================================================================
    find_project_config

    ## ========================================================================
    ## 中国地区特殊配置
    ## 如果处于中国区环境，启用 deploy.env 中的代理设置
    ## ========================================================================
    system_proxy

    ## ========================================================================
    ## Kubernetes配置初始化
    ## 初始化kubectl连接配置（KUBECTL_OPT/HELM_OPT）
    ## 注意: kube_create_* 独立功能依赖此处设置的 KUBECTL_OPT，位置不可后移
    ## ========================================================================
    kube_config_init

    ## ========================================================================
    ## 磁盘空间清理
    ## 如果磁盘空间不足，自动清理临时文件、旧镜像等
    ## ========================================================================
    system_clean_disk

    ## ========================================================================
    ## 系统工具安装
    ## 根据项目需求安装所需的系统工具和依赖
    ## ========================================================================
    system_install_tools

    ## ========================================================================
    ## 部署环境配置
    ## 设置SSH配置、acme.sh、AWS、Kubernetes、阿里云、python-gitlab、
    ## Cloudflare、rsync等工具的配置文件
    ## dry-run 由 config_deploy_setup 内部短路并提示，这里仅需一次调用
    ## ========================================================================
    config_deploy_setup

    ## ========================================================================
    ## 构建环境配置
    ## 根据项目语言配置Docker/Podman构建参数（G_DOCK/G_RUN）
    ## ========================================================================
    config_build_env

    ## ========================================================================
    ## 独立功能（RUN_TASKS 循环点2）
    ## 位置约束（按函数真实依赖）:
    ##   - kube_create_*:      依赖 kube_config_init 设置的 KUBECTL_OPT
    ##   - system_cert_renew:  依赖 config_deploy_setup 可能创建的 $HOME/.acme.sh 链接
    ##   - build_base_image:   依赖 config_build_env 设置的 G_DOCK
    ##   - 仍在 repo_inject_file 之前，保持 generate_lang_dockerfile / buildpacks 先于配置注入
    ## ========================================================================
    for fn in "${RUN_TASKS[@]}"; do "$fn"; done

    ## ========================================================================
    ## 配置文件注入
    ## 预处理项目配置文件，根据环境注入或覆盖配置
    ## 例如: 根据环境替换数据库连接字符串、API端点等
    ## arg_disable_inject: 如果为true，则跳过文件注入
    ## ========================================================================
    repo_inject_file

    ## ========================================================================
    ## 任务执行阶段（RUN_STAGES 循环点3）
    ##
    ## 每个阶段函数自打印阶段横幅（_msg stage，序号自动递增）。
    ## 执行顺序即 RUN_STAGES 数组顺序:
    ##   1. 代码质量检查 (stage_code_quality, stage_code_style)
    ##   2. 单元测试 (stage_unit_test)
    ##   3. 构建 (stage_build)
    ##   4. 部署 (stage_deploy)
    ##   5. 功能测试 (stage_functional_test)
    ##   6. 安全扫描 (stage_security_zap, stage_security_vulmap)
    ## ========================================================================
    for fn in "${RUN_STAGES[@]}"; do "$fn"; done

    ## ========================================================================
    ## 通知阶段: 发送部署结果通知（邮件、钉钉、企业微信、Slack等）
    ## ========================================================================
    handle_notify

    ## 记录脚本执行结束时间（耗时显示在行尾）
    _msg anchor "$(_t '✓ 完成' '✓ completed') ${G_NAME} · $(_t '全部任务完成' 'all tasks done') · $(_fmt_dur "$SECONDS")"

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
