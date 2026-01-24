#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# VPC (专有网络) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_vpc_help() {
    echo "VPC 操作："
    echo "  all                                     - 列出所有 VPC 相关资源"
    echo "  list [format]                           - 列出 VPC"
    echo "  create [名称] [网段] [disable_ipv6]    - 创建 VPC (自动生成名称，默认网段: 192.168.0.0/16)"
    echo "  update <VPC-ID> <新名称>                - 更新 VPC"
    echo "  delete <VPC-ID>                        - 删除 VPC"
    echo "  vswitch-list <VPC-ID> [format]          - 列出交换机"
    echo "  vswitch-create [VPC-ID] [名称] [网段] [可用区] - 创建交换机"
    echo "  vswitch-update <交换机ID> <新名称>     - 更新交换机"
    echo "  vswitch-delete <交换机ID>              - 删除交换机"
    echo "  sg-list <VPC-ID> [format]              - 列出安全组"
    echo "  sg-create <VPC-ID> <名称> <描述>       - 创建安全组"
    echo "  sg-update <安全组ID> <新名称> <新描述>  - 更新安全组"
    echo "  sg-delete <安全组ID>                    - 删除安全组"
    echo "  sg-rule-list <安全组ID>                  - 列出安全组规则"
    echo "  sg-rule-add <安全组ID> <协议> <端口范围> <源IP> <描述> - 添加安全组规则"
    echo "  sg-rule-update <安全组规则ID> <协议> <端口范围> <源IP> - 更新安全组规则"
    echo "  sg-rule-delete <规则ID> <安全组ID> [方向] - 删除安全组规则"
    echo "  ipv6gw-list <VPC-ID>                   - 列出 IPv6 网关"
    echo "  ipv6gw-create <VPC-ID> <名称> [规格]   - 创建 IPv6 网关"
    echo "  ipv6gw-update <IPv6网关ID> <新名称> [新规格] - 更新 IPv6 网关"
    echo "  ipv6gw-delete <IPv6网关ID>              - 删除 IPv6 网关"
    echo
    echo "示例："
    echo "  $0 vpc list"
    echo "  $0 vpc create"
    echo "  $0 vpc create my-vpc 10.0.0.0/8"
    echo "  $0 vpc update vpc-xxx new-name"
    echo "  $0 vpc delete vpc-xxx"
}

handle_vpc_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    all) vpc_list_all "$@" ;;
    list) vpc_list "$@" ;;
    create) vpc_create "$@" ;;
    update) vpc_update "$@" ;;
    delete) vpc_delete "$@" ;;
    vswitch-list) vpc_vswitch_list "$@" ;;
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
    help) show_vpc_help ;;
    *)
        echo "错误：未知的 VPC 操作：$operation" >&2
        show_vpc_help
        exit 1
        ;;
    esac
}

# 列出所有 VPC 相关资源（保持原有逻辑）
vpc_list_all() {
    echo "列出所有 VPC 相关资源："
    vpc_list "$@"

    local vpc_ids
    vpc_ids=$(call_aliyun_api vpc DescribeVpcs --RegionId "${region:-}" | jq -r '.Vpcs.Vpc[].VpcId')

    for vpc_id in $vpc_ids; do
        echo "VPC ID: $vpc_id 的资源："
        echo "交换机："
        vpc_vswitch_list "$vpc_id" "$@"
        echo "安全组："
        vpc_sg_list "$vpc_id" "$@"
        echo "IPv6 网关："
        vpc_ipv6gw_list "$vpc_id" "$@"
        echo "----------------------------------------"
    done
}

# 使用新框架的 VPC 列表函数
vpc_list() {
    local format=${1:-human}

    local table_header="VpcId\tVpcName\tStatus\tCidrBlock\tCreationTime"
    local jq_filter=".Vpcs.Vpc[] | [.VpcId, .VpcName, .Status, .CidrBlock, .CreationTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-18s  %-6s  %-14s  %s\n", $1, $2, $3, $4, $5}'

    generic_list \
        "vpc" \
        "DescribeVpcs" \
        "vpc" \
        "$format" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 VPC。" \
        "列出 VPC："
}

