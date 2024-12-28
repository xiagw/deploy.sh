#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# VPC (专有网络) 相关函数

show_vpc_help() {
    echo "VPC 操作："
    echo "  all                                     - 列出所有 VPC 相关资源"
    echo "  list                                   - 列出 VPC"
    echo "  create [名称] [网段] [disable_ipv6]       - 创建 VPC (自动生成名称，默认网段: 192.168.0.0/16)"
    echo "  update <VPC-ID> <新名称>                - 更新 VPC"
    echo "  delete <VPC-ID>                         - 删除 VPC"
    echo "  vswitch-list <VPC-ID>                   - 列出交换机"
    echo "  vswitch-create [VPC-ID] [名称] [网段] [可用区] - 创建交换机"
    echo "  vswitch-update <交换机ID> <新名称>         - 更新交换机"
    echo "  vswitch-delete <交换机ID>                - 删除交换机"
    echo "  sg-list <VPC-ID>                        - 列出安全组"
    echo "  sg-create <VPC-ID> <名称> <描述>         - 创建安全组"
    echo "  sg-update <安全组ID> <新名称> <新描述>     - 更新安全组"
    echo "  sg-delete <安全组ID>                     - 删除安全组"
    echo "  sg-rule-list <安全组ID>                  - 列出安全组规则"
    echo "  sg-rule-add <安全组ID> <协议> <端口范围> <源IP> <描述> - 添加安全组规则"
    echo "  sg-rule-update <安全组规则ID> <协议> <端口范围> <源IP> - 更新安全组规则"
    echo "  sg-rule-delete <规则ID> <安全组ID> [方向]    - 删除安全组规则"
    echo "  ipv6gw-list <VPC-ID>                    - 列出 IPv6 网关"
    echo "  ipv6gw-create <VPC-ID> <名称> [规格]     - 创建 IPv6 网关"
    echo "  ipv6gw-update <IPv6网关ID> <新名称> [新规格] - 更新 IPv6 网关"
    echo "  ipv6gw-delete <IPv6网关ID>               - 删除 IPv6 网关"
    echo
    echo "示例："
    echo "  $0 vpc list"
    echo "  $0 vpc create"
    echo "  $0 vpc create my-vpc"
    echo "  $0 vpc create my-vpc 10.0.0.0/8"
    echo "  $0 vpc create my-vpc 192.168.0.0/16 false"
    echo "  $0 vpc update vpc-bp1qpo0kug3a20qqe**** new-name"
    echo "  $0 vpc delete vpc-bp1qpo0kug3a20qqe****"
    echo "  $0 vpc vswitch-list vpc-bp1qpo0kug3a20qqe****"
    echo "  $0 vpc vswitch-create cn-hangzhou-b"
    echo "  $0 vpc vswitch-create my-vswitch cn-hangzhou-b"
    echo "  $0 vpc vswitch-create vpc-bp1qpo0kug3a20qqe**** my-vswitch 192.168.50.0/24 cn-hangzhou-b"
    echo "  $0 vpc vswitch-update vsw-bp1pkt1fba8e8**** new-name"
    echo "  $0 vpc vswitch-delete vsw-bp1pkt1fba8e8****"
    echo "  $0 vpc sg-list vpc-bp1qpo0kug3a20qqe****"
    echo "  $0 vpc sg-create vpc-bp1qpo0kug3a20qqe**** my-sg '我的安全组'"
    echo "  $0 vpc sg-update sg-bp1fg655nh68xyz**** new-name '新的描述'"
    echo "  $0 vpc sg-delete sg-bp1fg655nh68xyz****"
    echo "  $0 vpc sg-rule-list sg-bp1fg655nh68xyz****"
    echo "  $0 vpc sg-rule-add sg-bp1fg655nh68xyz**** tcp 22/22 0.0.0.0/0 'Allow SSH'"
    echo "  $0 vpc sg-rule-update sgr-bp18kz9axq4xt5ek**** tcp 80/80 10.0.0.0/8"
    echo "  $0 vpc sg-rule-delete sgr-bp18kz9axq4xt5ek**** sg-bp1fg655nh68xyz**** ingress"
    echo "  $0 vpc ipv6gw-list vpc-bp1qpo0kug3a20qqe****"
    echo "  $0 vpc ipv6gw-create vpc-bp1qpo0kug3a20qqe**** my-ipv6gw Small"
    echo "  $0 vpc ipv6gw-update ipv6gw-bp1g8i5h7yaa******** new-name Medium"
    echo "  $0 vpc ipv6gw-delete ipv6gw-bp1g8i5h7yaa********"
}

