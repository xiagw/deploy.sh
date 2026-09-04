#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016
# -*- coding: utf-8 -*-

# ACK (容器服务 Kubernetes 版) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_ack_help() {
    echo "ACK (容器服务 Kubernetes 版) 操作："
    echo "  集群："
    echo "  get                                     - 列出所有集群"
    echo "  add <名称> [参数...]                   - 创建新集群"
    echo "  del [<集群ID>]                          - 删除集群（集群ID可选，可使用fzf选择）"
    echo "  set [<集群ID>] [<新名称>]               - 更新集群（集群ID和新名称都是可选的，可使用fzf选择）"
    echo "  detail [<集群ID>]                       - 获取集群详情（集群ID可选，可使用fzf选择）"
    echo "  config [<集群ID>]                       - 获取集群的 kubeconfig（集群ID可选，可使用fzf选择）"
    echo "  节点："
    echo "  get-node [<集群ID>] [format]           - 列出集群节点（集群ID可选，可使用fzf选择）"
    echo "  add-node [<集群ID>] [<节点池>] [数量]   - 添加集群节点（集群ID和节点池可选，可使用fzf选择）"
    echo "  del-node [<集群ID>] [<节点名>]          - 移除集群节点（集群ID和节点名可选，可使用fzf选择）"
    echo "  set-node restart [<节点名>]             - 重启单个节点上的所有 deployment（节点名可选，可使用fzf选择）"
    echo "  set-node cordon [内存阈值]               - 根据节点内存使用率自动 cordon/uncordon（默认阈值 94）"
    echo "  节点池："
    echo "  add-pool [<集群ID>] [<名称>]             - 新建节点池并加入集群（名称缺省自动生成 pool-时间戳）"
    echo "  get-pool [<集群ID>]                     - 列出集群节点池"
    echo "  set-pool [<集群ID>] scale [<节点池>] [目标总数]      - 调整指定节点池的节点数（目标总数指该池的节点总数，如 scale 4 表示该池设 4 台）"
    echo "  set-pool [<集群ID>] scale mem [内存阈值]            - 全集群内存超标时自动从空池 +1（默认阈值 94，crontab）"
    echo "  set-pool [<集群ID>] cordon|uncordon [<节点池>]      - 禁止/解除调度到节点池所有节点"
    echo "  set-pool [<集群ID>] restart [<节点池>]              - 重启节点池内所有节点上的 deployment"
    echo "  del-pool [<集群ID>] [<节点池>]          - 删除节点池（池内有节点时提示）"
    echo "  自动扩缩容："
    echo "  scale-pod <deployment>[/namespace] [--watch] [--max N] - 通用 Deployment 自动扩缩容（namespace 默认 main；求和判断；--watch 常驻监控；--max 副本上限 缺省=真实节点数，0=不限；默认单次执行）"
    echo
    echo "示例："
    echo "  集群："
    echo "  $0 ack get"
    echo "  $0 ack get json"
    echo "  $0 ack add my-cluster"
    echo "  $0 ack add my-cluster --node-count 3 --instance-type ecs.g6.large"
    echo "  $0 ack del c-xxx"
    echo "  $0 ack set c-xxx new-name"
    echo "  $0 ack detail c-xxx"
    echo "  $0 ack config c-xxx"
    echo "  节点："
    echo "  $0 ack get-node c-xxx"
    echo "  $0 ack add-node c-xxx 2"
    echo "  $0 ack add-node c-xxx <节点池ID> 2"
    echo "  $0 ack del-node c-xxx i-xxx"
    echo "  $0 ack set-node restart <节点名>"
    echo "  $0 ack set-node cordon 94"
    echo "  节点池："
    echo "  $0 ack add-pool c-xxx new-pool"
    echo "  $0 ack get-pool c-xxx"
    echo "  $0 ack set-pool c-xxx scale 4"
    echo "  $0 ack set-pool c-xxx scale <节点池ID> 1"
    echo "  $0 ack set-pool c-xxx scale mem 94"
    echo "  $0 ack set-pool c-xxx cordon"
    echo "  $0 ack set-pool c-xxx uncordon"
    echo "  $0 ack set-pool c-xxx restart"
    echo "  $0 ack del-pool c-xxx <节点池ID>"
    echo "  自动扩缩容："
    echo "  $0 ack scale-pod fly-php71/main --watch"
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
    scale-pod) ack_scale_pod "$@" >>"${SCRIPT_LOG:-/tmp/ack_scale_pod.log}" ;;
    get-pool) ack_pool_list "$@" ;;
    set-pool)
        # set-pool [<集群ID>] <scale|cordon|uncordon|restart> [<节点池>] [参数]；scale 支持 mem 子模式（内存紧张 +1）
        local pool_action=${2:-} pool_id=${3:-} pool_param=${4:-}
        if [ -z "$pool_action" ]; then
            pool_action=$(select_with_fzf "选择节点池操作" "scale
cordon
uncordon
restart" | awk '{print $1}')
        fi
        [ -z "$pool_action" ] && echo "错误：未选择节点池操作。" >&2 && return 1
        case "$pool_action" in
        scale)
            if [ "$pool_id" = "mem" ]; then
                # 内存子模式：所有节点内存超阈值则 +1（阈值在参数位，默认 94，crontab 场景）
                ack_pool_scale_mem "$1" "${pool_param:-94}" >>"${SCRIPT_LOG:-/tmp/ack_pool_scale_mem.log}"
            elif [ -z "$pool_param" ] && [[ "$pool_id" =~ ^[0-9]+$ ]]; then
                # 省略节点池直接给目标数：set-pool c-xxx scale 4
                ack_pool_scale "$1" "" "$pool_id"
            else
                ack_pool_scale "$1" "$pool_id" "$pool_param"
            fi
            ;;
        cordon | uncordon)
            _ack_pool_schedule_set "$1" "$pool_id" "$pool_action"
            ;;
        restart)
            ack_restart_pool "$1" "$pool_id"
            ;;
        *)
            echo "错误：未知的节点池操作：$pool_action" >&2
            return 1
            ;;
        esac
        ;;
    add-pool) ack_pool_create "$@" ;;
    del-pool) ack_pool_delete "$@" ;;
    set-node)
        # set-node <restart|cordon> [参数]
        local node_action=${1:-} node_param=${2:-}
        if [ -z "$node_action" ]; then
            node_action=$(select_with_fzf "选择节点操作" "restart
cordon" | awk '{print $1}')
        fi
        [ -z "$node_action" ] && echo "错误：未选择节点操作。" >&2 && return 1
        case "$node_action" in
        restart)
            ack_restart_node "$node_param"
            ;;
        cordon)
            ack_node_cordon "$node_param"
            ;;
        *)
            echo "错误：未知的节点操作：$node_action" >&2
            return 1
            ;;
        esac
        ;;
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
                echo "错误：集群进入终态 $status ，创建失败。请在控制台检查集群状态。"
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

    # 安全删除：先 cordon 停新调度 -> 滚动重启全部 deployment（迁移业务）-> 再删（drain 只处理残余）
    if ! confirm_action "从集群中移除节点：$node_name（将依次执行 cordon -> 重启全部 deployment -> 删除）"; then
        return 1
    fi

    echo "1) 标记节点不可调度（cordon）..."
    kubectl cordon "$node_name"

    echo "2) 滚动重启节点上的 deployment（业务迁移到其他节点）..."
    _ack_restart_node_deployments "$node_name"

    echo "3) 删除节点（drain 残余 Pod）..."
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

