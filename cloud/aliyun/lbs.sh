#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 负载均衡服务（Load Balancer Services, LBS）相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_lbs_help() {
    echo "负载均衡服务 (Load Balancer Services) 操作："
    echo "  get [type] [format]                     - 列出负载均衡实例，type 可选 clb/nlb/alb"
    echo "  add <type> <名称> [其他参数...]         - 创建负载均衡实例"
    echo "  set <type> [<实例ID>] [<新名称>]        - 更新负载均衡实例（实例ID和新名称都是可选的，可使用fzf选择）"
    echo "  del [type] [<实例ID>]                   - 删除负载均衡实例（type 和实例ID 均可选，未提供时用 fzf 选择）"
    echo
    echo "示例："
    echo "  $0 lbs get"
    echo "  $0 lbs get nlb"
    echo "  $0 lbs get clb json"
    echo "  $0 lbs add clb my-clb slb.s1.small PayOnDemand"
    echo "  $0 lbs add nlb my-nlb vpc-xxx vsw-xxx"
    echo "  $0 lbs set alb alb-bp1b6c719dfa08exfuca1 new-name"
    echo "  $0 lbs del                              # 交互选择类型和实例"
    echo "  $0 lbs del clb lb-bp1b6c719dfa08exfuca1"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_lbs_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get)
        local lb_type=${1:-all}
        local format=${2:-human}
        lbs_list "$lb_type" "$format"
        ;;
    add)
        local lb_type=$1
        shift
        lbs_create "$lb_type" "$@"
        ;;
    set)
        local lb_type=$1
        shift
        lbs_update "$lb_type" "$@"
        ;;
    del)
        local lb_type=$1
        shift
        lbs_delete "$lb_type" "$@"
        ;;
    help) show_lbs_help ;;
    *)
        echo "错误：未知的负载均衡操作：$operation" >&2
        show_lbs_help
        exit 1
        ;;
    esac
}

lbs_list() {
    local lb_type=${1:-all}
    local format=${2:-human}

    case "$lb_type" in
    all)
        echo "列出 ALB、NLB、CLB 实例："
        alb_list "$format"
        nlb_list "$format"
        clb_list "$format"
        ;;
    alb)
        alb_list "$format"
        ;;
    nlb)
        nlb_list "$format"
        ;;
    clb | slb)
        clb_list "$format"
        ;;
    *)
        echo "错误：未知的负载均衡类型：$lb_type" >&2
        return 1
        ;;
    esac
}

# CLB 列表
clb_list() {
    local format=${1:-human}

    local table_header="LoadBalancerId\tLoadBalancerName\tLoadBalancerStatus\tAddress\tCreateTime"
    local jq_filter=".LoadBalancers.LoadBalancer[] | [.LoadBalancerId, .LoadBalancerName, .LoadBalancerStatus, .Address, .CreateTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"}
    {
        status = $3;
        if (status == "active") status = "运行中";
        else if (status == "inactive") status = "已停止";
        else status = "未知";
        printf "%-16s  %-18s  %-6s  %-12s  %s\n", $1, $2, status, $4, $5
    }'

    local result
    result=$(call_aliyun_api slb describe-load-balancers --biz-region-id "${region:-}" --api-version 2014-05-15)

    if [ $? -ne 0 ]; then
        echo "错误：无法获取 CLB 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "slb" \
        "list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 CLB 实例。" \
        "列出 CLB 实例："
}

