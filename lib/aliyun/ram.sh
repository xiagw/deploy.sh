#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# RAM (Resource Access Management) 相关函数

show_ram_help() {
    echo "RAM (Resource Access Management) 操作："
    echo "  list                                    - 列出所有子账号"
    echo "  create <用户名> <显示名>                  - 创建子账号"
    echo "  update <用户名> <新显示名>                - 更新子账号"
    echo "  delete <用户名>                          - 删除子账号"
    echo "  create-key <用户名>                      - 为子账号创建 AccessKey"
    echo "  grant-permission <用户名>                - 授予子账号权限"
    echo "  list-permissions <用户名>                - 列出用户的权限"
    echo
    echo "示例："
    echo "  $0 ram list"
    echo "  $0 ram create                          # 自动生成 dev 开头的用户名"
    echo "  $0 ram create test-user                # 自动生成显示名称"
    echo "  $0 ram create test-user 'Test User'    # 指定用户名和显示名称"
    echo "  $0 ram update test-user 'New Test User'"
    echo "  $0 ram delete test-user"
    echo "  $0 ram create-key test-user"
    echo "  $0 ram grant-permission test-user"
    echo "  $0 ram list-permissions test-user"
}

handle_ram_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) ram_list "$@" ;;
    create)
        ram_create "$1" "$2"
        ;;
    update)
        if [ $# -lt 2 ]; then
            echo "错误：update 操作需要提供用户名和新显示名。" >&2
            show_ram_help
            return 1
        fi
        ram_update "$1" "$2"
        ;;
    delete)
        if [ $# -lt 1 ]; then
            echo "错误：delete 操作需要提供用户名。" >&2
            show_ram_help
            return 1
        fi
        ram_delete "$1"
        ;;
    create-key)
        if [ $# -lt 1 ]; then
            echo "错误：create-key 操作需要提供用户名。" >&2
            show_ram_help
            return 1
        fi
        ram_create_key "$1"
        ;;
    grant-permission)
        if [ $# -lt 1 ]; then
            echo "错误：grant-permission 操作需要提供用户名。" >&2
            show_ram_help
            return 1
        fi
        ram_grant_permission "$1"
        ;;
    list-permissions)
        if [ $# -lt 1 ]; then
            echo "错误：list-permissions 操作需要提供用户名。" >&2
            show_ram_help
            return 1
        fi
        ram_list_permissions "$1"
        ;;
    *)
        echo "错误：未知的 RAM 操作：$operation" >&2
        show_ram_help
        exit 1
        ;;
    esac
}

ram_list() {
    local format=${1:-human}
    local result
    result=$(aliyun ram ListUsers --profile "${profile:-}" --region "${region:-}")
    if [ $? -ne 0 ]; then
        echo "错误：无法获取子账号列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        echo -e "UserName\tDisplayName\tCreateDate"
        echo "$result" | jq -r '.Users.User[] | [.UserName, .DisplayName, .CreateDate] | @tsv'
        ;;
    human | *)
        echo "列出所有子账号："
        if [[ $(echo "$result" | jq '.Users.User | length') -eq 0 ]]; then
            echo "没有找到子账号。"
        else
            echo "用户名              显示名称                      创建时间"
            echo "----------------    ----------------------------  -------------------------"
            echo "$result" | jq -r '.Users.User[] | [.UserName, .DisplayName, .CreateDate] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    printf "%-18s  %-28s  %s\n", $1, $2, $3
                }'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "ram" "list" "$result" "$format"
}

ram_create() {
    local username=$1
    local display_name=$2

    # 如果未提供用户名和显示名称,则自动生成
    if [ -z "$username" ]; then
        username="dev$(printf "%04d" $((RANDOM % 10000)))"
    fi
    if [ -z "$display_name" ]; then
        display_name="${username}-$(date +%F)"
    fi

    # 首先检查用户是否已存在
    if aliyun ram GetUser --UserName "$username" --profile "${profile:-}" --region "${region:-}" 2>&1; then
        echo "错误：用户 $username 已存在。" >&2
        return 1
    fi

    echo "创建子账号："
    local result
    result=$(aliyun ram CreateUser --UserName "$username" --DisplayName "$display_name" --profile "${profile:-}" --region "${region:-}")
    if [ $? -eq 0 ]; then
        echo "子账号创建成功："
        echo "$result" | jq '.'
        ram_create_key "$username"
        ram_grant_permission "$username"
    else
        echo "错误：子账号创建失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "${region:-}" "ram" "create" "$result"
}

ram_update() {
    local username=$1
    local new_display_name=$2
    echo "更新子账号："
    local result
    result=$(aliyun ram UpdateUser --UserName "$username" --NewDisplayName "$new_display_name" --profile "${profile:-}" --region "${region:-}")
    echo "$result" | jq '.'
    log_result "${profile:-}" "${region:-}" "ram" "update" "$result"
}

