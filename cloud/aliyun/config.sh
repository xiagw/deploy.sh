#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 配置管理相关函数（CRUD 与项目统一：get/add/set/del）
show_config_help() {
    echo "配置管理 (config) 操作："
    echo "  get                                     - 列出所有 profile"
    echo "  add <名称> <AccessKeyId> <AccessKeySecret> [RegionId]   - 创建 profile"
    echo "  set [名称] <AccessKeyId> <AccessKeySecret> [RegionId]   - 更新 profile（名称可选，fzf 选择）"
    echo "  del [名称]                              - 删除 profile（名称可选，fzf 选择）"
    echo "  help | h                                - 显示此帮助"
    echo ""
    echo "示例："
    echo "  $0 config get"
    echo "  $0 config add myprofile LTAI*** xxx cn-hangzhou"
    echo "  $0 config set myprofile LTAI*** xxx"
    echo "  $0 config del myprofile"
}

read_config() {
    local profile=${1:-default}
    local result
    result=$(aliyun configure get --profile "$profile" | jq -r '.region_id')
    if [ -z "$result" ]; then
        echo "错误：无法读取配置文件。请检查配置是否存在。" >&2
        return 1
    fi
    echo "$result"
}

list_profiles() {
    aliyun configure list
}

# 输出 profile 名称列表（每行一个），用于 fzf；从 aliyun configure list 解析
get_profile_names() {
    aliyun configure list 2>/dev/null | tail -n +3 | awk -F'|' '
        { gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/ \*$/, "", $1); if ($1 != "") print $1 }
    '
}

create_profile() {
    local name=$1
    local access_key_id=$2
    local access_key_secret=$3
    local region_id=${4:-cn-hangzhou}

    aliyun configure set \
        --profile "$name" \
        --mode AK \
        --region "$region_id" \
        --access-key-id "$access_key_id" \
        --access-key-secret "$access_key_secret"

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "配置文件已创建。"
    else
        echo "错误：创建配置文件失败。" >&2
        return 1
    fi
}

update_profile() {
    local name=$1
    local access_key_id=$2
    local access_key_secret=$3
    local region_id=${4:-cn-hangzhou}

    aliyun configure set \
        --profile "$name" \
        --mode AK \
        --region "$region_id" \
        --access-key-id "$access_key_id" \
        --access-key-secret "$access_key_secret"

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "配置文件已更新。"
    else
        echo "错误：更新配置文件失败。" >&2
        return 1
    fi
}

delete_profile() {
    local name=$1

    aliyun configure delete --profile "$name"

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "配置文件已删除。"
    else
        echo "错误：删除配置文件失败。" >&2
        return 1
    fi
}

handle_config_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get|list) list_profiles ;;
    help|h) show_config_help ;;
    add|create)
        if [ $# -lt 3 ]; then
            echo "错误：add 操作需要提供名称、AccessKeyId 和 AccessKeySecret。" >&2
            echo "用法：$0 config add <名称> <AccessKeyId> <AccessKeySecret> [RegionId]" >&2
            return 1
        fi
        create_profile "$1" "$2" "$3" "$4"
        ;;
    set|update)
        local name=$1
        shift
        local profile_list
        if [ -z "$name" ]; then
            profile_list=$(get_profile_names)
            if [ -z "$profile_list" ]; then
                echo "错误：没有可用的 profile，请先 config add 创建。" >&2
                return 1
            fi
            if type select_with_fzf >/dev/null 2>&1; then
                name=$(select_with_fzf "选择要更新的 profile" "$profile_list")
            else
                echo "错误：请提供 profile 名称，或安装 fzf 后使用交互选择。" >&2
                echo "用法：$0 config set <名称> <AccessKeyId> <AccessKeySecret> [RegionId]" >&2
                return 1
            fi
            [ -z "$name" ] && echo "错误：未选择 profile。" >&2 && return 1
        fi
        local access_key_id=$1 access_key_secret=$2 region_id=${3:-cn-hangzhou}
        if [ $# -lt 2 ]; then
            echo "请输入该 profile 的 AccessKey 与 Secret（或用法：$0 config set [名称] <AccessKeyId> <AccessKeySecret> [RegionId]）"
            [ -z "$access_key_id" ] && read -r -p "AccessKeyId: " access_key_id
            [ -z "$access_key_secret" ] && read -r -s -p "AccessKeySecret: " access_key_secret && echo
            region_id=${region_id:-cn-hangzhou}
        fi
        if [ -z "$access_key_id" ] || [ -z "$access_key_secret" ]; then
            echo "错误：AccessKeyId 和 AccessKeySecret 不能为空。" >&2
            return 1
        fi
        update_profile "$name" "$access_key_id" "$access_key_secret" "$region_id"
        ;;
    del|delete)
        local name=$1
        if [ -z "$name" ]; then
            local profile_list
            profile_list=$(get_profile_names)
            if [ -z "$profile_list" ]; then
                echo "错误：没有可用的 profile。" >&2
                return 1
            fi
            if [ "$(echo "$profile_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
                name=$(echo "$profile_list" | tr -d '\n')
                echo "自动选择唯一 profile: $name"
            elif type select_with_fzf >/dev/null 2>&1; then
                name=$(select_with_fzf "选择要删除的 profile" "$profile_list")
            else
                echo "错误：请提供 profile 名称，或安装 fzf 后使用交互选择。" >&2
                echo "用法：$0 config del <名称>" >&2
                return 1
            fi
        fi
        if [ -z "$name" ]; then
            echo "错误：未选择 profile。" >&2
            return 1
        fi
        delete_profile "$name"
        ;;
    *)
        echo "错误：未知的 config 操作：$operation" >&2
        echo "可用操作：get, add, set, del, help（或 h）" >&2
        return 1
        ;;
    esac
}
