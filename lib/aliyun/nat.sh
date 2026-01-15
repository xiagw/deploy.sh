#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# NAT网关相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_nat_help() {
    echo "NAT网关操作："
    echo "  list [format]                    - 列出NAT网关"
    echo "  create <VPC-ID> <名称> <规格>     - 创建NAT网关"
    echo "  update <NAT网关ID> <名称>         - 更新NAT网关"
    echo "  delete <NAT网关ID>                - 删除NAT网关"
    echo
    echo "示例："
    echo "  $0 nat list"
    echo "  $0 nat list json"
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
    help) show_nat_help ;;
    *)
        echo "错误：未知的NAT网关操作：$operation" >&2
        show_nat_help
        exit 1
        ;;
    esac
}

# 使用新框架的列表函数
nat_list() {
    local format=${1:-human}
    
    local table_header="NatGatewayId\tName\tStatus\tSpec\tVpcId\tCreationTime"
    local jq_filter=".NatGateways.NatGateway[] | [.NatGatewayId, .Name, .Status, .Spec, .VpcId, .CreationTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-18s  %-6s  %-6s  %-18s  %s\n", $1, $2, $3, $4, $5, $6}'
    
    generic_list \
        "vpc" \
        "DescribeNatGateways" \
        "nat" \
        "$format" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 NAT 网关。" \
        "列出 NAT 网关："
}

# 使用新框架的创建函数
nat_create() {
    local vpc_id=$1 name=$2 spec=$3
    
    if ! validate_required_params "$vpc_id" "$name" "$spec" "错误：VPC ID、名称和规格不能为空。"; then
        echo "用法：nat create <VPC-ID> <名称> <规格>" >&2
        return 1
    fi
    
    # 验证规格
    case "$spec" in
    Small | Medium | Large) ;;
    *)
        echo "错误：规格必须是 Small、Medium 或 Large。" >&2
        return 1
        ;;
    esac
    
    local api_args=(
        "--VpcId" "$vpc_id"
        "--Name" "$name"
        "--Spec" "$spec"
    )
    
    generic_create \
        "vpc" \
        "CreateNatGateway" \
        "nat" \
        "$name" \
        "${api_args[@]}"
}

# 使用新框架的更新函数
nat_update() {
    local nat_id=$1 new_name=$2
    
    if ! validate_required_params "$nat_id" "$new_name" "错误：NAT网关ID和新名称不能为空。"; then
        echo "用法：nat update <NAT网关ID> <新名称>" >&2
        return 1
    fi
    
    echo "更新NAT网关："
    local result
    result=$(call_aliyun_api vpc ModifyNatGatewayAttribute \
        --RegionId "$region" \
        --NatGatewayId "$nat_id" \
        --Name "$new_name")
    
    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "nat" "update" "$result"
    else
        echo "错误：更新失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 删除函数需要特殊处理（需要获取详细信息）
nat_delete() {
    local nat_id=$1
    
    if [ -z "$nat_id" ]; then
        echo "错误：NAT网关ID不能为空。" >&2
        return 1
    fi
    
    # 获取NAT网关详细信息
    local nat_info
    nat_info=$(call_aliyun_api vpc DescribeNatGateways \
        --NatGatewayId "$nat_id" \
        --RegionId "$region")
    
    local nat_name
    nat_name=$(echo "$nat_info" | jq -r '.NatGateways.NatGateway[0].Name // "未知"')
    local vpc_id
    vpc_id=$(echo "$nat_info" | jq -r '.NatGateways.NatGateway[0].VpcId // "未知"')
    
    # 检查 NAT 网关是否存在
    if [ "$nat_name" = "null" ] || [ -z "$nat_name" ] || [ "$nat_name" = "未知" ]; then
        echo "错误：未找到指定的 NAT 网关：$nat_id" >&2
        return 1
    fi
    
    # 确认删除
    echo "警告：您即将删除以下NAT网关："
    echo "  NAT网关ID: $nat_id"
    echo "  名称: $nat_name"
    echo "  VPC ID: $vpc_id"
    echo "  地域: $region"
    
    if ! confirm_action "删除 NAT 网关 $nat_id ($nat_name)"; then
        return 1
    fi
    
    # 删除NAT网关
    echo "删除NAT网关："
    local result
    result=$(call_aliyun_api vpc DeleteNatGateway \
        --RegionId "$region" \
        --NatGatewayId "$nat_id")
    
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "NAT网关删除成功。"
        echo "$result" | jq '.'
        log_delete_operation "${profile:-}" "$region" "nat" "$nat_id" "$nat_name" "成功"
    else
        echo "错误：NAT网关删除失败。" >&2
        echo "$result" >&2
        log_delete_operation "${profile:-}" "$region" "nat" "$nat_id" "$nat_name" "失败"
        return 1
    fi
    
    log_result "${profile:-}" "$region" "nat" "delete" "$result"
}