ram_delete() {
    local username=$1
    if [ -z "$username" ]; then
        echo "错误：未提供用户名。" >&2
        return 1
    fi

    echo "警告：您即将删除子账号：$username"
    read -r -p "请入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    # 检查用户是否存在
    if ! aliyun ram GetUser --UserName "$username" --profile "${profile:-}" --region "${region:-}" 2>/dev/null; then
        echo "错误：用户 $username 不存在。" >&2
        return 1
    fi

    echo "删除子账号的 AccessKey："
    local list_keys_result
    list_keys_result=$(aliyun ram ListAccessKeys --UserName "$username" --profile "${profile:-}" --region "${region:-}")
    if [ $? -eq 0 ]; then
        local access_key_ids
        access_key_ids=$(echo "$list_keys_result" | jq -r '.AccessKeys.AccessKey[].AccessKeyId')
        for key_id in $access_key_ids; do
            echo "删除 AccessKey: $key_id"
            aliyun ram DeleteAccessKey --UserName "$username" --UserAccessKeyId "$key_id" --profile "${profile:-}" --region "${region:-}"
        done
    else
        echo "警告：无法获取 AccessKey 列表。"
    fi

    echo "清理用户权限："
    local list_policies_result
    list_policies_result=$(aliyun ram ListPoliciesForUser --UserName "$username" --profile "${profile:-}" --region "${region:-}")
    if [ $? -eq 0 ]; then
        echo "$list_policies_result" | jq -r '.Policies.Policy[] | [.PolicyName, .PolicyType] | @tsv' |
            while IFS=$'\t' read -r policy_name policy_type; do
                if [ -n "$policy_name" ] && [ -n "$policy_type" ]; then
                    echo "取消附加策略: $policy_name (类型: $policy_type)"
                    aliyun ram DetachPolicyFromUser --PolicyName "$policy_name" --PolicyType "$policy_type" --UserName "$username" --profile "${profile:-}" --region "${region:-}"
                else
                    echo "警告：策略名称或类型为空，跳过。"
                fi
            done
    else
        echo "警告：无法获取用户权限列表。"
    fi

    echo "删除子账号："
    local result
    result=$(aliyun ram DeleteUser --UserName "$username" --profile "${profile:-}" --region "${region:-}")
    local status=$?

    if [ $status -eq 0 ]; then
        echo "子账号删除成功。"
        log_delete_operation "${profile:-}" "${region:-}" "ram" "$username" "子账号" "成功"
    else
        echo "子账号删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "${region:-}" "ram" "$username" "子账号" "失败"
    fi

    log_result "${profile:-}" "${region:-}" "ram" "delete" "$result"
}

ram_create_key() {
    local username=$1 result
    echo "为子账号创建 AccessKey："
    result=$(aliyun ram CreateAccessKey --UserName "$username" --profile "${profile:-}" --region "${region:-}")
    if [ $? -eq 0 ]; then
        echo "AccessKey 创建成功："
        echo "$result" | jq '.'
        # 使用新的 save_data_file 函数保存 AccessKey 数据
        save_data_file "${profile:-}" "${region:-}" "ram" "accesskey" "$result" "${username}_accesskey.json"
    else
        echo "错误：AccessKey 创建失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "${region:-}" "ram" "create-key" "$result"
}

ram_grant_permission() {
    local username=$1
    echo "授予子账号权限："
    local policies=(
        AliyunDomainReadOnlyAccess
        AliyunDNSFullAccess
        AliyunYundunCertFullAccess
        AliyunCDNFullAccess
        AliyunOSSFullAccess
    )
    local all_results=""
    for policy_name in "${policies[@]}"; do
        local result
        result=$(aliyun ram AttachPolicyToUser --PolicyType System --PolicyName "$policy_name" --UserName "$username" --profile "${profile:-}" --region "${region:-}")
        if [ $? -eq 0 ]; then
            echo "$policy_name 权限授予成功。"
        else
            echo "错误：$policy_name 权限授予失败。"
            echo "$result"
        fi
        all_results+="$policy_name: $result"$'\n'
    done
    log_result "${profile:-}" "${region:-}" "ram" "grant-permission" "$all_results"
}

ram_list_permissions() {
    local username=$1
    if [ -z "$username" ]; then
        echo "错误：未提供用户名。用法：ram list-permissions <用户名>" >&2
        return 1
    fi

    echo "列出用户 $username 的权限："
    local result
    result=$(aliyun ram ListPoliciesForUser --UserName "$username" --profile "${profile:-}" --region "${region:-}")
    if [ $? -eq 0 ]; then
        if [ "$(echo "$result" | jq '.Policies.Policy | length')" -eq 0 ]; then
            echo "用户 $username 没有任何权限。"
        else
            echo "用户 $username 的权限列表："
            echo "$result" | jq -r '.Policies.Policy[] | [.PolicyName, .PolicyType, .DefaultVersion, .AttachDate] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"; print "策略名称\t策略类型\t默认版本\t附加日期"}
                {printf "%-40s %-10s %-10s %s\n", $1, $2, $3, $4}'
        fi
    else
        echo "错误：无法获取用户权限列表。"
        echo "$result"
    fi
    log_result "${profile:-}" "${region:-}" "ram" "list-permissions" "$result"
}
