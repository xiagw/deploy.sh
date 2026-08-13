#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2016

# VPC (专有网络) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_vpc_help() {
    echo "VPC (虚拟私有云) 操作："
    echo "  get [<VPC-ID>] [format]                  - 列出 VPC 或指定 VPC 的详细信息（VPC-ID可选，可使用fzf选择）"
    echo "  add <名称> [网段] [enable_ipv6]          - 创建 VPC (名称可选，自动生成；网段默认: 192.168.0.0/16)"
    echo "  set [<VPC-ID>] [<新名称>]               - 更新 VPC (VPC-ID和新名称都是可选的，可使用fzf选择)"
    echo "  del [<VPC-ID>]                          - 删除 VPC (VPC-ID可选，可使用fzf选择)"
    echo "  set-ipv6 [<VPC-ID>]                     - 为已有 VPC 开启 IPv6 (VPC-ID可选，可使用fzf选择)"
    echo "  set-ipv6-bw [IPv6地址ID] [带宽Mbps]     - 为 IPv6 地址开通公网带宽 (默认10Mbps按流量计费，自动创建网关)"
    echo "  get-vsw [<VPC-ID>] [format]             - 列出交换机 (VPC-ID可选，可使用fzf选择)"
    echo "  add-vsw [<VPC-ID>] [名称] [网段] [可用区] - 创建交换机 (VPC-ID可选，可使用fzf选择)"
    echo "  set-vsw <交换机ID> <新名称>              - 更新交换机"
    echo "  del-vsw <交换机ID>                       - 删除交换机"
    echo "  get-sg [<VPC-ID>] [format]              - 列出安全组 (VPC-ID可选，可使用fzf选择)"
    echo "  add-sg <VPC-ID> <名称> <描述>           - 创建安全组"
    echo "  set-sg <安全组ID> <新名称> <新描述>      - 更新安全组"
    echo "  del-sg <安全组ID>                        - 删除安全组"
    echo "  get-sg-rule <安全组ID>                   - 列出安全组规则"
    echo "  add-sg-rule <安全组ID> <协议> <端口范围> <源IP> <描述> - 添加安全组规则"
    echo "  set-sg-rule <规则ID> <协议> <端口范围> <源IP> - 更新安全组规则"
    echo "  del-sg-rule [规则ID] [安全组ID] [方向]   - 删除安全组规则 (可使用fzf选择)"
    echo "  get-ipv6gw [<VPC-ID>]                   - 列出 IPv6 网关 (VPC-ID可选，可使用fzf选择)"
    echo "  add-ipv6gw <VPC-ID> <名称> [规格]       - 创建 IPv6 网关"
    echo "  set-ipv6gw <IPv6网关ID> <新名称> [新规格] - 更新 IPv6 网关"
    echo "  del-ipv6gw <IPv6网关ID>                  - 删除 IPv6 网关"
    echo
    echo "示例："
    echo "  $0 vpc get"
    echo "  $0 vpc get vpc-xxx"
    echo "  $0 vpc get json"
    echo "  $0 vpc add"
    echo "  $0 vpc add my-vpc 10.0.0.0/8"
    echo "  $0 vpc set vpc-xxx new-name"
    echo "  $0 vpc del vpc-xxx"
    echo "  $0 vpc get-vsw vpc-xxx"
    echo "  $0 vpc get-vsw vpc-xxx json"
    echo "  $0 vpc add-vsw vpc-xxx my-vswitch 10.0.1.0/24 cn-hangzhou-a"
    echo "  $0 vpc set-vsw vsw-xxx new-name"
    echo "  $0 vpc del-vsw vsw-xxx"
    echo "  $0 vpc get-sg vpc-xxx"
    echo "  $0 vpc get-sg vpc-xxx json"
    echo "  $0 vpc add-sg vpc-xxx my-sg '安全组描述'"
    echo "  $0 vpc set-sg sg-xxx new-name '新描述'"
    echo "  $0 vpc del-sg sg-xxx"
    echo "  $0 vpc get-sg-rule sg-xxx"
    echo "  $0 vpc add-sg-rule sg-xxx tcp 80/80 0.0.0.0/0 '开放80端口'"
    echo "  $0 vpc set-sg-rule rule-xxx tcp 443/443 0.0.0.0/0"
    echo "  $0 vpc del-sg-rule rule-xxx sg-xxx ingress"
    echo "  $0 vpc get-ipv6gw vpc-xxx"
    echo "  $0 vpc add-ipv6gw vpc-xxx my-ipv6gw Small"
    echo "  $0 vpc set-ipv6gw ipv6gw-xxx new-name Medium"
    echo "  $0 vpc del-ipv6gw ipv6gw-xxx"
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
    set-ipv6) vpc_enable_ipv6 "$@" ;;
    set-ipv6-bw) vpc_ipv6_bandwidth_allocate "$@" ;;
    del) vpc_delete "$@" ;;
    get-vsw) vpc_vswitch_list "$@" ;;
    add-vsw) vpc_vswitch_create "$@" ;;
    set-vsw) vpc_vswitch_update "$@" ;;
    del-vsw) vpc_vswitch_delete "$@" ;;
    get-sg) vpc_sg_list "$@" ;;
    add-sg) vpc_sg_create "$@" ;;
    set-sg) vpc_sg_update "$@" ;;
    del-sg) vpc_sg_delete "$@" ;;
    get-sg-rule) vpc_sg_rule_list "$@" ;;
    add-sg-rule) vpc_sg_rule_add "$@" ;;
    set-sg-rule) vpc_sg_rule_set "$@" ;;
    del-sg-rule) vpc_sg_rule_delete "$@" ;;
    get-ipv6gw) vpc_ipv6gw_list "$@" ;;
    add-ipv6gw) vpc_ipv6gw_create "$@" ;;
    set-ipv6gw) vpc_ipv6gw_update "$@" ;;
    del-ipv6gw) vpc_ipv6gw_delete "$@" ;;
    help) show_vpc_help ;;
    *)
        echo "错误：未知的 VPC 操作：$operation" >&2
        show_vpc_help
        exit 1
        ;;
    esac
}

