#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016
# -*- coding: utf-8 -*-

# ACK (容器服务 Kubernetes 版) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_ack_help() {
    echo "ACK (容器服务 Kubernetes 版) 操作："
    echo "  get                                     - 列出所有集群"
    echo "  add <名称> [参数...]                   - 创建新集群"
    echo "  del [<集群ID>]                          - 删除集群（集群ID可选，可使用fzf选择）"
    echo "  set [<集群ID>] [<新名称>]               - 更新集群（集群ID和新名称都是可选的，可使用fzf选择）"
    echo "  detail [<集群ID>]                       - 获取集群详情（集群ID可选，可使用fzf选择）"
    echo "  get-node [<集群ID>] [format]           - 列出集群节点（集群ID可选，可使用fzf选择）"
    echo "  add-node [<集群ID>] [<节点池>] [数量]   - 添加集群节点（集群ID和节点池可选，可使用fzf选择）"
    echo "  del-node [<集群ID>] [<节点名>]          - 移除集群节点（集群ID和节点名可选，可使用fzf选择）"
    echo "  config [<集群ID>]                       - 获取集群的 kubeconfig（集群ID可选，可使用fzf选择）"
    echo "  auto-scale <deployment> [namespace]     - 自定义 PHP 部署自动扩缩容（应对突发流量，用户级 systemd timer 每15秒触发，勿删）"
    echo "  auto-node [<集群ID>] [内存阈值]          - 所有节点（除virtual）内存都超阈值时自动扩容 +1（优先默认池，无则选名称含 dynamic 的池；适合 crontab，默认阈值 95）"
    echo "  rebalance [内存阈值]                     - 根据节点内存使用率自动 cordon/uncordon（默认阈值 95）"
    echo "  get-pool [<集群ID>]                     - 列出集群节点池"
    echo "  scale-pool [<集群ID>] [<节点池>] [目标数] - 调整节点池节点数（可扩/缩容；未给目标数则交互输入，留空扩容到集群上限，ACK 限制最多10节点）"
    echo "  add-pool <集群ID> <名称>                - 新建节点池并加入集群"
    echo "  cordon-pool [<集群ID>] [<节点池>]       - 禁止调度到指定节点池的所有节点"
    echo "  uncordon-pool [<集群ID>] [<节点池>]     - 解除指定节点池所有节点的调度限制"
    echo "  restart-node [<节点名>]                 - 重启单个节点上的所有 deployment"
    echo "  restart-pool [<集群ID>] [<节点池>]      - 重启节点池内所有节点上的 deployment"
    echo
    echo "示例："
    echo "  $0 ack get"
    echo "  $0 ack get json"
    echo "  $0 ack add my-cluster"
    echo "  $0 ack add my-cluster --node-count 3 --instance-type ecs.g6.large"
    echo "  $0 ack del c-xxx"
    echo "  $0 ack set c-xxx new-name"
    echo "  $0 ack detail c-xxx"
    echo "  $0 ack get-node c-xxx"
    echo "  $0 ack add-node c-xxx 2"
    echo "  $0 ack add-node c-xxx <节点池ID> 2"
    echo "  $0 ack del-node c-xxx i-xxx"
    echo "  $0 ack config c-xxx"
    echo "  $0 ack auto-scale my-deployment default"
    echo "  $0 ack auto-node c-xxx"
    echo "  $0 ack auto-node c-xxx 95"
    echo "  $0 ack rebalance"
    echo "  $0 ack rebalance 95"
    echo "  $0 ack get-pool c-xxx"
    echo "  $0 ack scale-pool c-xxx"
    echo "  $0 ack scale-pool c-xxx <节点池ID> 4"
    echo "  $0 ack scale-pool c-xxx <节点池ID> 1"
    echo "  $0 ack add-pool c-xxx new-pool"
    echo "  $0 ack cordon-pool c-xxx <节点池ID>"
    echo "  $0 ack uncordon-pool c-xxx <节点池ID>"
    echo "  $0 ack restart-node <节点名>"
    echo "  $0 ack restart-pool c-xxx <节点池ID>"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_ack_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) ack_list "$@" ;;
    add) ack_create "$@" ;;
    del) ack_delete "$@" ;;
    set) ack_update "$@" ;;
    detail) ack_detail "$@" ;;
    get-node) ack_node_list "$@" ;;
    add-node) ack_node_add "$@" ;;
    del-node) ack_node_remove "$@" ;;
    config) ack_get_kubeconfig "$@" ;;
    auto-scale) ack_auto_scale "$@" >>"${SCRIPT_LOG:-/tmp/ack_auto_scale.log}" ;;
    auto-node) ack_auto_node "$@" >>"${SCRIPT_LOG:-/tmp/ack_auto_node.log}" ;;
    rebalance) ack_rebalance "$@" ;;
    get-pool) ack_pool_list "$@" ;;
    scale-pool) ack_pool_scale "$@" ;;
    add-pool) ack_pool_create "$@" ;;
    cordon-pool) ack_pool_cordon "$@" ;;
    uncordon-pool) ack_pool_uncordon "$@" ;;
    restart-node) ack_restart_node "$@" ;;
    restart-pool) ack_restart_pool "$@" ;;
    help) show_ack_help ;;
    *)
        echo "错误：未知的 ACK 操作：$operation" >&2
        show_ack_help
        exit 1
        ;;
    esac
}

# ACK/CS 已切换到阿里云 CLI 新版 REST 参数格式；本文件统一使用
# `cs <METHOD> <PATH> [--body ...]` 写法。
# 使用新框架的列表函数
ack_list() {
    local format=${1:-human}

    local table_header="ClusterId\tName\tState\tRegionId\tVersion\tNodeCount\tCreated"
    local jq_filter=".[] | [.cluster_id, .name, .state, .region_id, .version, .size, .created] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-16s  %-18s  %-8s  %-12s  %-7s  %-6s  %s\n", $1, $2, $3, $4, $5, $6, $7}'

    local result
    result=$(call_aliyun_api cs GET /clusters --region "${region:-}")
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：无法获取集群列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "ack" \
        "list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 ACK 集群。" \
        "列出 ACK 集群："
}

