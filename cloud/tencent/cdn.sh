#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# CDN (内容分发网络) 相关函数

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_cdn_help() {
    echo "CDN (内容分发网络) 操作："
    echo "  list [format]                           - 列出 CDN 域名"
    echo "  add <域名> <服务类型> <源站信息>          - 添加 CDN 域名"
    echo "  delete <域名>                           - 删除 CDN 域名"
    echo "  start <域名>                            - 启用 CDN 域名"
    echo "  stop <域名>                             - 停用 CDN 域名"
    echo "  config <域名> [配置参数...]              - 修改域名配置"
    echo "  logs <域名> [日期]                       - 查看域名日志"
    echo "  purge-url <URL列表>                     - 预热URL缓存"
    echo "  purge-path <路径列表>                   - 预热路径缓存"
    echo
    echo "示例："
    echo "  $0 cdn list"
    echo "  $0 cdn list json"
    echo "  $0 cdn add www.example.com web [\"origin.example.com\"]"
    echo "  $0 cdn delete www.example.com"
    echo "  $0 cdn start www.example.com"
    echo "  $0 cdn stop www.example.com"
    echo "  $0 cdn purge-url https://www.example.com/index.html"
    echo "  $0 cdn purge-path https://www.example.com/images/"
}

handle_cdn_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) cdn_list "$@" ;;
    add) cdn_add "$@" ;;
    delete) cdn_delete "$@" ;;
    start) cdn_start "$@" ;;
    stop) cdn_stop "$@" ;;
    config) cdn_config "$@" ;;
    logs) cdn_logs "$@" ;;
    purge-url) cdn_purge_url "$@" ;;
    purge-path) cdn_purge_path "$@" ;;
    help) show_cdn_help ;;
    *)
        echo "错误：未知的 CDN 操作：$operation" >&2
        show_cdn_help
        exit 1
        ;;
    esac
}

# CDN 域名列表
cdn_list() {
    local format=${1:-human}
    local result

    result=$(call_tencent_api cdn DescribeDomains)
    if [ $? -ne 0 ]; then
        echo "错误：无法获取 CDN 域名列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "Domain\tStatus\tCname\tCdnSslSwitch"
        echo "$result" | jq -r '.Response.Domains[]? |
            [
                .Domain,
                .Status,
                .Cname,
                .CdnSsl.Switch
            ] | @tsv'
        ;;
    human | *)
        echo "列出 CDN 域名："
        local temp_output
        temp_output=$(echo "$result" | jq -r '.Response.Domains[]? |
            [
                .Domain,
                .Status,
                .Cname,
                .CdnSsl.Switch
            ] | @tsv')

        local count
        if [ -n "$temp_output" ] && [ "$temp_output" != "null" ] && [ "$temp_output" != "" ]; then
            count=$(echo "$temp_output" | grep -c . || echo "0")
        else
            count="0"
        fi

        if [ "$count" = "0" ] || [ -z "$count" ]; then
            echo "没有找到 CDN 域名。"
        else
            echo -e "Domain\t\t\tStatus\t\tCname\t\t\tCdnSslSwitch"
            echo "$temp_output" | awk 'BEGIN {FS="\t"; OFS="\t"} {
                printf "%-25s  %-12s  %-20s  %s\n", $1, $2, $3, $4
            }'
        fi
        ;;
    esac

    log_result "${profile:-}" "${region:-}" "cdn" "list" "$result" "$format"
}