# 私有解析器：VPC ID
_vpc_resolve_vpc_id() {
    resolve_resource_id "$1" "${2:-选择 VPC}" "错误：没有找到 VPC。" \
        '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"' \
        -- vpc describe-vpcs --biz-region-id "${region:-}"
}

# 私有解析器：交换机 ID（可选：传入 vpc_id 过滤）
_vpc_resolve_vsw_id() {
    local current=$1 prompt=$2 vpc_filter=$3
    local extra_args=()
    [ -n "$vpc_filter" ] && extra_args=(--vpc-id "$vpc_filter")
    resolve_resource_id "$current" "${prompt:-选择交换机}" "错误：没有找到交换机。" \
        '.VSwitches.VSwitch[] | "\(.VSwitchId) (\(.VSwitchName // .VSwitchId)) [\(.ZoneId)] [\(.Status)]"' \
        -- vpc describe-vswitches --biz-region-id "${region:-}" "${extra_args[@]}"
}

# 私有解析器：安全组 ID
_vpc_resolve_sg_id() {
    resolve_resource_id "$1" "${2:-选择安全组}" "错误：没有找到安全组。" \
        '.SecurityGroups.SecurityGroup[] | "\(.SecurityGroupId) (\(.SecurityGroupName // .SecurityGroupId)) [\(.VpcId)]"' \
        -- ecs describe-security-groups --biz-region-id "${region:-}"
}

# 私有解析器：IPv6 网关 ID
_vpc_resolve_ipv6gw_id() {
    resolve_resource_id "$1" "${2:-选择 IPv6 网关}" "错误：没有找到 IPv6 网关。" \
        '.Ipv6Gateways.Ipv6Gateway[] | "\(.Ipv6GatewayId) (\(.Name // .Ipv6GatewayId)) [\(.Spec)] [\(.Status)]"' \
        -- vpc describe-ipv6-gateways --biz-region-id "${region:-}"
}

# 列出所有 VPC 相关资源（保持原有逻辑）
vpc_list_all() {
    echo "列出所有 VPC 相关资源："
    vpc_list "$@"

    local vpc_ids
    vpc_ids=$(call_aliyun_api vpc describe-vpcs --biz-region-id "${region:-}" --pager | jq -r '.Vpcs.Vpc[].VpcId')

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

    if is_output_format "$vpc_id"; then
        format=$vpc_id
        vpc_id=""
    fi

    # 如果提供了 VPC ID，则获取特定 VPC 的详细信息
    if [ -n "$vpc_id" ]; then
        local result
        if ! result=$(call_aliyun_api vpc describe-vpcs --vpc-id "$vpc_id" --biz-region-id "$region" --region "$region" 2>/dev/null); then
            echo "错误：无法获取 VPC 详细信息。请检查您的凭证和权限。" >&2
            return 1
        fi

        local table_header="VpcId\tVpcName\tStatus\tCidrBlock\tRegionId\tCreationTime"
        local jq_filter='.Vpcs.Vpc[] | [.VpcId, .VpcName, .Status, .CidrBlock, .RegionId, .CreationTime] | @tsv'
        local status_mapper='BEGIN {FS="\t"; OFS="\t"}
        {
            status = $3;
            if (status == "Available") status = "可用";
            else if (status == "Creating") status = "创建中";
            else if (status == "Deleting") status = "删除中";
            else if (status == "Updating") status = "更新中";
            else status = "未知";
            printf "%-16s  %-18s  %-6s  %-12s  %-12s  %s\n", $1, $2, status, $4, $5, $6
        }'
        local human_header="VPC ID            名称                状态    CIDR          地域          创建时间
----------------  ------------------  ------  ------------  ------------  -------------------------"
        format_output "$result" "$format" "vpc" "get" \
            "$table_header" "$jq_filter" "$status_mapper" \
            "没有找到指定的 VPC。" "VPC 详细信息：" "$human_header" \
            '.Vpcs.Vpc | length'
        return
    fi

    # 如果没有提供 VPC ID，则列出所有 VPC
    local result
    if ! result=$(call_aliyun_api vpc describe-vpcs --biz-region-id "$region"); then
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
        existing_vpcs=$(call_aliyun_api vpc describe-vpcs --biz-region-id "$region" 2>/dev/null | jq -r '.Vpcs.Vpc[] | .CidrBlock' 2>/dev/null)

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
    call_api_logged "vpc" "add" "错误：VPC 创建失败。" \
        -- vpc create-vpc \
        --biz-region-id "$region" \
        --vpc-name "$name" \
        --cidr-block "$cidr" \
        --enable-ipv6 "$enable_ipv6"
}

