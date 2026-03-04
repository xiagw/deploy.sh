#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# VPC (专有网络) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_vpc_help() {
    echo "VPC (虚拟私有云) 操作："
    echo "  get [<VPC-ID>] [format]                  - 列出 VPC 或指定 VPC 的详细信息（VPC-ID可选，可使用fzf选择）"
    echo "  add <名称> [网段] [enable_ipv6]          - 创建 VPC (名称可选，自动生成；网段默认: 192.168.0.0/16)"
    echo "  set [<VPC-ID>] [<新名称>]               - 更新 VPC (VPC-ID和新名称都是可选的，可使用fzf选择)"
    echo "  del [<VPC-ID>]                          - 删除 VPC (VPC-ID可选，可使用fzf选择)"
    echo "  vsw-get [<VPC-ID>] [format]             - 列出交换机 (VPC-ID可选，可使用fzf选择)"
    echo "  vsw-add [<VPC-ID>] [名称] [网段] [可用区] - 创建交换机 (VPC-ID可选，可使用fzf选择)"
    echo "  vsw-set <交换机ID> <新名称>              - 更新交换机"
    echo "  vsw-del <交换机ID>                       - 删除交换机"
    echo "  sg-get [<VPC-ID>] [format]              - 列出安全组 (VPC-ID可选，可使用fzf选择)"
    echo "  sg-add <VPC-ID> <名称> <描述>           - 创建安全组"
    echo "  sg-set <安全组ID> <新名称> <新描述>      - 更新安全组"
    echo "  sg-del <安全组ID>                        - 删除安全组"
    echo "  sg-rule-get <安全组ID>                   - 列出安全组规则"
    echo "  sg-rule-add <安全组ID> <协议> <端口范围> <源IP> <描述> - 添加安全组规则"
    echo "  sg-rule-set <规则ID> <协议> <端口范围> <源IP> - 更新安全组规则"
    echo "  sg-rule-del <规则ID> <安全组ID> [方向]   - 删除安全组规则"
    echo "  ipv6gw-get [<VPC-ID>]                   - 列出 IPv6 网关 (VPC-ID可选，可使用fzf选择)"
    echo "  ipv6gw-add <VPC-ID> <名称> [规格]       - 创建 IPv6 网关"
    echo "  ipv6gw-set <IPv6网关ID> <新名称> [新规格] - 更新 IPv6 网关"
    echo "  ipv6gw-del <IPv6网关ID>                  - 删除 IPv6 网关"
    echo
    echo "示例："
    echo "  $0 vpc get"
    echo "  $0 vpc get vpc-xxx"
    echo "  $0 vpc get json"
    echo "  $0 vpc add"
    echo "  $0 vpc add my-vpc 10.0.0.0/8"
    echo "  $0 vpc set vpc-xxx new-name"
    echo "  $0 vpc del vpc-xxx"
    echo "  $0 vpc vsw-get vpc-xxx"
    echo "  $0 vpc vsw-get vpc-xxx json"
    echo "  $0 vpc vsw-add vpc-xxx my-vswitch 10.0.1.0/24 cn-hangzhou-a"
    echo "  $0 vpc vsw-set vsw-xxx new-name"
    echo "  $0 vpc vsw-del vsw-xxx"
    echo "  $0 vpc sg-get vpc-xxx"
    echo "  $0 vpc sg-get vpc-xxx json"
    echo "  $0 vpc sg-add vpc-xxx my-sg '安全组描述'"
    echo "  $0 vpc sg-set sg-xxx new-name '新描述'"
    echo "  $0 vpc sg-del sg-xxx"
    echo "  $0 vpc sg-rule-get sg-xxx"
    echo "  $0 vpc sg-rule-add sg-xxx tcp 80/80 0.0.0.0/0 '开放80端口'"
    echo "  $0 vpc sg-rule-set rule-xxx tcp 443/443 0.0.0.0/0"
    echo "  $0 vpc sg-rule-del rule-xxx sg-xxx ingress"
    echo "  $0 vpc ipv6gw-get vpc-xxx"
    echo "  $0 vpc ipv6gw-add vpc-xxx my-ipv6gw Small"
    echo "  $0 vpc ipv6gw-set ipv6gw-xxx new-name Medium"
    echo "  $0 vpc ipv6gw-del ipv6gw-xxx"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_vpc_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    all) vpc_list_all "$@" ;;
    get) vpc_list "$@" ;;
    add) vpc_create "$@" ;;
    set) vpc_update "$@" ;;
    del) vpc_delete "$@" ;;
    vsw-get) vpc_vswitch_list "$@" ;;
    vsw-add) vpc_vswitch_create "$@" ;;
    vsw-set) vpc_vswitch_update "$@" ;;
    vsw-del) vpc_vswitch_delete "$@" ;;
    sg-get) vpc_sg_list "$@" ;;
    sg-add) vpc_sg_create "$@" ;;
    sg-set) vpc_sg_update "$@" ;;
    sg-del) vpc_sg_delete "$@" ;;
    sg-rule-get) vpc_sg_rule_list "$@" ;;
    sg-rule-add) vpc_sg_rule_add "$@" ;;
    sg-rule-set) vpc_sg_rule_set "$@" ;;
    sg-rule-del) vpc_sg_rule_delete "$@" ;;
    ipv6gw-get) vpc_ipv6gw_list "$@" ;;
    ipv6gw-add) vpc_ipv6gw_create "$@" ;;
    ipv6gw-set) vpc_ipv6gw_update "$@" ;;
    ipv6gw-del) vpc_ipv6gw_delete "$@" ;;
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
    local vpc_id=$1
    local format=${2:-human}

    # 如果提供了 VPC ID，则获取特定 VPC 的详细信息
    if [ -n "$vpc_id" ]; then
        local result
        result=$(call_aliyun_api vpc DescribeVpcs --VpcId "$vpc_id" --RegionId "$region")

        if [ $? -ne 0 ]; then
            echo "错误：无法获取 VPC 详细信息。请检查您的凭证和权限。" >&2
            return 1
        fi

        case "$format" in
        json)
            # 直接输出原始结果
            echo "$result"
            ;;
        tsv)
            # TSV 格式
            echo -e "VpcId\tVpcName\tStatus\tCidrBlock\tRegionId\tCreationTime"
            echo "$result" | jq -r '.Vpcs.Vpc[] | [.VpcId, .VpcName, .Status, .CidrBlock, .RegionId, .CreationTime] | @tsv'
            ;;
        human | *)
            # 人类可读格式
            echo "VPC 详细信息："
            if [[ $(echo "$result" | jq '.Vpcs.Vpc | length') -eq 0 ]]; then
                echo "没有找到指定的 VPC。"
            else
                echo "VPC ID            名称                状态    CIDR          地域          创建时间"
                echo "----------------  ------------------  ------  ------------  ------------  -------------------------"
                echo "$result" | jq -r '.Vpcs.Vpc[] | [.VpcId, .VpcName, .Status, .CidrBlock, .RegionId, .CreationTime] | @tsv' |
                    awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    status = $3;
                    if (status == "Available") status = "可用";
                    else if (status == "Creating") status = "创建中";
                    else if (status == "Deleting") status = "删除中";
                    else if (status == "Updating") status = "更新中";
                    else status = "未知";
                    printf "%-16s  %-18s  %-6s  %-12s  %-12s  %s\n", $1, $2, status, $4, $5, $6
                }'
            fi
            ;;
        esac
        log_result "${profile:-}" "$region" "vpc" "get" "$result" "$format"
        return
    fi

    # 如果没有提供 VPC ID，则列出所有 VPC
    local result
    result=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region")

    if [ $? -ne 0 ]; then
        echo "错误：无法获取 VPC 列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    local table_header="VpcId\tVpcName\tStatus\tCidrBlock\tCreationTime"
    local jq_filter=".Vpcs.Vpc[] | [.VpcId, .VpcName, .Status, .CidrBlock, .CreationTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-18s  %-6s  %-14s  %s\n", $1, $2, $3, $4, $5}'

    format_output \
        "$result" \
        "$format" \
        "vpc" \
        "get" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 VPC。" \
        "列出 VPC："
}

