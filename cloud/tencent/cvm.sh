#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# CVM (云服务器) 相关函数

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_cvm_help() {
    echo "CVM (云服务器) 操作："
    echo "  list [format]                         - 列出 CVM 实例"
    echo "  start [<实例ID>]                      - 启动 CVM 实例（实例ID可选，可使用fzf选择）"
    echo "  stop [<实例ID>]                       - 停止 CVM 实例（实例ID可选，可使用fzf选择）"
    echo "  reboot [<实例ID>]                     - 重启 CVM 实例（实例ID可选，可使用fzf选择）"
    echo "  key-list [format]                     - 列出 SSH 密钥对"
    echo "  key-create <密钥对名称>                - 创建 SSH 密钥对"
    echo "  key-import [<密钥对名称>] [<公钥内容|文件|github:user>] - 导入 SSH 密钥对（参数可选，可使用fzf选择）"
    echo "  key-delete [<密钥对名称>]             - 删除 SSH 密钥对（密钥对名称可选，可使用fzf选择）"
    echo
    echo "示例："
    echo "  $0 cvm list"
    echo "  $0 cvm start ins-12345678"
    echo "  $0 cvm start (交互式选择实例)"
    echo "  $0 cvm stop ins-12345678"
    echo "  $0 cvm reboot ins-12345678"
    echo "  $0 cvm key-list"
    echo "  $0 cvm key-create my-key"
    echo "  $0 cvm key-import my-key 'ssh-rsa AAAAB3NzaC1yc2E...'"
    echo "  $0 cvm key-import my-key /path/to/public.key"
    echo "  $0 cvm key-import my-key github:username"
    echo "  $0 cvm key-import (交互式导入密钥)"
    echo "  $0 cvm key-delete my-key"
    echo "  $0 cvm key-delete (交互式选择密钥)"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_cvm_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) cvm_list "$@" ;;
    start) cvm_start "$@" ;;
    stop) cvm_stop "$@" ;;
    reboot) cvm_reboot "$@" ;;
    key-list) cvm_key_list "$@" ;;
    key-create) cvm_key_create "$@" ;;
    key-import) cvm_key_import "$@" ;;
    key-delete) cvm_key_delete "$@" ;;
    help) show_cvm_help ;;
    *)
        echo "错误：未知的 CVM 操作：$operation" >&2
        show_cvm_help
        exit 1
        ;;
    esac
}

handle_cvm_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) cvm_list "$@" ;;
    start) cvm_start "$@" ;;
    stop) cvm_stop "$@" ;;
    reboot) cvm_reboot "$@" ;;
    key-list) cvm_key_list "$@" ;;
    key-create) cvm_key_create "$@" ;;
    key-import) cvm_key_import "$@" ;;
    key-delete) cvm_key_delete "$@" ;;
    help) show_cvm_help ;;
    *)
        echo "错误：未知的 CVM 操作：$operation" >&2
        show_cvm_help
        exit 1
        ;;
    esac
}