# NLB 列表
nlb_list() {
    local format=${1:-human}

    local table_header="LoadBalancerId\tLoadBalancerName\tLoadBalancerStatus\tZoneIds\tPublicIP\tPrivateIP\tVpcId\tCreateTime"
    local jq_filter=".LoadBalancers[] | {
        LoadBalancerId: .LoadBalancerId,
        LoadBalancerName: .LoadBalancerName,
        LoadBalancerStatus: .LoadBalancerStatus,
        ZoneIds: ([.ZoneMappings[].ZoneId] | join(\",\")),
        PublicIPs: ([.ZoneMappings[].LoadBalancerAddresses[0].PublicIPv4Address] | map(select(. != null)) | join(\",\")),
        PrivateIPs: ([.ZoneMappings[].LoadBalancerAddresses[0].PrivateIPv4Address] | map(select(. != null)) | join(\",\")),
        VpcId: .VpcId,
        CreateTime: .CreateTime
    } | [
        .LoadBalancerId,
        .LoadBalancerName,
        .LoadBalancerStatus,
        .ZoneIds,
        (.PublicIPs // \"-\"),
        (.PrivateIPs // \"-\"),
        .VpcId,
        .CreateTime
    ] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-20s  %-20s  %-10s  %-30s  %-15s  %-15s  %-18s  %s\n", $1, $2, $3, $4, $5, $6, $7, $8}'

    local result
    result=$(call_aliyun_api nlb list-load-balancers --biz-region-id "${region:-}" --api-version 2022-04-30)

    if [ $? -ne 0 ]; then
        echo "错误：无法获取 NLB 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "nlb" \
        "list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 NLB 实例。" \
        "列出 NLB 实例："
}

# ALB 列表
alb_list() {
    local format=${1:-human}

    local table_header="LoadBalancerId\tLoadBalancerName\tLoadBalancerStatus\tAddressType\tVpcId\tCreateTime"
    local jq_filter=".LoadBalancers[] | [.LoadBalancerId, .LoadBalancerName, .LoadBalancerStatus, .AddressType, .VpcId, .CreateTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-20s  %-20s  %-10s  %-12s  %-18s  %s\n", $1, $2, $3, $4, $5, $6}'

    local result
    result=$(call_aliyun_api alb list-load-balancers --biz-region-id "${region:-}" --api-version 2022-04-30)

    if [ $? -ne 0 ]; then
        echo "错误：无法获取 ALB 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "alb" \
        "list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 ALB 实例。" \
        "列出 ALB 实例："
}

# 创建函数（保持原有逻辑，但使用框架函数）
lbs_create() {
    local lb_type=$1
    shift

    case "$lb_type" in
    clb | slb)
        slb_create "$@"
        ;;
    nlb)
        nlb_create "$@"
        ;;
    alb)
        alb_create "$@"
        ;;
    *)
        echo "错误：未知的负载均衡类型：$lb_type" >&2
        echo "支持的类型：clb, nlb, alb（clb 即传统型负载均衡）" >&2
        return 1
        ;;
    esac
}

slb_create() {
    local name=$1 spec=$2 pay_type=$3

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$name" ] || [ -z "$spec" ] || [ -z "$pay_type" ]; then
        echo "使用 fzf 交互式模式创建 CLB 实例"

        # 输入名称
        if [ -z "$name" ]; then
            read -r -p "请输入 CLB 实例名称: " name
            if [ -z "$name" ]; then
                echo "错误：实例名称不能为空。" >&2
                return 1
            fi
        fi

        # 选择规格
        if [ -z "$spec" ]; then
            echo "正在获取可用的 CLB 规格..."
            local spec_result
            spec_result=$(call_aliyun_api slb describe-load-balancers --biz-region-id "${region:-}" --api-version 2014-05-15 2>/dev/null)

            local spec_list
            if [ $? -eq 0 ] && [ -n "$spec_result" ]; then
                spec_list="slb.s1.small
slb.s1.medium
slb.s2.small
slb.s2.medium
slb.s3.small
slb.s3.medium
slb.s3.large
slb.s2.large
slb.s3.xlarge"
                echo "使用可用规格列表。"
            else
                echo "警告：无法从 API 获取规格信息，使用默认列表。" >&2
                spec_list="slb.s1.small
slb.s1.medium
slb.s2.small
slb.s2.medium
slb.s3.small
slb.s3.medium
slb.s3.large"
            fi

            if type select_with_fzf >/dev/null 2>&1; then
                spec=$(select_with_fzf "选择 CLB 规格" "$spec_list")
            else
                echo "错误：需要选择 CLB 规格，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi

        # 选择付费类型
        if [ -z "$pay_type" ]; then
            echo "获取付费类型选项..."
            local pay_type_list="PayOnDemand
PrePaid"
            if type select_with_fzf >/dev/null 2>&1; then
                pay_type=$(select_with_fzf "选择 CLB 付费类型" "$pay_type_list")
            else
                pay_type="PayOnDemand"
                echo "使用默认付费类型: $pay_type"
            fi
        fi
    fi

    if ! validate_required_params "$name" "$spec" "$pay_type" "错误：名称、规格和付费类型不能为空。"; then
        return 1
    fi

    echo "创建 CLB 实例："
    call_api_logged "slb" "create" "错误：CLB 实例创建失败。" \
        -- slb create-load-balancer --biz-region-id "${region:-}" --api-version 2014-05-15 \
        --load-balancer-name "$name" \
        --load-balancer-spec "$spec" \
        --pay-type "$pay_type"
}

nlb_create() {
    local name=$1 vpc_id=$2 vswitch_id=$3

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$name" ] || [ -z "$vpc_id" ] || [ -z "$vswitch_id" ]; then
        echo "使用 fzf 交互式模式创建 NLB 实例"

        # 输入名称
        if [ -z "$name" ]; then
            read -r -p "请输入 NLB 实例名称: " name
            if [ -z "$name" ]; then
                echo "错误：实例名称不能为空。" >&2
                return 1
            fi
        fi

        # 选择 VPC
        if [ -z "$vpc_id" ]; then
            vpc_id=$(resolve_resource_id "" "选择 VPC" "错误：没有找到 VPC。" \
                '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"' \
                -- vpc describe-vpcs --biz-region-id "${region:-}" --api-version 2016-04-28) || return 1
        fi

        # 选择交换机
        if [ -z "$vswitch_id" ]; then
            vswitch_id=$(resolve_resource_id "" "选择交换机" "错误：在选定的 VPC 中没有找到交换机。" \
                '.VSwitches.VSwitch[] | "\(.VSwitchId) (\(.VSwitchName // .VSwitchId)) [\(.CidrBlock)]"' \
                -- vpc describe-vswitches --biz-region-id "${region:-}" --api-version 2016-04-28 --vpc-id "$vpc_id") || return 1
        fi
    fi

    if ! validate_required_params "$name" "$vpc_id" "$vswitch_id" "错误：名称、VPC ID和交换机ID不能为空。"; then
        return 1
    fi

    echo "创建 NLB 实例："
    call_api_logged "nlb" "create" "错误：NLB 实例创建失败。" \
        -- nlb create-load-balancer --biz-region-id "${region:-}" --api-version 2022-04-30 \
        --load-balancer-name "$name" \
        --vpc-id "$vpc_id" \
        --zone-mappings "[{\"VSwitchId\":\"$vswitch_id\",\"ZoneId\":\"${zone:-}\"}]" \
        --address-type Internet
}

alb_create() {
    local name=$1 vpc_id=$2 vswitch_id=$3

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$name" ] || [ -z "$vpc_id" ] || [ -z "$vswitch_id" ]; then
        echo "使用 fzf 交互式模式创建 ALB 实例"

        # 输入名称
        if [ -z "$name" ]; then
            read -r -p "请输入 ALB 实例名称: " name
            if [ -z "$name" ]; then
                echo "错误：实例名称不能为空。" >&2
                return 1
            fi
        fi

        # 选择 VPC
        if [ -z "$vpc_id" ]; then
            vpc_id=$(resolve_resource_id "" "选择 VPC" "错误：没有找到 VPC。" \
                '.Vpcs.Vpc[] | "\(.VpcId) (\(.VpcName // .VpcId)) [\(.CidrBlock)]"' \
                -- vpc describe-vpcs --biz-region-id "${region:-}" --api-version 2016-04-28) || return 1
        fi

        # 选择交换机
        if [ -z "$vswitch_id" ]; then
            vswitch_id=$(resolve_resource_id "" "选择交换机" "错误：在选定的 VPC 中没有找到交换机。" \
                '.VSwitches.VSwitch[] | "\(.VSwitchId) (\(.VSwitchName // .VSwitchId)) [\(.CidrBlock)]"' \
                -- vpc describe-vswitches --biz-region-id "${region:-}" --api-version 2016-04-28 --vpc-id "$vpc_id") || return 1
        fi
    fi

    if ! validate_required_params "$name" "$vpc_id" "$vswitch_id" "错误：名称、VPC ID和交换机ID不能为空。"; then
        return 1
    fi

    echo "创建 ALB 实例："
    call_api_logged "alb" "create" "错误：ALB 实例创建失败。" \
        -- alb create-load-balancer --biz-region-id "${region:-}" --api-version 2022-04-30 \
        --load-balancer-name "$name" \
        --vpc-id "$vpc_id" \
        --zone-mappings "[{\"VSwitchId\":\"$vswitch_id\",\"ZoneId\":\"${zone:-}\"}]" \
        --address-type Internet
}

# 按类型填充 LB 元数据（调用方需先 local 声明这些变量，避免污染全局）
_lbs_set_meta() {
    case "$1" in
    clb | slb)
        _lb_product=slb _lb_api_ver=2014-05-15 _lb_list_action=describe-load-balancers
        _lb_jq_root='.LoadBalancers.LoadBalancer[]' _lb_label=CLB
        _lb_update_action=set-load-balancer-name
        ;;
    nlb)
        _lb_product=nlb _lb_api_ver=2022-04-30 _lb_list_action=list-load-balancers
        _lb_jq_root='.LoadBalancers[]' _lb_label=NLB
        _lb_update_action=update-load-balancer-attribute
        ;;
    alb)
        _lb_product=alb _lb_api_ver=2022-04-30 _lb_list_action=list-load-balancers
        _lb_jq_root='.LoadBalancers[]' _lb_label=ALB
        _lb_update_action=update-load-balancer-attribute
        ;;
    *)
        echo "错误：未知的负载均衡类型：$1" >&2
        return 1
        ;;
    esac
}

