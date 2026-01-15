#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 基础服务框架 - 提供统一的 API 调用、格式化输出、错误处理等功能

# 调用华为云 API
# 用法: call_huawei_api <service> <action> [参数...]
# 示例: call_huawei_api ecs NovaListServers --region cn-north-1
call_huawei_api() {
    local service=$1
    shift
    local action=$1
    shift
    local args=("$@")
    
    # 构建华为云 CLI 命令
    local huawei_cmd=("huaweicloud" "$service" "$action")
    
    # 添加 profile 参数（如果指定）
    if [ -n "${profile:-}" ] && [ "$profile" != "default" ]; then
        huawei_cmd+=("--profile" "$profile")
    fi
    
    # 添加 region 参数（如果指定）
    if [ -n "${region:-}" ]; then
        huawei_cmd+=("--region" "$region")
    fi
    
    # 添加其他参数
    huawei_cmd+=("${args[@]}")
    
    # 执行命令并输出 JSON
    "${huawei_cmd[@]}" --output json 2>/dev/null || "${huawei_cmd[@]}" --output json
}

# 格式化输出结果
# 用法: format_output <result> <format> <service_name> <operation> <table_header> <jq_filter> [status_mapper]
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
        if [ -n "$temp_output" ] && [ "$temp_output" != "null" ] && [ "$temp_output" != "" ]; then
            count=$(echo "$temp_output" | grep -c . || echo "0")
        else
            count="0"
        fi
        
        if [ "$count" = "0" ] || [ -z "$count" ]; then
            echo "$empty_message"
        else
            if [ -n "$table_header" ]; then
                echo -e "$table_header" | head -1
            fi
            if [ -n "$temp_output" ] && [ "$temp_output" != "null" ] && [ "$temp_output" != "" ]; then
                if [ -n "$status_mapper" ]; then
                    echo "$temp_output" | awk "$status_mapper"
                else
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
    local api_args=()
    
    if [ -n "${region:-}" ]; then
        api_args+=("--region" "$region")
    fi
    
    if ! result=$(call_huawei_api "$service" "$api_action" "${api_args[@]}"); then
        echo "错误：无法获取资源列表。请检查您的凭证和权限。" >&2
        return 1
    fi
    
    format_output "$result" "$format" "$service_name" "list" "$table_header" "$jq_filter" "$status_mapper" "$empty_message" "$title"
}

# 通用的创建操作
generic_create() {
    local service=$1
    local api_action=$2
    local service_name=$3
    local resource_name=$4
    shift 4
    local extra_args=("$@")
    
    echo "创建 $service_name 资源："
    
    local result
    local api_args=()
    
    api_args+=("${extra_args[@]}")
    
    result=$(call_huawei_api "$service" "$api_action" "${api_args[@]}")
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
    local api_args=()
    
    api_args+=("${extra_args[@]}")
    
    result=$(call_huawei_api "$service" "$api_action" "${api_args[@]}")
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
generic_delete() {
    local service=$1
    local api_action=$2
    local service_name=$3
    local resource_id=$4
    local resource_type=$5
    shift 5
    local extra_args=("$@")
    
    echo "警告：您即将删除 $service_name $resource_type：$resource_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm
    
    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi
    
    echo "删除 $service_name $resource_type："
    
    local result
    local api_args=()
    
    api_args+=("${extra_args[@]}")
    
    result=$(call_huawei_api "$service" "$api_action" "${api_args[@]}")
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_delete_operation "${profile:-}" "$region" "$service_name" "$resource_id" "$resource_type" "成功"
        log_result "${profile:-}" "$region" "$service_name" "delete" "$result"
    else
        echo "错误：删除失败。" >&2
        echo "$result" >&2
        log_delete_operation "${profile:-}" "$region" "$service_name" "$resource_id" "$resource_type" "失败"
        return 1
    fi
}

# 状态映射辅助函数
map_status() {
    local field_index=$1
    shift
    local mapping_rules="$*"
    
    local awk_script="BEGIN {FS=\"\\t\"; OFS=\"\\t\"}
    {
        status = \$$field_index;"
    
    IFS=',' read -ra RULES <<< "$mapping_rules"
    for rule in "${RULES[@]}"; do
        IFS=':' read -ra PARTS <<< "$rule"
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
validate_required_params() {
    local params=("$@")
    local error_msg="${params[-1]}"
    
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
confirm_action() {
    local message=$1
    echo "警告：$message"
    read -r -p "请输入 'YES' 以确认操作: " confirm
    
    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi
    
    return 0
}
