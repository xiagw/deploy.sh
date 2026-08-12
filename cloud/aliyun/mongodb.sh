#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# MongoDB (云数据库 MongoDB) 相关函数

# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_mongodb_help() {
    echo "MongoDB (云数据库 MongoDB) 操作："
    echo "  get [format]                            - 列出 MongoDB 实例"
    echo "  add <名称> <规格> <存储(GB)> <版本>      - 创建 MongoDB 实例"
    echo "  set [<实例ID>] [<新名称>]               - 更新实例名称"
    echo "  del [<实例ID>]                          - 删除实例"
    echo
    echo "示例："
    echo "  $0 mongodb get"
    echo "  $0 mongodb get json"
    echo "  $0 mongodb add my-mongo dds.mongo.mid 20 6.0"
    echo "  $0 mongodb set dds-xxx new-name"
    echo "  $0 mongodb del dds-xxx"
    echo ""
    echo "注意：创建实例需要较长时间（5-10分钟），请耐心等待。"
    echo "对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_mongodb_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) mongodb_list "$@" ;;
    add) mongodb_create "$@" ;;
    set) mongodb_update "$@" ;;
    del) mongodb_delete "$@" ;;
    help) show_mongodb_help ;;
    *)
        echo "错误：未知的 MongoDB 操作：$operation" >&2
        show_mongodb_help
        exit 1
        ;;
    esac
}

_mongodb_resolve_instance_id() {
    resolve_resource_id "$1" "${2:-选择 MongoDB 实例}" "错误：没有找到 MongoDB 实例。" \
        '.DBInstances.DBInstance[] | "\(.DBInstanceId) (\(.DBInstanceDescription // .DBInstanceId)) [\(.DBInstanceClass)] [\(.DBInstanceStatus)]"' \
        -- dds DescribeDBInstances --RegionId "${region:-}"
}

mongodb_list() {
    local format=${1:-human}

    local table_header="DBInstanceId\tDBInstanceDescription\tDBInstanceStatus\tDBInstanceClass\tDBInstanceStorage\tCreationTime"
    local jq_filter=".DBInstances.DBInstance[] | [.DBInstanceId, .DBInstanceDescription, .DBInstanceStatus, .DBInstanceClass, .DBInstanceStorage, .CreationTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-18s  %-8s  %-18s  %-10s  %s\n", $1, $2, $3, $4, $5, $6}'

    local result
    result=$(call_aliyun_api dds DescribeDBInstances --RegionId "${region:-}" 2>/dev/null)
    ret=$?
    if [ $ret -eq 0 ]; then
        format_output "$result" "$format" "mongodb" "list" "$table_header" "$jq_filter" "$status_mapper" "没有找到 MongoDB 实例。" "列出 MongoDB 实例："
    else
        echo "错误：无法获取 MongoDB 实例列表。" >&2
        return 1
    fi
}

mongodb_create() {
    local name=$1 instance_class=$2 storage=$3 engine_version=$4

    if [ -z "$name" ] || [ -z "$instance_class" ] || [ -z "$storage" ] || [ -z "$engine_version" ]; then
        echo "使用 fzf 交互式模式创建 MongoDB 实例"

        if [ -z "$name" ]; then
            read -r -p "请输入实例名称: " name
            if [ -z "$name" ]; then
                name="mongodb-$(date +%Y%m%d-%H%M%S)"
                echo "自动生成实例名称: $name"
            fi
        fi

        if [ -z "$instance_class" ]; then
            local class_list="dds.mongo.small
dds.mongo.mid
dds.mongo.standard
dds.mongo.large
dds.mongo.xlarge
dds.mongo.2xlarge
dds.mongo.4xlarge"
            if type select_with_fzf >/dev/null 2>&1; then
                instance_class=$(select_with_fzf "选择 MongoDB 实例规格" "$class_list")
            else
                read -r -p "请输入实例规格: " instance_class
            fi
        fi

        if [ -z "$storage" ]; then
            local storage_list="10
20
50
100
200
500
1000
2000"
            if type select_with_fzf >/dev/null 2>&1; then
                storage=$(select_with_fzf "选择存储空间 (GB)" "$storage_list")
            else
                read -r -p "请输入存储空间 (GB): " storage
            fi
        fi

        if [ -z "$engine_version" ]; then
            local version_list="8.0
7.0
6.0
5.0
4.4
4.2
4.0"
            if type select_with_fzf >/dev/null 2>&1; then
                engine_version=$(select_with_fzf "选择 MongoDB 版本" "$version_list")
            else
                read -r -p "请输入 MongoDB 版本: " engine_version
            fi
        fi
    fi

    if ! validate_required_params "$name" "$instance_class" "$storage" "$engine_version" "错误：名称、规格、存储和版本不能为空。"; then
        echo "用法：mongodb add <名称> <规格> <存储(GB)> <版本>" >&2
        return 1
    fi

    if ! [[ "$storage" =~ ^[0-9]+$ ]]; then
        echo "错误：存储空间必须是数字（单位：GB）。" >&2
        return 1
    fi

    echo "创建 MongoDB 实例："
    echo "  名称: $name"
    echo "  规格: $instance_class"
    echo "  存储: ${storage}GB"
    echo "  版本: $engine_version"
    echo "  付费类型: PostPaid"

    call_api_logged "mongodb" "create" "错误：MongoDB 实例创建失败。" \
        -- dds CreateDBInstance --DBInstanceClass "$instance_class" \
        --DBInstanceStorage "$storage" --EngineVersion "$engine_version" \
        --DBInstanceDescription "$name" --RegionId "$region" --ChargeType PostPaid
}

mongodb_update() {
    local instance_id new_name=$2
    instance_id=$(_mongodb_resolve_instance_id "$1" "选择要更新的 MongoDB 实例") || return 1

    if [ -z "$new_name" ]; then
        read -r -p "请输入新的实例名称: " new_name
        if [ -z "$new_name" ]; then
            echo "错误：新名称不能为空。" >&2
            return 1
        fi
    fi

    echo "更新 MongoDB 实例名称："
    call_api_logged "mongodb" "update" "错误：更新失败。" \
        -- dds ModifyDBInstanceDescription --DBInstanceId "$instance_id" \
        --DBInstanceDescription "$new_name" --RegionId "$region"
}

mongodb_delete() {
    local instance_id
    instance_id=$(_mongodb_resolve_instance_id "$1" "选择要删除的 MongoDB 实例") || return 1

    local instance_info
    instance_info=$(call_aliyun_api dds DescribeDBInstanceAttribute --DBInstanceId "$instance_id" --RegionId "$region" 2>/dev/null)
    ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：无法获取实例信息。" >&2
        return 1
    fi

    local instance_name
    instance_name=$(echo "$instance_info" | jq -r '.DBInstances.DBInstance[0].DBInstanceDescription // "未知"')

    echo "警告：您即将删除以下 MongoDB 实例："
    echo "  实例ID: $instance_id"
    echo "  名称: $instance_name"
    echo "  地域: $region"

    if ! confirm_action "删除 MongoDB 实例 $instance_id ($instance_name)"; then
        return 1
    fi

    echo "删除 MongoDB 实例："
    call_api_del_logged "mongodb" "$instance_id" "$instance_name" "错误：MongoDB 实例删除失败。" \
        -- dds DeleteDBInstance --DBInstanceId "$instance_id" --RegionId "$region" || return 1
    echo "MongoDB 实例删除成功。"
}