# 使用新框架的更新函数
vpc_update() {
    local vpc_id new_name=$2
    vpc_id=$(_vpc_resolve_vpc_id "$1" "选择要更新的 VPC") || return 1

    # 输入新名称
    if [ -z "$new_name" ]; then
        read -r -p "请输入新的 VPC 名称: " new_name
        if [ -z "$new_name" ]; then
            echo "错误：新名称不能为空。" >&2
            return 1
        fi
    fi

    echo "更新 VPC："
    call_api_logged "vpc" "set" "错误：VPC 更新失败。" \
        -- vpc modify-vpc-attribute --biz-region-id "$region" --region "$region" \
        --vpc-id "$vpc_id" \
        --vpc-name "$new_name"
}

# 为已有 VPC 开启 IPv6
vpc_enable_ipv6() {
    local vpc_id
    vpc_id=$(_vpc_resolve_vpc_id "$1" "选择要开启 IPv6 的 VPC") || return 1

    local ipv6_cidr
    ipv6_cidr=$(call_aliyun_api vpc describe-vpcs --vpc-id "$vpc_id" --biz-region-id "$region" --region "$region" 2>/dev/null | jq -r '.Vpcs.Vpc[0].Ipv6CidrBlock // ""')
    if [ -n "$ipv6_cidr" ]; then
        echo "VPC $vpc_id 已开启 IPv6: $ipv6_cidr"
        return 0
    fi

    echo "为 VPC $vpc_id 开启 IPv6："
    local result
    result=$(call_aliyun_api vpc modify-vpc-attribute --biz-region-id "$region" --region "$region" \
        --vpc-id "$vpc_id" \
        --enable-ipv6 true)
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "IPv6 开启成功。"
        ipv6_cidr=$(call_aliyun_api vpc describe-vpcs --vpc-id "$vpc_id" --biz-region-id "$region" --region "$region" 2>/dev/null | jq -r '.Vpcs.Vpc[0].Ipv6CidrBlock // ""')
        echo "IPv6 网段: ${ipv6_cidr:-分配中，请稍后查询}"
        log_result "${profile:-}" "$region" "vpc" "set-ipv6" "$result"
    else
        echo "错误：IPv6 开启失败。"
        echo "$result"
        return 1
    fi
}

# 使用新框架的删除函数
vpc_delete() {
    local vpc_id
    vpc_id=$(_vpc_resolve_vpc_id "$1" "选择要删除的 VPC") || return 1

    # 检查 VPC 是否存在
    local vpc_info
    vpc_info=$(call_aliyun_api vpc describe-vpcs --vpc-id "$vpc_id" --biz-region-id "$region" 2>/dev/null)
    local ret=$?
    if [ $ret -ne 0 ] || [ "$(echo "$vpc_info" | jq '.Vpcs.Vpc | length')" -eq 0 ]; then
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

    call_api_del_logged "vpc" "$vpc_id" "VPC" "错误：VPC 删除失败。" \
        -- vpc delete-vpc --vpc-id "$vpc_id" --biz-region-id "$region" --region "$region"
}

# 辅助函数：获取 VPC ID（支持 fzf 选择）— 薄委托
get_vpc_id() {
    _vpc_resolve_vpc_id "$1" "选择 VPC"
}

# 交换机列表（使用框架函数）
vpc_vswitch_list() {
    local vpc_id=$1
    local format=${2:-human}

    if is_output_format "$vpc_id"; then
        format=$vpc_id
        vpc_id=""
    fi

    vpc_id=$(_vpc_resolve_vpc_id "$vpc_id" "选择要查看交换机的 VPC") || return 1

    local table_header="VSwitchId\tVSwitchName\tStatus\tZoneId\tCidrBlock\tCreationTime"
    local jq_filter=".VSwitches.VSwitch[] | [.VSwitchId, .VSwitchName, .Status, .ZoneId, .CidrBlock, .CreationTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s %-18s %-6s %-14s %-14s %s\n", $1, $2, $3, $4, $5, $6}'

    local result
    if ! result=$(call_aliyun_api vpc describe-vswitches --vpc-id "$vpc_id" --biz-region-id "$region" --region "$region" 2>/dev/null); then
        echo "错误：无法获取交换机列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "vpc" \
        "get-vsw" \
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
    result=$(call_aliyun_api vpc describe-vswitches --vpc-id "$vpc_id" --biz-region-id "$region" --region "$region" 2>/dev/null)

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
    next_octet=$((BASH_REMATCH[1] + 1))
    echo "192.168.${next_octet}.0/24"
}