# CVM 列表
cvm_list() {
    local format=${1:-human}
    local result

    result=$(call_tencent_api cvm DescribeInstances)
    if [ $? -ne 0 ]; then
        echo "错误：无法获取 CVM 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "InstanceId\tInstanceType\tInstanceState\tPrivateIpAddress\tPublicIpAddress\tInstanceName"
        echo "$result" | jq -r '.Response.InstanceSet[]? |
            [
                .InstanceId,
                .InstanceType,
                .InstanceState,
                (.PrivateIpAddresses[0] // "-"),
                (.PublicIpAddresses[0] // "-"),
                (.InstanceName // "-")
            ] | @tsv'
        ;;
    human | *)
        echo "列出 CVM 实例："
        local temp_output
        temp_output=$(echo "$result" | jq -r '.Response.InstanceSet[]? |
            [
                .InstanceId,
                .InstanceType,
                .InstanceState,
                (.PrivateIpAddresses[0] // "-"),
                (.PublicIpAddresses[0] // "-"),
                (.InstanceName // "-")
            ] | @tsv')

        local count
        if [ -n "$temp_output" ] && [ "$temp_output" != "null" ] && [ "$temp_output" != "" ]; then
            count=$(echo "$temp_output" | grep -c . || echo "0")
        else
            count="0"
        fi

        if [ "$count" = "0" ] || [ -z "$count" ]; then
            echo "没有找到 CVM 实例。"
        else
            echo -e "InstanceId\t\tInstanceType\tState\t\tPrivateIp\tPublicIp\tName"
            echo "$temp_output" | awk 'BEGIN {FS="\t"; OFS="\t"} {
                printf "%-20s  %-15s  %-12s  %-15s  %-15s  %s\n", $1, $2, $3, $4, $5, $6
            }'
        fi
        ;;
    esac

    log_result "${profile:-}" "${region:-}" "cvm" "list" "$result" "$format"
}

# 启动 CVM 实例
cvm_start() {
    local instance_id=$1

    # 如果没有提供实例ID，则使用 fzf 选择
    if [ -z "$instance_id" ]; then
        local instance_list
        local result
        result=$(call_tencent_api cvm DescribeInstances)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 CVM 实例列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        instance_list=$(echo "$result" | jq -r '.Response.InstanceSet[]? | "\(.InstanceId) (\(.InstanceName // "-")) [\(.InstanceState)]"')

        if [ -z "$instance_list" ]; then
            echo "错误：没有找到任何 CVM 实例。" >&2
            return 1
        elif [ "$(echo "$instance_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            instance_id=$(echo "$instance_list" | awk '{print $1}')
            echo "自动选择唯一的实例: $instance_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                instance_id=$(select_with_fzf "选择 CVM 实例" "$instance_list" | awk '{print $1}')
                if [ -z "$instance_id" ]; then
                    echo "错误：未选择实例。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择实例，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    if [ -z "$instance_id" ]; then
        echo "错误：需要提供实例 ID。" >&2
        echo "用法：$0 cvm start <实例ID>" >&2
        return 1
    fi

    echo "启动 CVM 实例：$instance_id"

    local result
    result=$(call_tencent_api cvm StartInstances --InstanceIds "[\"$instance_id\"]")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cvm" "start" "$result"
    else
        echo "错误：启动失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 停止 CVM 实例
cvm_stop() {
    local instance_id=$1

    # 如果没有提供实例ID，则使用 fzf 选择
    if [ -z "$instance_id" ]; then
        local instance_list
        local result
        result=$(call_tencent_api cvm DescribeInstances)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 CVM 实例列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        instance_list=$(echo "$result" | jq -r '.Response.InstanceSet[]? | "\(.InstanceId) (\(.InstanceName // "-")) [\(.InstanceState)]"')

        if [ -z "$instance_list" ]; then
            echo "错误：没有找到任何 CVM 实例。" >&2
            return 1
        elif [ "$(echo "$instance_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            instance_id=$(echo "$instance_list" | awk '{print $1}')
            echo "自动选择唯一的实例: $instance_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                instance_id=$(select_with_fzf "选择要停止的 CVM 实例" "$instance_list" | awk '{print $1}')
                if [ -z "$instance_id" ]; then
                    echo "错误：未选择实例。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择实例，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    if [ -z "$instance_id" ]; then
        echo "错误：需要提供实例 ID。" >&2
        echo "用法：$0 cvm stop <实例ID>" >&2
        return 1
    fi

    echo "停止 CVM 实例：$instance_id"

    local result
    result=$(call_tencent_api cvm StopInstances --InstanceIds "[\"$instance_id\"]")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cvm" "stop" "$result"
    else
        echo "错误：停止失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 重启 CVM 实例
cvm_reboot() {
    local instance_id=$1

    # 如果没有提供实例ID，则使用 fzf 选择
    if [ -z "$instance_id" ]; then
        local instance_list
        local result
        result=$(call_tencent_api cvm DescribeInstances)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 CVM 实例列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        instance_list=$(echo "$result" | jq -r '.Response.InstanceSet[]? | "\(.InstanceId) (\(.InstanceName // "-")) [\(.InstanceState)]"')

        if [ -z "$instance_list" ]; then
            echo "错误：没有找到任何 CVM 实例。" >&2
            return 1
        elif [ "$(echo "$instance_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            instance_id=$(echo "$instance_list" | awk '{print $1}')
            echo "自动选择唯一的实例: $instance_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                instance_id=$(select_with_fzf "选择要重启的 CVM 实例" "$instance_list" | awk '{print $1}')
                if [ -z "$instance_id" ]; then
                    echo "错误：未选择实例。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择实例，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    if [ -z "$instance_id" ]; then
        echo "错误：需要提供实例 ID。" >&2
        echo "用法：$0 cvm reboot <实例ID>" >&2
        return 1
    fi

    echo "重启 CVM 实例：$instance_id"

    local result
    result=$(call_tencent_api cvm RebootInstances --InstanceIds "[\"$instance_id\"]")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cvm" "reboot" "$result"
    else
        echo "错误：重启失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 列出 SSH 密钥对
cvm_key_list() {
    local format=${1:-human}
    local result
    
    result=$(call_tencent_api cvm DescribeKeyPairs)
    if [ $? -ne 0 ]; then
        echo "错误：无法获取密钥对列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "KeyId\tKeyName"
        echo "$result" | jq -r '.Response.KeyPairSet[]? | [.KeyId, .KeyName] | @tsv'
        ;;
    human | *)
        echo "列出 SSH 密钥对："
        local temp_output
        temp_output=$(echo "$result" | jq -r '.Response.KeyPairSet[]? | [.KeyId, .KeyName] | @tsv')
        
        local count
        if [ -n "$temp_output" ] && [ "$temp_output" != "null" ] && [ "$temp_output" != "" ]; then
            count=$(echo "$temp_output" | grep -c . || echo "0")
        else
            count="0"
        fi
        
        if [ "$count" = "0" ] || [ -z "$count" ]; then
            echo "没有找到密钥对。"
        else
            echo -e "KeyId\t\t\tKeyName"
            echo "$temp_output" | awk 'BEGIN {FS="\t"; OFS="\t"} {
                printf "%-25s  %s\n", $1, $2
            }'
        fi
        ;;
    esac
    
    log_result "${profile:-}" "${region:-}" "cvm" "key-list" "$result" "$format"
}

# 创建 SSH 密钥对
cvm_key_create() {
    local key_name=$1
    
    if [ -z "$key_name" ]; then
        echo "错误：需要提供密钥对名称。" >&2
        echo "用法：$0 cvm key-create <密钥对名称>" >&2
        return 1
    fi
    
    echo "创建 SSH 密钥对：$key_name"
    
    local result
    result=$(call_tencent_api cvm CreateKeyPair --KeyName "$key_name")
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        # 保存私钥到文件
        local private_key
        private_key=$(echo "$result" | jq -r '.Response.PrivateKey // empty')
        if [ -n "$private_key" ]; then
            local key_file="${SCRIPT_DATA}/${profile:-default}/${region:-ap-guangzhou}/keys/${key_name}.pem"
            mkdir -p "$(dirname "$key_file")"
            echo "$private_key" > "$key_file"
            chmod 600 "$key_file"
            echo "私钥已保存到: $key_file"
        fi
        log_result "${profile:-}" "$region" "cvm" "key-create" "$result"
    else
        echo "错误：创建失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 删除 SSH 密钥对
cvm_key_delete() {
    local key_name=$1

    # 如果没有提供密钥对名称，则使用 fzf 选择
    if [ -z "$key_name" ]; then
        local key_list
        local result
        result=$(call_tencent_api cvm DescribeKeyPairs)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取密钥对列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        key_list=$(echo "$result" | jq -r '.Response.KeyPairSet[]? | "\(.KeyId) (\(.KeyName))"')

        if [ -z "$key_list" ]; then
            echo "错误：没有找到任何密钥对。" >&2
            return 1
        elif [ "$(echo "$key_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            key_name=$(echo "$key_list" | awk '{print $1}')
            echo "自动选择唯一的密钥对: $key_name"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                key_name=$(select_with_fzf "选择要删除的密钥对" "$key_list" | awk '{print $1}')
                if [ -z "$key_name" ]; then
                    echo "错误：未选择密钥对。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择密钥对，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    if [ -z "$key_name" ]; then
        echo "错误：需要提供密钥对名称。" >&2
        echo "用法：$0 cvm key-delete <密钥对名称>" >&2
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
    result=$(call_tencent_api cvm DeleteKeyPairs --KeyIds "[\"$key_name\"]")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "密钥对已删除。"
        log_result "${profile:-}" "$region" "cvm" "key-delete" "$result"
    else
        echo "错误：删除失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 导入 SSH 密钥对
cvm_key_import() {
    local key_name=$1
    local public_key=$2

    if [ -z "$key_name" ]; then
        echo "错误：需要提供密钥对名称。" >&2
        echo "用法：$0 cvm key-import <密钥对名称> <公钥内容|公钥文件路径>" >&2
        return 1
    fi

    # 如果第二个参数是文件路径且文件存在，则读取文件内容
    if [ -f "$public_key" ]; then
        public_key=$(cat "$public_key")
    fi

    if [ -z "$public_key" ]; then
        echo "错误：需要提供公钥内容或公钥文件路径。" >&2
        echo "用法：$0 cvm key-import <密钥对名称> <公钥内容|公钥文件路径>" >&2
        return 1
    fi

    # 验证公钥格式
    if ! echo "$public_key" | grep -qE '^ssh-(rsa|dss|ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) '; then
        # 如果不是标准SSH格式，尝试作为GitHub用户名处理
        if [[ "$public_key" == github:* ]]; then
            local github_username=${public_key#github:}
            echo "从 GitHub 获取公钥：https://github.com/${github_username}.keys"
            public_key=$(curl -s "https://github.com/${github_username}.keys")
            if [ -z "$public_key" ]; then
                echo "错误：无法从 GitHub 获取公钥。请检查用户名是否正确。" >&2
                return 1
            fi
        else
            echo "错误：公钥格式无效。必须是有效的SSH公钥格式（如ssh-rsa AAAAB3...）或 github:username 格式。" >&2
            return 1
        fi
    fi

    echo "导入 SSH 密钥对：$key_name"
    echo "公钥：$public_key"

    local result
    # 腾讯云CVM导入密钥对的正确API是 ImportKeyPair
    result=$(call_tencent_api cvm ImportKeyPair --KeyName "$key_name" --PublicKey "$public_key")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cvm" "key-import" "$result"
    else
        echo "错误：导入失败。" >&2
        echo "$result" >&2
        return 1
    fi
}