# 添加 CDN 域名
cdn_add() {
    local domain=$1
    local service_type=$2
    local origin=$3

    if [ -z "$domain" ] || [ -z "$service_type" ] || [ -z "$origin" ]; then
        echo "错误：需要提供域名、服务类型和源站信息。" >&2
        echo "用法：$0 cdn add <域名> <服务类型> <源站信息>" >&2
        echo "示例：$0 cdn add www.example.com web '[{\"Domain\":\"origin.example.com\",\"Origins\":[\"origin.example.com\"],\"BackupOrigins\":[],\"OriginType\":\"domain\",\"BackupOriginType\":\"domain\",\"ServerName\":\"origin.example.com\",\"CosPrivateAccess\":\"off\",\"OriginPullProtocol\":\"http\"}]'" >&2
        return 1
    fi

    echo "添加 CDN 域名：$domain"

    local result
    # 构建请求参数
    local origins_json="{\"Domain\":\"$domain\",\"ServiceType\":\"$service_type\",\"Origin\":{\"Origins\":[$origin],\"OriginType\":\"domain\",\"ServerName\":\"$origin\",\"CosPrivateAccess\":\"off\",\"OriginPullProtocol\":\"http\"}}"

    result=$(call_tencent_api cdn AddCdnDomain $origins_json)
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "add" "$result"
    else
        echo "错误：添加失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 删除 CDN 域名
cdn_delete() {
    local domain=$1

    if [ -z "$domain" ]; then
        echo "错误：需要提供域名。" >&2
        echo "用法：$0 cdn delete <域名>" >&2
        return 1
    fi

    echo "删除 CDN 域名：$domain"

    local result
    result=$(call_tencent_api cdn DeleteCdnDomain --Domains "[\"$domain\"]" --ForceRedirect "off")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "delete" "$result"
    else
        echo "错误：删除失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 启用 CDN 域名
cdn_start() {
    local domain=$1

    if [ -z "$domain" ]; then
        echo "错误：需要提供域名。" >&2
        echo "用法：$0 cdn start <域名>" >&2
        return 1
    fi

    echo "启用 CDN 域名：$domain"

    local result
    result=$(call_tencent_api cdn StartCdnDomain --Domains "[\"$domain\"]")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "start" "$result"
    else
        echo "错误：启用失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 停用 CDN 域名
cdn_stop() {
    local domain=$1

    if [ -z "$domain" ]; then
        echo "错误：需要提供域名。" >&2
        echo "用法：$0 cdn stop <域名>" >&2
        return 1
    fi

    echo "停用 CDN 域名：$domain"

    local result
    result=$(call_tencent_api cdn StopCdnDomain --Domains "[\"$domain\"]")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "stop" "$result"
    else
        echo "错误：停用失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 修改域名配置
cdn_config() {
    local domain=$1
    shift

    if [ -z "$domain" ]; then
        echo "错误：需要提供域名。" >&2
        echo "用法：$0 cdn config <域名> [配置参数...]" >&2
        return 1
    fi

    echo "修改 CDN 域名配置：$domain"
    echo "注意：此功能需要详细的配置参数，请根据实际需求调整。"

    # 这里可以进一步扩展以接受特定的配置参数
    local result
    result=$(call_tencent_api cdn UpdateDomainConfig --Domain "$domain")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "config" "$result"
    else
        echo "错误：配置失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 查看域名日志
cdn_logs() {
    local domain=$1
    local date=$2

    if [ -z "$domain" ]; then
        echo "错误：需要提供域名。" >&2
        echo "用法：$0 cdn logs <域名> [日期]" >&2
        return 1
    fi

    echo "获取 CDN 域名日志：$domain, 日期: ${date:-今天}"

    local result
    local params="--Domain $domain"
    if [ -n "$date" ]; then
        params="$params --Date $date"
    fi

    result=$(call_tencent_api cdn DescribeCdnDomainLogs $params)
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "logs" "$result"
    else
        echo "错误：获取日志失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 预热URL缓存
cdn_purge_url() {
    local urls=("$@")

    if [ ${#urls[@]} -eq 0 ]; then
        echo "错误：需要提供至少一个URL。" >&2
        echo "用法：$0 cdn purge-url <URL1> [URL2...]" >&2
        return 1
    fi

    echo "预热URL缓存："
    for url in "${urls[@]}"; do
        echo "  $url"
    done

    # 构建URL列表JSON
    local urls_json="["
    local first=true
    for url in "${urls[@]}"; do
        if [ "$first" = true ]; then
            urls_json="$urls_json\"$url\""
            first=false
        else
            urls_json="$urls_json,\"$url\""
        fi
    done
    urls_json="$urls_json]"

    local result
    result=$(call_tencent_api cdn PurgeUrlsCache --Urls "$urls_json")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "purge-url" "$result"
    else
        echo "错误：预热失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 预热路径缓存
cdn_purge_path() {
    local paths=("$@")

    if [ ${#paths[@]} -eq 0 ]; then
        echo "错误：需要提供至少一个路径。" >&2
        echo "用法：$0 cdn purge-path <路径1> [路径2...]" >&2
        return 1
    fi

    echo "预热路径缓存："
    for path in "${paths[@]}"; do
        echo "  $path"
    done

    # 构建路径列表JSON
    local paths_json="["
    local first=true
    for path in "${paths[@]}"; do
        if [ "$first" = true ]; then
            paths_json="$paths_json\"$path\""
            first=false
        else
            paths_json="$paths_json,\"$path\""
        fi
    done
    paths_json="$paths_json]"

    local result
    result=$(call_tencent_api cdn PurgePathCache --Paths "$paths_json" --FlushType "flush")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "cdn" "purge-path" "$result"
    else
        echo "错误：预热失败。" >&2
        echo "$result" >&2
        return 1
    fi
}