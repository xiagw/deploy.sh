#!/usr/bin/env bash
# shellcheck disable=SC2034
# -*- coding: utf-8 -*-

# ACK (容器服务 Kubernetes 版) 相关函数

show_ack_help() {
    echo "ACK (容器服务 Kubernetes 版) 操作："
    echo "  list [format]                           - 列出所有集群"
    echo "  create <名称> [参数...]                  - 创建新集群"
    echo "  delete <集群ID>                         - 删除集群"
    echo "  update <集群ID> <新名称>                - 更新集群"
    echo "  detail <集群ID>                         - 获取集群详情"
    echo "  node-list <集群ID>                      - 列出集群节点"
    echo "  node-add <集群ID> [数量]                - 添加集群节点"
    echo "  node-remove <集群ID> <节点ID>           - 移除集群节点"
    echo "  kubeconfig <集群ID>                     - 获取集群的 kubeconfig"
    echo "  auto-scale <deployment> [namespace]      - 自动扩缩容指定部署"
    echo
    echo "示例："
    echo "  $0 ack list"
    echo "  $0 ack list json"
    echo "  $0 ack create my-cluster"
    echo "  $0 ack create my-cluster --node-count 3 --instance-type ecs.g6.large"
    echo "  $0 ack delete c-xxx"
    echo "  $0 ack update c-xxx new-name"
    echo "  $0 ack detail c-xxx"
    echo "  $0 ack node-list c-xxx"
    echo "  $0 ack node-add c-xxx 2"
    echo "  $0 ack node-remove c-xxx i-xxx"
    echo "  $0 ack kubeconfig c-xxx"
    echo "  $0 ack auto-scale my-deployment default  # 自动扩缩容指定部署"
}

handle_ack_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) ack_list "$@" ;;
    create) ack_create "$@" ;;
    delete) ack_delete "$@" ;;
    update) ack_update "$@" ;;
    detail) ack_detail "$@" ;;
    node-list) ack_node_list "$@" ;;
    node-add) ack_node_add "$@" ;;
    node-remove) ack_node_remove "$@" ;;
    kubeconfig) ack_get_kubeconfig "$@" ;;
    auto-scale) ack_auto_scale "$@" ;;
    *)
        echo "错误：未知的 ACK 操作：$operation" >&2
        show_ack_help
        exit 1
        ;;
    esac
}

ack_list() {
    local format=${1:-human}
    local result
    if ! result=$(aliyun --profile "${profile:-}" cs DescribeClusters --region "${region:-}"); then
        echo "错误：无法获取集群列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        echo -e "ClusterId\tName\tState\tRegionId\tVersion\tNodeCount\tCreated"
        echo "$result" | jq -r '.[] | [.cluster_id, .name, .state, .region_id, .version, .size, .created] | @tsv'
        ;;
    human | *)
        echo "列出 ACK 集群："
        if [[ $(echo "$result" | jq '. | length') -eq 0 ]]; then
            echo "没有找到 ACK 集群。"
        else
            echo "集群ID            名称                状态      地域          版本     节点数  创建时间"
            echo "----------------  ------------------  --------  ------------  -------  ------  -------------------------"
            echo "$result" | jq -r '.[] | [.cluster_id, .name, .state, .region_id, .version, .size, .created] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    printf "%-16s  %-18s  %-8s  %-12s  %-7s  %-6s  %s\n", $1, $2, $3, $4, $5, $6, $7
                }'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "ack" "list" "$result" "$format"
}

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

    # 获取VPC信息
    local vpc_id
    vpc_id=$(get_vpc_id)
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    # 获取交换机信息
    local vswitch_id
    vswitch_id=$(vpc_vswitch_list "$vpc_id" json | jq -r '.[0].VSwitchId')
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
    result=$(aliyun --profile "${profile:-}" cs CreateCluster \
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

    ret=$?
    if [ $ret -eq 0 ]; then
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
            status=$(aliyun --profile "${profile:-}" cs DescribeClusterDetail \
                --ClusterId "$cluster_id" | jq -r '.state')

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
    else
        echo "错误：集群创建请求失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "ack" "create" "$result"
}

