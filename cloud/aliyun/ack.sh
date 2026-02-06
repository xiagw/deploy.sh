#!/usr/bin/env bash
# shellcheck disable=SC2034
# -*- coding: utf-8 -*-

# ACK (容器服务 Kubernetes 版) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_ack_help() {
    echo "ACK (容器服务 Kubernetes 版) 操作："
    echo "  get                                     - 列出所有集群"
    echo "  add <名称> [参数...]                   - 创建新集群"
    echo "  del [<集群ID>]                          - 删除集群（集群ID可选，可使用fzf选择）"
    echo "  set [<集群ID>] [<新名称>]               - 更新集群（集群ID和新名称都是可选的，可使用fzf选择）"
    echo "  detail [<集群ID>]                       - 获取集群详情（集群ID可选，可使用fzf选择）"
    echo "  node-get [<集群ID>] [format]           - 列出集群节点（集群ID可选，可使用fzf选择）"
    echo "  node-add [<集群ID>] [数量]              - 添加集群节点（集群ID可选，可使用fzf选择）"
    echo "  node-del [<集群ID>] [<节点ID>]          - 移除集群节点（集群ID和节点ID可选，可使用fzf选择）"
    echo "  config [<集群ID>]                       - 获取集群的 kubeconfig（集群ID可选，可使用fzf选择）"
    echo "  auto-scale <deployment> [namespace]     - 自动扩缩容指定部署"
    echo
    echo "示例："
    echo "  $0 ack get"
    echo "  $0 ack get json"
    echo "  $0 ack add my-cluster"
    echo "  $0 ack add my-cluster --node-count 3 --instance-type ecs.g6.large"
    echo "  $0 ack del c-xxx"
    echo "  $0 ack set c-xxx new-name"
    echo "  $0 ack detail c-xxx"
    echo "  $0 ack node-get c-xxx"
    echo "  $0 ack node-add c-xxx 2"
    echo "  $0 ack node-del c-xxx i-xxx"
    echo "  $0 ack config c-xxx"
    echo "  $0 ack auto-scale my-deployment default"
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
    node-get) ack_node_list "$@" ;;
    node-add) ack_node_add "$@" ;;
    node-del) ack_node_remove "$@" ;;
    config) ack_get_kubeconfig "$@" ;;
    auto-scale) ack_auto_scale "$@" >>"${SCRIPT_LOG:-/tmp/ack_auto_scale.log}" ;;
    help) show_ack_help ;;
    *)
        echo "错误：未知的 ACK 操作：$operation" >&2
        show_ack_help
        exit 1
        ;;
    esac
}

# 使用新框架的列表函数
ack_list() {
    local format=${1:-human}
    
    local table_header="ClusterId\tName\tState\tRegionId\tVersion\tNodeCount\tCreated"
    local jq_filter=".[] | [.cluster_id, .name, .state, .region_id, .version, .size, .created] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-16s  %-18s  %-8s  %-12s  %-7s  %-6s  %s\n", $1, $2, $3, $4, $5, $6, $7}'
    
    local result
    result=$(call_aliyun_api cs DescribeClusters --region "${region:-}")
    
    if [ $? -ne 0 ]; then
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
        vpc_result=$(call_aliyun_api vpc DescribeVpcs --RegionId "$region" 2>/dev/null)
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
        vswitch_result=$(call_aliyun_api vpc DescribeVSwitches --VpcId "$vpc_id" --RegionId "$region" 2>/dev/null)
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
    result=$(call_aliyun_api cs CreateCluster \
        --region "$region" \
        --name "$name" \
        --cluster-type "ManagedKubernetes" \
        --vpcid "$vpc_id" \
        --vswitch-ids "[$vswitch_id]" \
        --num-of-nodes "$node_count" \
        --instance-type "$instance_type" \
        --kubernetes-version "$kubernetes_version" \
        --worker-system-disk-category "$worker_system_disk_category" \
        --worker-system-disk-size "$worker_system_disk_size" \
        --container-cidr "172.20.0.0/16" \
        --service-cidr "172.21.0.0/20" \
        --is-enterprise-security-group true \
        --cloud-monitor-flags 1)

    if [ $? -eq 0 ]; then
        echo "ACK 集群创建请求已提交："
        echo "$result" | jq '.'

        # 获取集群ID
        local cluster_id
        cluster_id=$(echo "$result" | jq -r '.ClusterId')

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
            status=$(call_aliyun_api cs DescribeClusterDetail \
                --ClusterId "$cluster_id" 2>/dev/null | jq -r '.state')

            echo "集群状态: $status"
            if [ "$status" = "running" ]; then
                echo "集群创建成功！"
                break
            elif [ "$status" = "failed" ]; then
                echo "错误：集群创建失败。"
                break
            fi

            sleep 30
        done
        log_result "${profile:-}" "$region" "ack" "create" "$result"
    else
        echo "错误：集群创建请求失败。"
        echo "$result"
        return 1
    fi
}