# 创建集群（保持原有复杂逻辑，但使用框架函数）
ack_create() {
    local name=$1
    shift

    if [ -z "$name" ]; then
        echo "错误：集群名称不能为空。" >&2
        return 1
    fi

    # 默认参数
    local node_count=2
    local instance_type="ecs.g6.large"
    local kubernetes_version="1.24.6-aliyun.1"
    local worker_system_disk_category="cloud_essd"
    local worker_system_disk_size=120

    # 解析其他参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --node-count)
            node_count="$2"
            shift 2
            ;;
        --instance-type)
            instance_type="$2"
            shift 2
            ;;
        --k8s-version)
            kubernetes_version="$2"
            shift 2
            ;;
        --disk-category)
            worker_system_disk_category="$2"
            shift 2
            ;;
        --disk-size)
            worker_system_disk_size="$2"
            shift 2
            ;;
        *)
            echo "错误：未知的参数：$1" >&2
            return 1
            ;;
        esac
    done

    # 获取VPC信息（需要调用 vpc 函数）
    local vpc_id
    if type get_vpc_id >/dev/null 2>&1; then
        vpc_id=$(get_vpc_id)
    else
        local vpc_result
        vpc_result=$(call_aliyun_api vpc describe-vpcs --biz-region-id "${region:-cn-hangzhou}" 2>/dev/null)
        vpc_id=$(echo "$vpc_result" | jq -r '.Vpcs.Vpc[0].VpcId // empty')
    fi

    if [ -z "$vpc_id" ]; then
        echo "错误：未找到可用的 VPC。" >&2
        return 1
    fi

    # 获取交换机信息
    local vswitch_id
    if type vpc_vswitch_list >/dev/null 2>&1; then
        vswitch_id=$(vpc_vswitch_list "$vpc_id" json 2>/dev/null | jq -r '.[0].VSwitchId // .VSwitches.VSwitch[0].VSwitchId // empty')
    else
        local vswitch_result
        vswitch_result=$(call_aliyun_api vpc describe-vswitches --biz-region-id "${region:-cn-hangzhou}" --vpc-id "$vpc_id" 2>/dev/null)
        vswitch_id=$(echo "$vswitch_result" | jq -r '.VSwitches.VSwitch[0].VSwitchId // empty')
    fi

    if [ -z "$vswitch_id" ]; then
        echo "错误：未找到可用的交换机。" >&2
        return 1
    fi

    echo "创建 ACK 集群："
    echo "名称: $name"
    echo "节点数量: $node_count"
    echo "实例类型: $instance_type"
    echo "Kubernetes 版本: $kubernetes_version"
    echo "系统盘类型: $worker_system_disk_category"
    echo "系统盘大小: ${worker_system_disk_size}GB"
    echo "VPC ID: $vpc_id"
    echo "交换机 ID: $vswitch_id"

    local result
    result=$(call_aliyun_api cs POST /clusters \
        --region "$region" \
        --body "$(jq -nc \
            --arg name "$name" \
            --arg cluster_type "ManagedKubernetes" \
            --arg vpc_id "$vpc_id" \
            --arg vswitch_id "$vswitch_id" \
            --argjson node_count "$node_count" \
            --arg instance_type "$instance_type" \
            --arg kubernetes_version "$kubernetes_version" \
            --arg worker_system_disk_category "$worker_system_disk_category" \
            --argjson worker_system_disk_size "$worker_system_disk_size" \
            '{
                name: $name,
                cluster_type: $cluster_type,
                vpcid: $vpc_id,
                vswitch_ids: [$vswitch_id],
                num_of_nodes: $node_count,
                instance_type: $instance_type,
                kubernetes_version: $kubernetes_version,
                worker_system_disk_category: $worker_system_disk_category,
                worker_system_disk_size: $worker_system_disk_size,
                container_cidr: "172.20.0.0/16",
                service_cidr: "172.21.0.0/20",
                is_enterprise_security_group: true,
                cloud_monitor_flags: 1
            }')")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "ACK 集群创建请求已提交："
        echo "$result" | jq '.'

        # 获取集群ID（CreateCluster 响应字段为 snake_case 的 cluster_id）
        local cluster_id
        cluster_id=$(echo "$result" | jq -r '.cluster_id // empty')
        if [ -z "$cluster_id" ]; then
            echo "错误：集群创建请求已提交，但响应中未包含 cluster_id。" >&2
            echo "$result" >&2
            return 1
        fi

        echo "等待集群创建完成..."
        local max_wait_time=1800 # 30分钟
        local start_time
        start_time=$(date +%s)

        while true; do
            local current_time
            current_time=$(date +%s)
            local elapsed_time=$((current_time - start_time))

            if [ $elapsed_time -ge $max_wait_time ]; then
                echo "超时：集群创建时间超过30分钟。请在控制台检查集群状态。"
                break
            fi

            local status
            status=$(call_aliyun_api cs GET "/clusters/$cluster_id" \
                --region "$region" 2>/dev/null | jq -r '.state // empty')

            echo "集群状态: ${status:-未知}"
            case "$status" in
            running)
                echo "集群创建成功！"
                break
                ;;
            initial)
                # 仍在创建中，继续等待
                ;;
            "")
                echo "错误：无法获取集群状态。" >&2
                break
                ;;
            *)
                # failed/inactive/unavailable/updating/deleting/delete_failed 等终态
                echo "错误：集群进入终态 $status，创建失败。请在控制台检查集群状态。"
                break
                ;;
            esac

            sleep 30
        done
        log_result "${profile:-}" "$region" "ack" "create" "$result"
    else
        echo "错误：集群创建请求失败。"
        echo "$result"
        return 1
    fi
}

# 交互式解析 ACK 集群ID（REST-style cs GET /clusters）
_ack_resolve_cluster_id() {
    resolve_resource_id "$1" "${2:-选择 ACK 集群}" "错误：没有找到任何集群。" \
        '.[] | "\(.cluster_id) (\(.name // "无名称")) [\(.state)]"' \
        -- cs GET /clusters --region "${region:-}"
}

