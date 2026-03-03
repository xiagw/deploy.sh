#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# VPC (虚拟私有云) 相关函数

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_vpc_help() {
    echo "VPC (虚拟私有云) 操作："
    echo "  list [format]                           - 列出 VPC"
    echo "  subnet-list [format]                    - 列出子网"
    echo "  create <VPC名称> <CIDR> [描述]          - 创建 VPC"
    echo "  delete <VPC_ID>                         - 删除 VPC"
    echo "  describe <VPC_ID>                       - 描述 VPC 详情"
    echo "  create-subnet <子网名称> <VPC_ID> <CIDR> <可用区> - 创建子网"
    echo "  delete-subnet <子网ID>                  - 删除子网"
    echo
    echo "示例："
    echo "  $0 vpc list"
    echo "  $0 vpc list json"
    echo "  $0 vpc subnet-list"
    echo "  $0 vpc create \"MyVPC\" \"192.168.0.0/16\" \"我的VPC描述\""
    echo "  $0 vpc delete vpc-12345678"
    echo "  $0 vpc describe vpc-12345678"
    echo "  $0 vpc create-subnet \"mysubnet\" \"vpc-12345678\" \"192.168.1.0/24\" \"ap-guangzhou-1\""
    echo "  $0 vpc delete-subnet subnet-12345678"
}

handle_vpc_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) vpc_list "$@" ;;
    subnet-list) vpc_subnet_list "$@" ;;
    create) vpc_create "$@" ;;
    delete) vpc_delete "$@" ;;
    describe) vpc_describe "$@" ;;
    create-subnet) vpc_create_subnet "$@" ;;
    delete-subnet) vpc_delete_subnet "$@" ;;
    help) show_vpc_help ;;
    *)
        echo "错误：未知的 VPC 操作：$operation" >&2
        show_vpc_help
        exit 1
        ;;
    esac
}

# VPC 列表
vpc_list() {
    local format=${1:-human}
    local result

    result=$(call_tencent_api vpc DescribeVpcs)
    if [ $? -ne 0 ]; then
        echo "错误：无法获取 VPC 列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "VpcId\tVpcName\tCidrBlock\tIsDefault\tCreatedTime"
        echo "$result" | jq -r '.Response.VpcSet[]? |
            [
                .VpcId,
                .VpcName,
                .CidrBlock,
                .IsDefault,
                .CreatedTime
            ] | @tsv'
        ;;
    human | *)
        echo "列出 VPC："
        local temp_output
        temp_output=$(echo "$result" | jq -r '.Response.VpcSet[]? |
            [
                .VpcId,
                .VpcName,
                .CidrBlock,
                .IsDefault,
                .CreatedTime
            ] | @tsv')

        local count
        if [ -n "$temp_output" ] && [ "$temp_output" != "null" ] && [ "$temp_output" != "" ]; then
            count=$(echo "$temp_output" | grep -c . || echo "0")
        else
            count="0"
        fi

        if [ "$count" = "0" ] || [ -z "$count" ]; then
            echo "没有找到 VPC。"
        else
            echo -e "VpcId\t\t\tVpcName\t\tCidrBlock\t\tIsDefault\tCreatedTime"
            echo "$temp_output" | awk 'BEGIN {FS="\t"; OFS="\t"} {
                printf "%-25s  %-20s  %-20s  %-9s  %s\n", $1, $2, $3, $4, $5
            }'
        fi
        ;;
    esac

    log_result "${profile:-}" "${region:-}" "vpc" "list" "$result" "$format"
}

