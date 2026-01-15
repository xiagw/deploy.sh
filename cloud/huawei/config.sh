#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 配置管理相关函数
show_config_help() {
    if [ "${#@}" -eq 0 ]; then
        echo "错误：config 命令需要指定操作。"
        echo "用法：$0 config <list|create|update|delete> [参数...]"
    fi
}

read_config() {
    local profile=${1:-default}
    local result
    result=$(huaweicloud configure get region --profile "$profile" 2>/dev/null)
    if [ -z "$result" ]; then
        result=${HW_DEFAULT_REGION:-cn-north-1}
    fi
    echo "$result"
}

list_profiles() {
    echo "华为云配置的 Profile 列表："
    echo "================================"
    # 华为云 CLI 的配置存储在 ~/.huaweicloud/credentials 和 ~/.huaweicloud/config
    if [ -f "$HOME/.huaweicloud/config" ]; then
        grep -E "^\[profile |^\[default" "$HOME/.huaweicloud/config" 2>/dev/null | sed 's/\[profile //;s/\[//;s/\]//' | while read -r profile_name; do
            local region
            region=$(huaweicloud configure get region --profile "$profile_name" 2>/dev/null || echo "未设置")
            local access_key
            access_key=$(huaweicloud configure get access_key_id --profile "$profile_name" 2>/dev/null || echo "未设置")
            echo "Profile: $profile_name"
            echo "  Region: $region"
            echo "  Access Key: ${access_key:0:10}..."
            echo ""
        done
    fi
    # 检查 default profile
    if [ -f "$HOME/.huaweicloud/credentials" ]; then
        if grep -q "^\[default\]" "$HOME/.huaweicloud/credentials" 2>/dev/null; then
            local region
            region=$(huaweicloud configure get region 2>/dev/null || echo "未设置")
            local access_key
            access_key=$(huaweicloud configure get access_key_id 2>/dev/null || echo "未设置")
            echo "Profile: default"
            echo "  Region: $region"
            echo "  Access Key: ${access_key:0:10}..."
        fi
    fi
}

create_profile() {
    local name=$1
    local access_key_id=$2
    local access_key_secret=$3
    local region_id=${4:-cn-north-1}

    huaweicloud configure set access_key_id "$access_key_id" --profile "$name"
    huaweicloud configure set secret_access_key "$access_key_secret" --profile "$name"
    huaweicloud configure set region "$region_id" --profile "$name"

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
    local region_id=${4:-cn-north-1}

    huaweicloud configure set access_key_id "$access_key_id" --profile "$name"
    huaweicloud configure set secret_access_key "$access_key_secret" --profile "$name"
    huaweicloud configure set region "$region_id" --profile "$name"

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

    if [ "$name" = "default" ]; then
        echo "警告：不能删除 default profile。请手动编辑 ~/.huaweicloud/credentials 和 ~/.huaweicloud/config 文件。" >&2
        return 1
    fi

    # 从 credentials 文件删除
    if [ -f "$HOME/.huaweicloud/credentials" ]; then
        sed -i.bak "/^\[profile $name\]/,/^\[/ { /^\[profile $name\]/d; /^\[/!d; }" "$HOME/.huaweicloud/credentials" 2>/dev/null
    fi

    # 从 config 文件删除
    if [ -f "$HOME/.huaweicloud/config" ]; then
        sed -i.bak "/^\[profile $name\]/,/^\[/ { /^\[profile $name\]/d; /^\[/!d; }" "$HOME/.huaweicloud/config" 2>/dev/null
    fi

    echo "配置文件已删除（请手动确认）。"
}

handle_config_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) list_profiles ;;
    create)
        if [ $# -lt 3 ]; then
            echo "错误：create 操作需要提供名称、AccessKeyId 和 AccessKeySecret。"
            echo "用法：$0 config create <名称> <AccessKeyId> <AccessKeySecret> [Region]"
            return 1
        fi
        create_profile "$1" "$2" "$3" "$4"
        ;;
    update)
        if [ $# -lt 3 ]; then
            echo "错误：update 操作需要提供名称、AccessKeyId 和 AccessKeySecret。"
            echo "用法：$0 config update <名称> <AccessKeyId> <AccessKeySecret> [Region]"
            return 1
        fi
        update_profile "$1" "$2" "$3" "$4"
        ;;
    delete)
        if [ $# -lt 1 ]; then
            echo "错误：delete 操作需要提供配置文件名称。"
            echo "用法：$0 config delete <名称>"
            return 1
        fi
        delete_profile "$1"
        ;;
    *)
        echo "错误：未知的 config 操作：$operation"
        echo "可用操作：list, create, update, delete"
        return 1
        ;;
    esac
}