# 获取集群节点池列表，输出：name<TAB>id<TAB>节点数<TAB>is_default
_ack_nodepool_list() {
    local cluster_id=$1
    call_aliyun_api cs GET "/clusters/$cluster_id/nodepools" --region "${region:-}" 2>/dev/null |
        jq -r '.nodepools[]? | [.nodepool_info.name // "-", .nodepool_info.nodepool_id // "-", ((.status.total_nodes // []) | length), (.nodepool_info.is_default | tostring)] | @tsv'
}

# 解析/选择节点池 ID（未提供时 fzf 选择）
_ack_select_nodepool() {
    local current=$1 prompt=$2 cluster_id=$3
    if [ -n "$current" ]; then
        echo "$current"
        return 0
    fi
    local pools candidates
    pools=$(_ack_nodepool_list "$cluster_id")
    if [ -z "$pools" ]; then
        echo "错误：集群没有可用节点池。" >&2
        return 1
    fi
    candidates=$(echo "$pools" | awk -F'\t' '{printf "%s  %s [%s节点]%s\n", $2, $1, $3, ($4 == "true" ? " [默认]" : "")}')
    resolve_from_candidates "" "$prompt" "错误：集群没有可用节点池。" "$candidates"
}

# 使用新框架的删除函数
ack_delete() {
    local cluster_id

    local raw
    raw=$(_ack_resolve_cluster_id "$1" "选择要删除的 ACK 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    # 获取集群详情
    local cluster_info
    cluster_info=$(call_aliyun_api cs GET "/clusters/$cluster_id" --region "$region" 2>/dev/null)
    local cluster_name
    cluster_name=$(echo "$cluster_info" | jq -r '.name // "未知"')

    echo "警告：您即将删除以下集群："
    echo "  集群ID: $cluster_id"
    echo "  名称: $cluster_name"
    echo "  地域: $region"

    confirm_action "删除 ACK 集群：$cluster_id" || return 1

    echo "删除 ACK 集群："
    call_api_del_logged "ack" "$cluster_id" "ACK集群" "错误：ACK 集群删除请求失败。" \
        -- cs DELETE "/clusters/$cluster_id" --region "$region"
}

# 使用新框架的更新函数
ack_update() {
    local cluster_id new_name=$2

    local raw
    raw=$(_ack_resolve_cluster_id "$1" "选择要更新的 ACK 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    # 如果没有提供新名称，则提示输入
    if [ -z "$new_name" ]; then
        echo -n "请输入新的集群名称: "
        read -r new_name
        if [ -z "$new_name" ]; then
            echo "错误：新名称不能为空。" >&2
            return 1
        fi
    fi

    if ! validate_required_params "$cluster_id" "$new_name" "错误：集群ID和新名称不能为空。"; then
        return 1
    fi

    echo "更新 ACK 集群："
    call_api_logged "ack" "update" "错误：集群更新失败。" \
        -- cs PUT "/clusters/$cluster_id" \
        --region "$region" \
        --body "$(jq -nc --arg name "$new_name" '{name: $name}')"
}

# 获取集群详情（使用框架函数）
ack_detail() {
    local cluster_id=$1
    local format=${2:-human}

    if is_output_format "$cluster_id"; then
        format=$cluster_id
        cluster_id=""
    fi

    # 如果没有提供集群ID，则使用 fzf 选择
    if [ -z "$cluster_id" ]; then
        local raw
        raw=$(_ack_resolve_cluster_id "" "选择要查看详情的 ACK 集群") || return 1
        cluster_id=$(echo "$raw" | awk '{print $1}')
    fi

    # 检查集群 ID 是否为空
    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    local result
    result=$(call_aliyun_api cs GET "/clusters/$cluster_id" --region "$region")
    local ret=$?
    if [ $ret -eq 0 ]; then
        case "$format" in
        json)
            echo "$result"
            ;;
        *)
            echo "获取集群详情："
            echo "$result" | jq '.'
            ;;
        esac
        log_result "${profile:-}" "$region" "ack" "detail" "$result"
    else
        echo "错误：无法获取集群详情。"
        echo "$result"
        return 1
    fi
}

# 节点列表（使用框架函数）
ack_node_list() {
    local cluster_id=$1
    local format=${2:-human}

    if is_output_format "$cluster_id"; then
        format=$cluster_id
        cluster_id=""
    fi

    # 如果没有提供集群ID，则使用 fzf 选择
    if [ -z "$cluster_id" ]; then
        local raw
        raw=$(_ack_resolve_cluster_id "" "选择要查看节点的 ACK 集群") || return 1
        cluster_id=$(echo "$raw" | awk '{print $1}')
    fi

    # 检查集群 ID 是否为空
    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    local table_header="NodeId\tNodeName\tStatus\tInstanceType\tCreated"
    local jq_filter=".nodes[] | [.instance_id, .instance_name, .state, .instance_type, .creation_time] | @tsv"
    # shellcheck disable=2016
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-16s  %-18s  %-8s  %-15s  %s\n", $1, $2, $3, $4, $5}'

    local result
    result=$(call_aliyun_api cs GET "/clusters/$cluster_id/nodes" --region "$region")
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：无法获取节点列表。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "ack" \
        "node-list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到节点。" \
        "列出集群节点："
}