handle_vpc_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    all) vpc_list_all "$@" ;;
    list) vpc_list "$@" ;;
    create) vpc_create "$@" ;;
    update)
        if [ $# -lt 2 ]; then
            echo "错误：update 操作需要提供 VPC ID 和新名称。" >&2
            show_vpc_help
            return 1
        fi
        vpc_update "$@"
        ;;
    delete)
        if [ $# -lt 1 ]; then
            echo "错误：delete 操作需要提供 VPC ID。" >&2
            show_vpc_help
            return 1
        fi
        vpc_delete "$@"
        ;;
    vswitch-list)
        if [ $# -lt 1 ]; then
            echo "错误：vswitch-list 操作需要提供 VPC ID。" >&2
            show_vpc_help
            return 1
        fi
        vpc_vswitch_list "$@"
        ;;
    vswitch-create) vpc_vswitch_create "$@" ;;
    vswitch-update) vpc_vswitch_update "$@" ;;
    vswitch-delete) vpc_vswitch_delete "$@" ;;
    sg-list) vpc_sg_list "$@" ;;
    sg-create) vpc_sg_create "$@" ;;
    sg-update) vpc_sg_update "$@" ;;
    sg-delete) vpc_sg_delete "$@" ;;
    sg-rule-list) vpc_sg_rule_list "$@" ;;
    sg-rule-add) vpc_sg_rule_add "$@" ;;
    sg-rule-update) vpc_sg_rule_update "$@" ;;
    sg-rule-delete) vpc_sg_rule_delete "$@" ;;
    ipv6gw-list) vpc_ipv6gw_list "$@" ;;
    ipv6gw-create) vpc_ipv6gw_create "$@" ;;
    ipv6gw-update) vpc_ipv6gw_update "$@" ;;
    ipv6gw-delete) vpc_ipv6gw_delete "$@" ;;
    *)
        echo "错误：未知的 VPC 操作：$operation" >&2
        show_vpc_help
        exit 1
        ;;
    esac
}

vpc_list_all() {
    echo "列出所有 VPC 相关资源："

    # 列出 VPC
    vpc_list "$@"

    # 获取所有 VPC ID
    local vpc_ids
    vpc_ids=$(aliyun --profile "${profile:-}" vpc DescribeVpcs --RegionId "${region:-}" | jq -r '.Vpcs.Vpc[].VpcId')

    # 对每个 VPC 列出相关资源
    for vpc_id in $vpc_ids; do
        echo "VPC ID: $vpc_id 的资源："

        # 列出交换机
        echo "交换机："
        vpc_vswitch_list "$vpc_id" "$@"

        # 列出安全组
        echo "安全组："
        vpc_sg_list "$vpc_id" "$@"

        # 列出 IPv6 网关
        echo "IPv6 网关："
        vpc_ipv6gw_list "$vpc_id" "$@"

        echo "----------------------------------------"
    done
}

vpc_list() {
    local format=${1:-human}

    local result
    if ! result=$(aliyun --profile "${profile:-}" vpc DescribeVpcs --RegionId "${region:-}"); then
        echo "错误：无法获取 VPC 列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        echo -e "VPC-ID\t名称\t状态\t网段\t创建时间"
        echo "$result" | jq -r '.Vpcs.Vpc[] | [.VpcId, .VpcName, .Status, .CidrBlock, .CreationTime] | @tsv'
        ;;
    human | *)
        echo "列出 VPC："
        if [[ $(echo "$result" | jq '.Vpcs.Vpc | length') -eq 0 ]]; then
            echo "没有找到 VPC。"
        else
            echo "VPC-ID              名称                状态    网段            创建时间"
            echo "----------------    ------------------  ------  --------------  -------------------------"
            echo "$result" | jq -r '.Vpcs.Vpc[] | [.VpcId, .VpcName, .Status, .CidrBlock, .CreationTime] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    printf "%-18s  %-18s  %-6s  %-14s  %s\n", $1, $2, $3, $4, $5
                }'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "vpc" "list" "$result" "$format"
}

