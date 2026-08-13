#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# RAM (Resource Access Management) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

# 生成 RAM 登录用随机密码（含大小写+数字，末尾加 @@ 满足策略）
# 优先使用 common.sh 的 _get_random_password，否则用 openssl 等本地生成
_ram_random_password() {
    local p
    if declare -f _get_random_password >/dev/null 2>&1; then
        p=$(_get_random_password 14 2>/dev/null)
    fi
    if [ -z "$p" ] || [ "${#p}" -lt 8 ]; then
        p=$(openssl rand -base64 16 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 14)
    fi
    if [ -z "$p" ] || [ "${#p}" -lt 8 ]; then
        p=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 14)
    fi
    [ -n "$p" ] && echo "${p}@@" || echo ""
}

show_ram_help() {
    echo "RAM (Resource Access Management) 操作："
    echo "  get                                     - 列出所有子账号"
    echo "  add [<用户名>] [<显示名>]                - 创建子账号（用户名和显示名都是可选的，可使用 fzf 选择）"
    echo "  set [<用户名>] [<新显示名>] [--password <新密码>]  - 更新子账号（用户名、新显示名和密码都是可选的，可使用 fzf 选择）"
    echo "  del [<用户名>]                          - 删除子账号（用户名可选，可使用 fzf 选择）"
    echo "  add-key <用户名>                        - 为子账号创建 AccessKey"
    echo "  get-key <用户名>                        - 列出子账号的 AccessKey"
    echo "  del-key <用户名>                        - 删除子账号的 AccessKey（fzf 多选）"
    echo "  add-perm <用户名>                       - 授予子账号权限"
    echo "  get-perm <用户名>                       - 列出用户的权限"
    echo "  del-perm <用户名>                       - 撤销子账号权限（fzf 多选）"
    echo
    echo "示例："
    echo "  $0 ram get"
    echo "  $0 ram add                           # 自动生成 dev 开头的用户名"
    echo "  $0 ram add test-user                 # 自动生成显示名称"
    echo "  $0 ram add test-user 'Test User'     # 指定用户名和显示名称"
    echo "  $0 ram set test-user 'New Name'      # 只修改显示名"
    echo "  $0 ram set test-user --password 'NewPass123' # 只修改密码"
    echo "  $0 ram set test-user 'New Name' --password 'NewPass123' # 同时修改显示名和密码"
    echo "  （交互式 set 时若选择修改密码，将自动生成随机密码，无需手动输入）"
    echo "  $0 ram del test-user"
    echo "  $0 ram add-key test-user"
    echo "  $0 ram get-key test-user"
    echo "  $0 ram del-key test-user"
    echo "  $0 ram add-perm test-user"
    echo "  $0 ram get-perm test-user"
    echo "  $0 ram del-perm test-user"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_ram_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) ram_list "$@" ;;
    add) ram_create "$1" "$2" ;;
    set) ram_update "$@" ;;
    del) ram_delete "$1" ;;
    add-key) ram_create_key "$1" ;;
    get-key) ram_list_keys "$1" ;;
    del-key) ram_delete_key "$1" ;;
    add-perm) ram_grant_permission "$1" ;;
    get-perm) ram_list_permissions "$1" ;;
    del-perm) ram_revoke_permission "$1" ;;
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
    result=$(call_aliyun_api ram list-users --region "${region:-cn-hangzhou}" 2>/dev/null)
    local ret=$?
    if [ $ret -ne 0 ]; then
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

