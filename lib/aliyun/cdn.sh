#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# CDN (内容分发网络) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_cdn_help() {
    echo "CDN (内容分发网络) 操作："
    echo "  list [format]                           - 列出 CDN 域名"
    echo "  create <域名> <源站> <源站类型>         - 添加 CDN 加速域名"
    echo "  delete <域名>                           - 删除 CDN 加速域名"
    echo "  update <域名> <源站> <源站类型>         - 修改 CDN 域名配置"
    echo "  refresh <类型> <路径>                   - 刷新 CDN 目录或文件"
    echo "  prefetch <路径>                         - 预热 CDN 文件"
    echo "  pay [show_message]                      - 购买 CDN 资源包（自动判断余量）"
    echo
    echo "示例："
    echo "  $0 cdn list                                                  # 列出所有域名"
    echo "  $0 cdn list json                                            # 以 JSON 格式列出域名"
    echo "  $0 cdn create example.com example.oss-cn-hangzhou.aliyuncs.com oss  # 添加域名加速"
    echo "  $0 cdn delete example.com                                   # 删除加速域名"
    echo "  $0 cdn update example.com new-origin.com ip                 # 更新域名配置"
    echo "  $0 cdn refresh directory https://example.com/dir           # 刷新目录"
    echo "  $0 cdn refresh file https://example.com/path/to/file.jpg   # 刷新文件"
    echo "  $0 cdn prefetch https://example.com/path/to/file.jpg       # 预热文件"
    echo "  $0 cdn pay                                                  # 静默购买资源包"
    echo "  $0 cdn pay true                                            # 显示购买信息"
}

handle_cdn_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) cdn_list "$@" ;;
    create) cdn_create "$@" ;;
    delete) cdn_delete "$@" ;;
    update) cdn_update "$@" ;;
    refresh) cdn_refresh "$@" ;;
    prefetch) cdn_prefetch "$@" ;;
    pay) cdn_pay "$@" ;;
    help) show_cdn_help ;;
    *)
        echo "错误：未知的 CDN 操作：$operation" >&2
        show_cdn_help
        exit 1
        ;;
    esac
}

# 使用新框架的列表函数
cdn_list() {
    local format=${1:-human}
    
    local table_header="DomainName\tCname\tDomainStatus\tGmtCreated"
    local jq_filter=".Domains.PageData[] | [.DomainName, .Cname, .DomainStatus, .GmtCreated] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-20s  %-38s  %-6s  %s\n", $1, $2, $3, $4}'
    
    local result
    result=$(call_aliyun_api cdn DescribeUserDomains)
    
    if [ $? -ne 0 ]; then
        echo "错误：无法获取 CDN 域名列表。请检查您的凭证和权限。" >&2
        return 1
    fi
    
    format_output \
        "$result" \
        "$format" \
        "cdn" \
        "list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 CDN 域名。" \
        "列出 CDN 域名："
}

# 使用新框架的创建函数
cdn_create() {
    local domain_name=$1 sources=$2 source_type=$3
    
    if ! validate_required_params "$domain_name" "$sources" "$source_type" "错误：域名、源站和源站类型不能为空。"; then
        echo "用法：cdn create <域名> <源站> <源站类型>" >&2
        return 1
    fi
    
    echo "添加 CDN 加速域名："
    local result
    result=$(call_aliyun_api cdn AddCdnDomain \
        --DomainName "$domain_name" \
        --Sources "[{\"content\":\"$sources\",\"type\":\"$source_type\",\"priority\":\"20\",\"port\":80,\"weight\":\"15\"}]" \
        --CdnType web \
        --Scope domestic)
    
    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "create" "$result"
    else
        echo "错误：CDN 域名创建失败。"
        echo "$result"
        return 1
    fi
}

# 使用新框架的删除函数
cdn_delete() {
    local domain_name=$1
    
    if [ -z "$domain_name" ]; then
        echo "错误：域名不能为空。" >&2
        return 1
    fi
    
    if ! confirm_action "删除 CDN 加速域名：$domain_name"; then
        return 1
    fi
    
    echo "删除 CDN 加速域名："
    local result
    result=$(call_aliyun_api cdn DeleteCdnDomain --DomainName "$domain_name")
    
    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_delete_operation "${profile:-}" "$region" "cdn" "$domain_name" "CDN域名" "成功"
    else
        echo "错误：CDN 域名删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "cdn" "$domain_name" "CDN域名" "失败"
        return 1
    fi
    
    log_result "${profile:-}" "$region" "cdn" "delete" "$result"
}