# 使用新框架的创建函数
vpc_create() {
    local name=$1 cidr=$2 enable_ipv6=$3

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$name" ] || [ -z "$cidr" ] || [ -z "$enable_ipv6" ]; then
        echo "使用 fzf 交互式模式创建 VPC"

        # 输入名称
        if [ -z "$name" ]; then
            read -r -p "请输入 VPC 名称 (留空自动生成): " name
            if [ -z "$name" ]; then
                name="vpc-$(date +%Y%m%d-%H%M%S)"
                echo "自动生成 VPC 名称: $name"
            fi
        fi

        # 选择网段
        if [ -z "$cidr" ]; then
            echo "正在检查可用的 VPC 网段..."
            local existing_vpcs
            existing_vpcs=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region" 2>/dev/null | jq -r '.Vpcs.Vpc[] | .CidrBlock' 2>/dev/null)

            # 构建推荐网段列表，避免与现有VPC冲突
            local cidr_list="10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
10.1.0.0/16
172.20.0.0/16
192.169.0.0/16
10.100.0.0/16
172.21.0.0/16
192.170.0.0/16"

            if [ -n "$existing_vpcs" ] && [ "$existing_vpcs" != "null" ]; then
                echo "检测到现有VPC网段，请选择不冲突的网段："
                echo "$existing_vpcs" | sed 's/^/  已使用: /'
            fi

            if type select_with_fzf >/dev/null 2>&1; then
                cidr=$(select_with_fzf "选择 VPC 网段" "$cidr_list")
            else
                cidr="192.168.0.0/16"
                echo "使用默认网段: $cidr"
            fi
        fi

        # 选择是否启用 IPv6
        if [ -z "$enable_ipv6" ]; then
            # 检查当前区域是否支持IPv6
            local ipv6_support
            ipv6_support=$(call_aliyun_api vpc DescribeRegions --RegionId "$region" 2>/dev/null | jq -r '.Regions.Region[] | select(.RegionId == "'$region'") | .Ipv6Enabled' 2>/dev/null)

            local ipv6_list="true
false"
            if [ "$ipv6_support" = "true" ]; then
                echo "当前区域支持IPv6。"
            else
                echo "当前区域可能不支持IPv6，仍可选择但可能失败。"
            fi

            if type select_with_fzf >/dev/null 2>&1; then
                enable_ipv6=$(select_with_fzf "是否启用 IPv6" "$ipv6_list")
            else
                enable_ipv6="true"
                echo "默认启用 IPv6"
            fi
        fi
    else
        # 如果提供了名称为空，则自动生成
        if [ -z "$name" ]; then
            name="vpc-$(date +%Y%m%d-%H%M%S)"
            echo "未提供 VPC 名称，自动生成: $name"
        fi
    fi

    echo "创建 VPC："
    local result
    result=$(call_aliyun_api vpc CreateVpc \
        --RegionId "$region" \
        --VpcName "$name" \
        --CidrBlock "$cidr" \
        --EnableIpv6 "$enable_ipv6")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "create" "$result"
    else
        echo "错误：VPC 创建失败。"
        echo "$result"
        return 1
    fi
}