# 解析 LB 实例 ID（未传入时 fzf 选择）: _lbs_resolve_lb_id <type> <current> <动词>
_lbs_resolve_lb_id() {
    local _lb_product _lb_api_ver _lb_list_action _lb_jq_root _lb_label _lb_update_action
    _lbs_set_meta "$1" || return 1
    resolve_resource_id "$2" "选择要$3的 ${_lb_label} 实例" "错误：没有找到 ${_lb_label} 实例。" \
        "${_lb_jq_root} | \"\(.LoadBalancerId) (\(.LoadBalancerName)) [\(.LoadBalancerStatus)]\"" \
        -- "$_lb_product" "$_lb_list_action" --biz-region-id "${region:-}" --api-version "$_lb_api_ver"
}

# 更新函数（clb/nlb/alb 通用）
lbs_update() {
    local lb_type=$1
    shift

    local _lb_product _lb_api_ver _lb_list_action _lb_jq_root _lb_label _lb_update_action
    _lbs_set_meta "$lb_type" || return 1

    local lb_id new_name=$2
    lb_id=$(_lbs_resolve_lb_id "$lb_type" "$1" "更新") || return 1

    if [ -z "$new_name" ]; then
        read -r -p "请输入新的实例名称: " new_name
        if [ -z "$new_name" ]; then
            echo "错误：新名称不能为空。" >&2
            return 1
        fi
    fi

    echo "更新 ${_lb_label} 实例："
    call_api_logged "$_lb_product" "update" "错误：${_lb_label} 实例更新失败。" \
        -- "$_lb_product" "$_lb_update_action" --biz-region-id "${region:-}" --api-version "$_lb_api_ver" \
        --load-balancer-id "$lb_id" \
        --load-balancer-name "$new_name"
}