# 检查锁文件和冷却时间（保持原有逻辑；GNU stat/date 探测，兼容 macOS gstat/gdate）
check_cooldown() {
    local action=$1
    local lock_file=$2
    local cooldown_minutes=$3
    local action_name
    local gstat_cmd gdate_cmd
    gstat_cmd=$(command -v gstat || echo stat)
    gdate_cmd=$(command -v gdate || echo date)

    if [[ "$action" == "up" ]]; then
        action_name="扩容"
    else
        action_name="缩容"
    fi

    if [[ -f $lock_file ]]; then
        if [[ $("$gstat_cmd" -c %Y "$lock_file") -lt $("$gdate_cmd" -d "$cooldown_minutes minutes ago" +%s) ]]; then
            rm -f "$lock_file"
            return 1
        else
            return 0
        fi
    else
        return 1
    fi
}

# ============================================================
# 通用 Deployment 自动扩缩容。
# 适用: java / node 等应用（无 WorkloadSpread 绑定），多为单副本；沿用"pod 资源求和"判断。
# 自动识别 PHP 特例（部署名含 php，如 fly-php71）: 自动应用 PHP 参数
#   step=2 / min=2 / max=0 + PHP 生产阈值因子，无需单独命令（原 scale-php 已并入）。
#   PHP 关联 OpenKruise WorkloadSpread 双 subset，详见"闲时回收"分支注释。
#
# 用法:
#   ack scale-pod <deployment>[/namespace] [namespace] [选项]   （dep/ns 复合可省参数；namespace 默认 main）
#   选项:
#     --watch             死循环常驻监控（配合 systemd service 使用；默认单次执行后退出，供 cron/timer）
#     --interval 秒       相邻检查间隔，默认 15（配合 --watch）
#     --step N            每次扩容的副本增量，默认 1（PHP 特例默认 2）
#     --min N             自动缩容下限（基线），默认 1（PHP 特例默认 2）
#     --max N             副本上限：缺省 = 真实节点数（每节点 1 副本朴素预期）；
#                         --max 0 = 不限制（PHP 特例默认，kruise 管理上限）；>0 = 显式上限
#     --once              显式单次执行（默认行为，与 --watch 互斥冗余）
#
# 节点数口径（重要）:
#   真实节点数 = kubectl get nodes 排除 virtual-kubelet 节点后计数（无 -1 歧义）。
#   包含 cordon/不可调度节点 —— 理由是 cordon 随时可解除，按节点总数给足扩容余量；
#   且这是朴素预期（每节点 1 副本），实际分布由 k8s 调度决定，非准确保证。
#   PHP 的固定池上限（kruise chart 静态 4）与这里动态节点数口径不同，各自适用场景不同，勿混用。
#
# 隐形条件（设计约束，勿随意改动）:
#   1) 缩容终点 = 基线 min_replicas（扩容前的副本数，通常=1 单pod 运行、特殊=2）；
#      峰值扩、低谷缩回基线，不被节点数拦截。
#   2) 扩容上限 = --max（缺省=真实节点数，每节点 1 副本的朴素预期）；
#      资源有限时节点打满再加 pod 无意义，故顶到节点数为止。
#      注: 节点数口径含 cordon 节点（随时可解除，按总数给足余量）。
#   3) PHP 特例: 部署名含 php 自动套特例参数（step=2/min=2/max=0/PHP 阈值）；
#      WorkloadSpread 管理 virtual 扩容（max=0 → 脚本不限制）
#
# 运行方式（三选一，互不冲突可叠加）:
#   a) crontab 定时单次检查（最简单，无 --watch；每次独立进程，天然自愈，推荐日常兜底）:
#      0 3 * * * bash <repo>/cloud/aliyun/main.sh -p <profile> -r cn-hangzhou ack scale-pod <deployment>[/namespace]
#      注意：不要在 crontab 里每分钟触发 --watch（会堆叠多个死循环进程）；crontab 只配单次模式。
#   b) systemd template unit 常驻（推荐多部署场景；%i 即 deployment，namespace 默认 main；
#      崩溃自动拉起 Restart=always；注意单元名不可含 /，需显式 ns 时用 \x2f 转义）:
#      ~/.config/systemd/user/ack-scale-pod@.service:
#        [Unit]
#        Description=ACK scale-pod (%i) auto-scaling monitor
#        [Service]
#        Type=simple
#        Restart=always
#        RestartSec=5
#        ExecStart=/bin/bash <repo>/cloud/aliyun/main.sh -p <profile> -r cn-hangzhou ack scale-pod %i --watch
#        [Install]
#        WantedBy=timers.target
#      启用（单元名实例段不能含 /；namespace 默认 main 可直接用 deployment 名）:
#        systemctl --user enable --now ack-scale-pod@fly-php71.service
#        systemctl --user enable --now ack-scale-pod@order-java.service
#      非 main 命名空间需转义 / 为 \x2f（%i 展开时自动解码回 fly-php71/main）:
#        systemctl --user enable --now 'ack-scale-pod@fly-php71\x2fdev.service'
#      日志: 由 handle_ack_commands 重定向到 /tmp/ack_scale_pod.log
#   c) systemd timer 定时触发（不带 --watch，单次检查）:
#      ... ack scale-pod <deployment>[/namespace]
#   死循环意外退出兜底: b 由 Restart=always 自动拉起；a/c 每次都是新进程，崩溃只影响本轮，下次到点照跑。
#
# 触发逻辑（双因子 OR/AND 滞回）:
#   扩容 = CPU求和 > warn 阈值  OR  内存求和 > warn 阈值      （任一资源过载即扩）
#   缩容 = CPU求和 < normal 阈值 AND  内存求和 < normal 阈值   （两资源都回落才缩，避免抖动）
#   阈值 = 因子 × 当前副本数；因子单位: CPU 毫核/副本、内存 MiB/副本。
#   默认值（适中，可用环境变量覆盖）:
#     ACK_POD_CPU_WARN_FACTOR=2000 / ACK_POD_CPU_NORMAL_FACTOR=800
#     ACK_POD_MEM_WARN_FACTOR=2500 / ACK_POD_MEM_NORMAL_FACTOR=1000
#
# 互斥/冷却:
#   锁路径 ${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}（去尾斜杠）/lock.scale.all   helm 发布互斥（deploy.sh 部署时创建），5 分钟内跳过
#   /tmp/lock.scale.up|down.$deployment  冷却锁（扩容 1 分钟 / 缩容 5 分钟）
# 闲时回收: 资源回落后若 pod 仍跑在 virtual 节点，rollout restart 迁回真实节点（机制详见该分支注释）。
# ============================================================
ack_scale_pod() {
    local deployment=$1
    local namespace=""
    # 支持 dep/ns 复合写法（只传一个参数）：deployment 含 / 时按 deployment/namespace 拆解
    if [[ "$deployment" == */* ]]; then
        namespace="${deployment##*/}"
        deployment="${deployment%/*}"
    fi
    # $2 是选项（以 - 开头）时只消费 $1；否则消费 $1+$2（namespace）
    if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
        namespace="$2"
        shift 2
    else
        shift 1
    fi
    [ -z "$namespace" ] && namespace=main

    # 选项解析（step/min/max 用 -1 表示"未显式指定"，解析后按是否 PHP 特例套默认）
    local watch_mode=false interval=15 step=-1 min_replicas=-1 max_replicas=-1
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --watch) watch_mode=true && shift ;;
        --interval) interval="${2:?--interval 需要数字}" && shift 2 ;;
        --step) step="${2:?--step 需要数字}" && shift 2 ;;
        --min) min_replicas="${2:?--min 需要数字}" && shift 2 ;;
        --max) max_replicas="${2:?--max 需要数字}" && shift 2 ;;
        --once) watch_mode=false && shift ;;
        *)
            echo "错误：未知参数：$1" >&2
            return 1
            ;;
        esac
    done

    if [ -z "$deployment" ]; then
        echo "错误：部署名称不能为空。" >&2
        echo "用法：ack scale-pod <deployment> [namespace] [--watch] [--interval 15] [--step 1] [--min 1] [--max N]" >&2
        return 1
    fi

    # PHP 特例自动识别（命名约定：deployment 名含 php 视为 PHP 部署）：
    #   step=2 / min=2 / max=0（kruise 管理工作负载的 virtual 扩容上限）
    #   阈值因子在 run_once 内按 is_php 取不同默认；显式 --step/--min/--max 优先
    local is_php=false
    [[ "$deployment" == *php* ]] && is_php=true
    if $is_php; then
        [ "$step" -eq -1 ] && step=2
        [ "$min_replicas" -eq -1 ] && min_replicas=2
        [ "$max_replicas" -eq -1 ] && max_replicas=0
    else
        [ "$step" -eq -1 ] && step=1
        [ "$min_replicas" -eq -1 ] && min_replicas=1
        # max 保持 -1：非 PHP 缺省 = 真实节点数（eff_max，见 run_once）
    fi

    # 单次检查：求和判断 + 扩缩容 + virtual 闲时回收
    local run_once ret
    run_once() {
        # 运行时目录（${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}，去尾斜杠：macOS $TMPDIR 带 / 会拼出 //）
        local runtime_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
        runtime_dir="${runtime_dir%/}"
        local lock_file_all="${runtime_dir}/lock.scale.all"
        local lock_file_up="/tmp/lock.scale.up.$deployment"
        local lock_file_down="/tmp/lock.scale.down.$deployment"

        ## helm 发布互斥：deploy.sh 部署期间跳过扩缩容（锁存在 5 分钟内静默跳过；GNU stat/date 探测兼容 macOS）
        if [[ -f "${lock_file_all}" ]]; then
            local gstat_cmd gdate_cmd
            gstat_cmd=$(command -v gstat || echo stat)
            gdate_cmd=$(command -v gdate || echo date)
            if [[ $("$gstat_cmd" -c %Y "$lock_file_all") -lt $("$gdate_cmd" -d "5 minutes ago" +%s) ]]; then
                rm -f "${lock_file_all}"
            else
                $watch_mode && touch "${runtime_dir}/ack-scale-pod.heartbeat.$deployment"
                return 0
            fi
        fi

        # 阈值因子（环境变量可覆盖；PHP 特例走旧变量名 + 生产默认，非 PHP 走 ACK_POD_* + 适中默认）
        if $is_php; then
            local CPU_WARN_FACTOR=${ACK_CPU_WARN_FACTOR:-1500}
            local CPU_NORMAL_FACTOR=${ACK_CPU_NORMAL_FACTOR:-500}
            local MEM_WARN_FACTOR=${ACK_MEM_WARN_FACTOR:-2500}
            local MEM_NORMAL_FACTOR=${ACK_MEM_NORMAL_FACTOR:-1000}
        else
            local CPU_WARN_FACTOR=${ACK_POD_CPU_WARN_FACTOR:-2000}
            local CPU_NORMAL_FACTOR=${ACK_POD_CPU_NORMAL_FACTOR:-800}
            local MEM_WARN_FACTOR=${ACK_POD_MEM_WARN_FACTOR:-2500}
            local MEM_NORMAL_FACTOR=${ACK_POD_MEM_NORMAL_FACTOR:-1000}
        fi
        local COOLDOWN_MINUTES_SCALE_UP=1
        local COOLDOWN_MINUTES_SCALE_DOWN=5

        # 扩容冷却
        if check_cooldown "up" "$lock_file_up" $COOLDOWN_MINUTES_SCALE_UP; then
            return 0
        fi

        # 节点数（真实节点 = 排除 virtual，直接计数，无 -1 歧义）
        local node_fixed
        node_fixed=$(kubectl get nodes -o name --no-headers 2>/dev/null | grep -v virtual-kubelet | grep -c '^')

        # 副本上限：缺省 = 真实节点数（每节点 1 副本的朴素预期），每次检查重新计算跟随节点增减；
        # --max 0 = 不限制（PHP 特例，kruise 管理上限）；>0 = 显式上限
        local eff_max=$max_replicas
        [ "$eff_max" -eq -1 ] && eff_max=$node_fixed

        # pod 数
        local pod_total
        pod_total=$(kubectl -n "$namespace" get pod -l "app.kubernetes.io/name=$deployment" --no-headers | grep -c "$deployment")

        # 阈值 = 因子 × 副本数
        local pod_cpu_warn pod_mem_warn pod_cpu_normal pod_mem_normal
        pod_cpu_warn=$((pod_total * CPU_WARN_FACTOR))
        pod_mem_warn=$((pod_total * MEM_WARN_FACTOR))
        pod_cpu_normal=$((pod_total * CPU_NORMAL_FACTOR))
        pod_mem_normal=$((pod_total * MEM_NORMAL_FACTOR))

        # 求和（CPU 毫核 / 内存归一 MiB）
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

        # 扩容：任一资源过 warn 阈值
        if ((cpu > pod_cpu_warn)) || ((mem > pod_mem_warn)); then
            ## 副本上限：eff_max=0 表示不限制；达到上限则跳过扩容（默认不扩到 virtual，virtual 由 kruise/人工管理）
            local target_replicas=$((pod_total + step))
            if [ "$eff_max" -gt 0 ] && [ "$target_replicas" -gt "$eff_max" ]; then
                target_replicas=$eff_max
            fi
            if [ "$target_replicas" -le "$pod_total" ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] $deployment 已达副本上限 ${eff_max}，跳过扩容（CPU 求和 ${cpu} / 内存求和 ${mem}MiB）"
                return 0
            fi
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $deployment CPU求和 ${cpu}（阈值 ${pod_cpu_warn} 毫核）, 内存求和 ${mem}MiB（阈值 ${pod_mem_warn}MiB），扩容到 $target_replicas"
            if ! kubectl -n "$namespace" scale --replicas="$target_replicas" deployment "$deployment"; then
                echo "扩容失败" >&2
                return 1
            fi
            touch "$lock_file_up" "$lock_file_down"
            local up_msg
            up_msg="[$(date '+%Y-%m-%d %H:%M:%S')] 应用 ${deployment} 过载, 扩容到 ${target_replicas} 个副本"
            log_result "${profile:-}" "$region" "ack" "scale-pod" "$up_msg"
            type _notify_wecom >/dev/null 2>&1 && _notify_wecom "${WECOM_KEY:-}" "$up_msg"
            return 0
        fi

        # 缩容冷却
        if check_cooldown "down" "$lock_file_down" $COOLDOWN_MINUTES_SCALE_DOWN; then
            return 0
        fi

        # 缩容：两资源都低于 normal 阈值；缩到基线(min_replicas，扩容前副本数)为止，
        # 不被节点数拦截 —— 资源有限场景基线通常=1（单pod），特殊=2；峰值扩、低谷缩回基线
        if ((cpu < pod_cpu_normal)) && ((mem < pod_mem_normal)); then
            if ((pod_total > min_replicas)); then
                local new_replicas=$((pod_total - 1))
                ((new_replicas < min_replicas)) && new_replicas=$min_replicas
                if ((new_replicas < pod_total)); then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $deployment CPU求和 ${cpu}（正常阈值 ${pod_cpu_normal}）, 内存求和 ${mem}MiB（正常阈值 ${pod_mem_normal}），缩容到 $new_replicas"
                    kubectl -n "$namespace" scale --replicas="$new_replicas" deployment "$deployment"
                    touch "$lock_file_down"
                    local down_msg
                    down_msg="[$(date '+%Y-%m-%d %H:%M:%S')] 应用 ${deployment} 空闲, 缩容到 ${new_replicas} 个副本"
                    log_result "${profile:-}" "$region" "ack" "scale-pod" "$down_msg"
                    type _notify_wecom >/dev/null 2>&1 && _notify_wecom "${WECOM_KEY:-}" "$down_msg"
                fi
                return 0
            fi
            ## 闲时回收：已到基线仍有 virtual pod（残留/异常态兜底）
            ## ==========================================================
            ## 背景（仅 PHP 生效，非 PHP 不会命中）:
            ##   仅 PHP deployment 绑定了 OpenKruise WorkloadSpread 双 subset：
            ##     subset fixed-resource-pool（真实节点）→ subset elastic-resource-pool（virtual）
            ##   fixed pool 的 maxReplicas 是 helm chart 静态写死（当前=4），与节点数无关；
            ##   分配不感知节点 cordon/可用性 —— 固定扩到 4 台后多出的 pod 注入 elastic（virtual）
            ##   缩容顺序: WorkloadSpread 用 deletion-cost(-100) 保证 elastic subset 的 pod 优先删除，
            ##   因此主缩容（回到基线 min_replicas）过程中超出 fixed 容量的 elastic pod 已被顺带清空；
            ##   正常情况下回到基线后不应再有 virtual pod。
            ## 本分支只处理"基线仍有 virtual"的残留/异常态:
            ##   1) fixed 有空位（missingReplicas>0 或 -1）→ rollout restart：
            ##      重建时 webhook 按 missingReplicas 顺序注入 fixed subset，旧 elastic pod 被替换
            ##      -> virtual 消失
            ##   2) fixed 已满（missingReplicas=0）且已到基线 → 配置矛盾
            ##      （min_replicas > fixed maxReplicas），无法回收，提示人工排查
            ##   判断依据: WorkloadSpread status.missingReplicas
            ## 非 PHP (java/node) 无 WorkloadSpread，普通 pod 不会调度到 virtual 节点，此分支不命中
            ## ==========================================================
            local pod_on_virtual_node
            pod_on_virtual_node=$(kubectl -n "$namespace" get pod -l "app.kubernetes.io/name=$deployment" -o json 2>/dev/null |
                jq -r '.items[]? | select((.spec.nodeName // "") | contains("virtual-kubelet")) | .metadata.name')
            if [ -n "$pod_on_virtual_node" ]; then
                ## 读 WorkloadSpread：fixed 池（首个 subset）是否还有空位
                local ws_fixed_name ws_fixed_missing
                ws_fixed_name=$(kubectl -n "$namespace" get workloadspread "$deployment" -o json 2>/dev/null |
                    jq -r '.spec.subsets[0].name // ""')
                ws_fixed_missing=$(kubectl -n "$namespace" get workloadspread "$deployment" -o json 2>/dev/null |
                    jq -r --arg n "$ws_fixed_name" '.status.subsetStatuses[]? | select(.name == $n) | .missingReplicas')
                if [ -n "$ws_fixed_missing" ] && [ "$ws_fixed_missing" -ne 0 ]; then
                    ## fixed 有空位：滚动重启，新 pod 按序注入 fixed，替换 elastic 残留
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $deployment 基线 ${min_replicas} 仍有 virtual pod：$pod_on_virtual_node ，滚动重启迁回真实节点（fixed 池空位 missingReplicas=$ws_fixed_missing）"
                    kubectl -n "$namespace" rollout restart deployment "$deployment"
                elif [ -n "$ws_fixed_missing" ] && [ "$ws_fixed_missing" -eq 0 ]; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $deployment 基线 ${min_replicas} 已到但 fixed 池满（missingReplicas=0）仍有 virtual pod，疑似 min 配置 > fixed maxReplicas，请人工排查"
                else
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $deployment 无法读取 WorkloadSpread 状态（missingReplicas=${ws_fixed_missing:-空}），跳过回收"
                fi
            fi
        fi
        ## 心跳（仅 --watch 常驻）：touch 心跳文件（mtime=最近检查时间），供外部验证监控存活；
        ## 单次模式每次都是新进程、靠 cron/timer 调度天然自愈，无需探针，不写文件
        $watch_mode && touch "${runtime_dir}/ack-scale-pod.heartbeat.$deployment"
        return 0
    }

    if $watch_mode; then
        ## 死循环常驻：不退出；每 interval 秒检查一次；Ctrl+C 或 systemd stop 退出
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ack scale-pod 常驻监控开始：$deployment/$namespace ，间隔 ${interval}s（--watch）"
        while true; do
            run_once
            sleep "$interval"
        done
    else
        run_once
        return $?
    fi
}

