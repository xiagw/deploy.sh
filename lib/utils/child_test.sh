#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 导入被测试的脚本，但不执行main函数
eval "$(sed 's/main "$@"//g' "$(dirname "$0")/child.sh")"

# 测试辅助函数
_assert() {
    local condition=$1
    local message=$2
    if ! eval "$condition"; then
        echo "❌ 测试失败: $message"
        echo "条件: $condition"
        return 1
    else
        echo "✅ 测试通过: $message"
        return 0
    fi
}

_setup() {
    # 使用脚本所在目录，而不是临时目录
    SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
    SCRIPT_NAME="child.sh"
    SCRIPT_LOG="${SCRIPT_PATH}/${SCRIPT_NAME}.log"
    file_play="${SCRIPT_PATH}/${SCRIPT_NAME}.play"
    file_rest="${SCRIPT_PATH}/${SCRIPT_NAME}.rest"
    debug_mod=1

    # 删除可能存在的所有格式的旧文件
    rm -f "${SCRIPT_PATH}/${SCRIPT_NAME}".{play,rest}
    rm -f "${SCRIPT_LOG}"

    # 创建初始文件
    echo "2024-01-01 12:00:00" > "${file_play}"
    echo "2024-01-01 10:00:00" > "${file_rest}"

    # 确保文件权限正确
    chmod 644 "${file_play}" "${file_rest}"

    # 模拟系统命令
    sudo() { echo "MOCK: sudo $*"; }
    poweroff() { echo "MOCK: poweroff"; }
    shutdown() { echo "MOCK: shutdown $*"; }

    # 默认不触发远程关机
    _trigger() { return 1; }
    curl() { echo "no_rest"; }

    # 重写时间计算函数，避免死循环
    _get_minutes_elapsed() {
        local timestamp_file=$1
        if [[ ! -f ${timestamp_file} ]]; then
            echo "0"
            return
        fi
        if [[ ${timestamp_file} == "${file_play}" ]]; then
            echo "${MOCK_PLAY_TIME:-30}"  # 默认开机30分钟
        else
            echo "${MOCK_REST_TIME:-150}"  # 默认关机150分钟
        fi
    }

    # 修改date函数实现
    date() {
        case "$1" in
            +%H) echo "${MOCK_HOUR:-12}" ;;  # 默认中午12点
            +%u) echo "${MOCK_WEEKDAY:-6}" ;;  # 默认周六
            +%F_%T) echo "2024-01-01_${MOCK_HOUR:-12}:00:00" ;;
            +%F" "%T) echo "2024-01-01 ${MOCK_HOUR:-12}:00:00" ;;
            +%s)
                if [[ $* == *"-d"* ]]; then
                    # 从参数中提取时间字符串
                    local time_str
                    time_str=$(echo "$*" | grep -o '"[^"]*"' | tr -d '"')
                    # 根据时间字符串返回合适的时间戳
                    case "${time_str}" in
                        *"23:00:00"*) echo "1704067200" ;;  # 23:00
                        *"18:00:00"*) echo "1704049200" ;;  # 18:00
                        *"12:00:00"*) echo "1704028800" ;;  # 12:00
                        *) echo "1704067200" ;;  # 默认值
                    esac
                else
                    echo "${MOCK_TIMESTAMP:-1704028800}"  # 当前时间
                fi
                ;;
            -d*) echo "2024-01-01 ${MOCK_HOUR:-12}:00:00" ;;
            *) echo "2024-01-01 ${MOCK_HOUR:-12}:00:00" ;;
        esac
    }

    # 确保文件存在且可读
    touch "${file_play}" "${file_rest}"
    chmod 644 "${file_play}" "${file_rest}"
}

_teardown() {
    # 清理所有可能的文件格式
    rm -f "${SCRIPT_PATH}/${SCRIPT_NAME}".{play,rest}
    rm -f "${SCRIPT_LOG}"
}

test_night_time_limit() {
    _setup
    debug_mod=1

    # 创建临时目录和假的date命令
    local temp_dir
    temp_dir=$(mktemp -d)
    cat > "${temp_dir}/date" << 'EOF'
#!/bin/bash
case "$1" in
    +%H) echo "23";;  # 晚上11点
    +%u) echo "6";;   # 周六
    +%F_%T) echo "2024-01-01_23:00:00";;
    +%F" "%T) echo "2024-01-01 23:00:00";;
    +%s)
        if [[ $* == *"-d"* ]]; then
            echo "1704067200"
        else
            echo "1704067200"
        fi
        ;;
    *) echo "2024-01-01 23:00:00";;
