#!/usr/bin/env bash
# shellcheck shell=bash
# bats 测试共享 helper: 只 stub 环境/工具依赖的辅助函数，令 deploy.sh 纯逻辑可离确定测试
# 不 source 任何 lib 模块 —— deploy.sh 的 main() 才做模块加载，此处刻意避开，保证测试幂等。

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

## source deploy.sh 仅注册函数（守卫在 deploy.sh 末尾，直接 source 不会触发 main）
setup_deploy() {
    unset G_DEBUG_ON arg_cron arg_sub_path arg_test_unit arg_test_func arg_test_perf
    unset arg_security_semgrep arg_security_sca arg_security_image arg_security_gitleaks
    unset arg_workspace arg_git_clone_url arg_git_clone_branch arg_svn_checkout_url
    unset arg_build arg_build_base arg_gen_dockerfile arg_build_buildpacks
    unset arg_code_style arg_code_quality arg_security_zap arg_security_vulmap
    unset arg_create_k8s arg_create_storage_class arg_renew_cert arg_clean_tags
    unset arg_src arg_target arg_pvc_namespace arg_disable_inject arg_buildx_mode
    unset GITEA_ACTIONS GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER
    unset CI_PROJECT_PATH CI_PROJECT_PATH_SLUG CI_PROJECT_NAMESPACE CI_PROJECT_NAME
    unset CI_PROJECT_DIR CI_COMMIT_REF_NAME CI_COMMIT_SHORT_SHA GITHUB_REF_NAME GITHUB_SHA
    unset ENV_DOCKER_REGISTRY ENV_DOCKER_IMAGE_RANDOM ENV_DOCKER_RANDOM
    unset ENV_IS_CHINA CHANGE_SOURCE

    source "${REPO_ROOT}/deploy.sh"

    ## 环境/工具 stub —— 测试只关心纯逻辑结果，不触碰真实 git/网络/日志
    _msg() { :; }
    check_crontab_execution() { :; }
    _install_packages() { :; }
    _now_ms() { echo 0; }
    _fmt_dur() { echo "$1"; }
    _t() { echo "${2:-$1}"; }
    _stage_start_ms=0

    declare -g RUN=() RUN_DEPLOY=()
}