ack_delete() {
    local cluster_id=$1

    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    # 获取集群详情
    local cluster_info
    cluster_info=$(aliyun --profile "${profile:-}" cs DescribeClusterDetail --ClusterId "$cluster_id")
    local cluster_name
    cluster_name=$(echo "$cluster_info" | jq -r '.name')

    echo "警告：您即将删除以下集群："
    echo "  集群ID: $cluster_id"
    echo "  名称: $cluster_name"
    echo "  地域: $region"
    echo
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 ACK 集群："
    local result
    result=$(aliyun --profile "${profile:-}" cs DeleteCluster \
        --ClusterId "$cluster_id" \
        --retain-resources '[""]')
    local status=$?

    if [ $status -eq 0 ]; then
        echo "ACK 集群删除请求已提交。"
        log_delete_operation "${profile:-}" "$region" "ack" "$cluster_id" "$cluster_name" "成功"
    else
        echo "ACK 集群删除请求失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "ack" "$cluster_id" "$cluster_name" "失败"
    fi

    log_result "${profile:-}" "$region" "ack" "delete" "$result"
}

ack_update() {
    local cluster_id=$1
    local new_name=$2

    if [ -z "$cluster_id" ] || [ -z "$new_name" ]; then
        echo "错误：集群ID和新名称不能为空。" >&2
        return 1
    fi

    echo "更新 ACK 集群："
    local result
    result=$(aliyun --profile "${profile:-}" cs ModifyCluster \
        --ClusterId "$cluster_id" \
        --name "$new_name")

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "集群更新成功："
        echo "$result" | jq '.'
    else
        echo "错误：集群更新失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "ack" "update" "$result"
}

ack_detail() {
    local cluster_id=$1

    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    echo "获取集群详情："
    local result
    result=$(aliyun --profile "${profile:-}" cs DescribeClusterDetail --ClusterId "$cluster_id")

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
    else
        echo "错误：无法获取集群详情。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "ack" "detail" "$result"
}

ack_node_list() {
    local cluster_id=$1
    local format=${2:-human}

    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    echo "列出集群节点："
    local result
    result=$(aliyun --profile "${profile:-}" cs DescribeClusterNodes \
        --ClusterId "$cluster_id")

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "NodeId\tNodeName\tStatus\tInstanceType\tCreated"
        echo "$result" | jq -r '.nodes[] | [.instance_id, .instance_name, .state, .instance_type, .creation_time] | @tsv'
        ;;
    human | *)
        if [[ $(echo "$result" | jq '.nodes | length') -eq 0 ]]; then
            echo "没有找到节点。"
        else
            echo "节点ID            节点名称            状态      实例类型         创建时间"
            echo "----------------  ------------------  --------  ---------------  -------------------------"
            echo "$result" | jq -r '.nodes[] | [.instance_id, .instance_name, .state, .instance_type, .creation_time] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    printf "%-16s  %-18s  %-8s  %-15s  %s\n", $1, $2, $3, $4, $5
                }'
        fi
        ;;
    esac
    log_result "${profile:-}" "$region" "ack" "node-list" "$result" "$format"
}

ack_node_add() {
    local cluster_id=$1
    local count=${2:-1}

    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    echo "添加集群节点："
    local result
    result=$(aliyun --profile "${profile:-}" cs ScaleOutCluster \
        --ClusterId "$cluster_id" \
        --count "$count")

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "节点添加请求已提交："
        echo "$result" | jq '.'
    else
        echo "错误：节点添加请求失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "ack" "node-add" "$result"
}

ack_node_remove() {
    local cluster_id=$1
    local node_id=$2

    if [ -z "$cluster_id" ] || [ -z "$node_id" ]; then
        echo "错误：集群ID和节点ID不能为空。" >&2
        return 1
    fi

    echo "警告：您即将从集群中移除节点：$node_id"
    read -r -p "请输入 'YES' 以确认移除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "移除集群节点："
    local result
    result=$(aliyun --profile "${profile:-}" cs DeleteClusterNodes \
        --ClusterId "$cluster_id" \
        --nodes "[$node_id]" \
        --release-node true)

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "节点移除请求已提交："
        echo "$result" | jq '.'
    else
        echo "错误：节点移除请求失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "ack" "node-remove" "$result"
}

ack_get_kubeconfig() {
    local cluster_id=$1
    local private=${2:-false}

    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        return 1
    fi

    echo "获取集群 kubeconfig："
    local result
    result=$(aliyun --profile "${profile:-}" cs DescribeClusterUserKubeconfig \
        --ClusterId "$cluster_id" \
        --PrivateIpAddress "$private")

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "$result" | jq -r '.config'
    else
        echo "错误：无法获取 kubeconfig。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "ack" "kubeconfig" "$result"
}

