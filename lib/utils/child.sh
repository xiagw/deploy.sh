#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 函数定义
_log() {
    local msg
    msg="[$(date +%F_%T)] $*"
    if [[ ${debug_mod:-0} == 1 ]]; then
        echo "${msg}" >&2
    else
        echo "${msg}" >>"${SCRIPT_LOG}"
    fi
}

_validate_time_format() {
    local time_str=$1
    if ! date -d "${time_str}" +%s 2>/dev/null; then
        _log "无效的时间格式: ${time_str}"
        return 1
    fi
}

_get_minutes_elapsed() {
    local type=$1
    local current_time
    local time_str
    local time_seconds

    if [[ ${type} == "play" ]]; then
        time_str=$(awk -F= '/^play_time=/{print $2}' "${file_status}")
    else
        time_str=$(awk -F= '/^rest_time=/{print $2}' "${file_status}")
    fi

    if [[ -z ${time_str} ]] || ! _validate_time_format "${time_str}"; then
        _log "无效的时间格式: ${time_str}"
        return 1
    fi

    current_time=$(date +%s)
    time_seconds=$(date +%s -d "${time_str}")
    echo $(((current_time - time_seconds) / 60))
}

_do_shutdown() {
    local reason=$1
    if [[ ${debug_mod:-0} == 1 ]]; then
        _log "DEBUG模式: 触发关机条件: ${reason}"
        if [[ -f ${file_status} ]]; then
            _log "DEBUG模式: 显示状态文件内容: $(cat "${file_status}")"
        fi
        return 0
    fi

    _log "执行关机: ${reason}"
    sleep "${DELAY_SECONDS}"
    sudo poweroff
}

_check_time_limits() {
    local curr_hour
    local weekday
    curr_hour=$(date +%H)
    weekday=$(date +%u)

    # 检查21:00-08:00时间段
    if ((curr_hour >= WORK_HOUR_21)) || ((curr_hour < WORK_HOUR_8)); then
        _do_shutdown "现在是禁止使用时间段"
        return 1
    fi

    # 检查工作日17:00后限制
    if ((weekday <= 5)) && ((curr_hour >= WORK_HOUR_17)); then
        _do_shutdown "现在是工作日${WORK_HOUR_17}点后"
        return 1
    fi

    return 0
}

_remote_trigger() {
    if curl -fssSL -X POST "${URL_HOST}/trigger" 2>/dev/null | grep -qi "rest"; then
        _do_shutdown "收到远程关机命令"
        return 0
    fi
    return 1
}

_reset() {
    if [[ -f ${file_status} ]]; then
        rm -f "${file_status}" || return 1
    fi
    sudo shutdown -c || true
    return 0
}

main() {
    # 基础变量设置
    SCRIPT_NAME=$(basename "$0")
    SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
    SCRIPT_LOG="${SCRIPT_PATH}/${SCRIPT_NAME}.log"

    # 配置参数
    PLAY_MINUTES=50
    REST_MINUTES=120
    WORK_HOUR_8=8
    WORK_HOUR_17=17
    WORK_HOUR_21=21
    DELAY_SECONDS=60
    URL_HOST="http://192.168.5.1"

    # 文件路径
    file_status="${SCRIPT_PATH}/${SCRIPT_NAME}.status"

    # 命令处理
    case $1 in
    reset | r) _reset && return ;;
    debug | d) debug_mod=1 ;;
    esac

    # 检查时间限制
    _check_time_limits || return

    # 远程触发检查
    _remote_trigger

    # 初始化状态文件
    if [[ ! -f ${file_status} ]]; then
        {
            echo "play_time=$(date +"%F %T")"
            echo "rest_time=$(date -d "120 minutes ago" +"%F %T")"
        } > "${file_status}"
    fi

    # 检查时间限制
    local rest_elapsed play_elapsed
    rest_elapsed=$(_get_minutes_elapsed "rest")
    play_elapsed=$(_get_minutes_elapsed "play")

    # 检查是否需要更新启动时间
    local play_time rest_time
    play_time=$(awk -F= '/^play_time=/{print $2}' "${file_status}")
    rest_time=$(awk -F= '/^rest_time=/{print $2}' "${file_status}")

    if [[ -n ${play_time} && -n ${rest_time} ]]; then
        play_timestamp=$(date +%s -d "${play_time}")
        rest_timestamp=$(date +%s -d "${rest_time}")
        if ((play_timestamp < rest_timestamp)); then
            _log "更新启动时间: $(date +"%F %T") ， before: ${play_time}"
            sed -i "s/^play_time=.*/play_time=$(date +"%F %T")/" "${file_status}"
        fi
    fi

    # 检查关机条件
    if ((rest_elapsed < REST_MINUTES)); then
        _do_shutdown "距离上次关机未满${REST_MINUTES}分钟"
        return
    fi

    # 检查开机时长
    if ((play_elapsed >= PLAY_MINUTES)); then
        sed -i "s/^rest_time=.*/rest_time=$(date +"%F %T")/" "${file_status}"
        _do_shutdown "开机时间超过${PLAY_MINUTES}分钟"
        return
    fi
}

main "$@"