vpc_create() {
    local name=${1:-"vpc-$(date +%Y%m%d-%H%M%S)"}  # 如果未提供名称，则自动生成
    local cidr=${2:-"192.168.0.0/16"}  # 设置默认 CIDR
    local enable_ipv6=${3:-true}

    if [ -z "$name" ]; then
        echo "错误：无法生成 VPC 名称。" >&2
        return 1
    fi

    echo "创建 VPC："
    if [ "$1" = "" ]; then
        echo "未提供 VPC 名称，自动生成: $name"
    fi

    local result
    result=$(aliyun --profile "${profile:-}" vpc CreateVpc \
        --RegionId "$region" \
        --VpcName "$name" \
        --CidrBlock "$cidr" \
        --EnableIpv6 "$enable_ipv6")
    echo "$result" | jq '.'
    log_result "${profile:-}" "$region" "vpc" "create" "$result" "$format"
}

vpc_update() {
    local vpc_id=$1 new_name=$2

    if [ -z "$vpc_id" ] || [ -z "$new_name" ]; then
        echo "错误：VPC ID 和新名称不能为空。" >&2
        return 1
    fi

    echo "更新 VPC："
    local result
    result=$(aliyun --profile "${profile:-}" vpc ModifyVpcAttribute \
        --VpcId "$vpc_id" \
        --VpcName "$new_name")
    echo "$result" | jq '.'
    log_result "${profile:-}" "$region" "vpc" "update" "$result"
}

vpc_delete() {
    local vpc_id=$1

    if [ -z "$vpc_id" ]; then
        echo "错误：VPC ID 不能为空。" >&2
        return 1
    fi

    # 首先检查 VPC 是否存在
    local vpc_info
    vpc_info=$(aliyun --profile "${profile:-}" vpc DescribeVpcs --VpcId "$vpc_id" --RegionId "$region")
    ret=$?
    if [ $ret -ne 0 ] || [ "$(echo "$vpc_info" | jq '.Vpcs.Vpc | length')" -eq 0 ]; then
        echo "错误：VPC $vpc_id 不存在或无法访问。" >&2
        return 1
    fi

    local vpc_name
    vpc_name=$(echo "$vpc_info" | jq -r '.Vpcs.Vpc[0].VpcName')
    local cidr_block
    cidr_block=$(echo "$vpc_info" | jq -r '.Vpcs.Vpc[0].CidrBlock')

    echo "警告：您即将删除以下 VPC："
    echo "  VPC ID: $vpc_id"
    echo "  名称: $vpc_name"
    echo "  网段: $cidr_block"
    echo "  地域: $region"
    echo
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 VPC："
    local result
    result=$(aliyun --profile "${profile:-}" vpc DeleteVpc --VpcId "$vpc_id" --RegionId "$region")
    local status=$?

    if [ $status -eq 0 ]; then
        echo "VPC 删除成功。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$vpc_id" "成功"
    else
        echo "VPC 删除失败。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$vpc_id" "失败"
    fi

    echo "$result" | jq '.'
    log_result "${profile:-}" "$region" "vpc" "delete" "$result"
}

# 新增辅助函数：获取 VPC ID
get_vpc_id() {
    local specified_vpc_id=$1
    if [ -n "$specified_vpc_id" ]; then
        echo "$specified_vpc_id"
        return 0
    fi

    local result
    result=$(aliyun --profile "${profile:-}" vpc DescribeVpcs --RegionId "$region")
    local vpc_count
    vpc_count=$(echo "$result" | jq '.Vpcs.Vpc | length')

    if [ "$vpc_count" -eq 0 ]; then
        echo "错误：未找到任何 VPC。请先创建一个 VPC。" >&2
        return 1
    elif [ "$vpc_count" -eq 1 ]; then
        local vpc_id
        vpc_id=$(echo "$result" | jq -r '.Vpcs.Vpc[0].VpcId')
        echo "$vpc_id"
        return 0
    else
        echo "找到多个 VPC：" >&2
        echo "$result" | jq -r '.Vpcs.Vpc[] | "VPC ID: \(.VpcId), 名称: \(.VpcName)"' >&2
        echo "请指定要使用的 VPC ID。" >&2
        return 1
    fi
}