# 子网列表
vpc_subnet_list() {
    local format=${1:-human}
    local result

    result=$(call_tencent_api vpc DescribeSubnets)
    if [ $? -ne 0 ]; then
        echo "错误：无法获取子网列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "SubnetId\tSubnetName\tVpcId\tCidrBlock\tZone\tIsDefault"
        echo "$result" | jq -r '.Response.SubnetSet[]? |
            [
                .SubnetId,
                .SubnetName,
                .VpcId,
                .CidrBlock,
                .Zone,
                .IsDefault
            ] | @tsv'
        ;;
    human | *)
        echo "列出子网："
        local temp_output
        temp_output=$(echo "$result" | jq -r '.Response.SubnetSet[]? |
            [
                .SubnetId,
                .SubnetName,
                .VpcId,
                .CidrBlock,
                .Zone,
                .IsDefault
            ] | @tsv')

        local count
        if [ -n "$temp_output" ] && [ "$temp_output" != "null" ] && [ "$temp_output" != "" ]; then
            count=$(echo "$temp_output" | grep -c . || echo "0")
        else
            count="0"
        fi

        if [ "$count" = "0" ] || [ -z "$count" ]; then
            echo "没有找到子网。"
        else
            echo -e "SubnetId\t\tSubnetName\tVpcId\t\t\tCidrBlock\tZone\t\tIsDefault"
            echo "$temp_output" | awk 'BEGIN {FS="\t"; OFS="\t"} {
                printf "%-23s  %-15s  %-20s  %-15s  %-12s  %s\n", $1, $2, $3, $4, $5, $6
            }'
        fi
        ;;
    esac

    log_result "${profile:-}" "${region:-}" "vpc" "subnet-list" "$result" "$format"
}

# 创建 VPC
vpc_create() {
    local name=$1
    local cidr_block=$2
    local description=$3

    if [ -z "$name" ] || [ -z "$cidr_block" ]; then
        echo "错误：需要提供VPC名称和CIDR块。" >&2
        echo "用法：$0 vpc create <VPC名称> <CIDR> [描述]" >&2
        return 1
    fi

    echo "创建 VPC：$name ($cidr_block)"

    local result
    local params="--VpcName \"$name\" --CidrBlock \"$cidr_block\""
    if [ -n "$description" ]; then
        params="$params --DhcpOptionsId \"$description\""
    fi

    result=$(call_tencent_api vpc CreateVpc $params)
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "create" "$result"
    else
        echo "错误：创建VPC失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 删除 VPC
vpc_delete() {
    local vpc_id=$1

    if [ -z "$vpc_id" ]; then
        echo "错误：需要提供VPC ID。" >&2
        echo "用法：$0 vpc delete <VPC_ID>" >&2
        return 1
    fi

    echo "警告：您即将删除 VPC：$vpc_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 VPC：$vpc_id"

    local result
    result=$(call_tencent_api vpc DeleteVpc --VpcId "$vpc_id")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "delete" "$result"
    else
        echo "错误：删除VPC失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 描述 VPC 详情
vpc_describe() {
    local vpc_id=$1

    if [ -z "$vpc_id" ]; then
        echo "错误：需要提供VPC ID。" >&2
        echo "用法：$0 vpc describe <VPC_ID>" >&2
        return 1
    fi

    echo "获取 VPC 详情：$vpc_id"

    local result
    result=$(call_tencent_api vpc DescribeVpcs --VpcIds "[\"$vpc_id\"]")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "describe" "$result"
    else
        echo "错误：获取VPC详情失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 创建子网
vpc_create_subnet() {
    local subnet_name=$1
    local vpc_id=$2
    local cidr_block=$3
    local zone=$4

    if [ -z "$subnet_name" ] || [ -z "$vpc_id" ] || [ -z "$cidr_block" ] || [ -z "$zone" ]; then
        echo "错误：需要提供子网名称、VPC ID、CIDR块和可用区。" >&2
        echo "用法：$0 vpc create-subnet <子网名称> <VPC_ID> <CIDR> <可用区>" >&2
        return 1
    fi

    echo "创建子网：$subnet_name (VPC: $vpc_id, CIDR: $cidr_block, Zone: $zone)"

    local result
    result=$(call_tencent_api vpc CreateSubnet --VpcId "$vpc_id" --SubnetName "$subnet_name" --CidrBlock "$cidr_block" --Zone "$zone")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "create-subnet" "$result"
    else
        echo "错误：创建子网失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 删除子网
vpc_delete_subnet() {
    local subnet_id=$1

    if [ -z "$subnet_id" ]; then
        echo "错误：需要提供子网ID。" >&2
        echo "用法：$0 vpc delete-subnet <子网ID>" >&2
        return 1
    fi

    echo "警告：您即将删除子网：$subnet_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除子网：$subnet_id"

    local result
    result=$(call_tencent_api vpc DeleteSubnet --SubnetId "$subnet_id")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "delete-subnet" "$result"
    else
        echo "错误：删除子网失败。" >&2
        echo "$result" >&2
        return 1
    fi
}