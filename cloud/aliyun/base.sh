#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 基础服务框架 - 提供统一的 API 调用、格式化输出、错误处理等功能

# 统一调用阿里云 CLI/API
# 用法: call_aliyun_api <product/command> [action] [参数...]
# 示例 1 (API): call_aliyun_api ecs describe-instances --biz-region-id cn-hangzhou
# 示例 2 (命令): call_aliyun_api configure list
call_aliyun_api() {
    # 确保至少有一个参数
    [[ $# -lt 1 ]] && {
        echo "Error: Missing arguments."
        return 1
    }

    # 统一地域语义（AUDIT 1.5）：调用方未显式传 --region 时自动补上，保证
    # 全局 -r 对 nas/kvstore/dts 等一切区域服务都生效，不再落回 profile 默认地域。
    # --region 是全局 endpoint 选择参数，对中心化服务（ram/cdn/cas/alidns 等）无副作用。
    local api_args=("$@")
    if [ -n "${region:-}" ]; then
        local has_region=0 arg
        for arg in "$@"; do
            [ "$arg" = "--region" ] && has_region=1 && break
        done
        [ "$has_region" -eq 0 ] && api_args+=("--region" "${region}")
    fi

    aliyun --profile "${profile:-}" --auto-plugin-install true --auto-plugin-install-enable-pre true "${api_args[@]}"
}

# 通用资源 ID 解析器：已提供则直通；否则 列表 API -> jq 提取 "ID (名称)" 行
#   -> 空报错 -> 唯一自动选中 -> fzf 选择
# 用法: id=$(resolve_resource_id <当前值> <提示语> <空列表消息> <jq过滤器> -- <product> <action> [API 参数...]) || return 1
# 注意: 本函数 stdout 会被 $() 捕获，所有提示信息必须写 stderr
resolve_resource_id() {
    local current=$1 prompt=$2 empty_msg=$3 jq_filter=$4
    shift 4
    [ "$1" = "--" ] && shift

    if [ -n "$current" ]; then
        echo "$current"
        return 0
    fi

    local result
    if ! result=$(call_aliyun_api "$@" 2>/dev/null); then
        echo "错误：无法获取资源列表（${prompt}）。请检查您的凭证和权限。" >&2
        return 1
    fi

    resolve_from_candidates "" "$prompt" "$empty_msg" \
        "$(echo "$result" | jq -r "$jq_filter" 2>/dev/null)"
}

# 从预取的候选行解析 ID（首列为 ID）：空报错 -> 唯一自动选中 -> fzf 选择
# 用法: id=$(resolve_from_candidates <当前值> <提示语> <空列表消息> <候选行>) || return 1
# 注意: 本函数 stdout 会被 $() 捕获，所有提示信息必须写 stderr
resolve_from_candidates() {
    local current=$1 prompt=$2 empty_msg=$3 candidates=$4

    if [ -n "$current" ]; then
        echo "$current"
        return 0
    fi

    if [ -z "$candidates" ]; then
        echo "${empty_msg:-错误：没有找到资源。}" >&2
        return 1
    fi

    if [ "$(echo "$candidates" | grep -c '[^[:space:]]')" -eq 1 ]; then
        local only_id
        only_id=$(echo "$candidates" | awk '{print $1}')
        echo "自动选择唯一候选（${prompt}）: $only_id" >&2
        echo "$only_id"
        return 0
    fi

    local selected
    selected=$(select_with_fzf "$prompt" "$candidates" | awk '{print $1}')
    if [ -z "$selected" ]; then
        echo "错误：未选择（${prompt}），操作取消。" >&2
        return 1
    fi
    echo "$selected"
}

# 变更操作统一收尾：调用 API，成功则 jq 美化 + log_result；失败则中文报错 + 原始结果到 stderr + return 1
# 用法: call_api_logged <service_name> <operation> <失败消息> -- <product> <action> [API 参数...]
call_api_logged() {
    local service_name=$1 operation=$2 err_msg=$3
    shift 3
    [ "$1" = "--" ] && shift

    local result
    if result=$(call_aliyun_api "$@" 2>&1); then
        echo "$result" | jq '.' 2>/dev/null || echo "$result"
        log_result "${profile:-}" "${region:-}" "$service_name" "$operation" "$result"
        return 0
    fi
    echo "${err_msg:-错误：${operation} 操作失败。}" >&2
    echo "$result" >&2
    return 1
}

# 删除操作统一收尾：成功/失败均写 log_delete_operation
# 用法: call_api_del_logged <service_name> <resource_id> <resource_name> <失败消息> -- <product> <action> [API 参数...]
call_api_del_logged() {
    local service_name=$1 resource_id=$2 resource_name=$3 err_msg=$4
    shift 4
    [ "$1" = "--" ] && shift

    local result
    if result=$(call_aliyun_api "$@" 2>&1); then
        echo "$result" | jq '.' 2>/dev/null || echo "$result"
        log_delete_operation "${profile:-}" "${region:-}" "$service_name" "$resource_id" "$resource_name" "成功" "$result"
        return 0
    fi
    echo "${err_msg:-错误：删除失败。}" >&2
    echo "$result" >&2
    log_delete_operation "${profile:-}" "${region:-}" "$service_name" "$resource_id" "$resource_name" "失败" "$result"
    return 1
}

is_output_format() {
    case "$1" in
    json | tsv | human) return 0 ;;
    *) return 1 ;;
    esac
}

