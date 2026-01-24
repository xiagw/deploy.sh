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

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$name" ] || [ -z "$instance_class" ] || [ -z "$capacity" ]; then
        echo "使用 fzf 交互式模式创建 KVStore 实例"

        # 输入名称
        if [ -z "$name" ]; then
            read -r -p "请输入 KVStore 实例名称: " name
            if [ -z "$name" ]; then
                echo "错误：实例名称不能为空。" >&2
                return 1
            fi
        fi

        # 选择实例类型
        if [ -z "$instance_class" ]; then
            echo "正在获取可用的 KVStore 实例类型..."
            local class_result
            class_result=$(call_aliyun_api r-kvstore DescribeInstanceClasses --RegionId "$region" --Engine "Redis" 2>/dev/null)

            if [ $? -eq 0 ] && [ -n "$class_result" ]; then
                local class_list
                class_list=$(echo "$class_result" | jq -r '.AvailableZones.AvailableZone[].AvailableResources.AvailableResource[] | select(.Type == "InstanceClass") | .SupportedResources.SupportedResource[] | "\(.Value)"' | sort -u)

                if [ -z "$class_list" ]; then
                    echo "警告：无法从 API 获取实例类型，使用备用列表。" >&2
                    class_list="redis.master.micro.default
redis.master.small.default
redis.master.mid.default
redis.master.stand.default
redis.master.large.default
redis.master.2xlarge.default
redis.master.4xlarge.default"
                fi
            else
                echo "警告：调用 DescribeInstanceClasses API 失败，使用备用列表。" >&2
                class_list="redis.master.micro.default
redis.master.small.default
redis.master.mid.default
redis.master.stand.default
redis.master.large.default
redis.master.2xlarge.default
redis.master.4xlarge.default"
            fi

            if type select_with_fzf >/dev/null 2>&1; then
                instance_class=$(select_with_fzf "选择 KVStore 实例类型" "$class_list")
            else
                echo "错误：需要选择实例类型，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi

        # 选择容量
        if [ -z "$capacity" ]; then
            echo "正在获取可用的 KVStore 容量范围..."
            local capacity_result
            capacity_result=$(call_aliyun_api r-kvstore DescribeInstanceClasses --RegionId "$region" --Engine "Redis" --InstanceClass "$instance_class" 2>/dev/null)

            if [ $? -eq 0 ] && [ -n "$capacity_result" ]; then
                local capacity_list
                capacity_list=$(echo "$capacity_result" | jq -r '.AvailableZones.AvailableZone[].AvailableResources.AvailableResource[] | select(.Type == "Capacity") | .SupportedResources.SupportedResource[] | "\(.Value)"' | sort -n | uniq)

                if [ -z "$capacity_list" ]; then
                    echo "警告：无法从 API 获取容量选项，使用常用容量列表。" >&2
                    capacity_list="1024
2048
4096
8192
16384
32768
65536
131072"
                fi
            else
                echo "警告：调用容量 API 失败，使用常用容量列表。" >&2
                capacity_list="1024
2048
4096
8192
16384
32768
65536
131072"
            fi

            if type select_with_fzf >/dev/null 2>&1; then
                capacity=$(select_with_fzf "选择 KVStore 容量 (MB)" "$capacity_list")
            else
                read -r -p "请输入 KVStore 容量 (MB): " capacity
            fi
        fi
    fi

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

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$instance_id" ] || [ -z "$new_name" ]; then
        echo "使用 fzf 交互式模式更新 KVStore 实例"

        # 选择实例ID
        if [ -z "$instance_id" ]; then
            local instance_list
            instance_list=$(call_aliyun_api r-kvstore DescribeInstances --RegionId "$region" 2>/dev/null | jq -r '.Instances.KVStoreInstance[] | "\(.InstanceId) (\(.InstanceName)) [\(.InstanceClass)] [\(.Capacity)MB]"')

            if [ -z "$instance_list" ]; then
                echo "错误：没有找到 KVStore 实例。" >&2
                return 1
            elif [ "$(echo "$instance_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
                instance_id=$(echo "$instance_list" | awk '{print $1}')
                echo "自动选择唯一的 KVStore 实例: $instance_id"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    instance_id=$(select_with_fzf "选择 KVStore 实例" "$instance_list" | awk '{print $1}')
                else
                    echo "错误：需要选择 KVStore 实例，但未找到交互式选择工具。" >&2
                    return 1
                fi
            fi
        fi

        # 输入新名称
        if [ -z "$new_name" ]; then
            read -r -p "请输入新的实例名称: " new_name
            if [ -z "$new_name" ]; then
                echo "错误：新名称不能为空。" >&2
                return 1
            fi
        fi
    fi

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

    # 如果没有提供实例ID，则使用 fzf 交互式选择
    if [ -z "$instance_id" ]; then
        echo "使用 fzf 交互式模式删除 KVStore 实例"

        local instance_list
        instance_list=$(call_aliyun_api r-kvstore DescribeInstances --RegionId "$region" 2>/dev/null | jq -r '.Instances.KVStoreInstance[] | "\(.InstanceId) (\(.InstanceName)) [\(.InstanceClass)] [\(.Capacity)MB]"')

        if [ -z "$instance_list" ]; then
            echo "错误：没有找到 KVStore 实例。" >&2
            return 1
        elif [ "$(echo "$instance_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            instance_id=$(echo "$instance_list" | awk '{print $1}')
            echo "自动选择唯一的 KVStore 实例: $instance_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                instance_id=$(select_with_fzf "选择要删除的 KVStore 实例" "$instance_list" | awk '{print $1}')
            else
                echo "错误：需要选择 KVStore 实例，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

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