# 修改 vpc_vswitch_list 函数
vpc_vswitch_list() {
    local vpc_id
    vpc_id=$(get_vpc_id "$1")
    ret=$?
    if [ $ret -ne 0 ]; then
        return 1
    fi

    local format=${2:-human}

    local result
    if ! result=$(aliyun --profile "${profile:-}" vpc DescribeVSwitches --VpcId "$vpc_id" --RegionId "$region"); then
        echo "错误：无法获取交换机列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result" | jq '.VSwitches.VSwitch[]'
        ;;
    tsv)
        echo -e "交换机ID\t名称\t状态\t可用区\t网段\t创建时间"
        echo "$result" | jq -r '.VSwitches.VSwitch[] | [.VSwitchId, .VSwitchName, .Status, .ZoneId, .CidrBlock, .CreationTime] | @tsv'
        ;;
    human | *)
        echo "列出交换机："
        if [[ $(echo "$result" | jq '.VSwitches.VSwitch | length') -eq 0 ]]; then
            echo "没有找到交换机。"
        else
            echo "交换机ID           名称                状态     可用区          网段            创建时间"
            echo "----------------   ------------------  ------  --------------  --------------  -------------------------"
            echo "$result" | jq -r '.VSwitches.VSwitch[] | [.VSwitchId, .VSwitchName, .Status, .ZoneId, .CidrBlock, .CreationTime] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
            {
                printf "%-18s %-18s %-6s %-14s %-14s %s\n", $1, $2, $3, $4, $5, $6
            }'
        fi
        ;;
    esac
    log_result "${profile:-}" "$region" "vpc" "vswitch-list" "$result" "$format"
}

# 新增函数：获取下一个可用的交换机网段
get_next_vswitch_cidr() {
    local vpc_id=$1
    local result
    result=$(aliyun --profile "${profile:-}" vpc DescribeVSwitches --VpcId "$vpc_id" --RegionId "$region")

    # 获取所有已使用的网段
    local used_cidrs
    used_cidrs=$(echo "$result" | jq -r '.VSwitches.VSwitch[].CidrBlock' | sort)

    # 如果没有任何交换机，返回第一个网段
    if [ -z "$used_cidrs" ]; then
        echo "192.168.50.0/24"
        return 0
    fi

    # 找到最后一个使用的网段
    local last_cidr
    last_cidr=$(echo "$used_cidrs" | tail -n 1)

    # 如果不是预期格式的网段，返回默认起始网段
    if ! [[ $last_cidr =~ ^192\.168\.([0-9]+)\.0/24$ ]]; then
        echo "192.168.50.0/24"
        return 0
    fi

    # 提取第三个八位字节并加1
    local next_octet
    next_octet=$((${BASH_REMATCH[1]} + 1))

    # 返回下一个网段
    echo "192.168.${next_octet}.0/24"
}

# 新增函数：选择可用区
select_zone() {
    local zones
    zones=$(aliyun --profile "${profile:-}" ecs DescribeZones --RegionId "$region" | jq -r '.Zones.Zone[].ZoneId' | grep -v '[[:space:]]')

    # 如果只有一个可用区，直接返回
    local zone_count
    zone_count=$(echo "$zones" | grep -v '[[:space:]]' -c)
    if [ "$zone_count" -eq 1 ]; then
        echo "$zones" | cut -f1
        return 0
    fi

    # 使用 fzf 让用户选择
    local selected_zone
    selected_zone=$(echo "$zones" | fzf --height=10 --prompt="请选择可用区: " | cut -f1)
    if [ -z "$selected_zone" ]; then
        echo "错误：未选择可用区。" >&2
        return 1
    fi

    echo "$selected_zone"
}