ack_auto_scale() {
    local deployment=$1
    local namespace=${2:-main}
    local lock_file="/tmp/lock.scale.$deployment"

    if [ -z "$deployment" ]; then
        echo "错误：部署名称不能为空。" >&2
        return 1
    fi

    # 定义常量
    local CPU_WARN_FACTOR=1000  # CPU 警告阈值因子
    local MEM_WARN_FACTOR=1200  # 内存警告阈值因子
    local CPU_NORMAL_FACTOR=500 # CPU 正常阈值因子
    local MEM_NORMAL_FACTOR=500 # 内存正常阈值因子
    local SCALE_CHANGE=2        # 每次扩缩容的节点数量
    local COOLDOWN_MINUTES=5    # 冷却时间（分钟）

    # 获取节点和 Pod 信息
    local node_names
    readarray -t node_names < <(kubectl get nodes -o name)
    local node_total=${#node_names[@]}
    local node_fixed=$((node_total - 1)) # 实际节点数 = 所有节点数 - 虚拟节点 1 个

    local pod_total
    pod_total=$(kubectl -n "$namespace" get pod -l "app.kubernetes.io/name=$deployment" | grep -c "$deployment")

    # 检查锁文件
    if [[ -f $lock_file ]]; then
        # 检查锁文件是否过期（超过冷却时间）
        if [[ $(stat -c %Y "$lock_file") -gt $(date -d "$COOLDOWN_MINUTES minutes ago" +%s) ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 在冷却期（$COOLDOWN_MINUTES 分钟）内，跳过操作..." >&2
            return 1
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 删除过期的锁文件..." >&2
            # 删除过期的锁文件
            rm -f "$lock_file"
        fi
    fi

    # 计算阈值
    local pod_cpu_warn=$((pod_total * CPU_WARN_FACTOR))
    local pod_mem_warn=$((pod_total * MEM_WARN_FACTOR))
    local pod_cpu_normal=$((pod_total * CPU_NORMAL_FACTOR))
    local pod_mem_normal=$((pod_total * MEM_NORMAL_FACTOR))

    # 获取当前 CPU 和内存使用情况
    local cpu mem
    read -r cpu mem < <(kubectl -n "$namespace" top pod -l "app.kubernetes.io/name=$deployment" |
        awk 'NR>1 {c+=int($2); m+=int($3)} END {printf "%d %d", c, m}')

    # 扩缩容函数
    scale_deployment() {
        local load_status=$1
        local action=$2
        local new_total=$3

        echo "执行${action}操作：当前状态 - $load_status"
        echo "将部署 $deployment 的副本数调整为 $new_total"

        if kubectl -n "$namespace" scale --replicas="$new_total" deploy "$deployment"; then
            if kubectl -n "$namespace" rollout status deployment "$deployment" --timeout 120s; then
                local result="成功"
            else
                local result="失败"
            fi

            # 创建锁文件防止频繁操作
            touch "$lock_file"

            # 记录操作日志
            local msg_body
            msg_body="[$(date '+%Y-%m-%d %H:%M:%S')] 自动扩缩容: 应用 $deployment $load_status, $action $new_total; 结果: $result"
            echo "$msg_body"
            log_result "${profile:-}" "$region" "ack" "auto-scale" "$msg_body"
            _notify_wecom "${WECOM_KEY:-}" "$msg_body"
        else
            echo "扩缩容操作失败" >&2
            return 1
        fi
    }

    # 检查是否需要扩容
    if ((cpu > pod_cpu_warn && mem > pod_mem_warn)); then
        kubectl -n "$namespace" top pod -l "app.kubernetes.io/name=$deployment"
        scale_deployment "过载" "扩容" $((pod_total + SCALE_CHANGE))
        return
    fi

    # 检查冷却期
    if [[ -f "$lock_file" && $(stat -c %Y "$lock_file") -gt $(date -d "$COOLDOWN_MINUTES minutes ago" +%s) ]]; then
        echo "在冷却期内，跳过扩缩容操作"
        return
    fi

    # 检查是否需要缩容
    if ((pod_total > node_fixed && cpu < pod_cpu_normal && mem < pod_mem_normal)); then
        kubectl -n "$namespace" top pod -l "app.kubernetes.io/name=$deployment"
        scale_deployment "空闲" "缩容" $node_fixed
    fi
}
