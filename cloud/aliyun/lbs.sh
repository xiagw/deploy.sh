#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 负载均衡服务（Load Balancer Services, LBS）相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_lbs_help() {
    echo "负载均衡服务 (Load Balancer Services) 操作："
    echo "  list [type] [format]                    - 列出负载均衡实例，type 可选 slb/nlb/alb"
    echo "  create <type> <名称> [其他参数...]       - 创建负载均衡实例"
    echo "  update <type> <实例ID> <新名称>          - 更新负载均衡实例"
    echo "  delete <type> <实例ID>                  - 删除负载均衡实例"
    echo
    echo "示例："
    echo "  $0 lbs list"
    echo "  $0 lbs list nlb"
    echo "  $0 lbs list slb json"
    echo "  $0 lbs create slb my-slb slb.s1.small PayOnDemand"
    echo "  $0 lbs create nlb my-nlb vpc-xxx vsw-xxx"
    echo "  $0 lbs update alb alb-bp1b6c719dfa08exfuca1 new-name"
    echo "  $0 lbs delete slb lb-bp1b6c719dfa08exfuca1"
}

handle_lbs_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list)
        local lb_type=${1:-all}
        local format=${2:-human}
        lbs_list "$lb_type" "$format"
        ;;
    create)
        local lb_type=$1
        shift
        lbs_create "$lb_type" "$@"
        ;;
    update)
        local lb_type=$1
        shift
        lbs_update "$lb_type" "$@"
        ;;
    delete)
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
        echo "列出 ALB、NLB、SLB 实例："
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
    slb | clb)
        clb_list "$format"
        ;;
    *)
        echo "错误：未知的负载均衡类型：$lb_type" >&2
        return 1
        ;;
    esac
}

