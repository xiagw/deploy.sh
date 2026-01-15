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