# 创建子账号（保持原有实现，但使用框架函数，支持交互式输入）
ram_create() {
    local username=$1
    local display_name=$2

    # 如果没有提供参数，则使用交互式输入
    if [ -z "$username" ] || [ -z "$display_name" ]; then
        echo "使用交互式模式创建 RAM 子账号"

        # 输入用户名
        if [ -z "$username" ]; then
            read -r -p "请输入用户名 (回车生成 dev开头的用户名): " username_input
            if [ -z "$username_input" ]; then
                username="dev$(date +%Y%m%d%H%M%S)"
                echo "自动生成用户名：$username"
            else
                username="$username_input"
            fi
        fi

        # 输入显示名
        if [ -z "$display_name" ]; then
            read -r -p "请输入显示名称 (回车使用用户名): " display_name_input
            display_name=${display_name_input:-$username}
            if [ -z "$display_name" ]; then
                echo "错误：显示名称不能为空。" >&2
                return 1
            fi
        fi
    fi

    # 生成随机密码
    local password
    password=$(_ram_random_password)
    if [ -z "$password" ]; then
        echo "错误：无法生成随机密码。" >&2
        return 1
    fi

    echo "创建 RAM 子账号："
    echo "用户名：$username"
    echo "显示名：$display_name"
    echo "密码：$password"

    local result
    result=$(call_aliyun_api ram create-user --user-name "$username" --display-name "$display_name" --region "${region:-cn-hangzhou}")
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：子账号创建失败。"
        echo "$result"
        return 1
    fi

    echo "子账号创建成功："
    echo "$result" | jq '.'

    # 创建登录配置（失败不能吞：否则会打印一个登录不了的密码）
    local login_result
    login_result=$(call_aliyun_api ram create-login-profile --user-name "$username" --password "$password" --password-reset-required false --region "${region:-cn-hangzhou}" 2>&1)
    local login_ret=$?
    if [ $login_ret -ne 0 ]; then
        echo "警告：子账号已创建，但登录密码设置失败，请手动重设密码。" >&2
        echo "$login_result" >&2
        log_result "${profile:-}" "$region" "ram" "create" "$result"
        return 1
    fi

    local account_alias
    account_alias=$(call_aliyun_api ram get-account-alias 2>/dev/null | jq -r '.AccountAlias // empty')
    if [ -z "$account_alias" ]; then
        account_alias=$(call_aliyun_api sts get-caller-identity 2>/dev/null | jq -r '.AccountId // empty')
    fi
    [ -n "$account_alias" ] && echo "登录用户名：${username}@${account_alias}.onaliyun.com"
    echo "登录密码：$password"
    log_result "${profile:-}" "$region" "ram" "create" "$result"
}