# CLB (原 SLB) 列表
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
    result=$(call_aliyun_api slb DescribeLoadBalancers --RegionId "${region:-}")

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

    local table_header="LoadBalancerId\tLoadBalancerName\tLoadBalancerStatus\tZoneId\tPublicIP\tPrivateIP\tVpcId\tCreateTime"
    local jq_filter=".LoadBalancers[] | .ZoneMappings[] as \$zone | [
        .LoadBalancerId,
        .LoadBalancerName,
        .LoadBalancerStatus,
        \$zone.ZoneId,
        (\$zone.LoadBalancerAddresses[0].PublicIPv4Address // \"-\"),
        (\$zone.LoadBalancerAddresses[0].PrivateIPv4Address // \"-\"),
        .VpcId,
        .CreateTime
    ] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-20s  %-20s  %-10s  %-10s  %-15s  %-15s  %-18s  %s\n", $1, $2, $3, $4, $5, $6, $7, $8}'

    local result
    result=$(call_aliyun_api nlb ListLoadBalancers --RegionId "$region")

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
    result=$(call_aliyun_api alb ListLoadBalancers --RegionId "$region")

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
    slb | clb)
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
        echo "支持的类型：slb/clb, nlb, alb" >&2
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
            spec_result=$(call_aliyun_api slb DescribeLoadBalancers --RegionId "$region" 2>/dev/null)

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
    local result
    result=$(call_aliyun_api slb CreateLoadBalancer \
        --RegionId "$region" \
        --LoadBalancerName "$name" \
        --LoadBalancerSpec "$spec" \
        --PayType "$pay_type")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "slb" "create" "$result"
    else
        echo "错误：CLB 实例创建失败。"
        echo "$result"
        return 1
    fi
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

        # 选择交换机
        if [ -z "$vswitch_id" ]; then
            local vswitch_list
            vswitch_list=$(call_aliyun_api vpc DescribeVSwitches --RegionId "$region" --VpcId "$vpc_id" 2>/dev/null | jq -r '.VSwitches.VSwitch[] | "\(.VSwitchId) (\(.VSwitchName // .VSwitchId)) [\(.CidrBlock)]"')

            if [ -z "$vswitch_list" ]; then
                echo "错误：在选定的 VPC 中没有找到交换机。" >&2
                return 1
            elif [ "$(echo "$vswitch_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
                vswitch_id=$(echo "$vswitch_list" | awk '{print $1}')
                echo "自动选择唯一的交换机: $vswitch_id"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    vswitch_id=$(select_with_fzf "选择交换机" "$vswitch_list" | awk '{print $1}')
                else
                    echo "错误：需要选择交换机，但未找到交互式选择工具。" >&2
                    return 1
                fi
            fi
        fi
    fi

    if ! validate_required_params "$name" "$vpc_id" "$vswitch_id" "错误：名称、VPC ID和交换机ID不能为空。"; then
        return 1
    fi

    echo "创建 NLB 实例："
    local result
    result=$(call_aliyun_api nlb CreateLoadBalancer \
        --RegionId "$region" \
        --LoadBalancerName "$name" \
        --VpcId "$vpc_id" \
        --ZoneMappings "[{\"VSwitchId\":\"$vswitch_id\",\"ZoneId\":\"${zone:-}\"}]" \
        --AddressType Internet)

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "nlb" "create" "$result"
    else
        echo "错误：NLB 实例创建失败。"
        echo "$result"
        return 1
    fi
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

        # 选择交换机
        if [ -z "$vswitch_id" ]; then
            local vswitch_list
            vswitch_list=$(call_aliyun_api vpc DescribeVSwitches --RegionId "$region" --VpcId "$vpc_id" 2>/dev/null | jq -r '.VSwitches.VSwitch[] | "\(.VSwitchId) (\(.VSwitchName // .VSwitchId)) [\(.CidrBlock)]"')

            if [ -z "$vswitch_list" ]; then
                echo "错误：在选定的 VPC 中没有找到交换机。" >&2
                return 1
            elif [ "$(echo "$vswitch_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
                vswitch_id=$(echo "$vswitch_list" | awk '{print $1}')
                echo "自动选择唯一的交换机: $vswitch_id"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    vswitch_id=$(select_with_fzf "选择交换机" "$vswitch_list" | awk '{print $1}')
                else
                    echo "错误：需要选择交换机，但未找到交互式选择工具。" >&2
                    return 1
                fi
            fi
        fi
    fi

    if ! validate_required_params "$name" "$vpc_id" "$vswitch_id" "错误：名称、VPC ID和交换机ID不能为空。"; then
        return 1
    fi

    echo "创建 ALB 实例："
    local result
    result=$(call_aliyun_api alb CreateLoadBalancer \
        --RegionId "$region" \
        --LoadBalancerName "$name" \
        --VpcId "$vpc_id" \
        --ZoneMappings "[{\"VSwitchId\":\"$vswitch_id\",\"ZoneId\":\"${zone:-}\"}]" \
        --AddressType Internet)

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "alb" "create" "$result"
    else
        echo "错误：ALB 实例创建失败。"
        echo "$result"
        return 1
    fi
}

# 更新函数（使用框架函数）
lbs_update() {
    local lb_type=$1
    shift

    case "$lb_type" in
    slb | clb)
        slb_update "$@"
        ;;
    nlb)
        nlb_update "$@"
        ;;
    alb)
        alb_update "$@"
        ;;
    *)
        echo "错误：未知的负载均衡类型：$lb_type" >&2
        return 1
        ;;
    esac
}

slb_update() {
    local lb_id=$1 new_name=$2

    if ! validate_required_params "$lb_id" "$new_name" "错误：实例ID和新名称不能为空。"; then
        return 1
    fi

    echo "更新 CLB 实例："
    local result
    result=$(call_aliyun_api slb SetLoadBalancerName \
        --RegionId "$region" \
        --LoadBalancerId "$lb_id" \
        --LoadBalancerName "$new_name")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "slb" "update" "$result"
    else
        echo "错误：CLB 实例更新失败。"
        echo "$result"
        return 1
    fi
}