# 使用新框架的更新函数
vpc_update() {
    local vpc_id=$1 new_name=$2

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$vpc_id" ] || [ -z "$new_name" ]; then
        echo "使用 fzf 交互式模式更新 VPC"

        # 选择 VPC ID
        if [ -z "$vpc_id" ]; then
            local vpc_list
            vpc_list=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region" 2>/dev/null | jq -r '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"')

            if [ -z "$vpc_list" ]; then
                echo "错误：没有找到 VPC。" >&2
                return 1
            elif [ "$(echo "$vpc_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
                vpc_id=$(echo "$vpc_list" | awk '{print $1}')
                echo "自动选择唯一的 VPC: $vpc_id"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    vpc_id=$(select_with_fzf "选择 VPC" "$vpc_list" | awk '{print $1}')
                else
                    echo "错误：需要选择 VPC，但未找到交互式选择工具。" >&2
                    return 1
                fi
            fi
        fi

        # 输入新名称
        if [ -z "$new_name" ]; then
            read -r -p "请输入新的 VPC 名称: " new_name
            if [ -z "$new_name" ]; then
                echo "错误：新名称不能为空。" >&2
                return 1
            fi
        fi
    fi

    if ! validate_required_params "$vpc_id" "$new_name" "错误：VPC ID 和新名称不能为空。"; then
        return 1
    fi

    echo "更新 VPC："
    local result
    result=$(call_aliyun_api vpc ModifyVpcAttribute \
        --VpcId "$vpc_id" \
        --VpcName "$new_name")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "update" "$result"
    else
        echo "错误：VPC 更新失败。"
        echo "$result"
        return 1
    fi
}

# 使用新框架的删除函数
vpc_delete() {
    local vpc_id=$1

    # 如果没有提供 VPC ID，则使用 fzf 交互式选择
    if [ -z "$vpc_id" ]; then
        echo "使用 fzf 交互式模式删除 VPC"

        local vpc_list
        vpc_list=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region" 2>/dev/null | jq -r '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"')

        if [ -z "$vpc_list" ]; then
            echo "错误：没有找到 VPC。" >&2
            return 1
        elif [ "$(echo "$vpc_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            vpc_id=$(echo "$vpc_list" | awk '{print $1}')
            echo "自动选择唯一的 VPC: $vpc_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                vpc_id=$(select_with_fzf "选择要删除的 VPC" "$vpc_list" | awk '{print $1}')
            else
                echo "错误：需要选择 VPC，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    if [ -z "$vpc_id" ]; then
        echo "错误：VPC ID 不能为空。" >&2
        return 1
    fi

    # 检查 VPC 是否存在
    local vpc_info
    vpc_info=$(call_aliyun_api vpc DescribeVpcs --VpcId "$vpc_id" --RegionId "$region" 2>/dev/null)
    if [ $? -ne 0 ] || [ "$(echo "$vpc_info" | jq '.Vpcs.Vpc | length')" -eq 0 ]; then
        echo "错误：VPC $vpc_id 不存在或无法访问。" >&2
        return 1
    fi

    local vpc_name cidr_block
    vpc_name=$(echo "$vpc_info" | jq -r '.Vpcs.Vpc[0].VpcName')
    cidr_block=$(echo "$vpc_info" | jq -r '.Vpcs.Vpc[0].CidrBlock')

    echo "警告：您即将删除以下 VPC："
    echo "  VPC ID: $vpc_id"
    echo "  名称: $vpc_name"
    echo "  网段: $cidr_block"
    echo "  地域: $region"

    if ! confirm_action "删除 VPC：$vpc_id"; then
        return 1
    fi

    echo "删除 VPC："
    local result
    result=$(call_aliyun_api vpc DeleteVpc --VpcId "$vpc_id" --RegionId "$region")

    if [ $? -eq 0 ]; then
        echo "VPC 删除成功。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$vpc_id" "VPC" "成功"
    else
        echo "VPC 删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "vpc" "$vpc_id" "VPC" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "vpc" "delete" "$result"
}

# 辅助函数：获取 VPC ID（保持原有逻辑）
get_vpc_id() {
    local specified_vpc_id=$1
    if [ -n "$specified_vpc_id" ]; then
        echo "$specified_vpc_id"
        return 0
    fi

    local result
    result=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region")
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

# 交换机列表（使用框架函数）
vpc_vswitch_list() {
    local vpc_id
    vpc_id=$(get_vpc_id "$1")
    if [ $? -ne 0 ]; then
        return 1
    fi

    local format=${2:-human}

    local table_header="VSwitchId\tVSwitchName\tStatus\tZoneId\tCidrBlock\tCreationTime"
    local jq_filter=".VSwitches.VSwitch[] | [.VSwitchId, .VSwitchName, .Status, .ZoneId, .CidrBlock, .CreationTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s %-18s %-6s %-14s %-14s %s\n", $1, $2, $3, $4, $5, $6}'

    local result
    result=$(call_aliyun_api vpc DescribeVSwitches --VpcId "$vpc_id" --RegionId "$region")

    if [ $? -ne 0 ]; then
        echo "错误：无法获取交换机列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "vpc" \
        "vswitch-list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到交换机。" \
        "列出交换机："
}

# 获取下一个可用的交换机网段（保持原有逻辑）
get_next_vswitch_cidr() {
    local vpc_id=$1
    local result
    result=$(call_aliyun_api vpc DescribeVSwitches --VpcId "$vpc_id" --RegionId "$region")

    local used_cidrs
    used_cidrs=$(echo "$result" | jq -r '.VSwitches.VSwitch[].CidrBlock' | sort)

    if [ -z "$used_cidrs" ]; then
        echo "192.168.50.0/24"
        return 0
    fi

    local last_cidr
    last_cidr=$(echo "$used_cidrs" | tail -n 1)

    if ! [[ $last_cidr =~ ^192\.168\.([0-9]+)\.0/24$ ]]; then
        echo "192.168.50.0/24"
        return 0
    fi

    local next_octet
    next_octet=$((${BASH_REMATCH[1]} + 1))
    echo "192.168.${next_octet}.0/24"
}

# 选择可用区（保持原有逻辑）
select_zone() {
    local zones
    zones=$(call_aliyun_api ecs DescribeZones --RegionId "$region" | jq -r '.Zones.Zone[].ZoneId' | grep -v '[[:space:]]')

    local zone_count
    zone_count=$(echo "$zones" | grep -v '[[:space:]]' -c)
    if [ "$zone_count" -eq 1 ]; then
        echo "$zones" | cut -f1
        return 0
    fi

    local selected_zone
    if type fzf >/dev/null 2>&1; then
        selected_zone=$(echo "$zones" | fzf --height=10 --prompt="请选择可用区: " | cut -f1)
    else
        selected_zone=$(echo "$zones" | head -1)
    fi

    if [ -z "$selected_zone" ]; then
        echo "错误：未选择可用区。" >&2
        return 1
    fi

    echo "$selected_zone"
}

# 创建交换机（保持原有逻辑，但使用框架函数）
vpc_vswitch_create() {
    local vpc_id
    if [ -z "$1" ] || [ "$1" = "--auto" ]; then
        vpc_id=$(get_vpc_id)
        if [ $? -ne 0 ]; then
            return 1
        fi
        shift
    else
        vpc_id=$1
        shift
    fi

    local name cidr zone

    if [ -z "$1" ] || [[ "$1" =~ ^[0-9] ]]; then
        name="vswitch-$(date +%Y%m%d-%H%M%S)"
        cidr=$1
        zone=$2
    else
        name=$1
        cidr=$2
        zone=$3
    fi

    if [ -z "$cidr" ]; then
        cidr=$(get_next_vswitch_cidr "$vpc_id")
    fi

    if [ -z "$zone" ]; then
        echo "未指定可用区，正在获取可用区列表..."
        zone=$(select_zone)
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    echo "创建交换机："
    echo "VPC ID: $vpc_id"
    echo "名称: $name"
    echo "网段: $cidr"
    echo "可用区: $zone"

    local result
    result=$(call_aliyun_api vpc CreateVSwitch \
        --RegionId "$region" \
        --VpcId "$vpc_id" \
        --ZoneId "$zone" \
        --VSwitchName "$name" \
        --CidrBlock "$cidr")

    if [ $? -eq 0 ]; then
        echo "交换机创建成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "vswitch-create" "$result"
    else
        echo "错误：交换机创建失败。"
        echo "$result"
        return 1
    fi
}

# 更新交换机（使用框架函数）
vpc_vswitch_update() {
    local vswitch_id=$1 new_name=$2

    if ! validate_required_params "$vswitch_id" "$new_name" "错误：交换机 ID 和新名称不能为空。"; then
        return 1
    fi

    echo "更新交换机："
    local result
    result=$(call_aliyun_api vpc ModifyVSwitchAttribute \
        --RegionId "$region" \
        --VSwitchId "$vswitch_id" \
        --VSwitchName "$new_name")

    if [ $? -eq 0 ]; then
        echo "交换机更新成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "vswitch-update" "$result"
    else
        echo "错误：交换机更新失败。"
        echo "$result"
        return 1
    fi
}

# 删除交换机（使用框架函数）
vpc_vswitch_delete() {
    local vswitch_id=$1

    if [ -z "$vswitch_id" ]; then
        echo "错误：交换机 ID 不能为空。" >&2
        return 1
    fi

    if ! confirm_action "删除交换机：$vswitch_id"; then
        return 1
    fi

    echo "删除交换机："
    local result
    result=$(call_aliyun_api vpc DeleteVSwitch --VSwitchId "$vswitch_id" --RegionId "$region")

    if [ $? -eq 0 ]; then
        echo "交换机删除成功。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$vswitch_id" "交换机" "成功"
    else
        echo "交换机删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "vpc" "$vswitch_id" "交换机" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "vpc" "vswitch-delete" "$result"
}

# 安全组列表（使用框架函数）
vpc_sg_list() {
    local vpc_id
    vpc_id=$(get_vpc_id "$1")
    if [ $? -ne 0 ]; then
        return 1
    fi

    local format=${2:-human}

    local table_header="SecurityGroupId\tSecurityGroupName\tDescription\tCreationTime"
    local jq_filter=".SecurityGroups.SecurityGroup[] | [.SecurityGroupId, .SecurityGroupName, .Description, .CreationTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s %-18s %-28s %s\n", $1, substr($2, 1, 14), $3, $4}'

    local result
    result=$(call_aliyun_api ecs DescribeSecurityGroups --VpcId "$vpc_id" --RegionId "$region")

    if [ $? -ne 0 ]; then
        echo "错误：无法获取安全组列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "vpc" \
        "sg-list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到安全组。" \
        "列出安全组："
}

# 创建安全组（使用框架函数）
vpc_sg_create() {
    local vpc_id
    vpc_id=$(get_vpc_id "$1")
    if [ $? -ne 0 ]; then
        return 1
    fi

    local name=$2 description=$3

    if ! validate_required_params "$name" "$description" "错误：名称和描述不能为空。"; then
        return 1
    fi

    echo "创建安全组："
    local result
    result=$(call_aliyun_api ecs CreateSecurityGroup \
        --RegionId "$region" \
        --VpcId "$vpc_id" \
        --SecurityGroupName "$name" \
        --Description "$description")

    if [ $? -eq 0 ]; then
        echo "安全组创建成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "sg-create" "$result"
    else
        echo "错误：安全组创建失败。"
        echo "$result"
        return 1
    fi
}

# 更新安全组（使用框架函数）
vpc_sg_update() {
    local sg_id=$1 new_name=$2 new_description=$3

    if ! validate_required_params "$sg_id" "$new_name" "$new_description" "错误：安全组ID、新名称和新描述不能为空。"; then
        return 1
    fi

    echo "更新安全组："
    local result
    result=$(call_aliyun_api ecs ModifySecurityGroupAttribute \
        --RegionId "$region" \
        --SecurityGroupId "$sg_id" \
        --SecurityGroupName "$new_name" \
        --Description "$new_description")

    if [ $? -eq 0 ]; then
        echo "安全组更新成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "sg-update" "$result"
    else
        echo "错误：安全组更新失败。"
        echo "$result"
        return 1
    fi
}

# 删除安全组（使用框架函数）
vpc_sg_delete() {
    local sg_id=$1

    if [ -z "$sg_id" ]; then
        echo "错误：安全组 ID 不能为空。" >&2
        return 1
    fi

    if ! confirm_action "删除安全组：$sg_id"; then
        return 1
    fi

    echo "删除安全组："
    local result
    result=$(call_aliyun_api ecs DeleteSecurityGroup --SecurityGroupId "$sg_id" --RegionId "$region")

    if [ $? -eq 0 ]; then
        echo "安全组删除成功。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$sg_id" "安全组" "成功"
    else
        echo "安全组删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "vpc" "$sg_id" "安全组" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "vpc" "sg-delete" "$result"
}

# 安全组规则列表（保持原有逻辑，但使用框架函数）
vpc_sg_rule_list() {
    local sg_id=$1

    if [ -z "$sg_id" ]; then
        echo "错误：安全组ID不能为空。" >&2
        return 1
    fi

    echo "列出安全组规则："
    echo "规则ID             方向    协议    端口范围    源/目标IP        优先级  创建时间"
    echo "----------------   ------  ------  ----------  ---------------  ------  -------------------------"

    local result
    result=$(call_aliyun_api ecs DescribeSecurityGroupAttribute \
        --SecurityGroupId "$sg_id" \
        --RegionId "$region")

    if [ $? -ne 0 ]; then
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
    fi

    log_result "${profile:-}" "$region" "vpc" "sg-rule-list" "$result"
}

# 添加安全组规则（使用框架函数）
vpc_sg_rule_add() {
    local sg_id=$1 protocol=$2 port_range=$3 source_ip=$4 description=$5

    if ! validate_required_params "$sg_id" "$protocol" "$port_range" "$source_ip" "错误：安全组ID、协议、端口范围和源IP不能为空。"; then
        return 1
    fi

    echo "添加安全组规则："
    local result
    result=$(call_aliyun_api ecs AuthorizeSecurityGroup \
        --RegionId "$region" \
        --SecurityGroupId "$sg_id" \
        --IpProtocol "$protocol" \
        --PortRange "$port_range" \
        --SourceCidrIp "$source_ip" \
        --NicType intranet \
        --Policy accept \
        --Priority 1 \
        --Description "${description:-}")

    if [ $? -eq 0 ]; then
        echo "安全组规则添加成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "sg-rule-add" "$result"
    else
        echo "错误：安全组规则添加失败。"
        echo "$result"
        return 1
    fi
}

# 更新安全组规则（使用框架函数）
vpc_sg_rule_update() {
    local rule_id=$1 protocol=$2 port_range=$3 source_ip=$4

    if ! validate_required_params "$rule_id" "$protocol" "$port_range" "$source_ip" "错误：规则ID、协议、端口范围和源IP不能为空。"; then
        return 1
    fi

    echo "更新安全组规则："
    local result
    result=$(call_aliyun_api ecs ModifySecurityGroupRule \
        --RegionId "$region" \
        --SecurityGroupRuleId "$rule_id" \
        --IpProtocol "$protocol" \
        --PortRange "$port_range" \
        --SourceCidrIp "$source_ip" \
        --NicType intranet \
        --Policy accept \
        --Priority 1)

    if [ $? -eq 0 ]; then
        echo "安全组规则更新成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "sg-rule-update" "$result"
    else
        echo "错误：安全组规则更新失败。"
        echo "$result"
        return 1
    fi
}

# 删除安全组规则（使用框架函数）
vpc_sg_rule_delete() {
    local rule_id=$1 sg_id=$2 direction=${3:-ingress}

    if ! validate_required_params "$rule_id" "$sg_id" "错误：安全组规则ID和安全组ID不能为空。"; then
        return 1
    fi

    echo "警告：您即将删除安全组规则："
    echo "规则ID: $rule_id"
    echo "安全组ID: $sg_id"
    echo "方向: $direction"

    if ! confirm_action "删除安全组规则：$rule_id"; then
        return 1
    fi

    echo "删除安全组规则："
    local result
    if [ "$direction" = "ingress" ]; then
        result=$(call_aliyun_api ecs RevokeSecurityGroup \
            --RegionId "$region" \
            --SecurityGroupId "$sg_id" \
            --SecurityGroupRuleId.1 "$rule_id")
    else
        result=$(call_aliyun_api ecs RevokeSecurityGroupEgress \
            --RegionId "$region" \
            --SecurityGroupId "$sg_id" \
            --SecurityGroupRuleId.1 "$rule_id")
    fi

    if [ $? -eq 0 ]; then
        echo "安全组规则删除成功。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$rule_id" "安全组规则" "成功"
    else
        echo "安全组规则删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "vpc" "$rule_id" "安全组规则" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "vpc" "sg-rule-delete" "$result"
}

# IPv6 网关列表（使用框架函数）
vpc_ipv6gw_list() {
    local vpc_id=$1

    if [ -z "$vpc_id" ]; then
        echo "错误：VPC ID 不能为空。" >&2
        return 1
    fi

    echo "列出 IPv6 网关："
    local result
    result=$(call_aliyun_api vpc DescribeIpv6Gateways --VpcId "$vpc_id" --RegionId "$region")

    if [ $? -ne 0 ]; then
        echo "错误：无法获取 IPv6 网关列表。" >&2
        return 1
    fi

    if [[ $(echo "$result" | jq '.Ipv6Gateways.Ipv6Gateway | length') -eq 0 ]]; then
        echo "没有找到 IPv6 网关。"
    else
        echo "IPv6网关ID          名称                状态      规格      业务状态    创建时间"
        echo "$result" | jq -r '.Ipv6Gateways.Ipv6Gateway[] | [.Ipv6GatewayId, .Name, .Status, .Spec, .BusinessStatus, .CreationTime] | @tsv' |
            awk 'BEGIN {FS="\t"; OFS="\t"} {printf "%-20s %-20s %-10s %-10s %-15s %s\n", $1, $2, $3, $4, $5, $6}'
    fi

    log_result "${profile:-}" "$region" "vpc" "ipv6gw-list" "$result"
}

# 创建 IPv6 网关（使用框架函数）
vpc_ipv6gw_create() {
    local vpc_id=$1 name=$2 spec=${3:-Small}

    if ! validate_required_params "$vpc_id" "$name" "错误：VPC ID 和名称不能为空。"; then
        return 1
    fi

    echo "创建 IPv6 网关："
    local result
    result=$(call_aliyun_api vpc CreateIpv6Gateway \
        --VpcId "$vpc_id" \
        --Name "$name" \
        --Spec "$spec" \
        --RegionId "$region")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "ipv6gw-create" "$result"
    else
        echo "错误：IPv6 网关创建失败。"
        echo "$result"
        return 1
    fi
}

# 更新 IPv6 网关（使用框架函数）
vpc_ipv6gw_update() {
    local ipv6gw_id=$1 name=$2 spec=$3

    if ! validate_required_params "$ipv6gw_id" "$name" "错误：IPv6 网关ID 和名称不能为空。"; then
        return 1
    fi

    echo "更新 IPv6 网关："
    local api_args=(
        "--Ipv6GatewayId" "$ipv6gw_id"
        "--Name" "$name"
        "--RegionId" "$region"
    )

    if [ -n "$spec" ]; then
        api_args+=("--Spec" "$spec")
    fi

    local result
    result=$(call_aliyun_api vpc ModifyIpv6GatewayAttribute "${api_args[@]}")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "ipv6gw-update" "$result"
    else
        echo "错误：IPv6 网关更新失败。"
        echo "$result"
        return 1
    fi
}

# 删除 IPv6 网关（使用框架函数）
vpc_ipv6gw_delete() {
    local ipv6gw_id=$1

    if [ -z "$ipv6gw_id" ]; then
        echo "错误：IPv6 网关 ID 不能为空。" >&2
        return 1
    fi

    if ! confirm_action "删除 IPv6 网关：$ipv6gw_id"; then
        return 1
    fi

    echo "删除 IPv6 网关："
    local result
    result=$(call_aliyun_api vpc DeleteIpv6Gateway --Ipv6GatewayId "$ipv6gw_id" --RegionId "$region")

    if [ $? -eq 0 ]; then
        echo "IPv6 网关删除成功。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$ipv6gw_id" "IPv6网关" "成功"
    else
        echo "IPv6 网关删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "vpc" "$ipv6gw_id" "IPv6网关" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "vpc" "ipv6gw-delete" "$result"
}
