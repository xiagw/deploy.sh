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
    return 0
}

_get_minutes_elapsed() {
    local timestamp_file=$1
    local file_time
    local current_time

    if [[ ! -f ${timestamp_file} ]]; then
        _log "文件不存在: ${timestamp_file}"
        return 1
    fi

    if ! _validate_time_format "$(cat "${timestamp_file}")"; then
        _log "更新无效的时间文件: ${timestamp_file}"
        date +"%F %T" > "${timestamp_file}"
    fi

    file_time=$(date +%s -d "$(cat "${timestamp_file}")")
    current_time=$(date +%s)
    echo $(((current_time - file_time) / 60))
}

_ensure_file_permissions() {
    local file=$1
    if [[ -f ${file} ]]; then
        chmod 644 "${file}" || _log "无法设置文件权限: ${file}"
    fi
}

_do_shutdown() {
    local reason=$1
    if [[ ${debug_mod:-0} == 1 ]]; then
        _log "DEBUG模式: 触发关机条件: ${reason}"
        if [[ -f ${file_play} ]]; then
            _log "DEBUG模式: 显示启动时间文件内容: $(cat "${file_play}")"
        fi
        if [[ -f ${file_rest} ]]; then
            _log "DEBUG模式: 显示关机时间文件内容: $(cat "${file_rest}")"
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

_trigger() {
    if curl -fssSL -X POST "${URL_HOST}/trigger" 2>/dev/null | grep -qi "rest"; then
        _do_shutdown "收到远程关机命令"
        return 0
    fi
    return 1
}

_reset() {
    local result=0
    if [[ -f ${file_play} ]]; then
        rm -f "${file_play}" || result=1
    fi
    if [[ -f ${file_rest} ]]; then
        rm -f "${file_rest}" || result=1
    fi
    sudo shutdown -c || true
    return "${result}"
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
    URL_PORT=8899

    # 文件路径
    file_play="${SCRIPT_PATH}/${SCRIPT_NAME}.play"
    file_rest="${SCRIPT_PATH}/${SCRIPT_NAME}.rest"

    # 命令处理
    case $1 in
    reset | r)
        _reset
        return
        ;;
    debug | d)
        debug_mod=1
        ;;
    esac

    # 检查时间限制
    _check_time_limits || return

    # 触发检查
    _trigger

    # 创建启动时间文件
    if [[ ! -f ${file_play} ]]; then
        date +"%F %T" > "${file_play}"
        _ensure_file_permissions "${file_play}"
    fi

    # 创建关机时间文件
    if [[ ! -f ${file_rest} ]]; then
        date -d "120 minutes ago" +"%F %T" > "${file_rest}"
        _ensure_file_permissions "${file_rest}"
    fi

    # 检查时间限制
    local rest_elapsed play_elapsed
    rest_elapsed=$(_get_minutes_elapsed "${file_rest}")
    play_elapsed=$(_get_minutes_elapsed "${file_play}")

    # 检查是否需要更新启动时间
    if [[ -f ${file_rest} ]]; then
        local play_time rest_time
        play_time=$(date +%s -d "$(cat "${file_play}")")
        rest_time=$(date +%s -d "$(cat "${file_rest}")")
        if ((play_time < rest_time)); then
            _log "更新启动时间: $(date +"%F %T") ， before: $(cat "${file_play}")"
            date +"%F %T" > "${file_play}"
            _ensure_file_permissions "${file_play}"
        fi
    fi

    # 检查关机条件
    if ((rest_elapsed < REST_MINUTES)); then
        _do_shutdown "距离上次关机未满${REST_MINUTES}分钟"
        return
    fi

    # 检查开机时长
    if ((play_elapsed >= PLAY_MINUTES)); then
        date +"%F %T" > "${file_rest}"
        _ensure_file_permissions "${file_rest}"
        _do_shutdown "开机时间超过${PLAY_MINUTES}分钟"
        return
    fi
}

main "$@"