nlb_update() {
    local lb_id=$1 new_name=$2

    if ! validate_required_params "$lb_id" "$new_name" "错误：实例ID和新名称不能为空。"; then
        return 1
    fi

    echo "更新 NLB 实例："
    local result
    result=$(call_aliyun_api nlb UpdateLoadBalancerAttribute \
        --RegionId "$region" \
        --LoadBalancerId "$lb_id" \
        --LoadBalancerName "$new_name")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "nlb" "update" "$result"
    else
        echo "错误：NLB 实例更新失败。"
        echo "$result"
        return 1
    fi
}

alb_update() {
    local lb_id=$1 new_name=$2

    if ! validate_required_params "$lb_id" "$new_name" "错误：实例ID和新名称不能为空。"; then
        return 1
    fi

    echo "更新 ALB 实例："
    local result
    result=$(call_aliyun_api alb UpdateLoadBalancerAttribute \
        --RegionId "$region" \
        --LoadBalancerId "$lb_id" \
        --LoadBalancerName "$new_name")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "alb" "update" "$result"
    else
        echo "错误：ALB 实例更新失败。"
        echo "$result"
        return 1
    fi
}

# 删除函数（使用框架函数）
lbs_delete() {
    local lb_type=$1
    shift

    case "$lb_type" in
    slb | clb)
        slb_delete "$@"
        ;;
    nlb)
        nlb_delete "$@"
        ;;
    alb)
        alb_delete "$@"
        ;;
    *)
        echo "错误：未知的负载均衡类型：$lb_type" >&2
        return 1
        ;;
    esac
}

slb_delete() {
    local lb_id=$1

    if [ -z "$lb_id" ]; then
        echo "错误：实例ID不能为空。" >&2
        return 1
    fi

    if ! confirm_action "删除 CLB 实例：$lb_id"; then
        return 1
    fi

    echo "删除 CLB 实例："
    local result
    result=$(call_aliyun_api slb DeleteLoadBalancer \
        --RegionId "$region" \
        --LoadBalancerId "$lb_id")

    if [ $? -eq 0 ]; then
        echo "CLB 实例删除成功。"
        log_delete_operation "${profile:-}" "$region" "slb" "$lb_id" "CLB实例" "成功"
    else
        echo "错误：CLB 实例删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "slb" "$lb_id" "CLB实例" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "slb" "delete" "$result"
}

nlb_delete() {
    local lb_id=$1

    if [ -z "$lb_id" ]; then
        echo "错误：实例ID不能为空。" >&2
        return 1
    fi

    if ! confirm_action "删除 NLB 实例：$lb_id"; then
        return 1
    fi

    echo "删除 NLB 实例："
    local result
    result=$(call_aliyun_api nlb DeleteLoadBalancer \
        --RegionId "$region" \
        --LoadBalancerId "$lb_id")

    if [ $? -eq 0 ]; then
        echo "NLB 实例删除成功。"
        log_delete_operation "${profile:-}" "$region" "nlb" "$lb_id" "NLB实例" "成功"
    else
        echo "错误：NLB 实例删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "nlb" "$lb_id" "NLB实例" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "nlb" "delete" "$result"
}

alb_delete() {
    local lb_id=$1

    if [ -z "$lb_id" ]; then
        echo "错误：实例ID不能为空。" >&2
        return 1
    fi

    if ! confirm_action "删除 ALB 实例：$lb_id"; then
        return 1
    fi

    echo "删除 ALB 实例："
    local result
    result=$(call_aliyun_api alb DeleteLoadBalancer \
        --RegionId "$region" \
        --LoadBalancerId "$lb_id")

    if [ $? -eq 0 ]; then
        echo "ALB 实例删除成功。"
        log_delete_operation "${profile:-}" "$region" "alb" "$lb_id" "ALB实例" "成功"
    else
        echo "错误：ALB 实例删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "alb" "$lb_id" "ALB实例" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "alb" "delete" "$result"
}
