#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# ECS (弹性云服务器) 相关函数

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_ecs_help() {
    echo "ECS (弹性云服务器) 操作："
    echo "  list [format]                         - 列出 ECS 实例"
    echo "  start <实例ID>                         - 启动 ECS 实例"
    echo "  stop <实例ID>                          - 停止 ECS 实例"
    echo "  reboot <实例ID>                        - 重启 ECS 实例"
    echo "  key-list                              - 列出 SSH 密钥对"
    echo "  key-create <密钥对名称>                 - 创建 SSH 密钥对"
    echo "  key-delete <密钥对名称>                 - 删除 SSH 密钥对"
    echo
    echo "示例："
    echo "  $0 ecs list"
    echo "  $0 ecs start <instance-id>"
    echo "  $0 ecs stop <instance-id>"
    echo "  $0 ecs reboot <instance-id>"
    echo "  $0 ecs key-list"
    echo "  $0 ecs key-create my-key"
    echo "  $0 ecs key-delete my-key"
}

handle_ecs_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) ecs_list "$@" ;;
    start) ecs_start "$@" ;;
    stop) ecs_stop "$@" ;;
    reboot) ecs_reboot "$@" ;;
    key-list) ecs_key_list "$@" ;;
    key-create) ecs_key_create "$@" ;;
    key-delete) ecs_key_delete "$@" ;;
    help) show_ecs_help ;;
    *)
        echo "错误：未知的 ECS 操作：$operation" >&2
        show_ecs_help
        exit 1
        ;;
    esac
}

