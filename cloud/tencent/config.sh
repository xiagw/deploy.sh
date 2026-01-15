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
    result=$(tccli configure get region --profile "$profile" 2>/dev/null)
    if [ -z "$result" ]; then
        result=${TENCENT_DEFAULT_REGION:-ap-guangzhou}
    fi
    echo "$result"
}

list_profiles() {
    echo "腾讯云配置的 Profile 列表："
    echo "================================"
    # 腾讯云 CLI 的配置存储在 ~/.tccli/ 目录
    if [ -f "$HOME/.tccli/configure" ]; then
        # tccli 使用不同的配置格式，需要解析
        tccli configure list 2>/dev/null || {
            echo "无法列出配置，请使用 'tccli configure list' 查看"
        }
    else
        echo "未找到配置文件，请先运行 'tccli configure' 设置凭证。"
    fi
}

create_profile() {
    local name=$1
    local secret_id=$2
    local secret_key=$3
    local region_id=${4:-ap-guangzhou}

    # 腾讯云 CLI 使用不同的配置方式
    # 创建配置文件目录
    mkdir -p "$HOME/.tccli"
    
    # 写入配置到文件
    local config_file="$HOME/.tccli/configure"
    if [ ! -f "$config_file" ]; then
        touch "$config_file"
    fi
    
    # 添加配置段
    if ! grep -q "^\[$name\]" "$config_file" 2>/dev/null; then
        echo "[$name]" >> "$config_file"
        echo "secret_id = $secret_id" >> "$config_file"
        echo "secret_key = $secret_key" >> "$config_file"
        echo "region = $region_id" >> "$config_file"
        echo "配置文件已创建。"
    else
        echo "错误：Profile '$name' 已存在。" >&2
        return 1
    fi
}

update_profile() {
    local name=$1
    local secret_id=$2
    local secret_key=$3
    local region_id=${4:-ap-guangzhou}

    local config_file="$HOME/.tccli/configure"
    
    if [ ! -f "$config_file" ]; then
        echo "错误：配置文件不存在。" >&2
        return 1
    fi
    
    # 删除旧配置并添加新配置
    sed -i.bak "/^\[$name\]/,/^\[/ { /^\[$name\]/,/^\[/!d; }" "$config_file" 2>/dev/null
    echo "[$name]" >> "$config_file"
    echo "secret_id = $secret_id" >> "$config_file"
    echo "secret_key = $secret_key" >> "$config_file"
    echo "region = $region_id" >> "$config_file"
    
    echo "配置文件已更新。"
}

delete_profile() {
    local name=$1

    if [ "$name" = "default" ]; then
        echo "警告：不能删除 default profile。请手动编辑 ~/.tccli/configure 文件。" >&2
        return 1
    fi

    local config_file="$HOME/.tccli/configure"
    
    if [ ! -f "$config_file" ]; then
        echo "错误：配置文件不存在。" >&2
        return 1
    fi

    # 删除配置段
    sed -i.bak "/^\[$name\]/,/^\[/ { /^\[$name\]/,/^\[/!d; }" "$config_file" 2>/dev/null
    
    echo "配置文件已删除（请手动确认）。"
}

handle_config_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) list_profiles ;;
    create)
        if [ $# -lt 3 ]; then
            echo "错误：create 操作需要提供名称、SecretId 和 SecretKey。"
            echo "用法：$0 config create <名称> <SecretId> <SecretKey> [Region]"
            return 1
        fi
        create_profile "$1" "$2" "$3" "$4"
        ;;
    update)
        if [ $# -lt 3 ]; then
            echo "错误：update 操作需要提供名称、SecretId 和 SecretKey。"
            echo "用法：$0 config update <名称> <SecretId> <SecretKey> [Region]"
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