# 选择可用区
select_zone() {
    local zones_result
    zones_result=$(call_aliyun_api ecs describe-zones --biz-region-id "$region" --region "$region" 2>/dev/null)
    local zones
    zones=$(echo "$zones_result" | jq -r '.Zones.Zone[].ZoneId' | grep -v '[[:space:]]')
    resolve_from_candidates "" "请选择可用区" "错误：没有找到可用区。" "$zones"
}

# 创建交换机（保持原有逻辑，但使用框架函数）
vpc_vswitch_create() {
    local vpc_id name=$2 cidr=$3 zone=$4
    local ret

    vpc_id=$(_vpc_resolve_vpc_id "$1" "选择要创建交换机的 VPC") || return 1

    # 如果没有提供名称，则生成默认名称
    if [ -z "$name" ]; then
        name="vswitch-$(date +%Y%m%d-%H%M%S)"
        echo "未提供名称，自动生成: $name"
    fi

    # 如果没有提供 CIDR，则使用默认值
    if [ -z "$cidr" ]; then
        cidr=$(get_next_vswitch_cidr "$vpc_id")
        ret=$?
        if [ $ret -ne 0 ]; then
            echo "错误：无法获取下一个可用的交换机网段。" >&2
            return 1
        fi
        echo "未提供网段，使用默认值: $cidr"
    fi

    # 如果没有提供可用区，则使用选择功能
    if [ -z "$zone" ]; then
        echo "未指定可用区，正在获取可用区列表..."
        zone=$(select_zone)
        ret=$?
        if [ $ret -ne 0 ]; then
            return 1
        fi
    fi

    if ! validate_required_params "$vpc_id" "$name" "$cidr" "$zone" "错误：VPC ID、名称、网段和可用区不能为空。"; then
        echo "用法：vpc add-vsw <VPC-ID> [名称] [网段] [可用区]" >&2
        return 1
    fi

    echo "创建交换机："
    echo "VPC ID: $vpc_id"
    echo "名称: $name"
    echo "网段: $cidr"
    echo "可用区: $zone"

    # VPC 已开启 IPv6 时，自动为交换机分配 IPv6 网段（取 IPv4 网段第三段作为 IPv6 网段最后 8 位）
    local ipv6_args=()
    local vpc_ipv6
    vpc_ipv6=$(call_aliyun_api vpc describe-vpcs --vpc-id "$vpc_id" --biz-region-id "$region" --region "$region" 2>/dev/null | jq -r '.Vpcs.Vpc[0].Ipv6CidrBlock // ""')
    if [ -n "$vpc_ipv6" ]; then
        local ipv6_octet
        if [[ $cidr =~ ^[0-9]+\.[0-9]+\.([0-9]+)\.[0-9]+/ ]]; then
            ipv6_octet=${BASH_REMATCH[1]}
        else
            ipv6_octet=0
        fi
        ipv6_args=(--ipv6-cidr-block "$ipv6_octet")
        echo "IPv6 网段: ${vpc_ipv6}（分配第 ${ipv6_octet} 段）"
    fi

    call_api_logged "vpc" "add-vsw" "错误：交换机创建失败。" \
        -- vpc create-vswitch --biz-region-id "$region" --region "$region" \
        --vpc-id "$vpc_id" \
        --zone-id "$zone" \
        --vswitch-name "$name" \
        --cidr-block "$cidr" "${ipv6_args[@]}"
}

# 更新交换机（使用框架函数）
vpc_vswitch_update() {
    local vswitch_id new_name=$2

    vswitch_id=$(_vpc_resolve_vsw_id "$1" "选择要更新的交换机") || return 1

    # 如果没有提供新名称，则使用交互式输入
    if [ -z "$new_name" ]; then
        read -r -p "请输入新的交换机名称: " new_name
        if [ -z "$new_name" ]; then
            echo "错误：新名称不能为空。" >&2
            return 1
        fi
    fi

    echo "更新交换机："
    call_api_logged "vpc" "set-vsw" "错误：交换机更新失败。" \
        -- vpc modify-vswitch-attribute --biz-region-id "$region" --region "$region" \
        --vswitch-id "$vswitch_id" \
        --vswitch-name "$new_name"
}

# 删除交换机（使用框架函数）
vpc_vswitch_delete() {
    local vswitch_id
    vswitch_id=$(_vpc_resolve_vsw_id "$1" "选择要删除的交换机") || return 1

    if ! confirm_action "删除交换机：$vswitch_id"; then
        return 1
    fi

    call_api_del_logged "vpc" "$vswitch_id" "交换机" "错误：交换机删除失败。" \
        -- vpc delete-vswitch --vswitch-id "$vswitch_id" --biz-region-id "$region"
}

