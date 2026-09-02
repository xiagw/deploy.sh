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
# 函数: config_repo_vars
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
config_repo_vars() {
    ## 仓库目录优先级: -w/--workspace > CI_PROJECT_DIR (GitLab CI) > PWD
    G_REPO_DIR="${arg_workspace:-${CI_PROJECT_DIR:-$PWD}}"
    ## 去掉尾部斜杠，否则 ${G_REPO_DIR##*/} 取到空仓库名
    G_REPO_DIR="${G_REPO_DIR%/}"

    ## 切换到仓库目录，确保后续 git 命令在正确目录执行
    [[ -d "$G_REPO_DIR" ]] || {
        _msg error "Workspace directory not found: $G_REPO_DIR"
        return 1
    }
    cd "$G_REPO_DIR" || return 1

    ## 仓库名优先级: GITHUB_REPOSITORY (GitHub/Gitea) > CI_PROJECT_NAME (GitLab CI) > 当前目录名
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

    ## 获取Git提交哈希的简短版本（8个字符）
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
    _msg note "k8s namespace: ${G_NAMESPACE} (branch: ${G_REPO_BRANCH})"

    ## 构建输出统一写入日志文件，固定 --progress=plain 保证日志完整
    export G_PROGRESS='--progress=plain'

    ## 生成Docker镜像标签（Unix时间戳毫秒级）
    G_IMAGE_TAG="t$(date +%s%3N)"

    ## Docker镜像仓库路径配置
    ## 如果启用 ENV_DOCKER_IMAGE_RANDOM=true，会在仓库路径中添加随机字符前缀
    ## 格式说明:
    ##   1. ENV_DOCKER_IMAGE_RANDOM=false: $ENV_DOCKER_REGISTRY/$G_REPO_NAME:$G_IMAGE_TAG
    ##   2. ENV_DOCKER_IMAGE_RANDOM=true:  $ENV_DOCKER_REGISTRY/$RANDOM_CHARS:$G_IMAGE_TAG
    ENV_DOCKER_REGISTRY="${ENV_DOCKER_REGISTRY:-example.com/myrepo}"
    if [[ "${ENV_DOCKER_IMAGE_RANDOM:-${ENV_DOCKER_RANDOM:-false}}" = true ]]; then
        local chars
        chars=({a..o})  # 字符集 a-o（15个），随机取两字符组合
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
# 函数: usage
# 描述: 显示脚本使用帮助信息
# 参数: 无
# 返回: 无（输出到标准输出）
################################################################################
usage() {
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
    -p, --test-performance       Run performance tests (JMeter *.jmx / k6 scripts).
    -C, --code-style             Check code style.
    -Q, --code-quality           Check code quality.
    -z, --security-zap           Run ZAP security scan.
    -m, --security-vulmap        Run Vulmap security scan.
    --scan-semgrep               Run Semgrep SAST scan.
    --scan-sca                   Run Trivy SCA dependency scan.
    --scan-image                 Run Trivy image scan (after build).
    --scan-gitleaks              Run Gitleaks secret scan.

    # Kubernetes operations
    -K, --create-k8s             Create K8s cluster with Terraform.
    -P, --kube-pvc NAME          Create PVC with specified name.
    --create-storage-class       Create CNFS NAS storage class resources (needs ENV_NAS_URL).

    # Miscellaneous
    -D, --disable-overlay        Disable file overlay.
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
# 函数: parse_args
# 描述: 解析命令行参数并组装执行计划 RUN（位置即依赖顺序）
# 参数: "$@" - 所有命令行参数
# 返回: 无（填充 RUN/RUN_DEPLOY 及相关 arg_* 变量）
# 全局变量:
#   - RUN:       执行计划单数组，位置即依赖顺序（必备步骤 + 条件可选函数 + 阶段 + handle_notify）
#   - RUN_DEPLOY: 部署方式 key 数组，供 stage_deploy 按优先级选型（非循环）
#   - G_DEBUG_ON: 调试模式标志
#   - arg_cron: 定时任务执行标志
#   - arg_*: 各种命令行参数的值（布尔触发或参数）
# 说明: 组装规则与依赖依据见函数尾部注释及 docs/execution-plan.md
################################################################################
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        # Basic options
        -h | --help) usage && exit 0 ;;
        -v | --version) echo "Version: 5.0.0" && exit 0 ;;
        -d | --debug) G_DEBUG_ON=true && set -x && echo "Debug mode enabled" ;;
        -l | --cron | --loop) arg_cron=true ;;
        --dry) export G_DRY_RUN=true ;;
        -L | --lang) _msg_lang_val="${2:?usage: zh or en}" && shift ;;
        # Repository operations
        -w | --workspace) arg_workspace="${2:?empty workspace dir}" && shift ;;
        -g | --git-clone) arg_git_clone_url="${2:?empty git clone url}" && shift ;;
        -b | --git-branch) arg_git_clone_branch="${2:?empty git clone branch}" && shift ;;
        -s | --svn-checkout) arg_svn_checkout_url="${2:?empty svn url}" && shift ;;
        # Build operations
        -x | --build-base) arg_build_base=true ;;
        -B | --build) arg_build=true ;;
        --buildx-mode)
            arg_buildx_mode="${2:-auto}"
            export ENV_BUILDX_MODE="${arg_buildx_mode}"
            shift
            ;;
        --gen-dockerfile) arg_gen_dockerfile=true ;;
        --build-buildpacks) arg_build_buildpacks=true ;;
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
            arg_src="${2:?ERROR: example: nginx:stable-alpine}"
            arg_target="${3}"
            [ -z "$arg_src" ] || shift
            [ -z "$arg_target" ] || shift
            ;;
        # Testing and quality
        -u | --test-unit) arg_test_unit=true ;;
        -t | --test-function) arg_test_func=true ;;
        -p | --test-performance) arg_test_perf=true ;;
        -C | --code-style) arg_code_style=true ;;
        -Q | --code-quality) arg_code_quality=true ;;
        -z | --security-zap) arg_security_zap=true ;;
        -m | --security-vulmap) arg_security_vulmap=true ;;
        --scan-semgrep) arg_security_semgrep=true ;;
        --scan-sca) arg_security_sca=true ;;
        --scan-image) arg_security_image=true ;;
        --scan-gitleaks) arg_security_gitleaks=true ;;
        # Kubernetes operations
        -K | --create-k8s) arg_create_k8s=true ;;
        -P | --kube-pvc)
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
        -D | --disable-overlay) arg_disable_overlay=true ;;
        -r | --renew-cert) arg_renew_cert=true ;;
        --clean-tags) arg_clean_tags="${2:?ERROR: repository parameter is required}" && shift ;;
        *) usage && exit 1 ;;
        esac
        shift
    done

    ## ========================================================================
    ## 组装执行计划: RUN 单数组，位置即依赖顺序（依赖依据见 docs/execution-plan.md）
    ## 必备步骤无条件加入；可选函数按触发条件加入。
    ## auto_mode: 用户未请求任何功能（仅修饰参数如 -w/-d/-L）时为 true，追加全部阶段；
    ##            Gitea 的 setup_git_repo 属环境驱动，不计入用户请求。
    ## ========================================================================
    RUN=()
    local auto_mode=true
    if [[ -n "${arg_git_clone_url:-}" || -n "${arg_svn_checkout_url:-}" || -n "${arg_git_clone_branch:-}" ]] ||
        [[ -n "${arg_clean_tags:-}" || "${arg_create_k8s:-false}" == true ]] ||
        [[ "${arg_gen_dockerfile:-false}" == true || "${arg_build_buildpacks:-false}" == true ]] ||
        [[ -n "${arg_src:-}" ]] ||
        [[ "${arg_create_storage_class:-false}" == true || -n "${arg_sub_path:-}" ]] ||
        [[ "${arg_renew_cert:-false}" == true || "${arg_build_base:-false}" == true ]] ||
        [[ "${arg_build:-false}" == true || "${arg_test_unit:-false}" == true || "${arg_test_func:-false}" == true ]] ||
        [[ "${arg_test_perf:-false}" == true || "${arg_code_style:-false}" == true || "${arg_code_quality:-false}" == true ]] ||
        [[ "${arg_security_zap:-false}" == true || "${arg_security_vulmap:-false}" == true ]] ||
        [[ "${arg_security_semgrep:-false}" == true || "${arg_security_sca:-false}" == true ]] ||
        [[ "${arg_security_image:-false}" == true || "${arg_security_gitleaks:-false}" == true ]] ||
        [[ ${#RUN_DEPLOY[@]} -gt 0 ]]; then
        auto_mode=false
    fi

    ## 必备步骤
    RUN+=(config_deploy_init)
    RUN+=(system_check)

    ## 真独立功能: 仅依赖 ENV_*/G_DATA，最早执行，避免被无关 setup 阻断
    [[ -n "${arg_clean_tags:-}" ]] && RUN+=(clean_old_tags)
    [[ "${arg_create_k8s:-false}" == true ]] && RUN+=(kube_setup_terraform)

    ## 仓库准备: 必须早于 config_repo_vars（后者读仓库分支，见 get_git_branch）
    [[ -n "${arg_git_clone_url:-}" || "${GITEA_ACTIONS:-false}" == true ]] && RUN+=(setup_git_repo)
    [[ -n "${arg_svn_checkout_url:-}" ]] && RUN+=(setup_svn_repo)
    [[ -n "${arg_git_clone_branch:-}" && -z "${arg_git_clone_url:-}" ]] && RUN+=(setup_git_branch)

    RUN+=(config_repo_vars)

    ## 依赖 config_repo_vars 的 G_REPO_* / G_IMAGE_*
    [[ "${arg_gen_dockerfile:-false}" == true ]] && RUN+=(generate_lang_dockerfile)
    ## 须早于 repo_overlay_files，避免覆盖内容被构建进镜像
    [[ "${arg_build_buildpacks:-false}" == true ]] && RUN+=(detect_repo_language_and_build)

    ## 项目专用配置: 仅当计划含 stage_build（读 PROJECT_BUILD_METHOD）或
    ## stage_deploy（读 G_CONF hosts / PROJECT_DEPLOY_METHOD）时加载；
    ## 独立功能（-x/--clean-tags/-r 等）与测试跳过，避免无关配置阻断或产生模板残留告警
    [[ "${arg_build:-false}" == true || ${#RUN_DEPLOY[@]} -gt 0 || "$auto_mode" == true ]] && RUN+=(find_project_config)

    RUN+=(system_proxy)

    ## 中国区 skopeo 拉取需 system_proxy 代理
    [[ -n "${arg_src:-}" ]] && RUN+=(copy_docker_image)

    RUN+=(kube_config_init)

    ## 依赖 kube_config_init 设置的 KUBECTL_OPT
    [[ "${arg_create_storage_class:-false}" == true ]] && RUN+=(kube_create_storage_class)
    [[ -n "${arg_sub_path:-}" ]] && RUN+=(kube_create_pv_pvc)

    RUN+=(system_clean_disk)
    RUN+=(system_install_tools)
    RUN+=(config_deploy_setup)

    ## 依赖 config_deploy_setup 可能创建的 $HOME/.acme.sh 链接
    [[ "${arg_renew_cert:-false}" == true ]] && RUN+=(system_cert_renew)

    RUN+=(config_build_env)

    ## 依赖 config_build_env 设置的 IS_CHINA
    [[ "${arg_build_base:-false}" == true ]] && RUN+=(build_base_image_select)

    RUN+=(repo_overlay_files)

    ## 阶段（顺序即执行顺序）
    [[ "${arg_code_quality:-false}" == true ]] && RUN+=(stage_code_quality)
    [[ "${arg_code_style:-false}" == true ]] && RUN+=(stage_code_style)
    [[ "${arg_test_unit:-false}" == true ]] && RUN+=(stage_unit_test)
    [[ "${arg_build:-false}" == true ]] && RUN+=(stage_build)
    ## 镜像扫描须在 stage_build 之后（扫构建产物镜像）
    [[ "${arg_security_image:-false}" == true ]] && RUN+=(stage_security_image)
    ## 多个部署方式由 stage_deploy 内部按优先级取一
    [[ ${#RUN_DEPLOY[@]} -gt 0 ]] && RUN+=(stage_deploy)
    [[ "${arg_test_func:-false}" == true ]] && RUN+=(stage_functional_test)
    [[ "${arg_test_perf:-false}" == true ]] && RUN+=(stage_performance_test)
    [[ "${arg_security_zap:-false}" == true ]] && RUN+=(stage_security_zap)
    [[ "${arg_security_vulmap:-false}" == true ]] && RUN+=(stage_security_vulmap)
    [[ "${arg_security_semgrep:-false}" == true ]] && RUN+=(stage_security_semgrep)
    [[ "${arg_security_sca:-false}" == true ]] && RUN+=(stage_security_sca)
    [[ "${arg_security_gitleaks:-false}" == true ]] && RUN+=(stage_security_gitleaks)

    ## 自动模式: 未请求任何功能 → 追加全部阶段
    ## 独立功能不进自动模式，避免 -r/-K/--clean-tags 等单独执行时误跑完整流水线
    $auto_mode && RUN+=(
        stage_code_quality stage_code_style stage_unit_test stage_build stage_security_image stage_deploy
        stage_functional_test stage_performance_test stage_security_zap stage_security_vulmap
        stage_security_semgrep stage_security_sca stage_security_gitleaks
    )

    RUN+=(handle_notify)
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

    ## Docker/Podman 通用运行基底: 交互模式 + 容器退出自动清理
    G_RUN="${G_DOCK} run --interactive --rm"

    ## 追加容器内访问外部服务的主机映射 --add-host
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
    unset arg_test_unit arg_test_func arg_test_perf
    unset arg_security_semgrep arg_security_sca arg_security_image arg_security_gitleaks
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
    ## 执行计划初始化
    ## RUN:       由 parse_args 组装，位置即依赖顺序（docs/execution-plan.md）
    ## RUN_DEPLOY: 部署方式 key，供 stage_deploy 按优先级选型（非循环）
    ## ========================================================================
    declare -a RUN=() RUN_DEPLOY=()

    ## ========================================================================
    ## 命令行参数解析
    ## ========================================================================
    parse_args "$@"

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
    ## 执行执行计划: RUN 单数组，位置即依赖顺序
    ## 数组由 parse_args 组装（docs/execution-plan.md），包含必备步骤、
    ## 条件可选函数、阶段与 handle_notify；此处只做顺序执行
    ## ========================================================================
    for fn in "${RUN[@]}"; do "$fn"; done

    ## 记录脚本执行结束时间（耗时显示在行尾）
    _msg anchor "$(_t '✓ 完成' '✓ completed') ${G_NAME} · $(_fmt_dur "$SECONDS")"

    ## 返回部署结果状态码
    ## Exit codes:
    ## - 0: Deployment successful
    ## - 1: Deployment failed
    return "${G_DEPLOY_RESULT:-0}"
}

## 仅当直接执行时运行 main；被 bats/其它脚本 source 时不触发，便于对纯逻辑函数做单元测试
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

## Configure external service dependencies:
## - Authentication: .ssh/config
## - SSL: acme.sh
## - Cloud Providers: aliyun, huawei, tencent, aws, gcp
## - Container Orchestration: kubernetes
## - Version Control: GitLab, glab
## - DNS: Aliyun, cloudflare
## - File Transfer: rsync
