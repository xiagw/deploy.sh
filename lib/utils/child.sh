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
    local file=$2
    local current_time
    local time_str
    local time_seconds

    if [[ ${type} == "play" ]]; then
        time_str=$(awk -F= '/^play_time=/{print $2}' "${file}")
    else
        time_str=$(awk -F= '/^rest_time=/{print $2}' "${file}")
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
        return 1
    fi

    # 检查工作日17:00后限制
    if ((weekday < 5)) && ((curr_hour >= WORK_HOUR_17)); then
        return 1
    fi

    return 0
}

_remote_trigger() {
    local file=$1
    if curl -fssSL -X POST "${URL_HOST}/trigger" 2>/dev/null | grep -qi "rest"; then
        _do_shutdown "收到远程关机命令"
        return 0
    fi
    return 1
}

_reset() {
    local file=$1
    if [[ -f ${file} ]]; then
        rm -f "${file}" || return 1
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

    # 初始化状态文件
    file_status="${SCRIPT_PATH}/${SCRIPT_NAME}.status"
    if [[ -f ${file_status} ]]; then
        if [[ ${debug_mod:-0} == 1 ]]; then
            _log "DEBUG模式: 显示状态文件内容: $(cat "${file_status}")"
        fi
    else
        {
            echo "play_time=$(date +"%F %T")"
            echo "rest_time=$(date -d "120 minutes ago" +"%F %T")"
        } >"${file_status}"
    fi

    # 命令处理
    case $1 in
    reset | r) _reset "${file_status}" && return ;;
    debug | d) debug_mod=1 ;;
    esac

    # 远程触发检查
    _remote_trigger "${file_status}"

    # 检查时间段限制
    if ! _check_time_limits "${file_status}"; then
        _do_shutdown "现在是禁止时间段21:00-08:00或工作日17:00后"
        return
    fi

    # 检查时间限制
    local rest_elapsed play_elapsed
    rest_elapsed=$(_get_minutes_elapsed "rest" "${file_status}")
    play_elapsed=$(_get_minutes_elapsed "play" "${file_status}")

    # 检查关机条件
    if ((rest_elapsed < REST_MINUTES)); then
        _do_shutdown "距离上次关机未满${REST_MINUTES}分钟"
        return
    fi

    # 检查是否需要更新启动时间，大于等于120分钟则更新状态文件的启动时间
    if ((play_elapsed >= REST_MINUTES)); then
        sed -i "s/^play_time=.*/play_time=$(date +"%F %T")/" "${file_status}"
        return
    fi

    # 检查开机时长，大于等于50分钟则关机
    if ((play_elapsed >= PLAY_MINUTES)); then
        # 关机时更新状态文件的关机时间
        sed -i "s/^rest_time=.*/rest_time=$(date +"%F %T")/" "${file_status}"
        _do_shutdown "开机时间超过${PLAY_MINUTES}分钟"
        return
    fi
}

main "$@"