# 安全组列表（使用框架函数）
vpc_sg_list() {
    local vpc_id=$1
    local format=${2:-human}

    if is_output_format "$vpc_id"; then
        format=$vpc_id
        vpc_id=""
    fi

    vpc_id=$(_vpc_resolve_vpc_id "$vpc_id" "选择要查看安全组的 VPC") || return 1

    local table_header="SecurityGroupId\tSecurityGroupName\tDescription\tCreationTime"
    local jq_filter=".SecurityGroups.SecurityGroup[] | [.SecurityGroupId, .SecurityGroupName, .Description, .CreationTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s %-18s %-28s %s\n", $1, substr($2, 1, 14), $3, $4}'

    local result
    if ! result=$(call_aliyun_api ecs describe-security-groups --vpc-id "$vpc_id" --biz-region-id "$region"); then
        echo "错误：无法获取安全组列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "vpc" \
        "get-sg" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到安全组。" \
        "列出安全组："
}

# 创建安全组（使用框架函数）
vpc_sg_create() {
    local vpc_id name=$2 description=$3

    vpc_id=$(_vpc_resolve_vpc_id "$1" "选择要创建安全组的 VPC") || return 1

    # 如果没有提供名称，则生成默认名称
    if [ -z "$name" ]; then
        name="sg-$(date +%Y%m%d-%H%M%S)"
        echo "未提供名称，自动生成: $name"
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
        echo "用法：vpc add-sg <VPC-ID> <名称> <描述>" >&2
        return 1
    fi

    echo "创建安全组："
    call_api_logged "vpc" "add-sg" "错误：安全组创建失败。" \
        -- ecs create-security-group \
        --biz-region-id "$region" \
        --vpc-id "$vpc_id" \
        --security-group-name "$name" \
        --description "$description"
}

# 更新安全组（使用框架函数）
vpc_sg_update() {
    local sg_id new_name=$2 new_description=$3

    sg_id=$(_vpc_resolve_sg_id "$1" "选择要更新的安全组") || return 1

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

    echo "更新安全组："
    call_api_logged "vpc" "set-sg" "错误：安全组更新失败。" \
        -- ecs modify-security-group-attribute \
        --biz-region-id "$region" \
        --security-group-id "$sg_id" \
        --security-group-name "$new_name" \
        --description "$new_description"
}

# 删除安全组（使用框架函数）
vpc_sg_delete() {
    local sg_id
    sg_id=$(_vpc_resolve_sg_id "$1" "选择要删除的安全组") || return 1

    if ! confirm_action "删除安全组：$sg_id"; then
        return 1
    fi

    call_api_del_logged "vpc" "$sg_id" "安全组" "错误：安全组删除失败。" \
        -- ecs delete-security-group --security-group-id "$sg_id" --biz-region-id "$region"
}

# 安全组规则列表（使用框架函数并支持 fzf 选择）
vpc_sg_rule_list() {
    local sg_id
    sg_id=$(_vpc_resolve_sg_id "$1" "选择要查看规则的安全组") || return 1

    echo "列出安全组规则："
    echo "规则ID             方向    协议    端口范围    源/目标IP        优先级  创建时间"
    echo "----------------   ------  ------  ----------  ---------------  ------  -------------------------"

    local result
    if ! result=$(call_aliyun_api ecs describe-security-group-attribute \
        --security-group-id "$sg_id" \
        --biz-region-id "$region"); then
        echo "错误：无法获取安全组规则列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    if [[ $(echo "$result" | jq '.Permissions.Permission | length') -eq 0 ]]; then
        echo "没有找到安全组规则。"
    else
        echo "$result" | jq -r '.Permissions.Permission[] | [.SecurityGroupRuleId, .Direction, .IpProtocol, .PortRange, ([.SourceCidrIp, .Ipv6SourceCidrIp, .DestCidrIp, .Ipv6DestCidrIp] | map(select(. != null and . != "")) | first // "-"), .Priority, .CreateTime] | @tsv' |
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
    local sg_id protocol=$2 port_range=$3 source_ip=$4 description=$5

    sg_id=$(_vpc_resolve_sg_id "$1" "选择要添加规则的安全组") || return 1

    if [ -z "$protocol" ]; then
        read -r -p "请输入协议 (tcp/udp/icmp/all): " -e -i"tcp" protocol
        protocol=${protocol:-"tcp"}
        echo "使用协议: $protocol"
    fi
    if [ -z "$port_range" ]; then
        read -r -p "请输入端口范围 (如 80/80, 1/65535): " -e -i"21/23" port_range
        if [ -z "$port_range" ]; then
            echo "错误：端口范围不能为空。" >&2
            return 1
        fi
        echo "使用端口范围: $port_range"
    fi
    if [ -z "$source_ip" ]; then
        read -r -p "请输入源IP (如 0.0.0.0/0，IPv6 如 ::/0): " -e -i"0.0.0.0/0" source_ip
        if [ -z "$source_ip" ]; then
            echo "错误：源IP不能为空。" >&2
            return 1
        fi
        echo "使用源IP: $source_ip"
    fi
    if ! validate_required_params "$sg_id" "$protocol" "$port_range" "$source_ip" "错误：安全组ID、协议、端口范围和源IP不能为空。"; then
        return 1
    fi

    # 源IP含冒号视为 IPv6：改用 Ipv6SourceCidrIp，icmp 自动转 icmpv6
    local source_param="SourceCidrIp=$source_ip"
    if [[ $source_ip == *:* ]]; then
        source_param="Ipv6SourceCidrIp=$source_ip"
        if [ "$protocol" = "icmp" ]; then
            protocol="icmpv6"
            port_range="-1/-1"
            echo "IPv6 源地址，协议自动调整为 icmpv6"
        fi
    fi

    echo "添加安全组规则："
    call_api_logged "vpc" "add-sg-rule" "错误：安全组规则添加失败。" \
        -- ecs authorize-security-group --biz-region-id "$region" \
        --security-group-id "$sg_id" \
        --permissions "$source_param" PortRange="$port_range" IpProtocol="$protocol" Policy=Accept Priority=10
}

