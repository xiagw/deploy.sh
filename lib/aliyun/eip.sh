#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# EIP (弹性公网IP) 相关函数

show_eip_help() {
    echo "EIP (弹性公网IP) 操作："
    echo "  list [region]                           - 列出 EIP"
    echo "  create <带宽> [region]                   - 创建 EIP"
    echo "  update <EIP-ID> <新带宽> [region]        - 更新 EIP 带宽"
    echo "  delete <EIP-ID> [region]                 - 删除 EIP"
    echo
    echo "示例："
    echo "  $0 eip list"
    echo "  $0 eip create 5"
    echo "  $0 eip update eip-bp1v8dxgd9wqjb2g**** 10"
    echo "  $0 eip delete eip-bp1v8dxgd9wqjb2g****"
}

handle_eip_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) eip_list "$@" ;;
    create) eip_create "$@" ;;
    update) eip_update "$@" ;;
    delete) eip_delete "$@" ;;
    *)
        echo "错误：未知的 EIP 操作：$operation" >&2
        show_eip_help
        exit 1
        ;;
    esac
}

eip_list() {
    local format=${1:-human}
    local result
    if ! result=$(aliyun --profile "${profile:-}" vpc DescribeEipAddresses --RegionId "${region:-}"); then
        echo "错误：无法获取 EIP 列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        echo -e "AllocationId\tIpAddress\tStatus\tBandwidth\tInstanceId\tAllocationTime"
        echo "$result" | jq -r '.EipAddresses.EipAddress[] | [.AllocationId, .IpAddress, .Status, .Bandwidth, .InstanceId, .AllocationTime] | @tsv'
        ;;
    human | *)
        echo "列出 EIP："
        if [[ $(echo "$result" | jq '.EipAddresses.EipAddress | length') -eq 0 ]]; then
            echo "没有找到 EIP。"
        else
            echo "EIP-ID              IP地址         状态    带宽(Mbps)  实例ID             创建时间"
            echo "----------------    ------------   ------  ----------  ----------------   -------------------------"
            echo "$result" | jq -r '.EipAddresses.EipAddress[] | [.AllocationId, .IpAddress, .Status, .Bandwidth, .InstanceId, .AllocationTime] | @tsv' |
            awk 'BEGIN {FS="\t"; OFS="\t"}
            {
                printf "%-18s  %-14s %-7s %-10s %-18s %s\n", $1, $2, $3, $4, $5, $6
            }'
        fi
        ;;
    esac
    log_result "${profile:-}" "$region" "eip" "list" "$result" "$format"
}

eip_create() {
    local bandwidth=$1
    echo "创建 EIP："
    local result
    result=$(aliyun --profile "${profile:-}" vpc AllocateEipAddress \
        --RegionId "$region" \
        --Bandwidth "$bandwidth" \
        --InternetChargeType PayByTraffic)
    echo "$result" | jq '.'
    log_result "$profile" "$region" "eip" "create" "$result"
}

eip_update() {
    local eip_id=$1 new_bandwidth=$2
    echo "更新 EIP 带宽："
    local result
    result=$(aliyun --profile "${profile:-}" vpc ModifyEipAddressAttribute \
        --RegionId "$region" \
        --AllocationId "$eip_id" \
        --Bandwidth "$new_bandwidth")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "eip" "update" "$result"
}

eip_delete() {
    local eip_id=$1

    # 获取 EIP 详细信息
    local eip_info
    eip_info=$(aliyun --profile "${profile:-}" vpc DescribeEipAddresses --AllocationId "$eip_id" --RegionId "$region")
    local ip_address
    ip_address=$(echo "$eip_info" | jq -r '.EipAddresses.EipAddress[0].IpAddress')
    local eip_status
    eip_status=$(echo "$eip_info" | jq -r '.EipAddresses.EipAddress[0].Status')

    # 检查 EIP 状态
    if [[ "$eip_status" != "Available" ]]; then
        echo "警告：当前 EIP 状态为 '$eip_status'，不支持删除操作。" >&2
    fi

    echo "警告：您即将删除以下 EIP："
    echo "  EIP ID: $eip_id"
    echo "  IP 地址: $ip_address"
    echo "  地域: $region"
    echo
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "解绑 EIP："
    local unbind_result
    unbind_result=$(aliyun --profile "${profile:-}" vpc UnassociateEipAddress \
        --AllocationId "$eip_id" \
        --RegionId "$region")
    echo "$unbind_result" | jq '.'
    log_result "$profile" "$region" "eip" "unbind" "$unbind_result"

    echo "等待解绑EIP...10s"
    sleep 10

    echo "删除 EIP："
    local result
    result=$(aliyun --profile "${profile:-}" vpc ReleaseEipAddress --RegionId "$region" --AllocationId "$eip_id")
    local status=$?


    if [ $status -eq 0 ]; then
        echo "EIP 删除成功。"
        log_delete_operation "$profile" "$region" "eip" "$eip_id" "$ip_address" "成功"
    else
        echo "EIP 删除失败。"
        log_delete_operation "$profile" "$region" "eip" "$eip_id" "$ip_address" "失败"
    fi

    echo "$result" | jq '.'
    log_result "$profile" "$region" "eip" "delete" "$result"
}