# 使用新框架的创建函数
vpc_create() {
    local name=$1 cidr=$2 enable_ipv6=${3:-false}

    # 如果没有提供参数，则使用交互式输入
    if [ -z "$name" ]; then
        read -r -p "请输入 VPC 名称 (留空自动生成): " name_input
        if [ -z "$name_input" ]; then
            name="vpc-$(date +%Y%m%d-%H%M%S)"
            echo "自动生成 VPC 名称: $name"
        else
            name="$name_input"
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
            if [ -z "$cidr" ]; then
                cidr="192.168.0.0/16"
                echo "使用默认网段: $cidr"
            fi
        else
            read -r -p "请输入 VPC 网段 (默认: 192.168.0.0/16): " cidr_input
            cidr=${cidr_input:-"192.168.0.0/16"}
        fi
    fi

    # 选择是否启用 IPv6
    if [ -z "$enable_ipv6" ]; then
        local ipv6_list="true
false"
        if type select_with_fzf >/dev/null 2>&1; then
            enable_ipv6=$(select_with_fzf "选择是否启用 IPv6" "$ipv6_list")
            if [ -z "$enable_ipv6" ]; then
                enable_ipv6="false"
                echo "默认不启用 IPv6: $enable_ipv6"
            fi
        else
            read -r -p "是否启用 IPv6 (true/false，默认: false): " enable_ipv6_input
            enable_ipv6=${enable_ipv6_input:-false}
        fi
    fi

    if ! validate_required_params "$name" "$cidr" "错误：名称和网段不能为空。"; then
        echo "用法：vpc add <名称> <网段> [enable_ipv6]" >&2
        return 1
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
        log_result "${profile:-}" "$region" "vpc" "add" "$result"
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
            local result
            result=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region" 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo "错误：无法获取 VPC 列表。请检查您的凭证和权限。" >&2
                return 1
            fi

            vpc_list=$(echo "$result" | jq -r '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"')

            if [ -z "$vpc_list" ]; then
                echo "错误：没有找到 VPC。" >&2
                return 1
            elif [ "$(echo "$vpc_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
                vpc_id=$(echo "$vpc_list" | awk '{print $1}')
                echo "自动选择唯一的 VPC: $vpc_id"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    vpc_id=$(select_with_fzf "选择 VPC" "$vpc_list" | awk '{print $1}')
                    if [ -z "$vpc_id" ]; then
                        echo "错误：未选择 VPC。" >&2
                        return 1
                    fi
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
        echo "用法：vpc set <VPC-ID> <新名称>" >&2
        return 1
    fi

    echo "更新 VPC："
    local result
    result=$(call_aliyun_api vpc ModifyVpcAttribute \
        --VpcId "$vpc_id" \
        --VpcName "$new_name")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "vpc" "set" "$result"
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

    log_result "${profile:-}" "$region" "vpc" "del" "$result"
}

# 辅助函数：获取 VPC ID（支持 fzf 选择）
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
        local vpc_list
        vpc_list=$(echo "$result" | jq -r '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"')

        if type select_with_fzf >/dev/null 2>&1; then
            local selected_vpc
            selected_vpc=$(select_with_fzf "选择 VPC" "$vpc_list")
            if [ -z "$selected_vpc" ]; then
                echo "错误：未选择 VPC。" >&2
                return 1
            fi

            local vpc_id
            vpc_id=$(echo "$selected_vpc" | awk '{print $1}')
            echo "$vpc_id"
            return 0
        else
            echo "找到多个 VPC：" >&2
            echo "$result" | jq -r '.Vpcs.Vpc[] | "VPC ID: \(.VpcId), 名称: \(.VpcName)"' >&2
            echo "请指定要使用的 VPC ID。" >&2
            return 1
        fi
    fi
}