# 删除函数（使用框架函数）
lbs_delete() {
    local lb_type=$1
    shift

    # 未指定类型时，先让用户选择类型（clb/nlb/alb）
    if [ -z "$lb_type" ]; then
        local type_list="clb (传统型负载均衡)
nlb (网络型负载均衡)
alb (应用型负载均衡)"
        if type select_with_fzf >/dev/null 2>&1; then
            local selected
            selected=$(select_with_fzf "选择要删除的负载均衡类型" "$type_list")
            lb_type=$(echo "$selected" | awk '{print $1}')
        else
            echo "请先指定负载均衡类型：clb / nlb / alb" >&2
            echo "示例：$0 lbs del clb   或  $0 lbs del clb <实例ID>" >&2
            return 1
        fi
        if [ -z "$lb_type" ]; then
            echo "错误：未选择类型。" >&2
            return 1
        fi
    fi

    local _lb_product _lb_api_ver _lb_list_action _lb_jq_root _lb_label _lb_update_action
    _lbs_set_meta "$lb_type" || return 1

    local lb_id
    lb_id=$(_lbs_resolve_lb_id "$lb_type" "$1" "删除") || return 1

    if ! confirm_action "删除 ${_lb_label} 实例：$lb_id"; then
        return 1
    fi

    echo "删除 ${_lb_label} 实例："
    call_api_del_logged "$_lb_product" "$lb_id" "${_lb_label}实例" "错误：${_lb_label} 实例删除失败。" \
        -- "$_lb_product" delete-load-balancer --biz-region-id "${region:-}" --api-version "$_lb_api_ver" \
        --load-balancer-id "$lb_id" || return 1
    echo "${_lb_label} 实例删除成功。"
}