vpc_vswitch_create() {
    # 如果没有提供 VPC ID，尝试自动获取
    local vpc_id
    if [ -z "$1" ] || [ "$1" = "--auto" ]; then
        vpc_id=$(get_vpc_id)
        ret=$?
        if [ $ret -ne 0 ]; then
            return 1
        fi
        shift
    else
        vpc_id=$1
        shift
    fi

    local name cidr zone

    # 解析参数
    if [ -z "$1" ] || [[ "$1" =~ ^[0-9] ]]; then
        # 第一个参数为空或以数字开头（CIDR）
        name="vswitch-$(date +%Y%m%d-%H%M%S)"
        cidr=$1
        zone=$2
    else
        name=$1
        cidr=$2
        zone=$3
    fi

    # 如果未提供网段，自动分配
    if [ -z "$cidr" ]; then
        cidr=$(get_next_vswitch_cidr "$vpc_id")
    fi

    # 如果未提供可用区，自动选择
    if [ -z "$zone" ]; then
        echo "未指定可用区，正在获取可用区列表..."
        zone=$(select_zone)
        ret=$?
        if [ $ret -ne 0 ]; then
            return 1
        fi
    fi

    echo "创建交换机："
    echo "VPC ID: $vpc_id"
    echo "名称: $name"
    echo "网段: $cidr"
    echo "可用区: $zone"

    local result
    result=$(aliyun --profile "${profile:-}" vpc CreateVSwitch \
        --RegionId "$region" \
        --VpcId "$vpc_id" \
        --ZoneId "$zone" \
        --VSwitchName "$name" \
        --CidrBlock "$cidr")

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "交换机创建成功："
        echo "$result" | jq '.'
    else
        echo "错误：交换机创建失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "vpc" "vswitch-create" "$result"
}

vpc_vswitch_update() {
    local vswitch_id=$1 new_name=$2

    if [ -z "$vswitch_id" ] || [ -z "$new_name" ]; then
        echo "错误：交换机 ID 和新名称不能为空。" >&2
        return 1
    fi

    echo "更新交换机："
    local result
    result=$(aliyun --profile "${profile:-}" vpc ModifyVSwitchAttribute \
        --RegionId "$region" \
        --VSwitchId "$vswitch_id" \
        --VSwitchName "$new_name")

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "交换机更新成功："
        echo "$result" | jq '.'
    else
        echo "错误：交换机更新失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "vpc" "vswitch-update" "$result"
}

vpc_vswitch_delete() {
    local vswitch_id=$1

    if [ -z "$vswitch_id" ]; then
        echo "错误：交换机 ID 不能为空。" >&2
        return 1
    fi

    echo "警告：您即将删除交换机：$vswitch_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除交换机："
    local result
    result=$(aliyun --profile "${profile:-}" vpc DeleteVSwitch --VSwitchId "$vswitch_id" --RegionId "$region")
    ret=$?

    if [ $ret -eq 0 ]; then
        echo "交换机删除成功。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$vswitch_id" "交换机" "成功"
    else
        echo "交换机删除失败。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$vswitch_id" "交换机" "失败"
    fi

    echo "$result" | jq '.'
    log_result "${profile:-}" "$region" "vpc" "vswitch-delete" "$result"
}

# 修改 vpc_sg_list 函数
vpc_sg_list() {
    local vpc_id
    vpc_id=$(get_vpc_id "$1")
    ret=$?
    if [ $ret -ne 0 ]; then
        return 1
    fi

    local format=${2:-human}

    local result
    if ! result=$(aliyun --profile "${profile:-}" ecs DescribeSecurityGroups --VpcId "$vpc_id" --RegionId "$region"); then
        echo "错误：无法获取安全组列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result" | jq '.SecurityGroups.SecurityGroup'
        ;;
    tsv)
        echo -e "安全组ID\t名称\t描述\t创建时间"
        echo "$result" | jq -r '.SecurityGroups.SecurityGroup[] | [.SecurityGroupId, .SecurityGroupName, .Description, .CreationTime] | @tsv'
        ;;
    human | *)
        echo "列出安全组："
        if [[ $(echo "$result" | jq '.SecurityGroups.SecurityGroup | length') -eq 0 ]]; then
            echo "没有找到安全组。"
        else
            echo "安全组ID           名称                描述                          创建时间"
            echo "----------------   ------------------  ----------------------------  -------------------------"
            echo "$result" | jq -r '.SecurityGroups.SecurityGroup[] | [.SecurityGroupId, .SecurityGroupName, .Description, .CreationTime] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
            {
                printf "%-18s %-18s %-28s %s\n", $1, substr($2, 1, 14), $3, $4
            }'
        fi
        ;;
    esac
    log_result "${profile:-}" "$region" "vpc" "sg-list" "$result" "$format"
}

# 修改 vpc_sg_create 函数
vpc_sg_create() {
    local vpc_id
    vpc_id=$(get_vpc_id "$1")
    ret=$?
    if [ $ret -ne 0 ]; then
        return 1
    fi

    local name=$2 description=$3
    echo "创建安全组："
    local result
    result=$(aliyun --profile "${profile:-}" ecs CreateSecurityGroup \
        --RegionId "$region" \
        --VpcId "$vpc_id" \
        --SecurityGroupName "$name" \
        --Description "$description")

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "安全组创建成功："
        echo "$result" | jq '.'
    else
        echo "错误：安全组创建失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "vpc" "sg-create" "$result"
}