# 更新子账号（支持修改显示名和密码）
ram_update() {
    local username=$1
    shift
    local new_display_name=""
    local new_password=""

    # 解析参数：支持 --password 选项指定密码
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --password)
            new_password="$2"
            shift 2
            ;;
        *)
            if [ -z "$new_display_name" ]; then
                new_display_name="$1"
            fi
            shift
            ;;
        esac
    done

    # 如果没有提供用户名，则使用 fzf 选择
    if [ -z "$username" ]; then
        local raw
        raw=$(_ram_resolve_user "" "选择要更新的子账号") || return 1
        username=$(echo "$raw" | awk '{print $1}')
    fi

    # 交互式输入
    if [ -z "$new_display_name" ] && [ -z "$new_password" ]; then
        echo "交互式模式更新 RAM 子账号：$username"
        echo ""

        # 使用 fzf 选择操作类型（修改密码一律使用随机密码，避免手动输入两次不一致）
        local options=$'只修改显示名\n只修改密码（随机生成）\n同时修改显示名和密码（密码随机生成）'
        local choice
        if type select_with_fzf >/dev/null 2>&1; then
            choice=$(select_with_fzf "选择操作类型" "$options")
        else
            echo "错误：需要选择操作类型，但未找到交互式选择工具。" >&2
            return 1
        fi

        if [ -z "$choice" ]; then
            echo "错误：未选择操作类型。" >&2
            return 1
        fi

        case "$choice" in
        "只修改显示名")
            read -r -p "请输入新的显示名称： " new_display_name
            if [ -z "$new_display_name" ]; then
                echo "错误：显示名称不能为空。" >&2
                return 1
            fi
            ;;
        "只修改密码（随机生成）")
            new_password=$(_ram_random_password)
            if [ -z "$new_password" ]; then
                echo "错误：无法生成随机密码。" >&2
                return 1
            fi
            echo "自动生成密码：$new_password"
            ;;
        "同时修改显示名和密码（密码随机生成）")
            read -r -p "请输入新的显示名称： " new_display_name
            if [ -z "$new_display_name" ]; then
                echo "错误：显示名称不能为空。" >&2
                return 1
            fi
            new_password=$(_ram_random_password)
            if [ -z "$new_password" ]; then
                echo "错误：无法生成随机密码。" >&2
                return 1
            fi
            echo "自动生成密码：$new_password"
            ;;
        esac
    fi

    # 如果什么都没有提供，至少需要修改一项
    if [ -z "$new_display_name" ] && [ -z "$new_password" ]; then
        echo "错误：至少需要提供显示名或密码其中之一。" >&2
        echo "用法：ram set <用户名> [<新显示名>] [--password <新密码>]" >&2
        return 1
    fi

    echo "更新 RAM 子账号："
    echo "用户名：$username"

    local updated_display_name="$new_display_name"

    # 更新显示名（需要同时指定 NewUserName）
    if [ -n "$new_display_name" ]; then
        echo "新显示名：$new_display_name"
        local result
        result=$(call_aliyun_api ram update-user \
            --user-name "$username" \
            --new-user-name "$username" \
            --new-display-name "$new_display_name")
        local ret=$?
        if [ $ret -ne 0 ]; then
            echo "错误：子账号更新失败。"
            echo "$result"
            return 1
        fi
        echo "显示名更新成功"
    fi

    # 更新密码
    if [ -n "$new_password" ]; then
        echo "新密码：$new_password"
        local result
        result=$(call_aliyun_api ram update-login-profile \
            --user-name "$username" \
            --password "$new_password" \
            --password-reset-required false)
        local ret=$?
        if [ $ret -ne 0 ]; then
            echo "错误：密码更新失败。"
            echo "$result"
            return 1
        fi
        echo "密码更新成功"
    fi

    log_result "${profile:-}" "$region" "ram" "update" "{\"UserName\":\"$username\",\"DisplayName\":\"$updated_display_name\"}"
}

# 删除子账号（使用框架函数）
ram_delete() {
    local username=$1

    # 如果没有提供用户名，则使用 fzf 选择
    if [ -z "$username" ]; then
        local raw
        raw=$(_ram_resolve_user "" "选择要删除的子账号") || return 1
        username=$(echo "$raw" | awk '{print $1}')
    fi

    # 检查用户名是否为空
    if [ -z "$username" ]; then
        echo "错误：用户名不能为空。" >&2
        return 1
    fi

    if ! confirm_action "删除 RAM 子账号：$username"; then
        return 1
    fi

    echo "删除 RAM 子账号："
    local result
    result=$(call_aliyun_api ram delete-user --user-name "$username" 2>&1)
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "子账号删除成功。"
        log_delete_operation "${profile:-}" "$region" "ram" "$username" "RAM 子账号" "成功" "$result"
    else
        echo "错误：子账号删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "ram" "$username" "RAM 子账号" "失败" "$result"
        return 1
    fi
}

