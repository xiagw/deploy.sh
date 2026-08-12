#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# ECI (弹性容器实例) 相关函数

# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_eci_help() {
    echo "ECI (弹性容器实例) 操作："
    echo "  get [format]                            - 列出 ECI 实例"
    echo "  add <名称> <镜像> [CPU] [内存(GB)]      - 创建 ECI 实例"
    echo "  del [<实例ID>]                          - 删除 ECI 实例"
    echo
    echo "示例："
    echo "  $0 eci get"
    echo "  $0 eci get json"
    echo "  $0 eci add my-eci registry.aliyuncs.com/ns/my-image:latest 1.0 2"
    echo "  $0 eci del eci-xxx"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_eci_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) eci_list "$@" ;;
    add) eci_create "$@" ;;
    del) eci_delete "$@" ;;
    help) show_eci_help ;;
    *)
        echo "错误：未知的 ECI 操作：$operation" >&2
        show_eci_help
        exit 1
        ;;
    esac
}

_eci_resolve_instance_id() {
    resolve_resource_id "$1" "${2:-选择 ECI 实例}" "错误：没有找到 ECI 实例。" \
        '.ContainerGroups[] | "\(.ContainerGroupId) (\(.ContainerGroupName // .ContainerGroupId)) [\(.Status)]"' \
        -- eci DescribeContainerGroups --RegionId "${region:-}"
}

eci_list() {
    local format=${1:-human}

    local table_header="ContainerGroupId\tContainerGroupName\tStatus\tCpu\tMemory\tCreationTime"
    local jq_filter=".ContainerGroups[] | [.ContainerGroupId, .ContainerGroupName, .Status, .Cpu, .Memory, .CreationTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-18s  %-8s  %-6s  %-10s  %s\n", $1, $2, $3, $4, $5, $6}'

    local result
    result=$(call_aliyun_api eci DescribeContainerGroups --RegionId "${region:-}" 2>/dev/null)
    ret=$?
    if [ $ret -eq 0 ]; then
        format_output "$result" "$format" "eci" "list" "$table_header" "$jq_filter" "$status_mapper" "没有找到 ECI 实例。" "列出 ECI 实例："
    else
        echo "错误：无法获取 ECI 实例列表。" >&2
        return 1
    fi
}

eci_create() {
    local name=$1 image=$2 cpu=${3:-1.0} memory=${4:-2.0}

    if [ -z "$name" ] || [ -z "$image" ]; then
        echo "使用 fzf 交互式模式创建 ECI 实例"

        if [ -z "$name" ]; then
            read -r -p "请输入实例名称: " name
            if [ -z "$name" ]; then
                name="eci-$(date +%Y%m%d-%H%M%S)"
                echo "自动生成实例名称: $name"
            fi
        fi

        if [ -z "$image" ]; then
            read -r -p "请输入镜像地址 (如 registry.aliyuncs.com/ns/image:latest): " image
            if [ -z "$image" ]; then
                echo "错误：镜像地址不能为空。" >&2
                return 1
            fi
        fi
    fi

    if ! validate_required_params "$name" "$image" "错误：名称和镜像不能为空。"; then
        echo "用法：eci add <名称> <镜像> [CPU] [内存(GB)]" >&2
        return 1
    fi

    echo "创建 ECI 实例："
    echo "  名称: $name"
    echo "  镜像: $image"
    echo "  CPU: ${cpu}核"
    echo "  内存: ${memory}GB"

    call_api_logged "eci" "create" "错误：ECI 实例创建失败。" \
        -- eci CreateContainerGroup \
        --ContainerGroupName "$name" \
        --RegionId "$region" \
        --Cpu "$cpu" \
        --Memory "$memory" \
        --Container.1.Name "$name" \
        --Container.1.Image "$image"
}

eci_delete() {
    local instance_id
    instance_id=$(_eci_resolve_instance_id "$1" "选择要删除的 ECI 实例") || return 1

    local instance_info
    instance_info=$(call_aliyun_api eci DescribeContainerGroups --ContainerGroupIds "[\"$instance_id\"]" --RegionId "$region" 2>/dev/null)
    ret=$?
    local instance_name="未知"
    if [ $ret -eq 0 ]; then
        instance_name=$(echo "$instance_info" | jq -r '.ContainerGroups[0].ContainerGroupName // "未知"')
    fi

    echo "警告：您即将删除以下 ECI 实例："
    echo "  实例ID: $instance_id"
    echo "  名称: $instance_name"
    echo "  地域: $region"

    if ! confirm_action "删除 ECI 实例 $instance_id ($instance_name)"; then
        return 1
    fi

    echo "删除 ECI 实例："
    call_api_del_logged "eci" "$instance_id" "$instance_name" "错误：ECI 实例删除失败。" \
        -- eci DeleteContainerGroup --ContainerGroupId "$instance_id" --RegionId "$region" || return 1
    echo "ECI 实例删除成功。"
}