vpc_sg_update() {
    local sg_id=$1 new_name=$2 new_description=$3
    echo "更新安全组："
    local result
    result=$(aliyun --profile "${profile:-}" ecs ModifySecurityGroupAttribute \
        --RegionId "$region" \
        --SecurityGroupId "$sg_id" \
        --SecurityGroupName "$new_name" \
        --Description "$new_description")

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "安全组更新成功："
        echo "$result" | jq '.'
    else
        echo "错误：安全组更新失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "vpc" "sg-update" "$result"
}

vpc_sg_delete() {
    local sg_id=$1
    echo "警告：您即将删除安全组：$sg_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除安全组："
    local result
    result=$(aliyun --profile "${profile:-}" ecs DeleteSecurityGroup --SecurityGroupId "$sg_id" --RegionId "$region")
    ret=$?

    if [ $ret -eq 0 ]; then
        echo "安全组删除成功。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$sg_id" "安全组" "成功"
    else
        echo "安全组删除失败。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$sg_id" "安全组" "失败"
    fi

    echo "$result" | jq '.'
    log_result "${profile:-}" "$region" "vpc" "sg-delete" "$result"
}

vpc_sg_rule_list() {
    local sg_id=$1
    echo "列出安全组规则："
    echo "规则ID             方向    协议    端口范围    源/目标IP        优先级  创建时间"
    echo "----------------   ------  ------  ----------  ---------------  ------  -------------------------"
    local result
    if ! result=$(aliyun --profile "${profile:-}" ecs DescribeSecurityGroupAttribute --SecurityGroupId "${sg_id:? 安全组ID不能为空}" --RegionId "$region"); then
        echo "错误：无法获取安全组规则列表。请检查您的凭证和权限。" >&2
        return 1
    fi
    if [[ $(echo "$result" | jq '.Permissions.Permission | length') -eq 0 ]]; then
        echo "没有找到安全组规则。"
    else
        echo "$result" | jq -r '.Permissions.Permission[] | [.SecurityGroupRuleId, .Direction, .IpProtocol, .PortRange, (.SourceCidrIp // .DestCidrIp), .Priority, .CreateTime] | @tsv' |
            awk 'BEGIN {FS="\t"; OFS="\t"}
        {
            direction = ($2 == "ingress") ? "入方向" : "出方向";
            protocol = toupper($3);
            printf "%-18s %-7s %-7s %-11s %-16s %-7s %s\n", $1, direction, protocol, $4, $5, $6, $7
        }'
        log_result "${profile:-}" "$region" "vpc" "sg-rule-list" "$result"
    fi
}

vpc_sg_rule_add() {
    local sg_id=$1 protocol=$2 port_range=$3 source_ip=$4 description=$5
    echo "添加安全组规则："
    local result
    result=$(aliyun --profile "${profile:-}" ecs AuthorizeSecurityGroup \
        --RegionId "$region" \
        --SecurityGroupId "$sg_id" \
        --IpProtocol "$protocol" \
        --PortRange "$port_range" \
        --SourceCidrIp "$source_ip" \
        --NicType intranet \
        --Policy accept \
        --Priority 1 \
        --Description "$description")

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "安全组规则添加成功："
        echo "$result" | jq '.'
    else
        echo "错误：安全组规则添加失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "vpc" "sg-rule-add" "$result"
}

vpc_sg_rule_update() {
    local rule_id=$1 protocol=$2 port_range=$3 source_ip=$4
    echo "更新安全组规则："
    local result
    result=$(aliyun --profile "${profile:-}" ecs ModifySecurityGroupRule \
        --RegionId "$region" \
        --SecurityGroupRuleId "$rule_id" \
        --IpProtocol "$protocol" \
        --PortRange "$port_range" \
        --SourceCidrIp "$source_ip" \
        --NicType intranet \
        --Policy accept \
        --Priority 1)

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "安全组规则更新成功："
        echo "$result" | jq '.'
    else
        echo "错误：安全组规则更新失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "vpc" "sg-rule-update" "$result"
}

