#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# NAT网关相关函数

show_nat_help() {
    echo "NAT网关操作："
    echo "  list [region]                           - 列出NAT网关"
    echo "  create <VPC-ID> <名称> <规格> [region]   - 创建NAT网关"
    echo "  update <NAT网关ID> <名称> [region]       - 更新NAT网关"
    echo "  delete <NAT网关ID> [region]              - 删除NAT网关"
    echo
    echo "示例："
    echo "  $0 nat list"
    echo "  $0 nat create vpc-bp1qpo0kug3a20qqe**** my-nat Small"
    echo "  $0 nat update ngw-bp1uewa15k4iy5770**** new-name"
    echo "  $0 nat delete ngw-bp1uewa15k4iy5770****"
}

handle_nat_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) nat_list "$@" ;;
    create) nat_create "$@" ;;
    update) nat_update "$@" ;;
    delete) nat_delete "$@" ;;
    *)
        echo "错误：未知的NAT网关操作：$operation" >&2
        show_nat_help
        exit 1
        ;;
    esac
}

nat_list() {
    local format=${1:-human}
    local result
    if ! result=$(aliyun --profile "${profile:-}" vpc DescribeNatGateways --RegionId "${region:-}"); then
        echo "错误：无法获取 NAT 网关列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        echo -e "NatGatewayId\tName\tStatus\tSpec\tVpcId\tCreationTime"
        echo "$result" | jq -r '.NatGateways.NatGateway[] | [.NatGatewayId, .Name, .Status, .Spec, .VpcId, .CreationTime] | @tsv'
        ;;
    human | *)
        echo "列出 NAT 网关："
        if [[ $(echo "$result" | jq '.NatGateways.NatGateway | length') -eq 0 ]]; then
            echo "没有找到 NAT 网关。"
        else
            echo "NAT网关ID          名称                状态    规格    VPC-ID              创建时间"
            echo "----------------   ------------------  ------  ------  ------------------  -------------------------"
            echo "$result" | jq -r '.NatGateways.NatGateway[] | [.NatGatewayId, .Name, .Status, .Spec, .VpcId, .CreationTime] | @tsv' |
            awk 'BEGIN {FS="\t"; OFS="\t"}
            {
                printf "%-18s %-18s %-6s %-6s %-18s %s\n", $1, $2, $3, $4, $5, $6
            }'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "nat" "list" "$result" "$format"
}

nat_create() {
    local vpc_id=$1 name=$2 spec=$3
    echo "创建NAT网关："
    local result
    result=$(aliyun --profile "${profile:-}" vpc CreateNatGateway \
        --RegionId "$region" \
        --VpcId "$vpc_id" \
        --Name "$name" \
        --Spec "$spec")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "nat" "create" "$result"
}

nat_update() {
    local nat_id=$1 new_name=$2
    echo "更新NAT网关："
    local result
    result=$(aliyun --profile "${profile:-}" vpc ModifyNatGatewayAttribute \
        --RegionId "$region" \
        --NatGatewayId "$nat_id" \
        --Name "$new_name")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "nat" "update" "$result"
}

nat_delete() {
    local nat_id=$1

    # 获取NAT网关详细信息
    local nat_info
    nat_info=$(aliyun --profile "${profile:-}" vpc DescribeNatGateways --NatGatewayId "$nat_id" --RegionId "$region")
    local nat_name
    nat_name=$(echo "$nat_info" | jq -r '.NatGateways.NatGateway[0].Name')
    local vpc_id
    vpc_id=$(echo "$nat_info" | jq -r '.NatGateways.NatGateway[0].VpcId')

    echo "警告：您即将删除以下NAT网关："
    echo "  NAT网关ID: $nat_id"
    echo "  名称: $nat_name"
    echo "  VPC ID: $vpc_id"
    echo "  地域: $region"
    echo
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除NAT网关："
    local result
    result=$(aliyun --profile "${profile:-}" vpc DeleteNatGateway --RegionId "$region" --NatGatewayId "$nat_id")
    local status=$?

    if [ $status -eq 0 ]; then
        echo "NAT网关删除成功。"
        log_delete_operation "$profile" "$region" "nat" "$nat_id" "$nat_name" "成功"
    else
        echo "NAT网关删除失败。"
        echo "$result"
        log_delete_operation "$profile" "$region" "nat" "$nat_id" "$nat_name" "失败"
    fi

    echo "$result" | jq '.'
    log_result "$profile" "$region" "nat" "delete" "$result"
}