# 创建 AccessKey（保持原有实现，但使用框架函数并添加 fzf 选择）
ram_create_key() {
    local username=$1

    # 如果没有提供用户名，则使用 fzf 选择
    if [ -z "$username" ]; then
        local raw
        raw=$(_ram_resolve_user "" "选择要为其创建 AccessKey 的子账号") || return 1
        username=$(echo "$raw" | awk '{print $1}')
    fi

    if [ -z "$username" ]; then
        echo "错误：用户名不能为空。" >&2
        return 1
    fi

    echo "为子账号创建 AccessKey："
    local result
    result=$(call_aliyun_api ram create-access-key --user-name "$username" --region "${region:-cn-hangzhou}")
    local ret=$?
    if [ $ret -eq 0 ]; then
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

# 交互式解析 RAM 子账号（resolve_resource_id 封装，结果含全行供 awk 提取用户名）
_ram_resolve_user() {
    resolve_resource_id "$1" "${2:-选择子账号}" "错误：没有找到子账号。" \
        '.Users.User[] | "\(.UserName) (\(.DisplayName)) [\(.CreateDate)]"' \
        -- ram list-users --region "${region:-cn-hangzhou}"
}

# 选择子账号（无参数时用 fzf），结果输出到 stdout（保持向后兼容）
_ram_select_user() {
    local raw
    raw=$(_ram_resolve_user "" "${1:-选择子账号}") || return 1
    echo "$raw" | awk '{print $1}'
}

# 列出子账号的 AccessKey
ram_list_keys() {
    local username=$1

    if [ -z "$username" ]; then
        username=$(_ram_select_user "选择要查看 AccessKey 的子账号") || return 1
        if [ -z "$username" ]; then
            echo "错误：未选择子账号。" >&2
            return 1
        fi
    fi

    echo "列出子账号 AccessKey："
    echo "用户名：$username"

    local result
    result=$(call_aliyun_api ram list-access-keys --user-name "$username" --region "${region:-cn-hangzhou}")
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ram" "list-keys" "$result"
    else
        echo "错误：无法获取 AccessKey 列表。"
        echo "$result"
        return 1
    fi
}

# 删除子账号的 AccessKey（fzf 多选）
ram_delete_key() {
    local username=$1

    if [ -z "$username" ]; then
        username=$(_ram_select_user "选择要删除 AccessKey 的子账号") || return 1
        if [ -z "$username" ]; then
            echo "错误：未选择子账号。" >&2
            return 1
        fi
    fi

    echo "删除子账号 AccessKey："
    echo "用户名：$username"

    local result
    result=$(call_aliyun_api ram list-access-keys --user-name "$username" --region "${region:-cn-hangzhou}")
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：无法获取 AccessKey 列表。" >&2
        echo "$result"
        return 1
    fi

    local key_list
    key_list=$(echo "$result" | jq -r '.AccessKeys.AccessKey[] | "\(.AccessKeyId) \(.Status) [\(.CreateDate)]"')
    if [ -z "$key_list" ]; then
        echo "该用户没有 AccessKey。"
        return 0
    fi

    local selected_keys=()
    if command -v fzf >/dev/null 2>&1; then
        local choices
        choices=$(echo "$key_list" | fzf -m --prompt "选择要删除的 AccessKey (多选，Tab/Enter 确认): ")
        if [ -z "$choices" ]; then
            echo "未选择任何 AccessKey，取消操作。"
            return 1
        fi
        mapfile -t selected_keys <<<"$choices"
    else
        echo "错误：删除 AccessKey 需要 fzf 进行多选，请先安装 fzf。" >&2
        return 1
    fi

    if ! confirm_action "删除用户 $username 的 ${#selected_keys[@]} 个 AccessKey"; then
        return 1
    fi

    local line key_id
    local all_results=""
    local has_error=0

    for line in "${selected_keys[@]}"; do
        key_id=$(echo "$line" | awk '{print $1}')

        result=$(call_aliyun_api ram delete-access-key --region "${region:-cn-hangzhou}" \
            --user-access-key-id "$key_id" \
            --user-name "$username")
        local ret=$?
        if [ $ret -eq 0 ]; then
            echo "AccessKey 删除成功：$key_id"
        else
            echo "错误：AccessKey 删除失败：$key_id"
            echo "$result"
            has_error=1
        fi

        all_results+="${key_id}: ${result}"$'\n'
    done

    log_result "${profile:-}" "$region" "ram" "delete-key" "$all_results"

    if [ "$has_error" -ne 0 ]; then
        return 1
    fi
}

# 授予权限（保持原有实现，但使用框架函数并添加 fzf 选择）
ram_grant_permission() {
    local username=$1

    # 如果没有提供用户名，则使用 fzf 选择
    if [ -z "$username" ]; then
        local raw
        raw=$(_ram_resolve_user "" "选择要授予权限的子账号") || return 1
        username=$(echo "$raw" | awk '{print $1}')
    fi

    if [ -z "$username" ]; then
        echo "错误：用户名不能为空。" >&2
        return 1
    fi

    echo "授予子账号权限："
    echo "用户名：$username"

    # 说明：AttachPolicyToUser 每次只能授权一个策略。优先使用 fzf -m 支持多选。
    local policies=(
        AliyunYundunCertFullAccess
        AliyunRAMFullAccess
        AliyunEIPFullAccess
        AliyunALBFullAccess
        AliyunNLBFullAccess
        AliyunSLBFullAccess
        AliyunVPCFullAccess
        AliyunDTSFullAccess
        AliyunKvstoreFullAccess
        AliyunPolardbFullAccess
        AliyunRDSFullAccess
        AliyunNASFullAccess
        AliyunECSFullAccess
        AliyunCDNFullAccess
        AliyunDNSFullAccess
        AliyunOSSFullAccess
    )
    local result
    local policy_name
    local all_results=""
    local has_error=0
    local selected_policies=()

    if command -v fzf >/dev/null 2>&1; then
        local choices
        choices=$(printf "%s\n" "${policies[@]}" | fzf -m --prompt "选择要授予的权限 (多选，Tab/Enter 确认): ")
        if [ -z "$choices" ]; then
            echo "未选择任何策略，取消操作。"
            return 1
        fi
        mapfile -t selected_policies <<<"$choices"
    else
        # 未安装 fzf 时回退为全部授予（保持原有行为）
        selected_policies=("${policies[@]}")
    fi

    for policy_name in "${selected_policies[@]}"; do
        result=$(call_aliyun_api ram attach-policy-to-user --region "${region:-cn-hangzhou}" \
            --policy-type System \
            --policy-name "$policy_name" \
            --user-name "$username")
        local ret=$?
        if [ $ret -eq 0 ]; then
            echo "权限授予成功：$policy_name"
            echo "$result" | jq '.'
        else
            echo "错误：权限授予失败：$policy_name"
            echo "$result"
            has_error=1
        fi

        all_results+="${policy_name}: ${result}"$'\n'
    done

    log_result "${profile:-}" "$region" "ram" "grant-permission" "$all_results"

    if [ "$has_error" -ne 0 ]; then
        return 1
    fi
}

# 撤销权限（列出用户已有权限，fzf 多选后逐个撤销）
ram_revoke_permission() {
    local username=$1

    # 如果没有提供用户名，则使用 fzf 选择
    if [ -z "$username" ]; then
        local raw
        raw=$(_ram_resolve_user "" "选择要撤销权限的子账号") || return 1
        username=$(echo "$raw" | awk '{print $1}')
    fi

    if [ -z "$username" ]; then
        echo "错误：用户名不能为空。" >&2
        return 1
    fi

    echo "撤销子账号权限："
    echo "用户名：$username"

    local result
    result=$(call_aliyun_api ram list-policies-for-user --user-name "$username" --region "${region:-cn-hangzhou}")
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：无法获取用户权限列表。" >&2
        echo "$result"
        return 1
    fi

    # 每行格式：<PolicyName> <PolicyType> <范围>，范围为 account 或资源组 ID
    local policy_list
    policy_list=$(echo "$result" | jq -r '.Policies.Policy[] | "\(.PolicyName) \(.PolicyType) account"')

    # 资源组级授权（ResourceManager）
    local account_alias rg_result principal_name=""
    account_alias=$(call_aliyun_api ram get-account-alias 2>/dev/null | jq -r '.AccountAlias // empty')
    if [ -n "$account_alias" ]; then
        principal_name="${username}@${account_alias}.onaliyun.com"
        rg_result=$(call_aliyun_api resourcemanager list-policy-attachments \
            --principal-type IMSUser \
            --principal-name "$principal_name" 2>/dev/null)
        local rg_list
        rg_list=$(echo "$rg_result" | jq -r '.PolicyAttachments.PolicyAttachment[]? | "\(.PolicyName) \(.PolicyType) \(.ResourceGroupId)"')
        if [ -n "$rg_list" ]; then
            if [ -n "$policy_list" ]; then
                policy_list="${policy_list}"$'\n'"${rg_list}"
            else
                policy_list="$rg_list"
            fi
        fi
    fi

    if [ -z "$policy_list" ]; then
        echo "该用户没有已授予的权限。"
        return 0
    fi

    local selected_policies=()
    if command -v fzf >/dev/null 2>&1; then
        local choices
        choices=$(echo "$policy_list" | fzf -m --prompt "选择要撤销的权限 (多选，Tab/Enter 确认): ")
        if [ -z "$choices" ]; then
            echo "未选择任何策略，取消操作。"
            return 1
        fi
        mapfile -t selected_policies <<<"$choices"
    else
        echo "错误：撤销权限需要 fzf 进行多选，请先安装 fzf。" >&2
        return 1
    fi

    local line policy_name policy_type policy_scope
    local all_results=""
    local has_error=0

    for line in "${selected_policies[@]}"; do
        policy_name=$(echo "$line" | awk '{print $1}')
        policy_type=$(echo "$line" | awk '{print $2}')
        policy_scope=$(echo "$line" | awk '{print $3}')

        if [ "$policy_scope" = "account" ]; then
            result=$(call_aliyun_api ram detach-policy-from-user --region "${region:-cn-hangzhou}" \
                --policy-type "${policy_type:-System}" \
                --policy-name "$policy_name" \
                --user-name "$username")
        else
            result=$(call_aliyun_api resourcemanager detach-policy \
                --policy-type "${policy_type:-System}" \
                --policy-name "$policy_name" \
                --principal-type IMSUser \
                --principal-name "$principal_name" \
                --resource-group-id "$policy_scope")
        fi
        local ret=$?

        if [ $ret -eq 0 ]; then
            echo "权限撤销成功：$policy_name ($policy_scope)"
        else
            echo "错误：权限撤销失败：$policy_name ($policy_scope)"
            echo "$result"
            has_error=1
        fi

        all_results+="${policy_name} [${policy_scope}]: ${result}"$'\n'
    done

    log_result "${profile:-}" "$region" "ram" "revoke-permission" "$all_results"

    if [ "$has_error" -ne 0 ]; then
        return 1
    fi
}

# 列出权限（保持原有实现，但使用框架函数并添加 fzf 选择）
ram_list_permissions() {
    local username=$1

    # 如果没有提供用户名，则使用 fzf 选择
    if [ -z "$username" ]; then
        local raw
        raw=$(_ram_resolve_user "" "选择要查看权限的子账号") || return 1
        username=$(echo "$raw" | awk '{print $1}')
    fi

    if [ -z "$username" ]; then
        echo "错误：用户名不能为空。" >&2
        return 1
    fi

    echo "列出用户权限："
    echo "用户名：$username"

    local result
    result=$(call_aliyun_api ram list-policies-for-user --user-name "$username" --region "${region:-cn-hangzhou}")
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：无法获取用户权限列表。"
        echo "$result"
        return 1
    fi

    echo "账号级直接授权："
    echo "$result" | jq '.'

    # 资源组级授权不会出现在 ListPoliciesForUser 中，需通过 ResourceManager 查询
    local account_alias rg_result
    account_alias=$(call_aliyun_api ram get-account-alias 2>/dev/null | jq -r '.AccountAlias // empty')
    if [ -n "$account_alias" ]; then
        rg_result=$(call_aliyun_api resourcemanager list-policy-attachments \
            --principal-type IMSUser \
            --principal-name "${username}@${account_alias}.onaliyun.com" 2>/dev/null)
        if [ -n "$rg_result" ] && [ "$(echo "$rg_result" | jq '.PolicyAttachments.PolicyAttachment | length' 2>/dev/null)" -gt 0 ]; then
            echo "资源组级授权："
            echo "$rg_result" | jq '.PolicyAttachments.PolicyAttachment'
        fi
    fi

    log_result "${profile:-}" "$region" "ram" "list-permissions" "$result"
}

