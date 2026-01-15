#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# EC2 (弹性计算云) 相关函数

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_ec2_help() {
    echo "EC2 (弹性计算云) 操作："
    echo "  list [format]                         - 列出 EC2 实例"
    echo "  start <实例ID>                         - 启动 EC2 实例"
    echo "  stop <实例ID>                          - 停止 EC2 实例"
    echo "  reboot <实例ID>                        - 重启 EC2 实例"
    echo "  key-list                              - 列出 SSH 密钥对"
    echo "  key-create <密钥对名称>                 - 创建 SSH 密钥对"
    echo "  key-delete <密钥对名称>                 - 删除 SSH 密钥对"
    echo
    echo "示例："
    echo "  $0 ec2 list"
    echo "  $0 ec2 start i-1234567890abcdef0"
    echo "  $0 ec2 stop i-1234567890abcdef0"
    echo "  $0 ec2 reboot i-1234567890abcdef0"
    echo "  $0 ec2 key-list"
    echo "  $0 ec2 key-create my-key"
    echo "  $0 ec2 key-delete my-key"
}

handle_ec2_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) ec2_list "$@" ;;
    start) ec2_start "$@" ;;
    stop) ec2_stop "$@" ;;
    reboot) ec2_reboot "$@" ;;
    key-list) ec2_key_list "$@" ;;
    key-create) ec2_key_create "$@" ;;
    key-delete) ec2_key_delete "$@" ;;
    help) show_ec2_help ;;
    *)
        echo "错误：未知的 EC2 操作：$operation" >&2
        show_ec2_help
        exit 1
        ;;
    esac
}

# EC2 列表
ec2_list() {
    local format=${1:-human}
    local result
    
    result=$(call_aws_api ec2 describe-instances)
    if [ $? -ne 0 ]; then
        echo "错误：无法获取 EC2 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "InstanceId\tInstanceType\tState\tPrivateIpAddress\tPublicIpAddress\tTags"
        echo "$result" | jq -r '.Reservations[].Instances[] | 
            [
                .InstanceId,
                .InstanceType,
                .State.Name,
                (.PrivateIpAddress // "-"),
                (.PublicIpAddress // "-"),
                ([.Tags[]? | "\(.Key)=\(.Value)"] | join(",") // "-")
            ] | @tsv'
        ;;
    human | *)
        echo "列出 EC2 实例："
        local temp_output
        temp_output=$(echo "$result" | jq -r '.Reservations[].Instances[] | 
            [
                .InstanceId,
                .InstanceType,
                .State.Name,
                (.PrivateIpAddress // "-"),
                (.PublicIpAddress // "-"),
                ([.Tags[]? | select(.Key == "Name") | .Value] | first // "-")
            ] | @tsv')
        
        local count
        if [ -n "$temp_output" ] && [ "$temp_output" != "null" ] && [ "$temp_output" != "" ]; then
            count=$(echo "$temp_output" | grep -c . || echo "0")
        else
            count="0"
        fi
        
        if [ "$count" = "0" ] || [ -z "$count" ]; then
            echo "没有找到 EC2 实例。"
        else
            echo -e "InstanceId\t\tInstanceType\tState\t\tPrivateIp\tPublicIp\tName"
            echo "$temp_output" | awk 'BEGIN {FS="\t"; OFS="\t"} {
                printf "%-20s  %-15s  %-12s  %-15s  %-15s  %s\n", $1, $2, $3, $4, $5, $6
            }'
        fi
        ;;
    esac
    
    log_result "${profile:-}" "${region:-}" "ec2" "list" "$result" "$format"
}

# 启动 EC2 实例
ec2_start() {
    local instance_id=$1
    
    if [ -z "$instance_id" ]; then
        echo "错误：需要提供实例 ID。" >&2
        echo "用法：$0 ec2 start <实例ID>" >&2
        return 1
    fi
    
    echo "启动 EC2 实例：$instance_id"
    
    local result
    result=$(call_aws_api ec2 start-instances --instance-ids "$instance_id")
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ec2" "start" "$result"
    else
        echo "错误：启动失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 停止 EC2 实例
ec2_stop() {
    local instance_id=$1
    
    if [ -z "$instance_id" ]; then
        echo "错误：需要提供实例 ID。" >&2
        echo "用法：$0 ec2 stop <实例ID>" >&2
        return 1
    fi
    
    echo "停止 EC2 实例：$instance_id"
    
    local result
    result=$(call_aws_api ec2 stop-instances --instance-ids "$instance_id")
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ec2" "stop" "$result"
    else
        echo "错误：停止失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 重启 EC2 实例
ec2_reboot() {
    local instance_id=$1
    
    if [ -z "$instance_id" ]; then
        echo "错误：需要提供实例 ID。" >&2
        echo "用法：$0 ec2 reboot <实例ID>" >&2
        return 1
    fi
    
    echo "重启 EC2 实例：$instance_id"
    
    local result
    result=$(call_aws_api ec2 reboot-instances --instance-ids "$instance_id")
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ec2" "reboot" "$result"
    else
        echo "错误：重启失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 列出 SSH 密钥对
ec2_key_list() {
    local format=${1:-human}
    local result
    
    result=$(call_aws_api ec2 describe-key-pairs)
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
        echo "$result" | jq -r '.KeyPairs[] | [.KeyName, .KeyFingerprint] | @tsv'
        ;;
    human | *)
        echo "列出 SSH 密钥对："
        local temp_output
        temp_output=$(echo "$result" | jq -r '.KeyPairs[] | [.KeyName, .KeyFingerprint] | @tsv')
        
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
    
    log_result "${profile:-}" "${region:-}" "ec2" "key-list" "$result" "$format"
}

# 创建 SSH 密钥对
ec2_key_create() {
    local key_name=$1
    
    if [ -z "$key_name" ]; then
        echo "错误：需要提供密钥对名称。" >&2
        echo "用法：$0 ec2 key-create <密钥对名称>" >&2
        return 1
    fi
    
    echo "创建 SSH 密钥对：$key_name"
    
    local result
    result=$(call_aws_api ec2 create-key-pair --key-name "$key_name")
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        # 保存私钥到文件
        local private_key
        private_key=$(echo "$result" | jq -r '.KeyMaterial')
        if [ -n "$private_key" ]; then
            local key_file="${SCRIPT_DATA}/${profile:-default}/${region:-us-east-1}/keys/${key_name}.pem"
            mkdir -p "$(dirname "$key_file")"
            echo "$private_key" > "$key_file"
            chmod 600 "$key_file"
            echo "私钥已保存到: $key_file"
        fi
        log_result "${profile:-}" "$region" "ec2" "key-create" "$result"
    else
        echo "错误：创建失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 删除 SSH 密钥对
ec2_key_delete() {
    local key_name=$1
    
    if [ -z "$key_name" ]; then
        echo "错误：需要提供密钥对名称。" >&2
        echo "用法：$0 ec2 key-delete <密钥对名称>" >&2
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
    result=$(call_aws_api ec2 delete-key-pair --key-name "$key_name")
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo "密钥对已删除。"
        log_result "${profile:-}" "$region" "ec2" "key-delete" "$result"
    else
        echo "错误：删除失败。" >&2
        echo "$result" >&2
        return 1
    fi
}