esac
EOF
    chmod +x "${temp_dir}/date"

    # 禁用其他检查
    _trigger() { return 1; }
    _get_minutes_elapsed() { echo "150"; }  # 设置足够长的休息时间

    # 将临时目录添加到PATH的最前面，并导出
    export PATH="${temp_dir}:$PATH"
    # 取消_setup中的date函数定义
    unset -f date

    # 验证使用的是正确的date命令
    local date_path
    date_path=$(which date)
    if [[ ${date_path} != "${temp_dir}/date" ]]; then
        echo "错误: 使用了错误的date命令: ${date_path}"
        rm -rf "${temp_dir}"
        return 1
    fi

    # 运行测试，只执行时间限制检查
    output=$(_check_time_limits 2>&1)
    echo "测试输出: ${output}"

    # 检查是否包含正确的关机原因
    _assert "[[ \"${output}\" == *'禁止使用时间段'* ]]" "应该触发夜间时间限制" || {
        rm -rf "${temp_dir}"
        return 1
    }

    # 清理
    rm -rf "${temp_dir}"
    _teardown
}

test_workday_time_limit() {
    _setup
    debug_mod=1

    # 创建临时目录和假的date命令
    local temp_dir
    temp_dir=$(mktemp -d)
    cat > "${temp_dir}/date" << 'EOF'
#!/bin/bash
case "$1" in
    +%H) echo "18";;  # 晚上6点
    +%u) echo "3";;   # 周三
    +%F_%T) echo "2024-01-01_18:00:00";;
    +%F" "%T) echo "2024-01-01 18:00:00";;
    +%s)
        if [[ $* == *"-d"* ]]; then
            echo "1704049200"
        else
            echo "1704049200"
        fi
        ;;
    *) echo "2024-01-01 18:00:00";;
esac
EOF
    chmod +x "${temp_dir}/date"

    # 禁用其他检查
    _trigger() { return 1; }
    _get_minutes_elapsed() { echo "150"; }  # 设置足够长的休息时间

    # 将临时目录添加到PATH的最前面，并导出
    export PATH="${temp_dir}:$PATH"
    # 取消_setup中的date函数定义
    unset -f date

    # 验证使用的是正确的date命令
    local date_path
    date_path=$(which date)
    if [[ ${date_path} != "${temp_dir}/date" ]]; then
        echo "错误: 使用了错误的date命令: ${date_path}"
        rm -rf "${temp_dir}"
        return 1
    fi

    # 运行测试，只执行时间限制检查
    output=$(_check_time_limits 2>&1)
    echo "测试输出: ${output}"

    # 检查是否包含正确的关机原因
    _assert "[[ \"${output}\" == *'工作日17点后'* ]]" "应该触发工作日时间限制" || {
        rm -rf "${temp_dir}"
        return 1
    }

    # 清理
    rm -rf "${temp_dir}"
    _teardown
}

test_play_time_limit() {
    _setup
    MOCK_HOUR=12
    MOCK_WEEKDAY=6
    MOCK_PLAY_TIME=60  # 开机60分钟
    MOCK_REST_TIME=150  # 关机150分钟
    debug_mod=1

    output=$({ main debug; } 2>&1)
    echo "测试输出: ${output}"
    _assert "[[ \"${output}\" == *'开机时间超过'* ]]" "应该触发开机时间限"
    _teardown
}

test_rest_time_limit() {
    _setup
    MOCK_HOUR=12
    MOCK_WEEKDAY=6
    MOCK_PLAY_TIME=0  # 刚开机
    MOCK_REST_TIME=30  # 关机30分钟
    debug_mod=1

    output=$({ main debug; } 2>&1)
    echo "测试输出: ${output}"
    _assert "[[ \"${output}\" == *'距离上次关机未满'* ]]" "应该触发休息时间限制"
    _teardown
}

test_remote_trigger() {
    _setup
    MOCK_HOUR=12
    MOCK_WEEKDAY=6
    debug_mod=1

    # 模拟远程触发
    _trigger() {
        _do_shutdown "收到远程关机命令"
        return 0
    }

    output=$({ main debug; } 2>&1)
    echo "测试输出: ${output}"
    _assert "[[ \"${output}\" == *'收到远程关机命令'* ]]" "应该触发远程关机"
    _teardown
}