# 格式化输出结果
# 用法: format_output <result> <format> <service_name> <operation> <table_header> <jq_filter> [status_mapper] [empty_message] [title] [human_header] [count_filter]
# 参数:
#   - result: API 返回的 JSON 结果
#   - format: 输出格式 (json/tsv/human)，json 为原样透传
#   - service_name: 服务名称（用于日志）
#   - operation: 操作名称（用于日志）
#   - table_header: TSV 格式的表头
#   - jq_filter: jq 过滤表达式，用于提取数据
#   - status_mapper: 可选的 awk 脚本，用于状态映射
#   - empty_message: 可选的空结果提示
#   - title: 可选的 human 模式标题
#   - human_header: 可选的 human 模式专用表头（可多行，含分隔线；"-" 表示不打印表头）
#   - count_filter: 可选的 jq 计数表达式，如 '.Items.Backup | length'
format_output() {
    local result=$1
    local format=$2
    local service_name=$3
    local operation=$4
    local table_header=$5
    local jq_filter=$6
    local status_mapper=${7:-""}
    local empty_message=${8:-"没有找到资源。"}
    local title=${9:-"列出资源："}
    local human_header=${10:-""}
    local count_filter=${11:-""}

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        if [ -n "$table_header" ]; then
            echo -e "$table_header"
        fi
        if [ -n "$jq_filter" ]; then
            echo "$result" | jq -r "$jq_filter"
        fi
        ;;
    human | *)
        echo "$title"
        local temp_output
        temp_output=$(echo "$result" | jq -r "$jq_filter" 2>/dev/null)
        local count
        if [ -n "$count_filter" ]; then
            count=$(echo "$result" | jq -r "$count_filter" 2>/dev/null || echo "0")
            [ "$count" = "null" ] || [ -z "$count" ] && count="0"
        elif [ -n "$temp_output" ] && [ "$temp_output" != "null" ]; then
            count=$(echo "$temp_output" | grep -c . || echo "0")
        else
            count="0"
        fi

        if [ "$count" = "0" ]; then
            echo "$empty_message"
        else
            if [ "$human_header" = "-" ]; then
                : # "-" 表示 human 模式不打印表头（句式输出用）
            elif [ -n "$human_header" ]; then
                echo -e "$human_header"
            elif [ -n "$table_header" ]; then
                # 输出表头（TSV 格式的第一行，需要解析 \t）
                echo -e "$table_header" | head -1
            fi
            if [ -n "$temp_output" ] && [ "$temp_output" != "null" ]; then
                if [ -n "$status_mapper" ]; then
                    echo "$temp_output" | awk "$status_mapper"
                else
                    # 默认格式化输出（保持 TSV 格式，但美化显示）
                    echo "$temp_output" | awk 'BEGIN {FS="\t"; OFS="\t"} {
                        for (i=1; i<=NF; i++) {
                            printf "%-18s  ", $i
                        }
                        print ""
                    }'
                fi
            fi
        fi
        ;;
    esac

    log_result "${profile:-}" "${region:-}" "$service_name" "$operation" "$result" "$format"
}

# 通用的列表操作
# 用法: generic_list <service> <api_action> <service_name> <format> <table_header> <jq_filter> [status_mapper]
generic_list() {
    local service=$1
    local api_action=$2
    local service_name=$3
    local format=${4:-human}
    local table_header=$5
    local jq_filter=$6
    local status_mapper=${7:-""}
    local empty_message=${8:-"没有找到资源。"}
    local title=${9:-"列出资源："}

    local result
    local api_args=("--biz-region-id" "${region:-}")

    if ! result=$(call_aliyun_api "$service" "$api_action" "${api_args[@]}"); then
        echo "错误：无法获取资源列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output "$result" "$format" "$service_name" "list" "$table_header" "$jq_filter" "$status_mapper" "$empty_message" "$title"
}