# 交换机列表（使用框架函数）
vpc_vswitch_list() {
    local vpc_id=$1
    local format=${2:-human}

    # 如果没有提供 VPC ID，则使用 fzf 交互式选择
    if [ -z "$vpc_id" ]; then
        local vpc_list
        local result
        result=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 VPC 列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        vpc_list=$(echo "$result" | jq -r '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"')

        if [ -z "$vpc_list" ]; then
            echo "错误：没有找到 VPC。" >&2
            return 1
        elif [ "$(echo "$vpc_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            vpc_id=$(echo "$vpc_list" | awk '{print $1}')
            echo "自动选择唯一的 VPC: $vpc_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                vpc_id=$(select_with_fzf "选择要查看交换机的 VPC" "$vpc_list" | awk '{print $1}')
                if [ -z "$vpc_id" ]; then
                    echo "错误：未选择 VPC。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择 VPC，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

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
        "vsw-get" \
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
    local vpc_id=$1 name=$2 cidr=$3 zone=$4

    # 如果没有提供 VPC ID，则使用 fzf 交互式选择
    if [ -z "$vpc_id" ]; then
        local vpc_list
        local result
        result=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 VPC 列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        vpc_list=$(echo "$result" | jq -r '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"')

        if [ -z "$vpc_list" ]; then
            echo "错误：没有找到 VPC。" >&2
            return 1
        elif [ "$(echo "$vpc_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            vpc_id=$(echo "$vpc_list" | awk '{print $1}')
            echo "自动选择唯一的 VPC: $vpc_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                vpc_id=$(select_with_fzf "选择要创建交换机的 VPC" "$vpc_list" | awk '{print $1}')
                if [ -z "$vpc_id" ]; then
                    echo "错误：未选择 VPC。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择 VPC，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 如果没有提供名称，则生成默认名称
    if [ -z "$name" ]; then
        name="vswitch-$(date +%Y%m%d-%H%M%S)"
        echo "未提供名称，自动生成: $name"
    fi

    # 如果没有提供 CIDR，则使用默认值
    if [ -z "$cidr" ]; then
        cidr=$(get_next_vswitch_cidr "$vpc_id")
        if [ $? -ne 0 ]; then
            echo "错误：无法获取下一个可用的交换机网段。" >&2
            return 1
        fi
        echo "未提供网段，使用默认值: $cidr"
    fi

    # 如果没有提供可用区，则使用选择功能
    if [ -z "$zone" ]; then
        echo "未指定可用区，正在获取可用区列表..."
        zone=$(select_zone)
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    if ! validate_required_params "$vpc_id" "$name" "$cidr" "$zone" "错误：VPC ID、名称、网段和可用区不能为空。"; then
        echo "用法：vpc vswitch-add <VPC-ID> [名称] [网段] [可用区]" >&2
        return 1
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
        log_result "${profile:-}" "$region" "vpc" "vsw-add" "$result"
    else
        echo "错误：交换机创建失败。"
        echo "$result"
        return 1
    fi
}

# 更新交换机（使用框架函数）
vpc_vswitch_update() {
    local vswitch_id=$1 new_name=$2

    # 如果没有提供交换机ID，则使用 fzf 交互式选择
    if [ -z "$vswitch_id" ]; then
        local vswitch_list
        local result
        result=$(call_aliyun_api vpc DescribeVSwitches --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取交换机列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        vswitch_list=$(echo "$result" | jq -r '.VSwitches.VSwitch[] | "\(.VSwitchId) (\(.VSwitchName // .VSwitchId)) [\(.ZoneId)] [\(.Status)]"')

        if [ -z "$vswitch_list" ]; then
            echo "错误：没有找到交换机。" >&2
            return 1
        elif [ "$(echo "$vswitch_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            vswitch_id=$(echo "$vswitch_list" | awk '{print $1}')
            echo "自动选择唯一的交换机: $vswitch_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                vswitch_id=$(select_with_fzf "选择要更新的交换机" "$vswitch_list" | awk '{print $1}')
                if [ -z "$vswitch_id" ]; then
                    echo "错误：未选择交换机。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择交换机，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 如果没有提供新名称，则使用交互式输入
    if [ -z "$new_name" ]; then
        read -r -p "请输入新的交换机名称: " new_name
        if [ -z "$new_name" ]; then
            echo "错误：新名称不能为空。" >&2
            return 1
        fi
    fi

    if ! validate_required_params "$vswitch_id" "$new_name" "错误：交换机 ID 和新名称不能为空。"; then
        echo "用法：vpc vswitch-set <交换机ID> <新名称>" >&2
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
        log_result "${profile:-}" "$region" "vpc" "vsw-set" "$result"
    else
        echo "错误：交换机更新失败。"
        echo "$result"
        return 1
    fi
}

# 删除交换机（使用框架函数）
vpc_vswitch_delete() {
    local vswitch_id=$1

    # 如果没有提供交换机ID，则使用 fzf 交互式选择
    if [ -z "$vswitch_id" ]; then
        local vswitch_list
        local result
        result=$(call_aliyun_api vpc DescribeVSwitches --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取交换机列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        vswitch_list=$(echo "$result" | jq -r '.VSwitches.VSwitch[] | "\(.VSwitchId) (\(.VSwitchName // .VSwitchId)) [\(.ZoneId)] [\(.Status)]"')

        if [ -z "$vswitch_list" ]; then
            echo "错误：没有找到交换机。" >&2
            return 1
        elif [ "$(echo "$vswitch_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            vswitch_id=$(echo "$vswitch_list" | awk '{print $1}')
            echo "自动选择唯一的交换机: $vswitch_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                vswitch_id=$(select_with_fzf "选择要删除的交换机" "$vswitch_list" | awk '{print $1}')
                if [ -z "$vswitch_id" ]; then
                    echo "错误：未选择交换机。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择交换机，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 检查交换机 ID 是否为空
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

    log_result "${profile:-}" "$region" "vpc" "vsw-del" "$result"
}

# 安全组列表（使用框架函数）
vpc_sg_list() {
    local vpc_id=$1
    local format=${2:-human}

    # 如果没有提供 VPC ID，则使用 fzf 交互式选择
    if [ -z "$vpc_id" ]; then
        local vpc_list
        local result
        result=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 VPC 列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        vpc_list=$(echo "$result" | jq -r '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"')

        if [ -z "$vpc_list" ]; then
            echo "错误：没有找到 VPC。" >&2
            return 1
        elif [ "$(echo "$vpc_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            vpc_id=$(echo "$vpc_list" | awk '{print $1}')
            echo "自动选择唯一的 VPC: $vpc_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                vpc_id=$(select_with_fzf "选择要查看安全组的 VPC" "$vpc_list" | awk '{print $1}')
                if [ -z "$vpc_id" ]; then
                    echo "错误：未选择 VPC。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择 VPC，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

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
        "sg-get" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到安全组。" \
        "列出安全组："
}

# 创建安全组（使用框架函数）
vpc_sg_create() {
    local vpc_id=$1 name=$2 description=$3

    # 如果没有提供 VPC ID，则使用 fzf 交互式选择
    if [ -z "$vpc_id" ]; then
        local vpc_list
        local result
        result=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 VPC 列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        vpc_list=$(echo "$result" | jq -r '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"')

        if [ -z "$vpc_list" ]; then
            echo "错误：没有找到 VPC。" >&2
            return 1
        elif [ "$(echo "$vpc_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            vpc_id=$(echo "$vpc_list" | awk '{print $1}')
            echo "自动选择唯一的 VPC: $vpc_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                vpc_id=$(select_with_fzf "选择要创建安全组的 VPC" "$vpc_list" | awk '{print $1}')
                if [ -z "$vpc_id" ]; then
                    echo "错误：未选择 VPC。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择 VPC，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 如果没有提供名称，则使用交互式输入
    if [ -z "$name" ]; then
        read -r -p "请输入安全组名称: " name
        if [ -z "$name" ]; then
            echo "错误：安全组名称不能为空。" >&2
            return 1
        fi
    fi

    # 如果没有提供描述，则使用交互式输入
    if [ -z "$description" ]; then
        read -r -p "请输入安全组描述: " description
        if [ -z "$description" ]; then
            description="Created by CLI"
            echo "未提供描述，使用默认描述: $description"
        fi
    fi

    if ! validate_required_params "$vpc_id" "$name" "$description" "错误：VPC ID、名称和描述不能为空。"; then
        echo "用法：vpc sg-add <VPC-ID> <名称> <描述>" >&2
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
        log_result "${profile:-}" "$region" "vpc" "sg-add" "$result"
    else
        echo "错误：安全组创建失败。"
        echo "$result"
        return 1
    fi
}

# 更新安全组（使用框架函数）
vpc_sg_update() {
    local sg_id=$1 new_name=$2 new_description=$3

    # 如果没有提供安全组ID，则使用 fzf 交互式选择
    if [ -z "$sg_id" ]; then
        echo "使用 fzf 交互式模式更新安全组"

        local sg_list
        local result
        result=$(call_aliyun_api ecs DescribeSecurityGroups --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取安全组列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        sg_list=$(echo "$result" | jq -r '.SecurityGroups.SecurityGroup[] | "\(.SecurityGroupId) (\(.SecurityGroupName // .SecurityGroupId)) [\(.VpcId)]"')

        if [ -z "$sg_list" ]; then
            echo "错误：没有找到安全组。" >&2
            return 1
        elif [ "$(echo "$sg_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            sg_id=$(echo "$sg_list" | awk '{print $1}')
            echo "自动选择唯一的安全组: $sg_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                sg_id=$(select_with_fzf "选择要更新的安全组" "$sg_list" | awk '{print $1}')
                if [ -z "$sg_id" ]; then
                    echo "错误：未选择安全组。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择安全组，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 如果没有提供新名称，则使用交互式输入
    if [ -z "$new_name" ]; then
        read -r -p "请输入新的安全组名称: " new_name
        if [ -z "$new_name" ]; then
            echo "错误：新名称不能为空。" >&2
            return 1
        fi
    fi

    # 如果没有提供新描述，则使用交互式输入
    if [ -z "$new_description" ]; then
        read -r -p "请输入新的安全组描述: " new_description
        if [ -z "$new_description" ]; then
            new_description="Updated by CLI"
            echo "未提供描述，使用默认描述: $new_description"
        fi
    fi

    if ! validate_required_params "$sg_id" "$new_name" "$new_description" "错误：安全组ID、新名称和新描述不能为空。"; then
        echo "用法：vpc sg-set <安全组ID> <新名称> <新描述>" >&2
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
        log_result "${profile:-}" "$region" "vpc" "sg-set" "$result"
    else
        echo "错误：安全组更新失败。"
        echo "$result"
        return 1
    fi
}

# 删除安全组（使用框架函数）
vpc_sg_delete() {
    local sg_id=$1

    # 如果没有提供安全组ID，则使用 fzf 交互式选择
    if [ -z "$sg_id" ]; then
        local sg_list
        local result
        result=$(call_aliyun_api ecs DescribeSecurityGroups --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取安全组列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        sg_list=$(echo "$result" | jq -r '.SecurityGroups.SecurityGroup[] | "\(.SecurityGroupId) (\(.SecurityGroupName // .SecurityGroupId)) [\(.VpcId)]"')

        if [ -z "$sg_list" ]; then
            echo "错误：没有找到安全组。" >&2
            return 1
        elif [ "$(echo "$sg_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            sg_id=$(echo "$sg_list" | awk '{print $1}')
            echo "自动选择唯一的安全组: $sg_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                sg_id=$(select_with_fzf "选择要删除的安全组" "$sg_list" | awk '{print $1}')
                if [ -z "$sg_id" ]; then
                    echo "错误：未选择安全组。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择安全组，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 检查安全组 ID 是否为空
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

    log_result "${profile:-}" "$region" "vpc" "sg-del" "$result"
}

# 安全组规则列表（使用框架函数并支持 fzf 选择）
vpc_sg_rule_list() {
    local sg_id=$1

    # 如果没有提供安全组ID，则使用 fzf 交互式选择
    if [ -z "$sg_id" ]; then
        echo "使用 fzf 交互式模式选择安全组"

        local sg_list
        local result
        result=$(call_aliyun_api ecs DescribeSecurityGroups --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取安全组列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        sg_list=$(echo "$result" | jq -r '.SecurityGroups.SecurityGroup[] | "\(.SecurityGroupId) (\(.SecurityGroupName // .SecurityGroupId)) [\(.VpcId)]"')

        if [ -z "$sg_list" ]; then
            echo "错误：没有找到安全组。" >&2
            return 1
        elif [ "$(echo "$sg_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            sg_id=$(echo "$sg_list" | awk '{print $1}')
            echo "自动选择唯一的安全组: $sg_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                sg_id=$(select_with_fzf "选择要查看规则的安全组" "$sg_list" | awk '{print $1}')
                if [ -z "$sg_id" ]; then
                    echo "错误：未选择安全组。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择安全组，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
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

# 更新安全组规则（使用框架函数并支持 fzf 选择）
vpc_sg_rule_set() {
    local rule_id=$1 protocol=$2 port_range=$3 source_ip=$4

    # 如果没有提供规则ID，则先选择安全组，然后列出规则供选择
    if [ -z "$rule_id" ]; then
        echo "使用 fzf 交互式模式选择安全组规则"

        # 首先选择安全组
        local sg_list
        local result
        result=$(call_aliyun_api ecs DescribeSecurityGroups --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取安全组列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        sg_list=$(echo "$result" | jq -r '.SecurityGroups.SecurityGroup[] | "\(.SecurityGroupId) (\(.SecurityGroupName // .SecurityGroupId)) [\(.VpcId)]"')

        if [ -z "$sg_list" ]; then
            echo "错误：没有找到安全组。" >&2
            return 1
        elif [ "$(echo "$sg_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            sg_id=$(echo "$sg_list" | awk '{print $1}')
            echo "自动选择唯一的安全组: $sg_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                sg_id=$(select_with_fzf "选择安全组" "$sg_list" | awk '{print $1}')
                if [ -z "$sg_id" ]; then
                    echo "错误：未选择安全组。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择安全组，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi

        # 然后列出选定安全组的规则，并选择要更新的规则
        echo "获取安全组 $sg_id 的规则列表..."
        local rule_list
        result=$(call_aliyun_api ecs DescribeSecurityGroupAttribute \
            --SecurityGroupId "$sg_id" \
            --RegionId "$region")

        if [ $? -ne 0 ]; then
            echo "错误：无法获取安全组规则列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        rule_list=$(echo "$result" | jq -r '.Permissions.Permission[]? | "\(.SecurityGroupRuleId) \(.Direction) \(.IpProtocol) \(.PortRange) \(.SourceCidrIp // .DestCidrIp) \(.Description // "")"')

        if [ -z "$rule_list" ]; then
            echo "错误：没有找到安全组规则。" >&2
            return 1
        elif [ "$(echo "$rule_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            rule_id=$(echo "$rule_list" | awk '{print $1}')
            echo "自动选择唯一的规则: $rule_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                rule_id=$(select_with_fzf "选择要更新的规则" "$rule_list" | awk '{print $1}')
                if [ -z "$rule_id" ]; then
                    echo "错误：未选择规则。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择规则，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 如果其他必需参数未提供，则通过交互式输入获取
    if [ -z "$protocol" ]; then
        read -r -p "请输入协议 (tcp/udp/icmp/all): " protocol
        protocol=${protocol:-"tcp"}
        echo "使用协议: $protocol"
    fi

    if [ -z "$port_range" ]; then
        read -r -p "请输入端口范围 (如 80/80, 1/65535): " port_range
        if [ -z "$port_range" ]; then
            echo "错误：端口范围不能为空。" >&2
            return 1
        fi
        echo "使用端口范围: $port_range"
    fi

    if [ -z "$source_ip" ]; then
        read -r -p "请输入源IP (如 0.0.0.0/0): " source_ip
        if [ -z "$source_ip" ]; then
            echo "错误：源IP不能为空。" >&2
            return 1
        fi
        echo "使用源IP: $source_ip"
    fi

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
        log_result "${profile:-}" "$region" "vpc" "sg-rule-set" "$result"
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

    # 如果没有提供 VPC ID，则使用 fzf 交互式选择
    if [ -z "$vpc_id" ]; then
        local vpc_list
        local result
        result=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 VPC 列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        vpc_list=$(echo "$result" | jq -r '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"')

        if [ -z "$vpc_list" ]; then
            echo "错误：没有找到 VPC。" >&2
            return 1
        elif [ "$(echo "$vpc_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            vpc_id=$(echo "$vpc_list" | awk '{print $1}')
            echo "自动选择唯一的 VPC: $vpc_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                vpc_id=$(select_with_fzf "选择要查看 IPv6 网关的 VPC" "$vpc_list" | awk '{print $1}')
                if [ -z "$vpc_id" ]; then
                    echo "错误：未选择 VPC。" >&2
                    return 1
                fi
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

    log_result "${profile:-}" "$region" "vpc" "ipv6gw-get" "$result"
}

# 创建 IPv6 网关（使用框架函数并添加 fzf 选择）
vpc_ipv6gw_create() {
    local vpc_id=$1 name=$2 spec=${3:-Small}

    # 如果没有提供 VPC ID，则使用 fzf 交互式选择
    if [ -z "$vpc_id" ]; then
        local vpc_list
        local result
        result=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 VPC 列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        vpc_list=$(echo "$result" | jq -r '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"')

        if [ -z "$vpc_list" ]; then
            echo "错误：没有找到 VPC。" >&2
            return 1
        elif [ "$(echo "$vpc_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            vpc_id=$(echo "$vpc_list" | awk '{print $1}')
            echo "自动选择唯一的 VPC: $vpc_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                vpc_id=$(select_with_fzf "选择要创建 IPv6 网关的 VPC" "$vpc_list" | awk '{print $1}')
                if [ -z "$vpc_id" ]; then
                    echo "错误：未选择 VPC。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择 VPC，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 如果没有提供名称，则使用交互式输入
    if [ -z "$name" ]; then
        read -r -p "请输入 IPv6 网关名称: " name
        if [ -z "$name" ]; then
            echo "错误：名称不能为空。" >&2
            return 1
        fi
    fi

    # 如果没有提供规格，则使用 fzf 选择
    if [ -z "$spec" ]; then
        local spec_list="Small
Medium
Large
XLarge"
        if type select_with_fzf >/dev/null 2>&1; then
            spec=$(select_with_fzf "选择 IPv6 网关规格" "$spec_list")
            if [ -z "$spec" ]; then
                spec="Small"  # 默认规格
                echo "使用默认规格: $spec"
            fi
        else
            read -r -p "请输入规格 (Small/Medium/Large/XLarge，默认: Small): " spec_input
            spec=${spec_input:-Small}
        fi
    fi

    if ! validate_required_params "$vpc_id" "$name" "错误：VPC ID 和名称不能为空。"; then
        echo "用法：vpc ipv6gw-add <VPC-ID> <名称> [规格]" >&2
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
        log_result "${profile:-}" "$region" "vpc" "ipv6gw-add" "$result"
    else
        echo "错误：IPv6 网关创建失败。"
        echo "$result"
        return 1
    fi
}

# 更新 IPv6 网关（使用框架函数并添加 fzf 选择）
vpc_ipv6gw_update() {
    local ipv6gw_id=$1 name=$2 spec=$3

    # 如果没有提供 IPv6 网关ID，则使用 fzf 交互式选择
    if [ -z "$ipv6gw_id" ]; then
        local ipv6gw_list
        local result
        result=$(call_aliyun_api vpc DescribeIpv6Gateways --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 IPv6 网关列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        ipv6gw_list=$(echo "$result" | jq -r '.Ipv6Gateways.Ipv6Gateway[] | "\(.Ipv6GatewayId) (\(.Name // .Ipv6GatewayId)) [\(.Spec)] [\(.Status)]"')

        if [ -z "$ipv6gw_list" ]; then
            echo "错误：没有找到 IPv6 网关。" >&2
            return 1
        elif [ "$(echo "$ipv6gw_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            ipv6gw_id=$(echo "$ipv6gw_list" | awk '{print $1}')
            echo "自动选择唯一的 IPv6 网关: $ipv6gw_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                ipv6gw_id=$(select_with_fzf "选择要更新的 IPv6 网关" "$ipv6gw_list" | awk '{print $1}')
                if [ -z "$ipv6gw_id" ]; then
                    echo "错误：未选择 IPv6 网关。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择 IPv6 网关，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 如果没有提供名称，则使用交互式输入
    if [ -z "$name" ]; then
        read -r -p "请输入新名称: " name
        if [ -z "$name" ]; then
            echo "错误：名称不能为空。" >&2
            return 1
        fi
    fi

    # 如果没有提供规格，则使用交互式输入（可选）
    if [ -z "$spec" ]; then
        local spec_list="Small
Medium
Large
XLarge"
        if type select_with_fzf >/dev/null 2>&1; then
            spec=$(select_with_fzf "选择新的 IPv6 网关规格 (可选，回车跳过)" "$spec_list")
            if [ -z "$spec" ]; then
                spec=""  # 规格可选
                echo "跳过规格更新。"
            fi
        else
            read -r -p "请输入新规格 (Small/Medium/Large/XLarge，可选): " spec_input
            spec=${spec_input:-""}
        fi
    fi

    if ! validate_required_params "$ipv6gw_id" "$name" "错误：IPv6 网关ID 和名称不能为空。"; then
        echo "用法：vpc ipv6gw-set <IPv6网关ID> <新名称> [新规格]" >&2
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
        log_result "${profile:-}" "$region" "vpc" "ipv6gw-set" "$result"
    else
        echo "错误：IPv6 网关更新失败。"
        echo "$result"
        return 1
    fi
}

# 删除 IPv6 网关（使用框架函数并添加 fzf 选择）
vpc_ipv6gw_delete() {
    local ipv6gw_id=$1

    # 如果没有提供 IPv6 网关ID，则使用 fzf 交互式选择
    if [ -z "$ipv6gw_id" ]; then
        local ipv6gw_list
        local result
        result=$(call_aliyun_api vpc DescribeIpv6Gateways --RegionId "$region" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 IPv6 网关列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        ipv6gw_list=$(echo "$result" | jq -r '.Ipv6Gateways.Ipv6Gateway[] | "\(.Ipv6GatewayId) (\(.Name // .Ipv6GatewayId)) [\(.Spec)] [\(.Status)]"')

        if [ -z "$ipv6gw_list" ]; then
            echo "错误：没有找到 IPv6 网关。" >&2
            return 1
        elif [ "$(echo "$ipv6gw_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            ipv6gw_id=$(echo "$ipv6gw_list" | awk '{print $1}')
            echo "自动选择唯一的 IPv6 网关: $ipv6gw_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                ipv6gw_id=$(select_with_fzf "选择要删除的 IPv6 网关" "$ipv6gw_list" | awk '{print $1}')
                if [ -z "$ipv6gw_id" ]; then
                    echo "错误：未选择 IPv6 网关。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择 IPv6 网关，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 检查 IPv6 网关 ID 是否为空
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

    log_result "${profile:-}" "$region" "vpc" "ipv6gw-del" "$result"
}