# ECS 列表
ecs_list() {
    local format=${1:-human}
    local result
    
    result=$(call_huawei_api ecs NovaListServers)
    if [ $? -ne 0 ]; then
        echo "错误：无法获取 ECS 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "InstanceId\tInstanceType\tStatus\tPrivateIpAddress\tPublicIpAddress\tName"
        echo "$result" | jq -r '.servers[]? | 
            [
                .id,
                .flavor.id,
                .status,
                (.addresses | to_entries[0].value[0].addr // "-"),
                (.addresses | to_entries[] | select(.key != "internal") | .value[0].addr // "-" | first // "-"),
                (.name // "-")
            ] | @tsv'
        ;;
    human | *)
        echo "列出 ECS 实例："
        local temp_output
        temp_output=$(echo "$result" | jq -r '.servers[]? | 
            [
                .id,
                .flavor.id,
                .status,
                (.addresses | to_entries[0].value[0].addr // "-"),
                (.addresses | to_entries[] | select(.key != "internal") | .value[0].addr // "-" | first // "-"),
                (.name // "-")
            ] | @tsv')
        
        local count
        if [ -n "$temp_output" ] && [ "$temp_output" != "null" ] && [ "$temp_output" != "" ]; then
            count=$(echo "$temp_output" | grep -c . || echo "0")
        else
            count="0"
        fi
        
        if [ "$count" = "0" ] || [ -z "$count" ]; then
            echo "没有找到 ECS 实例。"
        else
            echo -e "InstanceId\t\t\tStatus\t\tPrivateIp\tPublicIp\tName"
            echo "$temp_output" | awk 'BEGIN {FS="\t"; OFS="\t"} {
                printf "%-30s  %-12s  %-15s  %-15s  %s\n", $1, $3, $4, $5, $6
            }'
        fi
        ;;
    esac
    
    log_result "${profile:-}" "${region:-}" "ecs" "list" "$result" "$format"
}

# 启动 ECS 实例
ecs_start() {
    local instance_id=$1
    
    if [ -z "$instance_id" ]; then
        echo "错误：需要提供实例 ID。" >&2
        echo "用法：$0 ecs start <实例ID>" >&2
        return 1
    fi
    
    echo "启动 ECS 实例：$instance_id"
    
    local result
    result=$(call_huawei_api ecs NovaStartServer --server-id "$instance_id")
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ecs" "start" "$result"
    else
        echo "错误：启动失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 停止 ECS 实例
ecs_stop() {
    local instance_id=$1
    
    if [ -z "$instance_id" ]; then
        echo "错误：需要提供实例 ID。" >&2
        echo "用法：$0 ecs stop <实例ID>" >&2
        return 1
    fi
    
    echo "停止 ECS 实例：$instance_id"
    
    local result
    result=$(call_huawei_api ecs NovaStopServer --server-id "$instance_id")
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ecs" "stop" "$result"
    else
        echo "错误：停止失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 重启 ECS 实例
ecs_reboot() {
    local instance_id=$1
    
    if [ -z "$instance_id" ]; then
        echo "错误：需要提供实例 ID。" >&2
        echo "用法：$0 ecs reboot <实例ID>" >&2
        return 1
    fi
    
    echo "重启 ECS 实例：$instance_id"
    
    local result
    result=$(call_huawei_api ecs NovaRebootServer --server-id "$instance_id")
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ecs" "reboot" "$result"
    else
        echo "错误：重启失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 列出 SSH 密钥对
ecs_key_list() {
    local format=${1:-human}
    local result
    
    result=$(call_huawei_api ecs NovaListKeypairs)
    if [ $? -ne 0 ]; then
        echo "错误：无法获取密钥对列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "KeyName\tKeyFingerprint"
        echo "$result" | jq -r '.keypairs[]? | [.keypair.name, .keypair.fingerprint] | @tsv'
        ;;
    human | *)
        echo "列出 SSH 密钥对："
        local temp_output
        temp_output=$(echo "$result" | jq -r '.keypairs[]? | [.keypair.name, .keypair.fingerprint] | @tsv')
        
        local count
        if [ -n "$temp_output" ] && [ "$temp_output" != "null" ] && [ "$temp_output" != "" ]; then
            count=$(echo "$temp_output" | grep -c . || echo "0")
        else
            count="0"
        fi
        
        if [ "$count" = "0" ] || [ -z "$count" ]; then
            echo "没有找到密钥对。"
        else
            echo -e "KeyName\t\t\tKeyFingerprint"
            echo "$temp_output" | awk 'BEGIN {FS="\t"; OFS="\t"} {
                printf "%-25s  %s\n", $1, $2
            }'
        fi
        ;;
    esac
    
    log_result "${profile:-}" "${region:-}" "ecs" "key-list" "$result" "$format"
}

# 创建 SSH 密钥对
ecs_key_create() {
    local key_name=$1
    
    if [ -z "$key_name" ]; then
        echo "错误：需要提供密钥对名称。" >&2
        echo "用法：$0 ecs key-create <密钥对名称>" >&2
        return 1
    fi
    
    echo "创建 SSH 密钥对：$key_name"
    
    local result
    result=$(call_huawei_api ecs NovaCreateKeypair --key-name "$key_name")
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        # 保存私钥到文件
        local private_key
        private_key=$(echo "$result" | jq -r '.keypair.private_key // empty')
        if [ -n "$private_key" ]; then
            local key_file="${SCRIPT_DATA}/${profile:-default}/${region:-cn-north-1}/keys/${key_name}.pem"
            mkdir -p "$(dirname "$key_file")"
            echo "$private_key" > "$key_file"
            chmod 600 "$key_file"
            echo "私钥已保存到: $key_file"
        fi
        log_result "${profile:-}" "$region" "ecs" "key-create" "$result"
    else
        echo "错误：创建失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 删除 SSH 密钥对
ecs_key_delete() {
    local key_name=$1
    
    if [ -z "$key_name" ]; then
        echo "错误：需要提供密钥对名称。" >&2
        echo "用法：$0 ecs key-delete <密钥对名称>" >&2
        return 1
    fi
    
    echo "警告：您即将删除 SSH 密钥对：$key_name"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm
    
    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi
    
    echo "删除 SSH 密钥对：$key_name"
    
    local result
    result=$(call_huawei_api ecs NovaDeleteKeypair --key-name "$key_name")
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo "密钥对已删除。"
        log_result "${profile:-}" "$region" "ecs" "key-delete" "$result"
    else
        echo "错误：删除失败。" >&2
        echo "$result" >&2
        return 1
    fi
}
