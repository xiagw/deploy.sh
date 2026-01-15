#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# KVStore (Redis) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_kvstore_help() {
    echo "KVStore (Redis) 操作："
    echo "  list [format]                    - 列出 KVStore 实例"
    echo "  create <名称> <实例类型> <容量>   - 创建 KVStore 实例"
    echo "  update <实例ID> <新名称>          - 更新 KVStore 实例"
    echo "  delete <实例ID>                  - 删除 KVStore 实例"
    echo
    echo "示例："
    echo "  $0 kvstore list"
    echo "  $0 kvstore list json"
    echo "  $0 kvstore create my-redis Redis.Master.Small.Default 1024"
    echo "  $0 kvstore update r-bp1zxszhcgatnx**** new-name"
    echo "  $0 kvstore delete r-bp1zxszhcgatnx****"
}

handle_kvstore_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) kvstore_list "$@" ;;
    create) kvstore_create "$@" ;;
    update) kvstore_update "$@" ;;
    delete) kvstore_delete "$@" ;;
    help) show_kvstore_help ;;
    *)
        echo "错误：未知的 KVStore 操作：$operation" >&2
        show_kvstore_help
        exit 1
        ;;
    esac
}

# 使用新框架的列表函数
kvstore_list() {
    local format=${1:-human}
    
    local table_header="InstanceId\tInstanceName\tInstanceStatus\tCapacity\tConnectionDomain\tCreateTime"
    local jq_filter=".Instances.KVStoreInstance[] | [.InstanceId, .InstanceName, .InstanceStatus, .Capacity, .ConnectionDomain, .CreateTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"}
    {
        status = $3;
        if (status == "Normal") status = "运行中";
        else if (status == "Creating") status = "创建中";
        else if (status == "Changing") status = "修改中";
        else if (status == "Inactive") status = "已停止";
        else status = "未知";
        printf "%-16s  %-18s  %-7s  %-9s  %-24s  %s\n", $1, $2, status, $4, $5, $6
    }'
    
    generic_list \
        "r-kvstore" \
        "DescribeInstances" \
        "kvstore" \
        "$format" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 Redis 实例。" \
        "列出 Redis 实例："
}

# 使用新框架的创建函数
kvstore_create() {
    local name=$1 instance_class=$2 capacity=$3
    
    if ! validate_required_params "$name" "$instance_class" "$capacity" "错误：名称、实例类型和容量不能为空。"; then
        echo "用法：kvstore create <名称> <实例类型> <容量>" >&2
        return 1
    fi
    
    # 验证容量是否为数字
    if ! [[ "$capacity" =~ ^[0-9]+$ ]]; then
        echo "错误：容量必须是数字（单位：MB）。" >&2
        return 1
    fi
    
    local api_args=(
        "--InstanceName" "$name"
        "--InstanceClass" "$instance_class"
        "--Capacity" "$capacity"
        "--InstanceType" "Redis"
        "--ChargeType" "PostPaid"
    )
    
    generic_create \
        "r-kvstore" \
        "CreateInstance" \
        "kvstore" \
        "$name" \
        "${api_args[@]}"
}

# 使用新框架的更新函数
kvstore_update() {
    local instance_id=$1 new_name=$2
    
    if ! validate_required_params "$instance_id" "$new_name" "错误：实例ID和新名称不能为空。"; then
        echo "用法：kvstore update <实例ID> <新名称>" >&2
        return 1
    fi
    
    echo "更新 KVStore 实例："
    local result
    result=$(call_aliyun_api r-kvstore ModifyInstanceAttribute \
        --InstanceId "$instance_id" \
        --InstanceName "$new_name")
    
    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "kvstore" "update" "$result"
    else
        echo "错误：更新失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 删除函数需要特殊处理（需要确认）
kvstore_delete() {
    local instance_id=$1
    
    if [ -z "$instance_id" ]; then
        echo "错误：实例ID不能为空。" >&2
        return 1
    fi
    
    # 获取实例详细信息
    local instance_info
    instance_info=$(call_aliyun_api r-kvstore DescribeInstanceAttribute \
        --InstanceId "$instance_id")
    
    local instance_name
    instance_name=$(echo "$instance_info" | jq -r '.InstanceName // "未知"')
    
    # 检查实例是否存在
    if [ "$instance_name" = "null" ] || [ -z "$instance_name" ] || [ "$instance_name" = "未知" ]; then
        echo "错误：未找到指定的 Redis 实例：$instance_id" >&2
        return 1
    fi
    
    # 确认删除
    echo "警告：您即将删除以下 Redis 实例："
    echo "  实例ID: $instance_id"
    echo "  名称: $instance_name"
    echo "  地域: $region"
    
    if ! confirm_action "删除 Redis 实例 $instance_id ($instance_name)"; then
        return 1
    fi
    
    # 删除实例
    echo "删除 Redis 实例："
    local result
    result=$(call_aliyun_api r-kvstore DeleteInstance \
        --InstanceId "$instance_id")
    
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "Redis 实例删除成功。"
        echo "$result" | jq '.'
        log_delete_operation "${profile:-}" "$region" "kvstore" "$instance_id" "$instance_name" "成功"
    else
        echo "错误：Redis 实例删除失败。" >&2
        echo "$result" >&2
        log_delete_operation "${profile:-}" "$region" "kvstore" "$instance_id" "$instance_name" "失败"
        return 1
    fi
    
    log_result "${profile:-}" "$region" "kvstore" "delete" "$result"
}