# 通用的创建操作
# 用法: generic_create <service> <api_action> <service_name> <resource_name> [额外参数...]
generic_create() {
    local service=$1
    local api_action=$2
    local service_name=$3
    local resource_name=$4
    shift 4
    local extra_args=("$@")

    echo "创建 $service_name 资源："

    local result
    local api_args=("--biz-region-id" "${region:-}")

    # 添加额外参数
    api_args+=("${extra_args[@]}")

    result=$(call_aliyun_api "$service" "$api_action" "${api_args[@]}")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "$service_name" "create" "$result"
    else
        echo "错误：创建失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 通用的更新操作
# 用法: generic_update <service> <api_action> <service_name> <resource_id> <new_name> [额外参数...]
generic_update() {
    local service=$1
    local api_action=$2
    local service_name=$3
    local resource_id=$4
    local new_name=$5
    shift 5
    local extra_args=("$@")

    echo "更新 $service_name 资源："

    local result
    local api_args=("--biz-region-id" "${region:-}")

    # 添加资源ID和名称参数（根据不同的API调整参数名）
    if [[ "$api_action" == *"Description"* ]]; then
        # 对于 Description 类型的更新
        api_args+=("--${service_name^}Id" "$resource_id")
        api_args+=("--${service_name^}Description" "$new_name")
    else
        # 通用方式
        api_args+=("--${service_name^}Id" "$resource_id")
        api_args+=("--name" "$new_name")
    fi

    # 添加额外参数
    api_args+=("${extra_args[@]}")

    result=$(call_aliyun_api "$service" "$api_action" "${api_args[@]}")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "$service_name" "update" "$result"
    else
        echo "错误：更新失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 通用的删除操作
# 用法: generic_delete <service> <api_action> <service_name> <resource_id> <resource_type> [额外参数...]
generic_delete() {
    local service=$1
    local api_action=$2
    local service_name=$3
    local resource_id=$4
    local resource_type=$5
    shift 5
    local extra_args=("$@")

    confirm_action "您即将删除 $service_name $resource_type：$resource_id" || return 1

    echo "删除 $service_name $resource_type："

    local result
    local api_args=()

    # 根据不同的API调整参数名
    case "$service" in
    rds)
        api_args+=("--db-instance-id" "$resource_id")
        ;;
    polardb)
        api_args+=("--db-cluster-id" "$resource_id")
        ;;
    ecs)
        api_args+=("--instance-id" "$resource_id")
        api_args+=("--biz-force" "true")
        ;;
    *)
        # 通用方式
        api_args+=("--${service_name^}Id" "$resource_id")
        ;;
    esac

    # 添加额外参数
    api_args+=("${extra_args[@]}")

    result=$(call_aliyun_api "$service" "$api_action" "${api_args[@]}" 2>&1)
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_delete_operation "${profile:-}" "$region" "$service_name" "$resource_id" "$resource_type" "成功" "$result"
    else
        echo "错误：删除失败。" >&2
        echo "$result" >&2
        log_delete_operation "${profile:-}" "$region" "$service_name" "$resource_id" "$resource_type" "失败" "$result"
        return 1
    fi
}

# 状态映射辅助函数
# 用法: map_status <status_field_index> <mapping_rules>
# 示例: map_status 3 "Running:运行中,Stopped:已停止"
map_status() {
    local field_index=$1
    shift
    local mapping_rules="$*"

    # 构建 awk 脚本
    local awk_script="BEGIN {FS=\"\\t\"; OFS=\"\\t\"}
    {
        status = \$$field_index;"

    # 解析映射规则
    IFS=',' read -ra RULES <<<"$mapping_rules"
    for rule in "${RULES[@]}"; do
        IFS=':' read -ra PARTS <<<"$rule"
        local from="${PARTS[0]}"
        local to="${PARTS[1]}"
        awk_script+="
        if (status == \"$from\") status = \"$to\";"
    done

    awk_script+="
        print
    }"

    echo "$awk_script"
}

# 验证必需参数
# 用法: validate_required_params <param1> <param2> ... [错误消息]
validate_required_params() {
    local params=("$@")
    local error_msg="${params[-1]}"

    # 如果最后一个参数包含空格，可能是错误消息
    if [[ "$error_msg" == *" "* ]]; then
        unset 'params[-1]'
    else
        error_msg="错误：缺少必需参数。"
    fi

    for param in "${params[@]}"; do
        if [ -z "$param" ]; then
            echo "$error_msg" >&2
            return 1
        fi
    done

    return 0
}

# 确认操作
# 用法: confirm_action <message>
confirm_action() {
    local message=$1
    echo "警告：$message"
    read -r -p "确认操作？[y/N] " confirm

    if [[ ! "$confirm" =~ ^([yY]|[yY][eE][sS])$ ]]; then
        echo "操作已取消。"
        return 1
    fi

    return 0
}