# 添加节点（扩容节点池；原 POST /clusters/{id}/nodes 实为 DeleteClusterNodes，语义错位已废弃）
ack_node_add() {
    local cluster_id=$1
    local nodepool_id=$2
    local count=${3:-1}

    # 如果没有提供集群ID，则使用 fzf 选择
    if [ -z "$cluster_id" ]; then
        local raw
        raw=$(_ack_resolve_cluster_id "" "选择要添加节点的 ACK 集群") || return 1
        cluster_id=$(echo "$raw" | awk '{print $1}')
    fi

    # 检查集群 ID 是否为空
    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    # 校验数量
    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
        echo "错误：节点数量必须是数字。" >&2
        return 1
    fi

    # 未指定节点池则 fzf 选择
    if [ -z "$nodepool_id" ]; then
        nodepool_id=$(_ack_select_nodepool "" "选择要扩容的节点池" "$cluster_id") || return 1
    fi

    echo "扩容集群节点池：$nodepool_id 增加 $count 个节点"
    local result
    result=$(call_aliyun_api cs POST "/clusters/$cluster_id/nodepools/$nodepool_id" \
        --region "${region:-}" \
        --body "$(jq -nc --argjson count "$count" '{count: $count}')")
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "节点扩容请求已提交："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ack" "add-node" "$result"
    else
        echo "错误：节点扩容请求失败。"
        echo "$result"
        return 1
    fi
}

# 移除节点（使用框架函数；DeleteClusterNodes 需要 Kubernetes 节点名，非 ECS 实例ID）
ack_node_remove() {
    local cluster_id=$1
    local node_name=$2

    # 如果没有提供集群ID，则使用 fzf 选择
    if [ -z "$cluster_id" ]; then
        local raw
        raw=$(_ack_resolve_cluster_id "" "选择要移除节点的 ACK 集群") || return 1
        cluster_id=$(echo "$raw" | awk '{print $1}')
    fi

    # 如果没有提供节点名，则使用 fzf 选择
    if [ -z "$node_name" ]; then
        local node_result node_candidates raw_node
        node_result=$(call_aliyun_api cs GET "/clusters/$cluster_id/nodes" --region "$region" 2>/dev/null)
        local ret=$?
        if [ $ret -ne 0 ]; then
            echo "错误：无法获取节点列表。" >&2
            return 1
        fi
        node_candidates=$(echo "$node_result" | jq -r '.nodes[] | "\(.node_name) (\(.instance_id)) [\(.state)]"')
        raw_node=$(resolve_from_candidates "" "选择要移除的节点" "错误：没有找到任何节点。" "$node_candidates") || return 1
        node_name=$(echo "$raw_node" | awk '{print $1}')
    fi

    if ! validate_required_params "$cluster_id" "$node_name" "错误：集群ID和节点名不能为空。"; then
        return 1
    fi

    if ! confirm_action "从集群中移除节点：$node_name"; then
        return 1
    fi

    echo "移除集群节点："
    local result
    result=$(call_aliyun_api cs DELETE "/clusters/$cluster_id/nodes" \
        --region "$region" \
        --body "$(jq -nc --arg node_name "$node_name" '{nodes: [$node_name], release_node: true, drain_node: true}')")
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "节点移除请求已提交："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ack" "node-remove" "$result"
    else
        echo "错误：节点移除请求失败。"
        echo "$result"
        return 1
    fi
}

# 获取 kubeconfig（使用框架函数）
ack_get_kubeconfig() {
    local cluster_id=$1
    local private=${2:-false}

    if [ -z "$cluster_id" ]; then
        local raw
        raw=$(_ack_resolve_cluster_id "" "选择要获取 kubeconfig 的 ACK 集群") || return 1
        cluster_id=$(echo "$raw" | awk '{print $1}')
    fi

    echo "获取集群 kubeconfig："
    local result
    result=$(call_aliyun_api cs GET "/k8s/$cluster_id/user_config" \
        --region "$region" \
        --private_ip_address "$private")
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "$result" | jq -r '.config'
        log_result "${profile:-}" "$region" "ack" "kubeconfig" "$result"
    else
        echo "错误：无法获取 kubeconfig。"
        echo "$result"
        return 1
    fi
}

# 检查锁文件和冷却时间（保持原有逻辑）
check_cooldown() {
    local action=$1
    local lock_file=$2
    local cooldown_minutes=$3
    local action_name

    if [[ "$action" == "up" ]]; then
        action_name="扩容"
    else
        action_name="缩容"
    fi

    if [[ -f $lock_file ]]; then
        if [[ $(stat -c %Y "$lock_file") -lt $(date -d "$cooldown_minutes minutes ago" +%s) ]]; then
            rm -f "$lock_file"
            return 1
        else
            return 0
        fi
    else
        return 1
    fi
}

# 扩缩容函数（保持原有逻辑）
scale_deployment() {
    local action=$1
    local new_total=$2
    local lock_file_up=$3
    local lock_file_down=$4
    local action_name load_status

    if [[ "$action" == "up" ]]; then
        action_name="扩容"
        load_status="过载"
        touch "$lock_file_up" "$lock_file_down"
    else
        action_name="缩容"
        load_status="空闲"
        touch "$lock_file_down"
    fi

    if ! kubectl -n "$namespace" scale --replicas="$new_total" deployment "$deployment"; then
        echo "扩缩容操作失败" >&2
        return 1
    fi

    local msg_body
    msg_body="[$(date '+%Y-%m-%d %H:%M:%S')], 应用 ${deployment} ${load_status}, ${action_name} 到 ${new_total} 个副本"
    echo "$msg_body"

    if kubectl -n "$namespace" rollout status deployment "$deployment" --timeout 60s; then
        local result="成功"
    else
        local result="失败"
    fi

    # 记录操作日志
    msg_body="${msg_body}，结果: ${result}"
    log_result "${profile:-}" "$region" "ack" "auto-scale" "$msg_body"

    # 如果存在通知函数，则调用
    if type _notify_wecom >/dev/null 2>&1; then
        _notify_wecom "${WECOM_KEY:-}" "$msg_body"
    fi
    echo ""
}

