#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 负载均衡服务（Load Balancer Services, LBS）相关函数

show_lbs_help() {
    echo "负载均衡服务 (Load Balancer Services) 操作："
    echo "  list [type]                              - 列出负载均衡实例，type 可选 slb/nlb/alb"
    echo "  create <type> <名称> [其他参数...]        - 创建负载均衡实例"
    echo "  update <type> <实例ID> <新名称> [地域]    - 更新负载均衡实例"
    echo "  delete <type> <实例ID> [地域]             - 删除负载均衡实例"
    echo
    echo "示例："
    echo "  $0 lbs list"
    echo "  $0 lbs list nlb"
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
    slb)
        clb_list "$format"
        ;;
    *)
        echo "错误：未知的负载均衡类型：$lb_type" >&2
        return 1
        ;;
    esac
}

clb_list() {
    local format=${1:-human}
    local result
    if ! result=$(aliyun --profile "${profile:-}" slb DescribeLoadBalancers --RegionId "${region:-}"); then
        echo "错误：无法获取 CLB 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        echo -e "LoadBalancerId\tLoadBalancerName\tLoadBalancerStatus\tAddress\tCreateTime"
        echo "$result" | jq -r '.LoadBalancers.LoadBalancer[] | [.LoadBalancerId, .LoadBalancerName, .LoadBalancerStatus, .Address, .CreateTime] | @tsv'
        ;;
    human | *)
        if [[ $(echo "$result" | jq '.LoadBalancers.LoadBalancer | length') -eq 0 ]]; then
            echo "没有找到 CLB 实例。"
        else
            echo "列出 CLB 实例："
            echo "实例ID            名称                状态    IP地址        创建时间"
            echo "----------------  ------------------  ------  ------------  -------------------------"
            echo "$result" | jq -r '.LoadBalancers.LoadBalancer[] | [.LoadBalancerId, .LoadBalancerName, .LoadBalancerStatus, .Address, .CreateTime] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
            {
                status = $3;
                if (status == "active") status = "运行中";
                else if (status == "inactive") status = "已停止";
                else status = "未知";
                printf "%-16s  %-18s  %-6s  %-12s  %s\n", $1, $2, status, $4, $5
            }'
        fi
        ;;
    esac
    log_result "${profile:-}" "$region" "slb" "list" "$result" "$format"
}

nlb_list() {
    local format=${1:-human}
    local result
    if ! result=$(aliyun --profile "${profile:-}" nlb ListLoadBalancers --RegionId "$region"); then
        echo "错误：无法获取 NLB 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        echo -e "LoadBalancerId\tLoadBalancerName\tLoadBalancerStatus\tZoneId\tPublicIP\tPrivateIP\tVpcId\tCreateTime"
        echo "$result" | jq -r '.LoadBalancers[] | .ZoneMappings[] as $zone | [
            .LoadBalancerId,
            .LoadBalancerName,
            .LoadBalancerStatus,
            $zone.ZoneId,
            ($zone.LoadBalancerAddresses[0].PublicIPv4Address // "-"),
            ($zone.LoadBalancerAddresses[0].PrivateIPv4Address // "-"),
            .VpcId,
            .CreateTime
        ] | @tsv'
        ;;
    human | *)
        if [[ $(echo "$result" | jq '.LoadBalancers | length') -eq 0 ]]; then
            echo "没有找到 NLB 实例。"
        else
            echo "列出 NLB 实例："
            echo "实例ID            名称          状态  可用区      公网IP        内网IP        VPC-ID         创建时间"
            echo "----------------  ------------  ----  ----------  ------------  ------------  -------------  -------------------------"
            echo "$result" | jq -r '.LoadBalancers[] | .ZoneMappings[] as $zone | [
                .LoadBalancerId,
                .LoadBalancerName,
                .LoadBalancerStatus,
                $zone.ZoneId,
                ($zone.LoadBalancerAddresses[0].PublicIPv4Address // "-"),
                ($zone.LoadBalancerAddresses[0].PrivateIPv4Address // "-"),
                .VpcId,
                .CreateTime
            ] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
            {
                status = $3;
                if (status == "Active") status = "运行";
                else if (status == "Inactive") status = "停止";
                else status = "未知";
                printf "%-16s  %-12s  %-4s  %-10s  %-12s  %-12s  %-13s  %s\n", $1, $2, status, $4, $5, $6, $7, $8
            }'
        fi
        ;;
    esac
    log_result "$profile" "$region" "nlb" "list" "$result" "$format"
}

alb_list() {
    local format=${1:-human}
    local result
    if ! result=$(aliyun --profile "${profile:-}" alb ListLoadBalancers --RegionId "$region"); then
        echo "错误：无法获取 ALB 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "LoadBalancerId\tLoadBalancerName\tLoadBalancerStatus\tDNSName\tCreateTime"
        echo "$result" | jq -r '.LoadBalancers[] | [.LoadBalancerId, .LoadBalancerName, .LoadBalancerStatus, .DNSName, .CreateTime] | @tsv'
        ;;
    human | *)
        if [[ $(echo "$result" | jq '.LoadBalancers | length') -eq 0 ]]; then
            echo "没有找到 ALB 实例。"
        else
            echo "列出 ALB 实例："
            echo "实例ID            名称                状态    DNS名称                                  创建时间"
            echo "----------------  ------------------  ------  ----------------------------------------  -------------------------"
            echo "$result" | jq -r '.LoadBalancers[] | [.LoadBalancerId, .LoadBalancerName, .LoadBalancerStatus, .DNSName, .CreateTime] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
            {
                status = $3;
                if (status == "Active") status = "运行中";
                else if (status == "Inactive") status = "已停止";
                else status = "未知";
                printf "%-16s  %-18s  %-6s  %-40s  %s\n", $1, $2, status, $4, $5
            }'
        fi
        ;;
    esac
    log_result "$profile" "$region" "alb" "list" "$result" "$format"
}

