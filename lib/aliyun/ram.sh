#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# RAM (Resource Access Management) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

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
    echo "  $0 ram update test-user 'New password'"
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
    create) ram_create "$1" "$2" ;;
    update) ram_update "$1" "$2" ;;
    delete) ram_delete "$1" ;;
    create-key) ram_create_key "$1" ;;
    grant-permission) ram_grant_permission "$1" ;;
    list-permissions) ram_list_permissions "$1" ;;
    help) show_ram_help ;;
    *)
        echo "错误：未知的 RAM 操作：$operation" >&2
        show_ram_help
        exit 1
        ;;
    esac
}

# 使用新框架的列表函数
ram_list() {
    local format=${1:-human}
    
    local table_header="UserName\tDisplayName\tCreateDate"
    local jq_filter=".Users.User[] | [.UserName, .DisplayName, .CreateDate] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-20s  %-20s  %s\n", $1, $2, $3}'
    
    local result
    result=$(call_aliyun_api ram ListUsers)
    
    if [ $? -ne 0 ]; then
        echo "错误：无法获取子账号列表。请检查您的凭证和权限。" >&2
        return 1
    fi
    
    format_output \
        "$result" \
        "$format" \
        "ram" \
        "list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到子账号。" \
        "列出所有子账号："
}

# 创建子账号（保持原有实现，但使用框架函数）
ram_create() {
    local username=$1
    local display_name=$2

    # 如果没有提供用户名，自动生成
    if [ -z "$username" ]; then
        username="dev-$(date +%Y%m%d-%H%M%S)"
        echo "未提供用户名，自动生成: $username"
    fi

    # 如果没有提供显示名，使用用户名
    if [ -z "$display_name" ]; then
        display_name="$username"
    fi

    # 生成随机密码
    local password
    password="$(_get_random_password 2>/dev/null)@@"

    echo "创建 RAM 子账号："
    echo "用户名: $username"
    echo "显示名: $display_name"
    echo "密码: $password"

    local result
    result=$(call_aliyun_api ram CreateUser \
        --UserName "$username" \
        --DisplayName "$display_name")

    if [ $? -eq 0 ]; then
        echo "子账号创建成功："
        echo "$result" | jq '.'
        
        # 创建登录配置
        call_aliyun_api ram CreateLoginProfile \
            --UserName "$username" \
            --Password "$password" \
            --PasswordResetRequired false >/dev/null 2>&1
        
        echo "登录密码: $password"
        log_result "${profile:-}" "$region" "ram" "create" "$result"
    else
        echo "错误：子账号创建失败。"
        echo "$result"
        return 1
    fi
}

# 更新子账号（保持原有实现，但使用框架函数）
ram_update() {
    local username=$1
    local new_display_name=$2

    if [ -z "$username" ]; then
        echo "错误：用户名不能为空。" >&2
        echo "用法：ram update <用户名> <新显示名>" >&2
        return 1
    fi

    if [ -z "$new_display_name" ]; then
        echo "错误：新显示名不能为空。" >&2
        return 1
    fi

    echo "更新 RAM 子账号："
    local result
    result=$(call_aliyun_api ram UpdateUser \
        --UserName "$username" \
        --NewDisplayName "$new_display_name")

    if [ $? -eq 0 ]; then
        echo "子账号更新成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ram" "update" "$result"
    else
        echo "错误：子账号更新失败。"
        echo "$result"
        return 1
    fi
}

# 删除子账号（使用框架函数）
ram_delete() {
    local username=$1

    if [ -z "$username" ]; then
        echo "错误：用户名不能为空。" >&2
        return 1
    fi

    if ! confirm_action "删除 RAM 子账号：$username"; then
        return 1
    fi

    echo "删除 RAM 子账号："
    local result
    result=$(call_aliyun_api ram DeleteUser --UserName "$username")

    if [ $? -eq 0 ]; then
        echo "子账号删除成功。"
        log_delete_operation "${profile:-}" "$region" "ram" "$username" "RAM子账号" "成功"
    else
        echo "错误：子账号删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "ram" "$username" "RAM子账号" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "ram" "delete" "$result"
}

# 创建 AccessKey（保持原有实现，但使用框架函数）
ram_create_key() {
    local username=$1

    if [ -z "$username" ]; then
        echo "错误：用户名不能为空。" >&2
        return 1
    fi

    echo "为子账号创建 AccessKey："
    local result
    result=$(call_aliyun_api ram CreateAccessKey --UserName "$username")

    if [ $? -eq 0 ]; then
        echo "AccessKey 创建成功："
        echo "$result" | jq '.'
        echo "请保存 AccessKeyId 和 AccessKeySecret，它们只会显示一次！"
        log_result "${profile:-}" "$region" "ram" "create-key" "$result"
    else
        echo "错误：AccessKey 创建失败。"
        echo "$result"
        return 1
    fi
}

# 授予权限（保持原有实现，但使用框架函数）
ram_grant_permission() {
    local username=$1

    if [ -z "$username" ]; then
        echo "错误：用户名不能为空。" >&2
        return 1
    fi

    echo "授予子账号权限："
    echo "用户名: $username"
    
    # 授予 AliyunECSFullAccess 权限
    local result
    result=$(call_aliyun_api ram AttachPolicyToUser \
        --PolicyType System \
        --PolicyName AliyunECSFullAccess \
        --UserName "$username")

    if [ $? -eq 0 ]; then
        echo "权限授予成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ram" "grant-permission" "$result"
    else
        echo "错误：权限授予失败。"
        echo "$result"
        return 1
    fi
}

# 列出权限（保持原有实现，但使用框架函数）
ram_list_permissions() {
    local username=$1

    if [ -z "$username" ]; then
        echo "错误：用户名不能为空。" >&2
        return 1
    fi

    echo "列出用户权限："
    echo "用户名: $username"
    
    local result
    result=$(call_aliyun_api ram ListPoliciesForUser --UserName "$username")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ram" "list-permissions" "$result"
    else
        echo "错误：无法获取用户权限列表。"
        echo "$result"
        return 1
    fi
}