# ============================================================
# 自动扩缩容：自定义 PHP 部署专用（不用 K8s HPA），应对突发流量。
#   K8s HPA 不够灵敏/快速，故自研，由用户级 systemd timer 每 15 秒触发一次：
#     ~/.config/systemd/user/ack-auto-scale.service：
#       [Service]
#       Type=oneshot
#       ExecStart=/bin/bash <repo>/cloud/aliyun/main.sh -p <profile> -r cn-hangzhou ack auto-scale <deployment> [namespace]
#     ~/.config/systemd/user/ack-auto-scale.timer：
#       [Timer]
#       OnBootSec=30s
#       OnUnitActiveSec=15s
#       AccuracySec=1s
#       [Install]
#       WantedBy=timers.target
#   启用：systemctl --user enable --now ack-auto-scale.timer；输出由 handle_ack_commands 重定向到 /tmp/ack_auto_scale.log。
#
# 触发逻辑（双因子 OR/AND 滞回）：
#   扩容 = CPU求和 > warn 阈值  OR  内存求和 > warn 阈值      （任一资源过载即扩，保应用）
#   缩容 = CPU求和 < normal 阈值 AND  内存求和 < normal 阈值   （两资源都回落后才缩，避免抖动）
#   阈值 = 因子 × 当前副本数；warn/normal 构成滞回带，配合冷却锁防止频繁扩缩。
#   因子单位：CPU 毫核/副本、内存 MiB/副本，可用环境变量覆盖（默认值为实际生产值）：
#     ACK_CPU_WARN_FACTOR / ACK_CPU_NORMAL_FACTOR / ACK_MEM_WARN_FACTOR / ACK_MEM_NORMAL_FACTOR
#   数据源：kubectl top pod，mem 会把 Ki/Mi/Gi/裸字节统一归一化为 MiB（注意 top 输出如 1.5Gi 不能直接 int()）。
#
# 互斥机制：
#   /tmp/lock.scale.all：helm 发布或人工运维时由外部 touch 创建，检测到后 5 分钟内静默跳过，避免与 15 秒轮询冲突。
#   /tmp/lock.scale.up|down.$deployment：冷却锁（扩容 1 分钟 / 缩容 5 分钟）。
#
# 注意：本功能必须保留，勿删（依赖：check_cooldown / scale_deployment）。
# ============================================================
ack_auto_scale() {
    local deployment=$1
    local namespace=${2:-main}
    local lock_file_all="/tmp/lock.scale.all"
    local lock_file_up="/tmp/lock.scale.up.$deployment"
    local lock_file_down="/tmp/lock.scale.down.$deployment"

    ## 发布/人工运维互斥：外部创建 lock.scale.all 后 5 分钟内跳过（helm install/upgrade 时禁用 auto-scale）
    if [[ -f "${lock_file_all}" ]]; then
        if [[ $(stat -c %Y "$lock_file_all") -lt $(date -d "5 minutes ago" +%s) ]]; then
            rm "${lock_file_all}"
        fi
        return 0
    fi

    if [ -z "$deployment" ]; then
        echo "错误：部署名称不能为空。" >&2
        return 1
    fi

    # 定义常量（四因子可用环境变量覆盖，默认值为实际生产值；单位：CPU 毫核/副本、内存 MiB/副本）
    local CPU_WARN_FACTOR=${ACK_CPU_WARN_FACTOR:-1500}    # CPU 警告阈值因子（毫核/副本）
    local CPU_NORMAL_FACTOR=${ACK_CPU_NORMAL_FACTOR:-500}  # CPU 正常阈值因子（毫核/副本）
    local MEM_WARN_FACTOR=${ACK_MEM_WARN_FACTOR:-1200}     # 内存警告阈值因子（MiB/副本）
    local MEM_NORMAL_FACTOR=${ACK_MEM_NORMAL_FACTOR:-500}  # 内存正常阈值因子（MiB/副本）
    local SCALE_CHANGE=2                # 每次扩缩容的节点数量
    local MIN_REPLICAS=2                # 自动缩容下限，不低于此副本数
    local COOLDOWN_MINUTES_SCALE_UP=1   # 扩容冷却时间（分钟）
    local COOLDOWN_MINUTES_SCALE_DOWN=5 # 缩容冷却时间（分钟）

    # 检查扩容冷却期
    if check_cooldown "up" "$lock_file_up" $COOLDOWN_MINUTES_SCALE_UP; then
        return
    fi

    # 获取节点和 Pod 信息
    local node_total
    node_total=$(kubectl get nodes -o name --no-headers | grep -c "^")
    local node_fixed=$((node_total - 1)) # 实际节点数 = 所有节点数 - 1 个虚拟节点

    local pod_total
    pod_total=$(kubectl -n "$namespace" get pod -l "app.kubernetes.io/name=$deployment" --no-headers | grep -c "$deployment")

    # 计算阈值
    local pod_cpu_warn=$((pod_total * CPU_WARN_FACTOR))
    local pod_mem_warn=$((pod_total * MEM_WARN_FACTOR))
    local pod_cpu_normal=$((pod_total * CPU_NORMAL_FACTOR))
    local pod_mem_normal=$((pod_total * MEM_NORMAL_FACTOR))

    # 获取当前 CPU 和内存使用情况。
    # CPU：top 输出为毫核（如 2000m），int() 取整即毫核，直接求和。
    # 内存：top 输出带单位（如 1245Mi / 1.5Gi / 512Ki / 裸字节），不能直接 int()（1.5Gi 会截成 1），
    #      统一归一化为 MiB：Ki÷1024、Mi×1、Gi×1024、裸字节÷1048576。
    # 注意：--no-headers 已无表头，不能用 NR>1（会跳过第一行数据，单 pod 时求和恒为 0）；
    #       改为按"$2 是否数字开头"识别表头行再跳过。
    local cpu mem
    read -r cpu mem < <(kubectl -n "$namespace" top pod -l "app.kubernetes.io/name=$deployment" --no-headers |
        awk '
        $2 ~ /^[0-9]/ {
            c += int($2)
            v = $3
            unit = v; gsub(/[0-9.]/, "", unit)
            gsub(/[^0-9.]/, "", v)
            if (unit ~ /^[Gg]/) m += v * 1024
            else if (unit ~ /^[Mm]/) m += v
            else if (unit ~ /^[Kk]/) m += v / 1024
            else m += v / 1048576
        }
        END {printf "%d %d", c, m}')

    # 检查是否需要扩容（CPU 或 内存 任一超过警告阈值即扩，避免任一资源过载拖垮应用）
    if ((cpu > pod_cpu_warn)) || ((mem > pod_mem_warn)); then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')], 当前CPU求和: ${cpu}（警告阈值 ${pod_cpu_warn} 毫核）, 内存求和: ${mem}MiB（警告阈值 ${pod_mem_warn}MiB）"
        kubectl -n "$namespace" top pod -l "app.kubernetes.io/name=$deployment"
        ## 扩容数量每次增加2，应对突发流量
        scale_deployment "up" $((pod_total + SCALE_CHANGE)) "$lock_file_up" "$lock_file_down"
        return
    fi

    # 检查缩容冷却期
    if check_cooldown "down" "$lock_file_down" $COOLDOWN_MINUTES_SCALE_DOWN; then
        return
    fi

    # 检查是否需要缩容（CPU 和 内存 都低于正常阈值才缩，避免缩下去又弹回来）
    if ((cpu < pod_cpu_normal)) && ((mem < pod_mem_normal)); then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')], 当前CPU求和: ${cpu}（正常阈值 ${pod_cpu_normal} 毫核）, 内存求和: ${mem}MiB（正常阈值 ${pod_mem_normal}MiB）"
        ## 缩容门槛：副本数须大于可用节点数才缩，避免缩到节点装不下（隐含"每节点至少能放 1 副本"的假设）
        if ((pod_total > node_fixed)); then
            local new_replicas=$((pod_total - SCALE_CHANGE))
            ((new_replicas < MIN_REPLICAS)) && new_replicas=$MIN_REPLICAS
            if ((new_replicas < pod_total)); then
                kubectl -n "$namespace" top pod -l "app.kubernetes.io/name=$deployment"
                scale_deployment "down" "$new_replicas" "$lock_file_up" "$lock_file_down"
            fi
            return
        fi
        ## 资源已回落后，若仍有 pod 跑在虚拟节点上，强制 rollout restart 把 pod 迁回真实节点
        ## （虚拟节点 ECI 计费贵，资源空闲时不该继续占着；nodeName 含 virtual-kubelet 即视为虚拟节点，不限地域）
        local pod_on_virtual_node
        pod_on_virtual_node=$(kubectl -n "$namespace" get pod -l "app.kubernetes.io/name=$deployment" -o json 2>/dev/null |
            jq -r '.items[]? | select((.spec.nodeName // "") | contains("virtual-kubelet")) | .metadata.name')
        if [ -n "$pod_on_virtual_node" ]; then
            echo "警告：以下pod运行在虚拟节点上：$pod_on_virtual_node ，即将重启"
            kubectl -n "$namespace" patch deployment "$deployment" -p '{"spec":{"strategy":{"rollingUpdate":{"maxUnavailable":"25%"}}}}'
            kubectl -n "$namespace" rollout restart deployment "$deployment"
        fi
    fi
}

## 手动节点维护锁：cordon-pool 持有、uncordon-pool 释放；rebalance 检测到则跳过，避免互斥冲突
_ack_cordon_locked() {
    local ACK_CORDON_LOCK_FILE=/tmp/ack.cordon.maintenance
    [[ -f $ACK_CORDON_LOCK_FILE ]] || return 1
    local last now
    last=$(cat "$ACK_CORDON_LOCK_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    (( now - last < 7200 ))
}

## 根据node内存使用率，禁止调度到内存使用率最高的节点上
# 参数：$1 - 内存使用率阈值（默认 95），达到或超过该值的节点将被 cordon
ack_rebalance() {
    local value_threshold=${1:-95}
    local node mem_usage

    if _ack_cordon_locked; then
        echo "检测到手动节点维护（cordon-pool 进行中），本次跳过自动 rebalance。"
        return 0
    fi

    while read -r node mem_usage; do
        if ((mem_usage >= value_threshold)); then
            # echo "[$(date '+%Y-%m-%d %H:%M:%S')], 节点 $node 内存使用率 $mem_usage%，达到阈值 $value_threshold%，将节点 $node cordon"
            kubectl cordon "$node" >/dev/null || true
        else
            # echo "[$(date '+%Y-%m-%d %H:%M:%S')], 节点 $node 内存使用率 $mem_usage%，未达到阈值 $value_threshold%，将节点 $node 解除 cordon"
            kubectl uncordon "$node" >/dev/null || true
        fi
    done < <(
        kubectl top node --no-headers | grep -v "virtual" | sort --reverse --key 5 --numeric | awk '{print $1, int($5)}'
    )
}

# 列出节点池
ack_pool_list() {
    local cluster_id=$1

    local raw
    raw=$(_ack_resolve_cluster_id "$cluster_id" "选择要查看节点池的 ACK 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    echo "列出集群 $cluster_id 的节点池："
    local pools
    pools=$(_ack_nodepool_list "$cluster_id")
    if [ -z "$pools" ]; then
        echo "错误：集群没有可用节点池。" >&2
        return 1
    fi

    echo "节点池名称       ID                      节点数  默认"
    echo "$pools" | awk -F'\t' '{printf "%-16s  %-20s  %-5s  %s\n", $1, $2, $3, ($4 == "true" ? "是" : "")}'
}

# 调整指定节点池的节点数（可扩容/缩容；未给目标数则扩容到集群上限可容纳数，ACK 限制最多 10 节点扣除 virtual）
ack_pool_scale() {
    local cluster_id=$1
    local nodepool_id=$2
    local target=$3
    local ack_node_limit=10
    local virtual_node_count=1

    local raw
    raw=$(_ack_resolve_cluster_id "$cluster_id" "选择要调整的 ACK 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    nodepool_id=$(_ack_select_nodepool "$nodepool_id" "选择要调整的节点池" "$cluster_id") || return 1

    local pools
    pools=$(_ack_nodepool_list "$cluster_id")
    if [ -z "$pools" ]; then
        echo "错误：集群没有可用节点池。" >&2
        return 1
    fi

    local current others_total max_allowed
    current=$(echo "$pools" | awk -F'\t' -v id="$nodepool_id" '$2 == id {print $3; exit}')
    others_total=$(echo "$pools" | awk -F'\t' -v id="$nodepool_id" '$2 != id {sum += $3} END {print sum + 0}')
    current=${current:-0}
    max_allowed=$((ack_node_limit - virtual_node_count - others_total))

    if [ -z "$target" ]; then
        read -r -p "目标节点数（留空则扩容到上限 $max_allowed）: " target
        target=${target:-$max_allowed}
    fi

    if ! [[ "$target" =~ ^[0-9]+$ ]]; then
        echo "错误：目标节点数必须是数字。" >&2
        return 1
    fi
    if [ "$target" -gt "$max_allowed" ]; then
        echo "错误：目标节点数 $target 超过集群上限可容纳数 ${max_allowed}（上限 ${ack_node_limit}，扣除 $virtual_node_count 个 virtual 节点）。" >&2
        return 1
    fi

    if [ "$target" -eq "$current" ]; then
        echo "节点池 $nodepool_id 当前已是 $current 个节点，无需调整。"
        return 0
    fi

    local action="扩容"
    if [ "$target" -lt "$current" ]; then
        action="缩容"
        confirm_action "即将对节点池 $nodepool_id 缩容：从 $current 个节点缩到 $target 个" || return 1
    fi

    echo "${action}节点池 ${nodepool_id}：从 $current 个节点到 $target 个（集群上限 ${ack_node_limit}，扣除 $virtual_node_count 个 virtual 节点）"
    local result
    result=$(call_aliyun_api cs PUT "/clusters/$cluster_id/nodepools/$nodepool_id" \
        --region "${region:-}" \
        --body "$(jq -nc --argjson size "$target" '{scaling_group: {desired_size: $size}}')")
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "节点池调整请求已提交："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ack" "scale-pool" "$result"
    else
        echo "错误：节点池调整请求失败。"
        echo "$result"
        return 1
    fi
}

# 新建节点池并加入集群
ack_pool_create() {
    local cluster_id=$1
    local name=$2

    local raw
    raw=$(_ack_resolve_cluster_id "$cluster_id" "选择要新建节点池的 ACK 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    if [ -z "$name" ]; then
        read -r -p "请输入节点池名称: " name
        if [ -z "$name" ]; then
            echo "错误：节点池名称不能为空。" >&2
            return 1
        fi
    fi

    # 选择 vSwitch（优先从 vpc 模块列出现有交换机供 fzf 选择）
    local vswitch_id=""
    if type get_vpc_id >/dev/null 2>&1; then
        local vpc_id vswitches
        vpc_id=$(get_vpc_id)
        if [ -n "$vpc_id" ]; then
            vswitches=$(call_aliyun_api vpc describe-vswitches --vpc-id "$vpc_id" --biz-region-id "$region" --region "$region" 2>/dev/null |
                jq -r '.VSwitches.VSwitch[]? | "\(.VSwitchId)  \(.VSwitchName // "-") [\(.ZoneId)]"')
            if [ -n "$vswitches" ]; then
                vswitch_id=$(select_with_fzf "选择 vSwitch" "$vswitches" | awk '{print $1}') || vswitch_id=""
            fi
        fi
    fi
    if [ -z "$vswitch_id" ]; then
        read -r -p "请输入 vSwitch ID: " vswitch_id
        if [ -z "$vswitch_id" ]; then
            echo "错误：vSwitch ID 不能为空。" >&2
            return 1
        fi
    fi

    local instance_type=""
    read -r -p "请输入实例类型 (默认 ecs.g6.large): " instance_type
    instance_type=${instance_type:-ecs.g6.large}

    local count=2 count_input
    read -r -p "请输入节点数 (默认 2): " count_input
    if [ -n "$count_input" ]; then
        count=$count_input
    fi

    echo "创建节点池：$name"
    echo "vSwitch: $vswitch_id"
    echo "实例类型: $instance_type"
    echo "节点数: $count"

    local result
    result=$(call_aliyun_api cs POST "/clusters/$cluster_id/nodepools" \
        --region "${region:-}" \
        --body "$(jq -nc \
            --arg name "$name" \
            --arg vswitch "$vswitch_id" \
            --arg instance_type "$instance_type" \
            --argjson count "$count" \
            '{nodepool_info: {name: $name}, scaling_group: {vswitch_ids: [$vswitch], instance_types: [$instance_type], instance_charge_type: "PostPaid"}, desired_size: $count}')")
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "节点池创建请求已提交："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ack" "add-pool" "$result"
    else
        echo "错误：节点池创建失败。"
        echo "$result"
        return 1
    fi
}

# 禁止调度到指定节点池的所有节点（持有维护锁，rebalance 期间跳过）
ack_pool_cordon() {
    local cluster_id=$1
    local nodepool_id=$2

    local raw
    raw=$(_ack_resolve_cluster_id "$cluster_id" "选择 ACK 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    nodepool_id=$(_ack_select_nodepool "$nodepool_id" "选择要禁止调度的节点池" "$cluster_id") || return 1

    local ACK_CORDON_LOCK_FILE=/tmp/ack.cordon.maintenance
    date +%s > "$ACK_CORDON_LOCK_FILE"
    echo "禁止调度到节点池 $nodepool_id 的节点："
    kubectl cordon -l "node.alibabacloud.com/nodepool-id=$nodepool_id"
}

# 解除指定节点池所有节点的调度限制（释放维护锁）
ack_pool_uncordon() {
    local cluster_id=$1
    local nodepool_id=$2

    local raw
    raw=$(_ack_resolve_cluster_id "$cluster_id" "选择 ACK 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    nodepool_id=$(_ack_select_nodepool "$nodepool_id" "选择要解除调度限制的节点池" "$cluster_id") || return 1

    local ACK_CORDON_LOCK_FILE=/tmp/ack.cordon.maintenance
    rm -f "$ACK_CORDON_LOCK_FILE"
    echo "解除节点池 $nodepool_id 节点的调度限制："
    kubectl uncordon -l "node.alibabacloud.com/nodepool-id=$nodepool_id"
}

# 重启指定节点上的所有 deployment（跳过 kube-system/kruise-system 与 fly-nginx/fly-php/node-* 前缀，逐个重启间隔 30s）
_ack_restart_node_deployments() {
    local node_name=$1
    local ns rs dep
    while IFS=$'\t' read -r ns rs; do
        [ -z "$rs" ] && continue
        dep="${rs%-*}"
        [[ $dep =~ fly-nginx ]] && continue
        [[ $dep =~ fly-php ]] && continue
        [[ $dep =~ node- ]] && continue
        echo "重启 \"$ns/$dep\""
        kubectl rollout restart deployment "$dep" -n "$ns" || echo "警告：$ns/$dep 重启失败" >&2
        sleep 30
    done < <(
        kubectl get pods --all-namespaces \
            --field-selector="spec.nodeName=${node_name},status.phase=Running,metadata.namespace!=kube-system,metadata.namespace!=kruise-system" \
            -o jsonpath="{range .items[*]}{.metadata.namespace}{'\t'}{.metadata.ownerReferences[?(@.kind=='ReplicaSet')].name}{'\n'}{end}"
    )
}

# 重启单个节点上的所有 deployment
ack_restart_node() {
    local node_name=$1

    if [ -z "$node_name" ]; then
        local candidates
        candidates=$(kubectl get nodes -o jsonpath="{.items[*].metadata.name}" |
            tr ' ' '\n' | grep -v virtual | grep -v '^$')
        node_name=$(resolve_from_candidates "" "选择要重启部署的节点" "错误：没有可用的非虚拟节点。" "$candidates") || return 1
    fi

    echo "重启节点 $node_name 上的 deployment："
    _ack_restart_node_deployments "$node_name"
}

# 重启节点池内所有节点上的 deployment（逐个节点依次重启，节点间间隔 30s）
ack_restart_pool() {
    local cluster_id=$1
    local nodepool_id=$2

    local raw
    raw=$(_ack_resolve_cluster_id "$cluster_id" "选择 ACK 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    nodepool_id=$(_ack_select_nodepool "$nodepool_id" "选择要重启部署的节点池" "$cluster_id") || return 1

    local nodes
    nodes=$(kubectl get nodes -l "node.alibabacloud.com/nodepool-id=$nodepool_id" \
        -o jsonpath="{.items[*].metadata.name}" | tr ' ' '\n' | grep -v '^$')
    if [ -z "$nodes" ]; then
        echo "错误：节点池 $nodepool_id 没有节点。" >&2
        return 1
    fi

    local node first=1
    while read -r node; do
        [ $first -eq 0 ] && sleep 30
        first=0
        echo "重启节点 $node 上的 deployment："
        _ack_restart_node_deployments "$node"
    done <<< "$nodes"
}

# 自动扩容：监控所有节点（除 virtual）内存，任一超过阈值则默认节点池扩容一个节点（适合 crontab）
ack_auto_node() {
    local cluster_id=$1
    local threshold=${2:-95}
    local lock_file="/tmp/lock.auto.node"
    local cooldown_seconds=300

    # 冷却期：避免 cron 高频触发重复扩容
    if [ -f "$lock_file" ]; then
        local last now
        last=$(cat "$lock_file" 2>/dev/null || echo 0)
        now=$(date +%s)
        if (( now - last < cooldown_seconds )); then
            return 0
        fi
    fi

    # 未指定集群则取第一个（cron 场景建议显式传集群 ID）
    if [ -z "$cluster_id" ]; then
        cluster_id=$(call_aliyun_api cs GET /clusters --region "${region:-}" 2>/dev/null | jq -r '.[0].cluster_id // empty')
    fi
    if [ -z "$cluster_id" ]; then
        echo "错误：无法确定集群。" >&2
        return 1
    fi

    # 检查节点内存（排除 virtual）：仅当所有节点内存都超过阈值才扩容
    local node_stats hot_count total_count
    node_stats=$(kubectl top node --no-headers 2>/dev/null | grep -v "virtual")
    if [ -z "$node_stats" ]; then
        return 0
    fi
    total_count=$(echo "$node_stats" | grep -c '^')
    hot_count=$(echo "$node_stats" | awk -v t="$threshold" 'int($5) >= t {c++} END {print c+0}')

    if [ "$hot_count" -lt "$total_count" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 节点内存超阈值(${threshold}%) ${hot_count}/${total_count}，未全部超过，不扩容。"
        return 0
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 所有节点（${total_count} 个）内存均超过阈值 ${threshold}%："
    echo "$node_stats" | awk -v t="$threshold" '{printf "%s  %s\n", $1, $5}'

    # 选择要扩容的节点池：优先默认节点池（is_default），无则退回名称含 dynamic 的池
    local pools nodepool_id nodepool_name
    pools=$(_ack_nodepool_list "$cluster_id")
    nodepool_id=$(echo "$pools" | awk -F'\t' '$4 == "true" {print $2; exit}')
    if [ -z "$nodepool_id" ]; then
        nodepool_name=$(echo "$pools" | awk -F'\t' '$1 ~ /dynamic/ {print $1; exit}')
        nodepool_id=$(echo "$pools" | awk -F'\t' '$1 ~ /dynamic/ {print $2; exit}')
        if [ -z "$nodepool_id" ]; then
            echo "错误：集群 $cluster_id 没有默认节点池，也没有名称含 dynamic 的节点池，无法自动扩容。" >&2
            return 1
        fi
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 无默认节点池，选择名称含 dynamic 的节点池：$nodepool_name"
    fi

    echo "自动扩容节点池 ${nodepool_id}：增加 1 个节点"
    local result
    result=$(call_aliyun_api cs POST "/clusters/$cluster_id/nodepools/$nodepool_id" \
        --region "${region:-}" \
        --body "$(jq -nc '{count: 1}')")
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "自动扩容请求已提交："
        echo "$result" | jq '.'
        date +%s > "$lock_file"
        log_result "${profile:-}" "$region" "ack" "auto-node" "$result"
    else
        echo "错误：自动扩容失败。"
        echo "$result"
        return 1
    fi
}