# 使用新框架的删除函数
ack_delete() {
    local cluster_id=$1

    # 如果没有提供集群ID，则使用 fzf 选择
    if [ -z "$cluster_id" ]; then
        local cluster_list
        local result
        result=$(call_aliyun_api cs DescribeClusters --region "${region:-}")
        if [ $? -ne 0 ]; then
            echo "错误：无法获取集群列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        cluster_list=$(echo "$result" | jq -r '.[] | "\(.cluster_id) (\(.name // "无名称")) [\(.state)]"')

        if [ -z "$cluster_list" ]; then
            echo "错误：没有找到任何集群。" >&2
            return 1
        elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            cluster_id=$(echo "$cluster_list" | awk '{print $1}')
            echo "自动选择唯一的集群: $cluster_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                cluster_id=$(select_with_fzf "选择要删除的 ACK 集群" "$cluster_list" | awk '{print $1}')
                if [ -z "$cluster_id" ]; then
                    echo "错误：未选择集群。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择集群，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 检查集群 ID 是否为空
    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    # 获取集群详情
    local cluster_info
    cluster_info=$(call_aliyun_api cs DescribeClusterDetail --ClusterId "$cluster_id" 2>/dev/null)
    local cluster_name
    cluster_name=$(echo "$cluster_info" | jq -r '.name // "未知"')

    echo "警告：您即将删除以下集群："
    echo "  集群ID: $cluster_id"
    echo "  名称: $cluster_name"
    echo "  地域: $region"

    if ! confirm_action "删除 ACK 集群：$cluster_id"; then
        return 1
    fi

    echo "删除 ACK 集群："
    local result
    result=$(call_aliyun_api cs DeleteCluster \
        --ClusterId "$cluster_id" \
        --retain-resources '[""]')

    if [ $? -eq 0 ]; then
        echo "ACK 集群删除请求已提交。"
        log_delete_operation "${profile:-}" "$region" "ack" "$cluster_id" "ACK集群" "成功"
    else
        echo "ACK 集群删除请求失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "ack" "$cluster_id" "ACK集群" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "ack" "delete" "$result"
}

# 使用新框架的更新函数
ack_update() {
    local cluster_id=$1
    local new_name=$2

    # 如果没有提供集群ID，则使用 fzf 选择
    if [ -z "$cluster_id" ]; then
        local cluster_list
        local result
        result=$(call_aliyun_api cs DescribeClusters --region "${region:-}")
        if [ $? -ne 0 ]; then
            echo "错误：无法获取集群列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        cluster_list=$(echo "$result" | jq -r '.[] | "\(.cluster_id) (\(.name // "无名称")) [\(.state)]"')

        if [ -z "$cluster_list" ]; then
            echo "错误：没有找到任何集群。" >&2
            return 1
        elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            cluster_id=$(echo "$cluster_list" | awk '{print $1}')
            echo "自动选择唯一的集群: $cluster_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                cluster_id=$(select_with_fzf "选择要更新的 ACK 集群" "$cluster_list" | awk '{print $1}')
                if [ -z "$cluster_id" ]; then
                    echo "错误：未选择集群。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择集群，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

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
    local result
    result=$(call_aliyun_api cs ModifyCluster \
        --ClusterId "$cluster_id" \
        --name "$new_name")

    if [ $? -eq 0 ]; then
        echo "集群更新成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ack" "update" "$result"
    else
        echo "错误：集群更新失败。"
        echo "$result"
        return 1
    fi
}

# 获取集群详情（使用框架函数）
ack_detail() {
    local cluster_id=$1

    # 如果没有提供集群ID，则使用 fzf 选择
    if [ -z "$cluster_id" ]; then
        local cluster_list
        local result
        result=$(call_aliyun_api cs DescribeClusters --region "${region:-}")
        if [ $? -ne 0 ]; then
            echo "错误：无法获取集群列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        cluster_list=$(echo "$result" | jq -r '.[] | "\(.cluster_id) (\(.name // "无名称")) [\(.state)]"')

        if [ -z "$cluster_list" ]; then
            echo "错误：没有找到任何集群。" >&2
            return 1
        elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            cluster_id=$(echo "$cluster_list" | awk '{print $1}')
            echo "自动选择唯一的集群: $cluster_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                cluster_id=$(select_with_fzf "选择要查看详情的 ACK 集群" "$cluster_list" | awk '{print $1}')
                if [ -z "$cluster_id" ]; then
                    echo "错误：未选择集群。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择集群，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 检查集群 ID 是否为空
    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    echo "获取集群详情："
    local result
    result=$(call_aliyun_api cs DescribeClusterDetail --ClusterId "$cluster_id")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
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

    # 如果没有提供集群ID，则使用 fzf 选择
    if [ -z "$cluster_id" ]; then
        local cluster_list
        local result
        result=$(call_aliyun_api cs DescribeClusters --region "${region:-}")
        if [ $? -ne 0 ]; then
            echo "错误：无法获取集群列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        cluster_list=$(echo "$result" | jq -r '.[] | "\(.cluster_id) (\(.name // "无名称")) [\(.state)]"')

        if [ -z "$cluster_list" ]; then
            echo "错误：没有找到任何集群。" >&2
            return 1
        elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            cluster_id=$(echo "$cluster_list" | awk '{print $1}')
            echo "自动选择唯一的集群: $cluster_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                cluster_id=$(select_with_fzf "选择要查看节点的 ACK 集群" "$cluster_list" | awk '{print $1}')
                if [ -z "$cluster_id" ]; then
                    echo "错误：未选择集群。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择集群，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 检查集群 ID 是否为空
    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    local table_header="NodeId\tNodeName\tStatus\tInstanceType\tCreated"
    local jq_filter=".nodes[] | [.instance_id, .instance_name, .state, .instance_type, .creation_time] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-16s  %-18s  %-8s  %-15s  %s\n", $1, $2, $3, $4, $5}'

    local result
    result=$(call_aliyun_api cs DescribeClusterNodes --ClusterId "$cluster_id")

    if [ $? -ne 0 ]; then
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

# 添加节点（使用框架函数）
ack_node_add() {
    local cluster_id=$1
    local count=${2:-1}

    # 如果没有提供集群ID，则使用 fzf 选择
    if [ -z "$cluster_id" ]; then
        local cluster_list
        local result
        result=$(call_aliyun_api cs DescribeClusters --region "${region:-}")
        if [ $? -ne 0 ]; then
            echo "错误：无法获取集群列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        cluster_list=$(echo "$result" | jq -r '.[] | "\(.cluster_id) (\(.name // "无名称")) [\(.state)]"')

        if [ -z "$cluster_list" ]; then
            echo "错误：没有找到任何集群。" >&2
            return 1
        elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            cluster_id=$(echo "$cluster_list" | awk '{print $1}')
            echo "自动选择唯一的集群: $cluster_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                cluster_id=$(select_with_fzf "选择要添加节点的 ACK 集群" "$cluster_list" | awk '{print $1}')
                if [ -z "$cluster_id" ]; then
                    echo "错误：未选择集群。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择集群，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 检查集群 ID 是否为空
    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    echo "添加集群节点："
    local result
    result=$(call_aliyun_api cs ScaleOutCluster \
        --ClusterId "$cluster_id" \
        --count "$count")

    if [ $? -eq 0 ]; then
        echo "节点添加请求已提交："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ack" "node-add" "$result"
    else
        echo "错误：节点添加请求失败。"
        echo "$result"
        return 1
    fi
}

# 移除节点（使用框架函数）
ack_node_remove() {
    local cluster_id=$1
    local node_id=$2

    # 如果没有提供集群ID，则使用 fzf 选择
    if [ -z "$cluster_id" ]; then
        local cluster_list
        local result
        result=$(call_aliyun_api cs DescribeClusters --region "${region:-}")
        if [ $? -ne 0 ]; then
            echo "错误：无法获取集群列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        cluster_list=$(echo "$result" | jq -r '.[] | "\(.cluster_id) (\(.name // "无名称")) [\(.state)]"')

        if [ -z "$cluster_list" ]; then
            echo "错误：没有找到任何集群。" >&2
            return 1
        elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            cluster_id=$(echo "$cluster_list" | awk '{print $1}')
            echo "自动选择唯一的集群: $cluster_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                cluster_id=$(select_with_fzf "选择要移除节点的 ACK 集群" "$cluster_list" | awk '{print $1}')
                if [ -z "$cluster_id" ]; then
                    echo "错误：未选择集群。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择集群，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 如果没有提供节点ID，则使用 fzf 选择
    if [ -z "$node_id" ]; then
        local node_list
        local node_result
        node_result=$(call_aliyun_api cs DescribeClusterNodes --ClusterId "$cluster_id" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取节点列表。" >&2
            return 1
        fi

        node_list=$(echo "$node_result" | jq -r '.nodes[] | "\(.instance_id) (\(.instance_name // "无名称")) [\(.state)]"')

        if [ -z "$node_list" ]; then
            echo "错误：没有找到任何节点。" >&2
            return 1
        elif [ "$(echo "$node_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            node_id=$(echo "$node_list" | awk '{print $1}')
            echo "自动选择唯一的节点: $node_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                node_id=$(select_with_fzf "选择要移除的节点" "$node_list" | awk '{print $1}')
                if [ -z "$node_id" ]; then
                    echo "错误：未选择节点。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择节点，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    if ! validate_required_params "$cluster_id" "$node_id" "错误：集群ID和节点ID不能为空。"; then
        return 1
    fi

    if ! confirm_action "从集群中移除节点：$node_id"; then
        return 1
    fi

    echo "移除集群节点："
    local result
    result=$(call_aliyun_api cs DeleteClusterNodes \
        --ClusterId "$cluster_id" \
        --nodes "[$node_id]" \
        --release-node true)

    if [ $? -eq 0 ]; then
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

    # 如果没有提供集群ID，则使用 fzf 选择
    if [ -z "$cluster_id" ]; then
        local cluster_list
        local result
        result=$(call_aliyun_api cs DescribeClusters --region "${region:-}")
        if [ $? -ne 0 ]; then
            echo "错误：无法获取集群列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        cluster_list=$(echo "$result" | jq -r '.[] | "\(.cluster_id) (\(.name // "无名称")) [\(.state)]"')

        if [ -z "$cluster_list" ]; then
            echo "错误：没有找到任何集群。" >&2
            return 1
        elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            cluster_id=$(echo "$cluster_list" | awk '{print $1}')
            echo "自动选择唯一的集群: $cluster_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                cluster_id=$(select_with_fzf "选择要获取 kubeconfig 的 ACK 集群" "$cluster_list" | awk '{print $1}')
                if [ -z "$cluster_id" ]; then
                    echo "错误：未选择集群。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择集群，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 检查集群 ID 是否为空
    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    echo "获取集群 kubeconfig："
    local result
    result=$(call_aliyun_api cs DescribeClusterUserKubeconfig \
        --ClusterId "$cluster_id" \
        --PrivateIpAddress "$private")

    if [ $? -eq 0 ]; then
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

# 自动扩缩容（保持原有复杂逻辑）
ack_auto_scale() {
    local deployment=$1
    local namespace=${2:-main}
    local lock_file_all="/tmp/lock.scale.all"
    local lock_file_up="/tmp/lock.scale.up.$deployment"
    local lock_file_down="/tmp/lock.scale.down.$deployment"

    ## disable auto scale when helm install/upgrade
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

    # 定义常量
    local CPU_WARN_FACTOR=1500          # CPU 警告阈值因子
    local MEM_WARN_FACTOR=1200          # 内存警告阈值因子
    local CPU_NORMAL_FACTOR=500         # CPU 正常阈值因子
    local MEM_NORMAL_FACTOR=500         # 内存正常阈值因子
    local SCALE_CHANGE=2                # 每次扩缩容的节点数量
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

    # 获取当前 CPU 和内存使用情况
    local cpu mem
    read -r cpu mem < <(kubectl -n "$namespace" top pod -l "app.kubernetes.io/name=$deployment" --no-headers |
        awk 'NR>1 {c+=int($2); m+=int($3)} END {printf "%d %d", c, m}')

    # 检查是否需要扩容
    if ((cpu > pod_cpu_warn)); then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')], 当前CPU求和: $cpu, 内存求和: $mem"
        kubectl -n "$namespace" top pod -l "app.kubernetes.io/name=$deployment"
        ## 扩容数量每次增加2，应对突发流量
        scale_deployment "up" $((pod_total + SCALE_CHANGE)) "$lock_file_up" "$lock_file_down"
        return
    fi

    # 检查缩容冷却期
    if check_cooldown "down" "$lock_file_down" $COOLDOWN_MINUTES_SCALE_DOWN; then
        return
    fi
    
    # 检查是否需要缩容
    if ((cpu < pod_cpu_normal)); then
        if ((pod_total > node_fixed)); then
            kubectl -n "$namespace" top pod -l "app.kubernetes.io/name=$deployment"
            scale_deployment "down" $((pod_total - SCALE_CHANGE)) "$lock_file_up" "$lock_file_down"
            return
        fi
        ## 检查是否有pod运行在虚拟节点，如果有则执行 kubectl rollout restart 命令
        local pod_on_virtual_node
        pod_on_virtual_node=$(kubectl -n "$namespace" get pod -l "app.kubernetes.io/name=$deployment" -o jsonpath='{range .items[?(@.spec.nodeName=="virtual-kubelet-cn-hangzhou-k")]}{.metadata.name}{"\n"}{end}')
        if [ -n "$pod_on_virtual_node" ]; then
            echo "警告：以下pod运行在虚拟节点上：$pod_on_virtual_node ，即将重启"
            kubectl -n "$namespace" patch deployment "$deployment" -p '{"spec":{"strategy":{"rollingUpdate":{"maxUnavailable":"25%"}}}}'
            kubectl -n "$namespace" rollout restart deployment "$deployment"
        fi
    fi
}