lbs_create() {
    local lb_type=$1
    shift

    case "$lb_type" in
    slb)
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
        return 1
        ;;
    esac
}

slb_create() {
    local name=$1 spec=$2 pay_type=$3
    echo "创建 SLB 实例："
    local result
    result=$(aliyun --profile "${profile:-}" slb CreateLoadBalancer \
        --RegionId "$region" \
        --LoadBalancerName "$name" \
        --LoadBalancerSpec "$spec" \
        --PayType "$pay_type")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "slb" "create" "$result"
}

nlb_create() {
    local name=$1 vpc_id=$2 vswitch_id=$3
    echo "创建 NLB 实例："
    local result
    result=$(aliyun --profile "${profile:-}" nlb CreateLoadBalancer \
        --RegionId "$region" \
        --LoadBalancerName "$name" \
        --VpcId "$vpc_id" \
        --ZoneMappings "[{\"VSwitchId\":\"$vswitch_id\"}]")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "nlb" "create" "$result"
}

alb_create() {
    local name=$1 vpc_id=$2 vswitch_id=$3
    echo "创建 ALB 实例："
    local result
    result=$(aliyun --profile "${profile:-}" alb CreateLoadBalancer \
        --RegionId "$region" \
        --LoadBalancerName "$name" \
        --VpcId "$vpc_id" \
        --ZoneMappings "[{\"VSwitchId\":\"$vswitch_id\"}]")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "alb" "create" "$result"
}

lbs_update() {
    local lb_type=$1 lb_id=$2 new_name=$3

    case "$lb_type" in
    slb)
        slb_update "$lb_id" "$new_name" "$region"
        ;;
    nlb)
        nlb_update "$lb_id" "$new_name" "$region"
        ;;
    alb)
        alb_update "$lb_id" "$new_name" "$region"
        ;;
    *)
        echo "错误：未知的负载均衡类型：$lb_type" >&2
        return 1
        ;;
    esac
}

slb_update() {
    local lb_id=$1 new_name=$2
    echo "更新 SLB 实例："
    local result
    result=$(aliyun --profile "${profile:-}" slb SetLoadBalancerName \
        --LoadBalancerId "$lb_id" \
        --LoadBalancerName "$new_name")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "slb" "update" "$result"
}

nlb_update() {
    local lb_id=$1 new_name=$2
    echo "更新 NLB 实例："
    local result
    result=$(aliyun --profile "${profile:-}" nlb UpdateLoadBalancerAttribute \
        --LoadBalancerId "$lb_id" \
        --LoadBalancerName "$new_name")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "nlb" "update" "$result"
}

alb_update() {
    local lb_id=$1 new_name=$2
    echo "更新 ALB 实例："
    local result
    result=$(aliyun --profile "${profile:-}" alb UpdateLoadBalancerAttribute \
        --LoadBalancerId "$lb_id" \
        --LoadBalancerName "$new_name")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "alb" "update" "$result"
}

lbs_delete() {
    local lb_type=$1 lb_id=$2

    case "$lb_type" in
    slb)
        slb_delete "$lb_id" "$region"
        ;;
    nlb)
        nlb_delete "$lb_id" "$region"
        ;;
    alb)
        alb_delete "$lb_id" "$region"
        ;;
    *)
        echo "错误：未知的负载均衡类型：$lb_type" >&2
        return 1
        ;;
    esac
}

slb_delete() {
    local lb_id=$1
    echo "删除 SLB 实例："
    local result
    result=$(aliyun --profile "${profile:-}" slb DeleteLoadBalancer --LoadBalancerId "$lb_id")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "slb" "delete" "$result"
}

nlb_delete() {
    local lb_id=$1
    echo "删除 NLB 实例："
    local result
    result=$(aliyun --profile "${profile:-}" nlb DeleteLoadBalancer --LoadBalancerId "$lb_id")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "nlb" "delete" "$result"
}

alb_delete() {
    local lb_id=$1
    echo "删除 ALB 实例："
    local result
    result=$(aliyun --profile "${profile:-}" alb DeleteLoadBalancer --LoadBalancerId "$lb_id")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "alb" "delete" "$result"
}