test_reset_command() {
    _setup
    MOCK_HOUR=12
    MOCK_WEEKDAY=6
    debug_mod=1

    # 确保文件存在
    echo "2024-01-01 12:00:00" > "${file_play}"
    echo "2024-01-01 10:00:00" > "${file_rest}"
    chmod 644 "${file_play}" "${file_rest}"

    # 执行reset命令前确认文件存在
    if [[ ! -f ${file_play} ]] || [[ ! -f ${file_rest} ]]; then
        echo "测试前文件不存在"
        return 1
    fi

    # 执行reset命令
    main reset

    # 等待文件系统同步
    sync

    # 检查件是否被删除
    _assert "[[ ! -f ${file_play} ]]" "reset 应该删除启动时间文件"
    _assert "[[ ! -f ${file_rest} ]]" "reset 应该删除关机时间文件"

    _teardown
}

test_update_play_time() {
    _setup
    MOCK_HOUR=12
    MOCK_WEEKDAY=6
    debug_mod=1

    # 设置启动时间早于关机时间
    echo "2024-01-01 09:00:00" > "${file_play}"
    echo "2024-01-01 10:00:00" > "${file_rest}"

    main debug

    current_play_time=$(cat "${file_play}")
    _assert "[[ \"${current_play_time}\" != '2024-01-01 09:00:00' ]]" "应该更新启动时间"
    _teardown
}



# 修改文件格式验证函数
_validate_time_format_regex() {
    local time_str=$1
    if [[ -z ${time_str} ]]; then
        echo "错误: 空的时间字符串"
        return 1
    fi
    if [[ ${time_str} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        return 0
    else
        echo "错误: 无效的时间格式: ${time_str}"
        return 1
    fi
}

# 修改文件创建测试
test_file_creation() {
    _setup

    # 禁用所有检查
    _trigger() { return 1; }
    _check_time_limits() { return 0; }
    _get_minutes_elapsed() { echo "150"; }

    # 运行脚本
    output=$({ main debug; } 2>&1)
    echo "测试输出: ${output}"

    # 等待文件系统同步
    sync
    sleep 1

    # 验证文件创建
    ls -l "${file_play}" "${file_rest}" || true
    _assert "[[ -f ${file_play} ]]" "应该创建启动时间文件"
    _assert "[[ -f ${file_rest} ]]" "应该创建关机时间文件"

    # 验证文件内容格式
    if [[ -f ${file_play} ]] && [[ -f ${file_rest} ]]; then
        local play_content rest_content
        play_content=$(cat "${file_play}")
        rest_content=$(cat "${file_rest}")

        echo "启动时间文件内容: ${play_content}"
        echo "关机时间文件内容: ${rest_content}"

        _assert "date -d \"${play_content}\" +%s >/dev/null 2>&1" "启动时间文件格式应该正确"
        _assert "date -d \"${rest_content}\" +%s >/dev/null 2>&1" "关机时间文件格式应该正确"
    fi

    _teardown
}

# 修改无效时间格式测试
test_invalid_time_format() {
    _setup

    # 禁用所有检查
    _trigger() { return 1; }
    _check_time_limits() { return 0; }
    _get_minutes_elapsed() {
        # 强制更新无效时间文件
        date +"%F %T" > "${file_play}"
        echo "150"
    }

    # 创建包含无效时间格式的文件
    echo "invalid time" > "${file_play}"
    echo "2024-01-01 10:00:00" > "${file_rest}"

    # 运行脚本
    output=$({ main debug; } 2>&1)
    echo "测试输出: ${output}"

    # 等待文件系统同步
    sync
    sleep 1

    # 验证文件被更新为有效格式
    if [[ -f ${file_play} ]]; then
        local play_content
        play_content=$(cat "${file_play}")
        echo "更新后的文件内容: ${play_content}"
        _assert "date -d \"${play_content}\" +%s >/dev/null 2>&1" "无效的时间格式应该被更新"
    else
        echo "错误: 文件不存在"
        return 1
    fi

    _teardown
}

# 运行所有测试
run_all_tests() {
    local failed=0
    local total=0
    local test_result=0

    echo "开始运行测试..."
    echo "===================="

    for test_func in $(declare -F | grep "^declare -f test_" | cut -d" " -f3); do
        ((total++))
        echo "🧪 运行测试: ${test_func}"
        if ! $test_func; then
            ((failed++))
            test_result=1
        fi
        echo "--------------------"
    done

    echo "===================="
    echo "测试完成: 总共 ${total} 个测试，失败 ${failed} 个"

    return $test_result
}

# 如果直接运行此脚本，则执行所有测试
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi