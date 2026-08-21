#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# shell 脚本模板：单入口 + 模块化函数
# 结构：parse / log / help / main，main 尽量简单，只做编排
#
# Usage: ./template.sh [options] [args]

set -Eeuo pipefail

# 全局变量：G_* 跨函数共享，arg_* 命令行参数
G_LOG_FILE="${G_LOG_FILE:-}"
G_LOG_LEVEL=${G_LOG_LEVEL:-2}
G_NO_COLOR="${G_NO_COLOR:-}"
arg_param=''
G_RUN=()
G_POS_ARGS=()

# ---- 日志级别常量（级别越高越详细） ----
LOG_LEVEL_ERROR=0
LOG_LEVEL_WARNING=1
LOG_LEVEL_INFO=2
LOG_LEVEL_DEBUG=3

# ---- 日志：log <级别> <消息...>，级别过滤 + 终端显示 + 文件落盘 ----
log() {
    local level=$1
    shift
    local message="$*"
    local level_name color

    case "$level" in
        "$LOG_LEVEL_ERROR") level_name="ERROR" color='\033[0;31m' ;;
        "$LOG_LEVEL_WARNING") level_name="WARNING" color='\033[0;33m' ;;
        "$LOG_LEVEL_INFO") level_name="INFO" color='\033[0;36m' ;;
        "$LOG_LEVEL_DEBUG") level_name="DEBUG" color='\033[0;34m' ;;
        *) die "Unknown log level: $level" ;;
    esac

    [[ $level -le $G_LOG_LEVEL ]] || return 0

    if [[ -n "$G_LOG_FILE" ]]; then
        printf '[%s] %s - %s\n' "$level_name" "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >>"$G_LOG_FILE"
    fi

    if [[ -t 2 ]] && [[ -z "$G_NO_COLOR" ]]; then
        printf '%b[%s] %s%b\n' "$color" "$level_name" "$message" '\033[0m' >&2
    else
        printf '[%s] %s\n' "$level_name" "$message" >&2
    fi
}

die() {
    log "$LOG_LEVEL_ERROR" "$1"
    exit "${2:-1}"
}

cleanup() {
    trap - ERR EXIT
    log "$LOG_LEVEL_DEBUG" "cleanup"
}

# ---- 参数解析：不同参数向 G_RUN 追加不同业务函数 ----
parse_params() {
    local requested=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help) usage ;;
            -v | --verbose)
                G_LOG_LEVEL=$LOG_LEVEL_DEBUG
                set -x
                ;;
            -q | --quiet) G_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
            -l | --log-level)
                [[ -n "${2-}" ]] || die "Missing value for parameter: $1"
                case "${2,,}" in
                    error) G_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
                    warning | warn) G_LOG_LEVEL=$LOG_LEVEL_WARNING ;;
                    info) G_LOG_LEVEL=$LOG_LEVEL_INFO ;;
                    debug) G_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
                    *) die "Invalid log level: $2" ;;
                esac
                shift
                ;;
            --log-file)
                [[ -n "${2-}" ]] || die "Missing value for parameter: $1"
                G_LOG_FILE=$2
                shift
                ;;
            --no-color) G_NO_COLOR=1 ;;
            -p | --param)
                [[ -n "${2-}" ]] || die "Missing value for parameter: $1"
                arg_param=$2
                shift
                ;;
            -b | --build) requested+=(do_build) ;;
            -t | --test) requested+=(do_test) ;;
            -d | --deploy) requested+=(do_deploy) ;;
            -?*) die "Unknown option: $1" ;;
            *) break ;;
        esac
        shift
    done
    G_POS_ARGS=("$@")

    ## 必备步骤无条件加入（位置在依赖的最前面）；未指定业务参数时追加全部
    G_RUN+=(prepare_workspace)
    if [[ ${#requested[@]} -eq 0 ]]; then
        G_RUN+=(do_build do_test do_deploy)
    else
        G_RUN+=("${requested[@]}")
    fi
    G_RUN+=(report_done)
}

# ---- 帮助 ----
usage() {
    cat <<EOF
Usage: ${0##*/} [options] [args]

脚本描述。

Available options:

    -h, --help      Print this help and exit
    -v, --verbose   Print script debug info
    -q, --quiet     Only print error messages
    -l, --log-level Set log level: error|warning|info|debug
        --log-file  Append log to <FILE>
        --no-color  Disable colored output
    -p, --param     Some param description
    -b, --build     Run build stage
    -t, --test      Run test stage
    -d, --deploy    Run deploy stage

Examples:
    ${0##*/} -b -t -p value arg1
    ${0##*/} -d        # 只执行 deploy 阶段
    ${0##*/}           # 未指定业务参数时执行全部阶段
EOF
    exit 0
}

# ---- 业务逻辑（按需替换） ----
prepare_workspace() {
    log "$LOG_LEVEL_INFO" "prepare workspace"
    log "$LOG_LEVEL_DEBUG" "param=${arg_param} args=${G_POS_ARGS[*]:-}"
}

do_build() {
    log "$LOG_LEVEL_INFO" "build stage"
}

do_test() {
    log "$LOG_LEVEL_INFO" "test stage"
}

do_deploy() {
    log "$LOG_LEVEL_WARNING" "deploy stage"
}

report_done() {
    log "$LOG_LEVEL_INFO" "all stages completed"
}

# ---- 入口：main 只做单循环执行，不感知具体业务 ----
main() {
    trap cleanup ERR EXIT
    parse_params "$@"
    for fn in "${G_RUN[@]}"; do "$fn"; done
}

# 被 source 时不执行 main
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
