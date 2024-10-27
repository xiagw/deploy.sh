#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# KVStore (Redis) 相关函数

show_kvstore_help() {
    echo "KVStore (Redis) 操作："
    echo "  list [region]                           - 列出 KVStore 实例"
    echo "  create <名称> <实例类型> <容量> [region] - 创建 KVStore 实例"
    echo "  update <实例ID> <新名称> [region]        - 更新 KVStore 实例"
    echo "  delete <实例ID> [region]                 - 删除 KVStore 实例"
    echo
    echo "示例："
    echo "  $0 kvstore list"
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
    *)
        echo "错误：未知的 KVStore 操作：$operation" >&2
        show_kvstore_help
        exit 1
        ;;
    esac
}

# 其他函数名称也需要从 redis_* 改为 kvstore_*

kvstore_list() {
    local format=${1:-human}
    local result
    if ! result=$(aliyun --profile "${profile:-}" r-kvstore DescribeInstances --RegionId "${region:-}"); then
        echo "错误：无法获取 Redis 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        echo -e "InstanceId\tInstanceName\tInstanceStatus\tCapacity\tConnectionDomain\tCreateTime"
        echo "$result" | jq -r '.Instances.KVStoreInstance[] | [.InstanceId, .InstanceName, .InstanceStatus, .Capacity, .ConnectionDomain, .CreateTime] | @tsv'
        ;;
    human | *)
        echo "列出 Redis 实例："
        if [[ $(echo "$result" | jq '.Instances.KVStoreInstance | length') -eq 0 ]]; then
            echo "没有找到 Redis 实例。"
        else
            echo "实例ID            名称                状态     容量(MB)  连接地址                  创建时间"
            echo "----------------  ------------------  -------  ---------  ------------------------  -------------------------"
            echo "$result" | jq -r '.Instances.KVStoreInstance[] | [.InstanceId, .InstanceName, .InstanceStatus, .Capacity, .ConnectionDomain, .CreateTime] | @tsv' |
            awk 'BEGIN {FS="\t"; OFS="\t"}
            {
                status = $3;
                if (status == "Normal") status = "运行中";
                else if (status == "Creating") status = "创建中";
                else if (status == "Changing") status = "修改中";
                else if (status == "Inactive") status = "已停止";
                else status = "未知";
                printf "%-16s  %-18s  %-7s  %-9s  %-24s  %s\n", $1, $2, status, $4, $5, $6
            }'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "kvstore" "list" "$result" "$format"
}

kvstore_create() {
    local name=$1 instance_class=$2 capacity=$3
    echo "创建 Redis 实例："
    local result
    result=$(aliyun --profile "${profile:-}" r-kvstore CreateInstance \
        --RegionId "$region" \
        --InstanceName "$name" \
        --InstanceClass "$instance_class" \
        --Capacity "$capacity" \
        --ChargeType PostPaid \
        --EngineVersion 5.0)
    echo "$result" | jq '.'
    log_result "$profile" "$region" "kvstore" "create" "$result"
}

kvstore_update() {
    local instance_id=$1 new_name=$2
    echo "更新 Redis 实例："
    local result
    result=$(aliyun --profile "${profile:-}" r-kvstore ModifyInstanceAttribute \
        --InstanceId "$instance_id" \
        --InstanceName "$new_name")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "kvstore" "update" "$result"
}

kvstore_delete() {
    local instance_id=$1

    echo "警告：您即将删除 Redis 实例：$instance_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 Redis 实例："
    local result
    result=$(aliyun --profile "${profile:-}" r-kvstore DeleteInstance --InstanceId "$instance_id")

    if [ $? -eq 0 ]; then
        echo "Redis 实例删除成功。"
        log_delete_operation "${profile:-}" "$region" "kvstore" "$instance_id" "Redis实例" "成功"
    else
        echo "Redis 实例删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "kvstore" "$instance_id" "Redis实例" "失败"
    fi

    log_result "$profile" "$region" "kvstore" "delete" "$result"
}