vpc_sg_rule_delete() {
    local rule_id=$1
    local sg_id=$2
    local direction=${3:-ingress}  # 默认为入方向规则

    if [ -z "$rule_id" ] || [ -z "$sg_id" ]; then
        echo "错误：安全组规则ID和安全组ID不能为空。" >&2
        echo "用法：vpc sg-rule-delete <规则ID> <安全组ID> [方向]" >&2
        return 1
    fi

    echo "警告：您即将删除安全组规则："
    echo "规则ID: $rule_id"
    echo "安全组ID: $sg_id"
    echo "方向: $direction"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除安全组规则："
    # aliyun ecs RevokeSecurityGroup --region cn-beijing --RegionId 'cn-beijing' \
    # --SecurityGroupId 'sg-2zegkxe7j1cgz2nb0bwq' --SecurityGroupRuleId.1 sgr-2zeh4twm100nruazjfnv -p ynvip
    local result
    if [ "$direction" = "ingress" ]; then
        result=$(aliyun --profile "${profile:-}" ecs RevokeSecurityGroup \
            --RegionId "$region" \
            --SecurityGroupId "$sg_id" \
            --SecurityGroupRuleId.1 "$rule_id")
    else
        result=$(aliyun --profile "${profile:-}" ecs RevokeSecurityGroupEgress \
            --RegionId "$region" \
            --SecurityGroupId "$sg_id" \
            --SecurityGroupRuleId.1 "$rule_id")
    fi
    ret=$?

    if [ $ret -eq 0 ]; then
        echo "安全组规则删除成功。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$rule_id" "安全组规则" "成功"
    else
        echo "安全组规则删除失败。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$rule_id" "安全组规则" "失败"
    fi

    echo "$result" | jq '.'
    log_result "${profile:-}" "$region" "vpc" "sg-rule-delete" "$result"
}

# 添加新的函数来处理 IPv6 网关操作
vpc_ipv6gw_list() {
    local vpc_id=$1
    echo "列出 IPv6 网关："
    local result
    result=$(aliyun --profile "${profile:-}" vpc DescribeIpv6Gateways --VpcId "$vpc_id" --RegionId "$region")
    echo "$result" | jq -r '.Ipv6Gateways.Ipv6Gateway[] | [.Ipv6GatewayId, .Name, .Status, .Spec, .BusinessStatus, .CreationTime] | @tsv' |
        awk 'BEGIN {FS="\t"; OFS="\t"}
        {
            printf "%-20s %-20s %-10s %-10s %-15s %s\n", $1, $2, $3, $4, $5, $6
        }'
    log_result "${profile:-}" "$region" "vpc" "ipv6gw-list" "$result"
}

vpc_ipv6gw_create() {
    local vpc_id=$1 name=$2 spec=${3:-Small}
    echo "创建 IPv6 网关："
    local result
    result=$(aliyun --profile "${profile:-}" vpc CreateIpv6Gateway --VpcId "$vpc_id" --Name "$name" --Spec "$spec" --RegionId "$region")
    echo "$result" | jq '.'
    log_result "${profile:-}" "$region" "vpc" "ipv6gw-create" "$result"
}

vpc_ipv6gw_update() {
    local ipv6gw_id=$1 name=$2 spec=$3
    echo "更新 IPv6 网关："
    local result
    result=$(aliyun --profile "${profile:-}" vpc ModifyIpv6GatewayAttribute --Ipv6GatewayId "$ipv6gw_id" --Name "$name" --Spec "$spec" --RegionId "$region")
    echo "$result" | jq '.'
    log_result "${profile:-}" "$region" "vpc" "ipv6gw-update" "$result"
}

vpc_ipv6gw_delete() {
    local ipv6gw_id=$1
    echo "警告：您即将删除 IPv6 网关：$ipv6gw_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 IPv6 网关："
    local result
    result=$(aliyun --profile "${profile:-}" vpc DeleteIpv6Gateway --Ipv6GatewayId "$ipv6gw_id" --RegionId "$region")
    local status=$?

    if [ $status -eq 0 ]; then
        echo "IPv6 网关删除成功。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$ipv6gw_id" "IPv6网关" "成功"
    else
        echo "IPv6 网关删除失败。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$ipv6gw_id" "IPv6网关" "失败"
    fi

    echo "$result" | jq '.'
    log_result "${profile:-}" "$region" "vpc" "ipv6gw-delete" "$result"
}

