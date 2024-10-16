#!/usr/bin/env bash

# 定义日志级别常量
readonly LOG_LEVEL_ERROR=0
readonly LOG_LEVEL_WARNING=1
readonly LOG_LEVEL_INFO=2
readonly LOG_LEVEL_SUCCESS=3
readonly LOG_LEVEL_FILE=4

# 定义颜色代码
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RESET='\033[0m'

_log() {
    local level=$1
    shift
    local message="$*"
    local level_name
    local color

    case $level in
    "$LOG_LEVEL_ERROR")
        level_name="ERROR"
        color="$COLOR_RED"
        ;;
    "$LOG_LEVEL_WARNING")
        level_name="WARNING"
        color="$COLOR_YELLOW"
        ;;
    "$LOG_LEVEL_INFO")
        level_name="INFO"
        color="$COLOR_RESET"
        ;;
    "$LOG_LEVEL_SUCCESS")
        level_name="SUCCESS"
        color="$COLOR_GREEN"
        ;;
    "$LOG_LEVEL_FILE")
        level_name="FILE"
        color="$COLOR_RESET"
        ;;
    *)
        level_name="UNKNOWN"
        color="$COLOR_RESET"
        ;;
    esac

    if [[ $CURRENT_LOG_LEVEL -ge $level ]]; then
        if [[ $level -eq $LOG_LEVEL_FILE ]]; then
            # 输出到日志文件，不使用颜色
            echo "[${level_name}] $(date '+%Y-%m-%d %H:%M:%S') - $message" >>"$LOG_FILE"
        else
            # 输出到终端，使用颜色
            echo -e "${color}[${level_name}] $(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET} - $message" >&2
        fi
    fi
}

_check_commands() {
    # 检查必要的命令是否可用
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            _log $LOG_LEVEL_ERROR "$cmd command not found. Please install $cmd."
            return 1
        fi
    done
}

_check_disk_space() {
    local required_space_gb=$1
    # 检查磁盘空间
    local available_space
    available_space=$(df -k . | awk 'NR==2 {print $4}')
    local required_space=$((required_space_gb * 1024 * 1024)) # 转换为 KB
    if [[ $available_space -lt $required_space ]]; then
        _log $LOG_LEVEL_ERROR "Not enough disk space. Required: ${required_space_gb}GB, Available: $((available_space / 1024 / 1024))GB"
        return 1
    fi
    _log $LOG_LEVEL_INFO "Sufficient disk space available. Required: ${required_space_gb}GB, Available: $((available_space / 1024 / 1024))GB"
}

# ... 可以继续添加其他通用函数 ...