# 更新安全组规则（使用框架函数并支持 fzf 选择）
vpc_sg_rule_set() {
    local rule_id=$1 protocol=$2 port_range=$3 source_ip=$4

    # 如果没有提供规则ID，则先选择安全组，然后列出规则供选择
    if [ -z "$rule_id" ]; then
        local sg_id
        sg_id=$(_vpc_resolve_sg_id "" "选择安全组") || return 1

        # 然后列出选定安全组的规则，并选择要更新的规则
        echo "获取安全组 $sg_id 的规则列表..."
        local rule_list result
        result=$(call_aliyun_api ecs describe-security-group-attribute \
            --security-group-id "$sg_id" \
            --biz-region-id "$region")
        local ret=$?
        if [ $ret -ne 0 ]; then
            echo "错误：无法获取安全组规则列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        rule_list=$(echo "$result" | jq -r '.Permissions.Permission[]? | "\(.SecurityGroupRuleId) \(.Direction) \(.IpProtocol) \(.PortRange) \([.SourceCidrIp, .Ipv6SourceCidrIp, .DestCidrIp, .Ipv6DestCidrIp] | map(select(. != null and . != "")) | first // "-") \(.Description // "")"')

        local selected_rule
        selected_rule=$(resolve_from_candidates "" "选择要更新的规则" "错误：没有找到安全组规则。" "$rule_list") || return 1
        rule_id=$(echo "$selected_rule" | awk '{print $1}')
    fi

    # 如果其他必需参数未提供，则通过交互式输入获取
    if [ -z "$protocol" ]; then
        read -r -p "请输入协议 (tcp/udp/icmp/all): " -e -i"tcp" protocol
        protocol=${protocol:-"tcp"}
        echo "使用协议: $protocol"
    fi

    if [ -z "$port_range" ]; then
        read -r -p "请输入端口范围 (如 80/80, 1/65535): " -e -i"21/23" port_range
        if [ -z "$port_range" ]; then
            echo "错误：端口范围不能为空。" >&2
            return 1
        fi
        echo "使用端口范围: $port_range"
    fi

    if [ -z "$source_ip" ]; then
        read -r -p "请输入源IP (如 0.0.0.0/0): " -e -i"0.0.0.0/0" source_ip
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
    call_api_logged "vpc" "set-sg-rule" "错误：安全组规则更新失败。" \
        -- ecs modify-security-group-rule \
        --biz-region-id "$region" \
        --security-group-id "$sg_id" \
        --security-group-rule-id "$rule_id" \
        --ip-protocol "$protocol" \
        --port-range "$port_range" \
        --source-cidr-ip "$source_ip" \
        --policy accept \
        --priority 10
}

# 删除安全组规则（使用框架函数）
vpc_sg_rule_delete() {
    local rule_id=$1 sg_id=$2 direction=$3

    # 如果没有提供安全组ID，则使用 fzf 交互式选择
    if [ -z "$sg_id" ]; then
        sg_id=$(_vpc_resolve_sg_id "" "选择安全组") || return 1
    fi

    # 如果没有提供规则ID，则列出安全组的规则供选择
    if [ -z "$rule_id" ]; then
        echo "获取安全组 $sg_id 的规则列表..."
        local rule_list
        local result
        result=$(call_aliyun_api ecs describe-security-group-attribute \
            --security-group-id "$sg_id" \
            --biz-region-id "$region")
        local ret=$?
        if [ $ret -ne 0 ]; then
            echo "错误：无法获取安全组规则列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        rule_list=$(echo "$result" | jq -r '.Permissions.Permission[]? | "\(.SecurityGroupRuleId) \(.Direction) \(.IpProtocol) \(.PortRange) \([.SourceCidrIp, .Ipv6SourceCidrIp, .DestCidrIp, .Ipv6DestCidrIp] | map(select(. != null and . != "")) | first // "-") \(.Description // "")"')

        if [ -z "$rule_list" ]; then
            echo "错误：没有找到安全组规则。" >&2
            return 1
        fi

        local selected_rule
        if [ "$(echo "$rule_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            selected_rule=$rule_list
            echo "自动选择唯一的规则: $(echo "$selected_rule" | awk '{print $1}')" >&2
        else
            if type select_with_fzf >/dev/null 2>&1; then
                selected_rule=$(select_with_fzf "选择要删除的规则" "$rule_list")
                if [ -z "$selected_rule" ]; then
                    echo "错误：未选择规则。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择规则，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
        rule_id=$(echo "$selected_rule" | awk '{print $1}')
        direction=${direction:-$(echo "$selected_rule" | awk '{print $2}')}
    fi

    direction=${direction:-ingress}

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
        result=$(call_aliyun_api ecs revoke-security-group \
            --biz-region-id "$region" \
            --security-group-id "$sg_id" \
            --security-group-rule-id "$rule_id")
    else
        result=$(call_aliyun_api ecs revoke-security-group-egress \
            --biz-region-id "$region" \
            --security-group-id "$sg_id" \
            --security-group-rule-id "$rule_id")
    fi
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "安全组规则删除成功。"
        log_delete_operation "${profile:-}" "$region" "vpc" "$rule_id" "安全组规则" "成功" "$result"
    else
        echo "安全组规则删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "vpc" "$rule_id" "安全组规则" "失败" "$result"
        return 1
    fi
}

# IPv6 网关列表（使用框架函数）
vpc_ipv6gw_list() {
    local vpc_id
    vpc_id=$(_vpc_resolve_vpc_id "$1" "选择要查看 IPv6 网关的 VPC") || return 1

    echo "列出 IPv6 网关："
    local result
    if ! result=$(call_aliyun_api vpc describe-ipv6-gateways --vpc-id "$vpc_id" --biz-region-id "$region" --region "$region" 2>/dev/null); then
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

    log_result "${profile:-}" "$region" "vpc" "get-ipv6gw" "$result"
}

# 为 IPv6 地址开通公网带宽
vpc_ipv6_bandwidth_allocate() {
    local ipv6_address_id=$1 bandwidth=${2:-10}

    # 如果没有提供 IPv6 地址 ID，则使用 fzf 交互式选择
    if [ -z "$ipv6_address_id" ]; then
        local addr_list
        addr_list=$(call_aliyun_api vpc describe-ipv6-addresses --biz-region-id "$region" --region "$region" 2>/dev/null |
            jq -r '.Ipv6Addresses.Ipv6Address[] | "\(.Ipv6AddressId) \(.Ipv6Address) [\(.AssociatedInstanceId // "未关联")] \(.NetworkType) 带宽:\(.Ipv6InternetBandwidth.InternetBandwidthId // "无")"')

        ipv6_address_id=$(resolve_from_candidates "" "选择要开通公网带宽的 IPv6 地址" "错误：没有找到 IPv6 地址。" "$addr_list") || return 1
        ipv6_address_id=$(echo "$ipv6_address_id" | awk '{print $1}')
    fi

    # 获取地址所属 VPC，查找其 IPv6 网关，没有则自动创建（网关本身免费）
    local vpc_id
    vpc_id=$(call_aliyun_api vpc describe-ipv6-addresses --ipv6-address-id "$ipv6_address_id" --biz-region-id "$region" --region "$region" 2>/dev/null |
        jq -r '.Ipv6Addresses.Ipv6Address[0].VpcId // ""')
    if [ -z "$vpc_id" ]; then
        echo "错误：无法获取 IPv6 地址 $ipv6_address_id 的信息。" >&2
        return 1
    fi

    local gateway_id
    gateway_id=$(call_aliyun_api vpc describe-ipv6-gateways --vpc-id "$vpc_id" --biz-region-id "$region" --region "$region" 2>/dev/null |
        jq -r '.Ipv6Gateways.Ipv6Gateway[0].Ipv6GatewayId // ""')

    if [ -z "$gateway_id" ]; then
        echo "VPC $vpc_id 没有 IPv6 网关（网关免费）。"
        if ! confirm_action "为该 VPC 创建 IPv6 网关"; then
            return 1
        fi
        local gw_result
        gw_result=$(call_aliyun_api vpc create-ipv6-gateway --biz-region-id "$region" --region "$region" \
            --vpc-id "$vpc_id" \
            --name "ipv6gw-$(date +%Y%m%d-%H%M%S)")
        local ret=$?
        if [ $ret -ne 0 ]; then
            echo "错误：IPv6 网关创建失败。" >&2
            echo "$gw_result"
            return 1
        fi
        gateway_id=$(echo "$gw_result" | jq -r '.Ipv6GatewayId')
        echo "IPv6 网关创建成功: $gateway_id，等待网关就绪..."
        local gw_status
        for _ in {1..30}; do
            sleep 5
            gw_status=$(call_aliyun_api vpc describe-ipv6-gateways --vpc-id "$vpc_id" --biz-region-id "$region" --region "$region" 2>/dev/null |
                jq -r --arg id "$gateway_id" '.Ipv6Gateways.Ipv6Gateway[] | select(.Ipv6GatewayId == $id) | .Status')
            [ "$gw_status" = "Available" ] && break
        done
        if [ "$gw_status" != "Available" ]; then
            echo "错误：IPv6 网关未就绪（状态: ${gw_status:-未知}），请稍后重试。" >&2
            return 1
        fi
    fi

    echo "开通 IPv6 公网带宽："
    echo "IPv6 地址 ID: $ipv6_address_id"
    echo "IPv6 网关 ID: $gateway_id"
    echo "带宽: ${bandwidth}Mbps (按流量计费)"

    if ! confirm_action "开通 IPv6 公网带宽（将产生流量费用）"; then
        return 1
    fi

    call_api_logged "vpc" "set-ipv6-bw" "错误：IPv6 公网带宽开通失败。" \
        -- vpc allocate-ipv6-internet-bandwidth --biz-region-id "$region" --region "$region" \
        --ipv6-address-id "$ipv6_address_id" \
        --ipv6-gateway-id "$gateway_id" \
        --bandwidth "$bandwidth" \
        --internet-charge-type PayByTraffic
}

# 创建 IPv6 网关（使用框架函数并添加 fzf 选择）
vpc_ipv6gw_create() {
    local vpc_id name=$2 spec=${3:-Small}

    vpc_id=$(_vpc_resolve_vpc_id "$1" "选择要创建 IPv6 网关的 VPC") || return 1

    # 如果没有提供名称，则使用交互式输入
    if [ -z "$name" ]; then
        read -r -p "请输入 IPv6 网关名称: " name
        if [ -z "$name" ]; then
            echo "错误：名称不能为空。" >&2
            return 1
        fi
    fi

    # 如果没有提供规格，则忽略（新版 IPv6 网关免费，API 已不支持 --spec 参数）
    if [ -n "$spec" ]; then
        echo "提示：新版 IPv6 网关已免费，规格参数 ($spec) 将被忽略。"
    fi

    if ! validate_required_params "$vpc_id" "$name" "错误：VPC ID 和名称不能为空。"; then
        echo "用法：vpc add-ipv6gw <VPC-ID> <名称>" >&2
        return 1
    fi

    echo "创建 IPv6 网关："
    call_api_logged "vpc" "add-ipv6gw" "错误：IPv6 网关创建失败。" \
        -- vpc create-ipv6-gateway --biz-region-id "$region" --region "$region" \
        --vpc-id "$vpc_id" \
        --name "$name"
}

# 更新 IPv6 网关（使用框架函数并添加 fzf 选择）
vpc_ipv6gw_update() {
    local ipv6gw_id name=$2 spec=$3

    ipv6gw_id=$(_vpc_resolve_ipv6gw_id "$1" "选择要更新的 IPv6 网关") || return 1

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
                spec=""
                echo "跳过规格更新。"
            fi
        else
            read -r -p "请输入新规格 (Small/Medium/Large/XLarge，可选): " spec_input
            spec=${spec_input:-""}
        fi
    fi

    if ! validate_required_params "$ipv6gw_id" "$name" "错误：IPv6 网关ID 和名称不能为空。"; then
        echo "用法：vpc set-ipv6gw <IPv6网关ID> <新名称> [新规格]" >&2
        return 1
    fi

    echo "更新 IPv6 网关："
    local api_args=(
        "--ipv6-gateway-id" "$ipv6gw_id"
        "--name" "$name"
        "--biz-region-id" "$region"
    )

    if [ -n "$spec" ]; then
        api_args+=("--spec" "$spec")
    fi

    call_api_logged "vpc" "set-ipv6gw" "错误：IPv6 网关更新失败。" \
        -- vpc modify-ipv6-gateway-attribute "${api_args[@]}"
}

# 删除 IPv6 网关（使用框架函数并添加 fzf 选择）
vpc_ipv6gw_delete() {
    local ipv6gw_id
    ipv6gw_id=$(_vpc_resolve_ipv6gw_id "$1" "选择要删除的 IPv6 网关") || return 1

    if ! confirm_action "删除 IPv6 网关：$ipv6gw_id"; then
        return 1
    fi

    call_api_del_logged "vpc" "$ipv6gw_id" "IPv6网关" "错误：IPv6 网关删除失败。" \
        -- vpc delete-ipv6-gateway --ipv6-gateway-id "$ipv6gw_id" --biz-region-id "$region" --region "$region"
}