## 手动节点维护锁：set-pool cordon 持有、set-pool uncordon 释放；set-node cordon 检测到则跳过，避免互斥冲突
_ack_cordon_locked() {
    local ACK_CORDON_LOCK_FILE=/tmp/ack.cordon.maintenance
    [[ -f $ACK_CORDON_LOCK_FILE ]] || return 1
    local last now
    last=$(cat "$ACK_CORDON_LOCK_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    (( now - last < 7200 ))
}

## 根据node内存使用率，禁止调度到内存使用率最高的节点上
# 参数：$1 - 内存使用率阈值（默认 94），达到或超过该值的节点将被 cordon
ack_node_cordon() {
    local value_threshold=${1:-94}
    local node mem_usage

    if _ack_cordon_locked; then
        echo "检测到手动节点维护（set-pool cordon 进行中），本次跳过自动 cordon。"
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
        read -r -p "目标节点数（留空则扩容到上限 $max_allowed ）: " target
        target=${target:-$max_allowed}
    fi

    if ! [[ "$target" =~ ^[0-9]+$ ]]; then
        echo "错误：目标节点数必须是数字。" >&2
        return 1
    fi
    if [ "$target" -gt "$max_allowed" ]; then
        echo "错误：目标节点数 $target 超过集群上限可容纳数 ${max_allowed} （上限 ${ack_node_limit} ，扣除 $virtual_node_count 个 virtual 节点）。" >&2
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

    echo "${action}节点池 ${nodepool_id} ：从 $current 个节点到 $target 个"
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

# 删除节点池（节点池内有节点时提示，可先 set-pool scale 0 清空）
ack_pool_delete() {
    local cluster_id=$1 nodepool_id=$2

    local raw
    raw=$(_ack_resolve_cluster_id "$cluster_id" "选择要删除节点池的 ACK 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    nodepool_id=$(_ack_select_nodepool "$nodepool_id" "选择要删除的节点池" "$cluster_id") || return 1

    # 显示池内当前节点数，提醒清空
    local current
    current=$(_ack_nodepool_list "$cluster_id" | awk -F'\t' -v id="$nodepool_id" '$2 == id {print $3; exit}')
    current=${current:-0}
    if [ "$current" -gt 0 ]; then
        echo "警告：节点池 $nodepool_id 当前有 $current 个节点，建议先 set-pool $cluster_id scale 0 清空再删除。" >&2
        confirm_action "节点池 $nodepool_id 仍有 $current 个节点（可能被释放/删除），确认继续删除？" || return 1
    else
        confirm_action "删除节点池 $nodepool_id" || return 1
    fi

    echo "删除节点池："
    call_api_del_logged "ack" "$nodepool_id" "节点池" "错误：节点池删除失败。" \
        -- cs DELETE "/clusters/$cluster_id/nodepools/$nodepool_id" --region "$region"
}

# 新建节点池并加入集群（名称缺省时自动生成 pool-时间戳，复用既有 fzf 选择 vSwitch 流程）
ack_pool_create() {
    local cluster_id=$1
    local name=$2

    local raw
    raw=$(_ack_resolve_cluster_id "$cluster_id" "选择要新建节点池的 ACK 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    if [ -z "$name" ]; then
        name="pool-$(date +%Y%m%d-%H%M%S)"
        echo "未提供节点池名称，自动生成: $name"
    fi

    # 选择 vSwitch（多选多个可用区的交换机，符合官方跨可用区高可用规范）
    local vswitch_ids=""
    if type get_vpc_id >/dev/null 2>&1; then
        local vpc_id vswitches
        vpc_id=$(get_vpc_id)
        if [ -n "$vpc_id" ]; then
            vswitches=$(call_aliyun_api vpc describe-vswitches --vpc-id "$vpc_id" --biz-region-id "$region" --region "$region" 2>/dev/null |
                jq -r '.VSwitches.VSwitch[]? | "\(.VSwitchId)  \(.VSwitchName // "-") [\(.ZoneId)]"')
            if [ -n "$vswitches" ]; then
                vswitch_ids=$(select_with_fzf "选择 vSwitch（Tab 多选多个可用区）" "$vswitches" -m 2>/dev/null | awk '{print $1}' | paste -sd "," -) || vswitch_ids=""
            fi
        fi
    fi
    if [ -z "$vswitch_ids" ]; then
        read -r -p "请输入 vSwitch ID（多个用逗号分隔）: " vswitch_ids
        if [ -z "$vswitch_ids" ]; then
            echo "错误：vSwitch ID 不能为空。" >&2
            return 1
        fi
    fi
    # 转成 JSON 数组，供 --argjson vswitch_ids 使用
    local vswitch_ids_json
    vswitch_ids_json=$(echo "$vswitch_ids" | tr ',' '\n' | jq -R -s 'split("\n") | map(select(length > 0))')

    # 操作系统镜像（默认与集群现有池一致：阿里云 Linux 4 容器优化版）
    local image_type="AliyunLinux4ContainerOptimized"
    read -r -p "请输入操作系统镜像 (默认 AliyunLinux4ContainerOptimized): " image_type
    image_type=${image_type:-AliyunLinux4ContainerOptimized}

    # 实例规格方式：按实例属性匹配（instance_patterns，默认，对齐现有池）或固定实例规格（instance_types）
    local compute_mode input
    read -r -p "实例规格方式，按实例属性=1 固定规格=2 [1]: " input
    compute_mode=${input:-1}

    local instance_patterns_json="[]"
    local instance_type_json="[]"
    if [ "$compute_mode" = "2" ]; then
        local instance_type=""
        read -r -p "请输入实例规格 (如 ecs.g6.large): " instance_type
        if [ -z "$instance_type" ]; then
            echo "错误：实例规格不能为空。" >&2
            return 1
        fi
        instance_type_json=$(printf '[%s]' "$(jq -nc --arg t "$instance_type" '$t')")
    else
        # 默认与集群现有池 nodepool-fixed 对齐：X86、g6/c6/r6/g7/c7/r7/g8i/c8i/r8i/u1、4~8 核、32~64GiB
        local cpu_arch="X86"
        local families="ecs.g6,ecs.c6,ecs.r6,ecs.g7,ecs.c7,ecs.r7,ecs.g8i,ecs.c8i,ecs.r8i,ecs.u1"
        local min_cpu=4 max_cpu=8 min_mem=32 max_mem=64 input_v
        [ -z "$cpu_arch" ] || :
        read -r -p "CPU 架构 (X86/Arm64, 默认 $cpu_arch): " input_v
        cpu_arch=${input_v:-$cpu_arch}
        read -r -p "实例族，逗号分隔 (默认 $families): " input_v
        families=${input_v:-$families}
        read -r -p "最小核数 (默认 $min_cpu): " input_v
        min_cpu=${input_v:-$min_cpu}
        read -r -p "最大核数 (默认 $max_cpu): " input_v
        max_cpu=${input_v:-$max_cpu}
        read -r -p "最小内存 GiB (默认 $min_mem): " input_v
        min_mem=${input_v:-$min_mem}
        read -r -p "最大内存 GiB (默认 $max_mem): " input_v
        max_mem=${input_v:-$max_mem}
        instance_patterns_json=$(jq -nc \
            --arg arch "$cpu_arch" \
            --arg families "$families" \
            --argjson min_cpu "$min_cpu" \
            --argjson max_cpu "$max_cpu" \
            --argjson min_mem "$min_mem" \
            --argjson max_mem "$max_mem" \
            '[{instance_type_families: ($families | split(",")), cpu_architectures: [$arch], min_cpu_cores: $min_cpu, max_cpu_cores: $max_cpu, min_memory_size: $min_mem, max_memory_size: $max_mem, burst_performance_option: "Exclude", maximum_gpu_amount: 0}]')
    fi

    local system_disk_category="cloud_essd"
    read -r -p "请输入系统盘类型 (默认 cloud_essd): " system_disk_category
    system_disk_category=${system_disk_category:-cloud_essd}

    local system_disk_size=120
    read -r -p "请输入系统盘大小 GiB (默认 120): " system_disk_size
    system_disk_size=${system_disk_size:-120}

    local runtime="containerd"
    local runtime_version="2.1.8"
    read -r -p "请输入容器运行时 (默认 containerd): " runtime
    runtime=${runtime:-containerd}
    read -r -p "请输入运行时版本 (默认 2.1.8): " runtime_version
    runtime_version=${runtime_version:-2.1.8}

    # 节点池托管（对应控制台"自定义托管"）：默认开启自动修复/自动升级
    local managed=1
    read -r -p "是否启用节点池托管 (自定义托管，1=是 0=否 [1]): " managed
    managed=${managed:-1}

    local count=2 count_input
    read -r -p "请输入节点数 (默认 2): " count_input
    if [ -n "$count_input" ]; then
        count=$count_input
    fi

    echo "创建节点池：$name"
    echo "vSwitch: $vswitch_ids"
    echo "操作系统镜像: $image_type"
    if [ -n "$instance_patterns_json" ] && [ "$instance_patterns_json" != "[]" ]; then
        echo "实例规格: 按实例属性匹配 $(echo "$instance_patterns_json" | jq -c '.[0] | {"架构": .cpu_architectures, "族": .instance_type_families, "核": "\(.min_cpu_cores)-\(.max_cpu_cores)", "内存GiB": "\(.min_memory_size)-\(.max_memory_size)"}')"
    else
        echo "实例规格: 固定 $(echo "$instance_type_json" | jq -c '.')"
    fi
    echo "系统盘类型: $system_disk_category"
    echo "系统盘大小: ${system_disk_size}GiB"
    echo "容器运行时: $runtime $runtime_version"
    echo "节点池托管: $([ "$managed" = 1 ] && echo 是 || echo 否)"
    echo "节点数: $count"

    local result
    result=$(call_aliyun_api cs POST "/clusters/$cluster_id/nodepools" \
        --region "${region:-}" \
        --body "$(jq -nc \
            --arg name "$name" \
            --argjson vswitch_ids "$vswitch_ids_json" \
            --argjson instance_patterns "$instance_patterns_json" \
            --argjson instance_types "$instance_type_json" \
            --arg image_type "$image_type" \
            --arg system_disk_category "$system_disk_category" \
            --argjson system_disk_size "$system_disk_size" \
            --arg runtime "$runtime" \
            --arg runtime_version "$runtime_version" \
            --argjson managed "$managed" \
            --argjson count "$count" \
            '{nodepool_info: {name: $name}, scaling_group: {vswitch_ids: $vswitch_ids, instance_patterns: $instance_patterns, instance_types: $instance_types, image_type: $image_type, instance_charge_type: "PostPaid", system_disk_category: $system_disk_category, system_disk_size: $system_disk_size}, kubernetes_config: {runtime: $runtime, runtime_version: $runtime_version}, management: {enable: ($managed == 1), auto_repair: ($managed == 1), auto_upgrade: ($managed == 1)}, desired_size: $count}')")
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

# 禁止/解除调度到指定节点池的所有节点（action: cordon 持有维护锁，uncordon 释放；两者互斥锁使 set-node cordon 期间跳过）
_ack_pool_schedule_set() {
    local cluster_id=$1 nodepool_id=$2 action=$3

    local raw
    raw=$(_ack_resolve_cluster_id "$cluster_id" "选择 ACK 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    nodepool_id=$(_ack_select_nodepool "$nodepool_id" "选择节点池" "$cluster_id") || return 1

    local ACK_CORDON_LOCK_FILE=/tmp/ack.cordon.maintenance
    if [ "$action" = "cordon" ]; then
        date +%s > "$ACK_CORDON_LOCK_FILE"
        echo "禁止调度到节点池 $nodepool_id 的节点："
        kubectl cordon -l "node.alibabacloud.com/nodepool-id=$nodepool_id"
    else
        rm -f "$ACK_CORDON_LOCK_FILE"
        echo "解除节点池 $nodepool_id 节点的调度限制："
        kubectl uncordon -l "node.alibabacloud.com/nodepool-id=$nodepool_id"
    fi
}

# 重启节点上所有 deployment（跳过 kube-system/kruise-system 与 fly-nginx/fly-php 前缀，逐个重启间隔 30s）
_ack_restart_node_deployments() {
    local node_name=$1
    local ns rs dep count=0
    while IFS=$'\t' read -r ns rs; do
        [ -z "$rs" ] && continue
        dep="${rs%-*}"
        [[ $dep =~ fly-nginx ]] && continue
        [[ $dep =~ fly-php ]] && continue
        count=$((count + 1))
        echo "重启 \"$ns/$dep\""
        kubectl rollout restart deployment "$dep" -n "$ns" || echo "警告：$ns/$dep 重启失败" >&2
        sleep 30
    done < <(
        kubectl get pods --all-namespaces \
            --field-selector="spec.nodeName=${node_name},status.phase=Running,metadata.namespace!=kube-system,metadata.namespace!=kruise-system" \
            -o jsonpath="{range .items[*]}{.metadata.namespace}{'\t'}{.metadata.ownerReferences[?(@.kind=='ReplicaSet')].name}{'\n'}{end}"
    )
    [ "$count" -eq 0 ] && echo "节点 $node_name 上没有匹配的 deployment，无需重启。"
}

# 重启单个节点上的所有 deployment（先 cordon 停新调度，重启后节点保持不可调度）
ack_restart_node() {
    local node_name=$1

    if [ -z "$node_name" ]; then
        local candidates
        candidates=$(kubectl get nodes -o jsonpath="{.items[*].metadata.name}" |
            tr ' ' '\n' | grep -v virtual | grep -v '^$')
        node_name=$(resolve_from_candidates "" "选择要重启部署的节点" "错误：没有可用的非虚拟节点。" "$candidates") || return 1
    fi

    echo "标记节点不可调度（cordon）..."
    kubectl cordon "$node_name"

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

# 自动扩容：监控所有节点（除 virtual）内存，所有节点内存都超过阈值则默认节点池扩容一个节点（适合 crontab）
ack_pool_scale_mem() {
    local cluster_id=$1
    local threshold=${2:-94}
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
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 节点内存超阈值(${threshold}%) ${hot_count}/${total_count} ，未全部超过，不扩容。"
        return 0
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 所有节点（${total_count} 个）内存均超过阈值 ${threshold}%："
    echo "$node_stats" | awk -v t="$threshold" '{printf "%s  %s\n", $1, $5}'

    # 选择要扩容的节点池：自动选当前节点数为 0 的空池（扩容 +1 激活；无可扩容的空池则报错）
    local pools nodepool_id nodepool_name
    pools=$(_ack_nodepool_list "$cluster_id")
    nodepool_id=$(echo "$pools" | awk -F'\t' '$3 == "0" {print $2; exit}')
    nodepool_name=$(echo "$pools" | awk -F'\t' '$3 == "0" {print $1; exit}')
    if [ -z "$nodepool_id" ]; then
        echo "错误：集群 $cluster_id 没有节点数为 0 的空节点池，无法自动扩容。" >&2
        return 1
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 选择空节点池（0 节点）：$nodepool_name"

    echo "自动扩容节点池 ${nodepool_id} ：增加 1 个节点"
    local result
    result=$(call_aliyun_api cs POST "/clusters/$cluster_id/nodepools/$nodepool_id" \
        --region "${region:-}" \
        --body "$(jq -nc '{count: 1}')")
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "自动扩容请求已提交："
        echo "$result" | jq '.'
        date +%s > "$lock_file"
        log_result "${profile:-}" "$region" "ack" "scale-pool-mem" "$result"
    else
        echo "错误：自动扩容失败。"
        echo "$result"
        return 1
    fi
}
