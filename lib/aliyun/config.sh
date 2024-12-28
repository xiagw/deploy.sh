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
    local operation=${1:-list}
    shift

    case "$operation" in
    list) list_profiles ;;
    create)
        if [ $# -lt 3 ]; then
            echo "错误：create 操作需要提供名称、AccessKeyId 和 AccessKeySecret。"
            echo "用法：$0 config create <名称> <AccessKeyId> <AccessKeySecret> [RegionId]"
            return 1
        fi
        create_profile "$1" "$2" "$3" "$4"
        ;;
    update)
        if [ $# -lt 3 ]; then
            echo "错误：update 操作需要提供名称、AccessKeyId 和 AccessKeySecret。"
            echo "用法：$0 config update <名称> <AccessKeyId> <AccessKeySecret> [RegionId]"
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