# 使用新框架的更新函数
cdn_update() {
    local domain_name=$1 sources=$2 source_type=$3
    
    if ! validate_required_params "$domain_name" "$sources" "$source_type" "错误：域名、源站和源站类型不能为空。"; then
        echo "用法：cdn update <域名> <源站> <源站类型>" >&2
        return 1
    fi
    
    echo "修改 CDN 域名配置："
    local result
    result=$(call_aliyun_api cdn ModifyCdnDomain \
        --DomainName "$domain_name" \
        --Sources "[{\"content\":\"$sources\",\"type\":\"$source_type\",\"priority\":\"20\",\"port\":80,\"weight\":\"15\"}]")
    
    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "update" "$result"
    else
        echo "错误：CDN 域名更新失败。"
        echo "$result"
        return 1
    fi
}

# 刷新功能（保持原有实现，但使用框架函数）
cdn_refresh() {
    local type=$1
    local path=$2

    if ! validate_required_params "$type" "$path" "错误：刷新操作需要指定类型（directory 或 file）和路径。"; then
        return 1
    fi

    local object_type
    case "$type" in
    directory) object_type="Directory" ;;
    file) object_type="File" ;;
    *)
        echo "错误：无效的刷新类型。请使用 'directory' 或 'file'。" >&2
        return 1
        ;;
    esac

    echo "刷新 CDN $type ："
    local result
    result=$(call_aliyun_api cdn RefreshObjectCaches \
        --region "$region" \
        --Force true \
        --ObjectPath "$path" \
        --ObjectType "$object_type")

    if [ $? -eq 0 ]; then
        echo "CDN $type 刷新请求已提交："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "refresh" "$result"
    else
        echo "错误：CDN $type 刷新请求失败。"
        echo "$result"
        return 1
    fi
}

# 预热功能（保持原有实现，但使用框架函数）
cdn_prefetch() {
    local path=$1

    if [ -z "$path" ]; then
        echo "错误：预热操作需要指定路径。" >&2
        return 1
    fi

    echo "预热 CDN 文件："
    local result
    result=$(call_aliyun_api cdn PushObjectCache \
        --region "$region" \
        --ObjectPath "$path")

    if [ $? -eq 0 ]; then
        echo "CDN 文件预热请求已提交："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "prefetch" "$result"
    else
        echo "错误：CDN 文件预热请求失败。"
        echo "$result"
        return 1
    fi
}

# 购买资源包功能（保持原有实现，但使用框架函数）
cdn_pay() {
    local show_message=${1:-false}
    local balance_threshold=700     # 账户余额阈值 700 元

    # 查询账户可用余额
    local balance_result
    balance_result=$(call_aliyun_api bssopenapi QueryAccountBalance 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo "错误：无法查询账户余额。" >&2
        return 1
    fi
    
    local available_balance
    available_balance=$(echo "$balance_result" | jq -r '.Data.AvailableAmount // 0')
    
    # 检查账户余额是否充足
    if (( $(echo "$available_balance < $balance_threshold" | bc -l) )); then
        echo -e "[$(date +'%F %T')] ${color_red}账户剩余 $available_balance 元，余额不足，无法购买资源包。${color_reset}"
        return 1
    fi
    
    # 根据账户余额计算可购买的资源包规格
    local package_spec
    if (( $(echo "$available_balance >= 5000" | bc -l) )); then
        package_spec="5000"
    elif (( $(echo "$available_balance >= 2000" | bc -l) )); then
        package_spec="2000"
    elif (( $(echo "$available_balance >= 1000" | bc -l) )); then
        package_spec="1000"
    else
        package_spec="500"
    fi
    
    if [ "$show_message" = "true" ]; then
        echo "账户余额：$available_balance 元"
        echo "将购买资源包规格：$package_spec 元"
    fi
    
    echo "购买 CDN 资源包："
    local result
    result=$(call_aliyun_api cdn AddCdnDomain \
        --ProductCode cdn \
        --SubscriptionType PayAsYouGo \
        --PackageType Standard \
        --PackageSpec "$package_spec")
    
    if [ $? -eq 0 ]; then
        echo "CDN 资源包购买成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "pay" "$result"
    else
        echo "错误：CDN 资源包购买失败。"
        echo "$result"
        return 1
    fi
}
