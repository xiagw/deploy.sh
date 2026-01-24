#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# DNS (域名解析服务) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_dns_help() {
    echo "DNS 操作："
    echo "  list   <域名> [format]                   - 列出 DNS 记录"
    echo "  create <域名> <主机记录> <类型> <值>     - 创建 DNS 记录"
    echo "  update <记录ID> <主机记录> <类型> <值>   - 更新 DNS 记录"
    echo "  delete <记录ID>                         - 删除 DNS 记录"
    echo
    echo "示例："
    echo "  $0 dns list example.com"
    echo "  $0 dns list example.com json"
    echo "  $0 dns create example.com www A 192.168.0.1"
    echo "  $0 dns update 123456 www A 192.168.0.2"
    echo "  $0 dns delete 123456"
}

show_domain_help() {
    echo "域名操作："
    echo "  list [format]                           - 列出所有域名"
    echo
    echo "示例："
    echo "  $0 domain list"
    echo "  $0 domain list json"
}

handle_dns_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) dns_list "$@" ;;
    create) dns_create "$@" ;;
    update) dns_update "$@" ;;
    delete) dns_delete "$@" ;;
    help) show_dns_help ;;
    *)
        echo "错误：未知的 DNS 操作：$operation" >&2
        show_dns_help
        return 1
        ;;
    esac
}

handle_domain_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) dns_domain_list "$@" ;;
    help) show_domain_help ;;
    *)
        echo "错误：未知的 Domain 操作：$operation" >&2
        show_domain_help
        return 1
        ;;
    esac
}

get_domain_list() {
    local result
    result=$(call_aliyun_api alidns DescribeDomains)
    echo "$result" | jq -r '.Domains.Domain[] | .DomainName'
}

# 使用新框架的 DNS 列表函数
dns_list() {
    local domain=$1
    local format=${2:-human}

    if [ -z "$domain" ]; then
        echo "列出所有域名："
        dns_domain_list "$format"
        return
    fi

    local table_header="RecordId\tRR\tType\tValue\tStatus"
    local jq_filter=".DomainRecords.Record[] | [.RecordId, .RR, .Type, .Value, .Status] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-16s  %-10s  %-6s  %-22s  %s\n", $1, $2, $3, $4, $5}'

    local result
    result=$(call_aliyun_api alidns DescribeDomainRecords \
        --DomainName "$domain" \
        --PageSize 100)

    if [ $? -ne 0 ]; then
        echo "错误：无法获取 DNS 记录列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "dns" \
        "list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 DNS 记录。" \
        "列出 DNS 记录："
}

# 使用新框架的创建函数
dns_create() {
    local domain=$1 rr=$2 type=$3 value=$4

    # 如果没有提供参数，则使用交互式输入
    if [ -z "$domain" ] || [ -z "$rr" ] || [ -z "$type" ] || [ -z "$value" ]; then
        echo "使用交互式模式创建 DNS 记录"

        # 输入域名 - 必须用户明确输入
        if [ -z "$domain" ]; then
            read -r -p "请输入域名: " domain
            if [ -z "$domain" ]; then
                echo "错误：域名不能为空。" >&2
                return 1
            fi
        fi

        # 输入主机记录 - 必须用户明确输入
        if [ -z "$rr" ]; then
            read -r -p "请输入主机记录 (如: www, @, api): " rr
            if [ -z "$rr" ]; then
                echo "错误：主机记录不能为空。" >&2
                return 1
            fi
        fi

        # 选择记录类型 - 可以从预定义列表选择
        if [ -z "$type" ]; then
            local type_list="A
AAAA
CNAME
MX
TXT
NS
SRV
CAA"
            if type select_with_fzf >/dev/null 2>&1; then
                type=$(select_with_fzf "选择 DNS 记录类型" "$type_list")
            else
                read -r -p "请输入记录类型 (A/AAAA/CNAME/MX/TXT/NS/SRV/CAA): " type
                if [ -z "$type" ]; then
                    echo "错误：记录类型不能为空。" >&2
                    return 1
                fi
            fi
        fi

        # 输入记录值 - 必须用户明确输入
        if [ -z "$value" ]; then
            case "$type" in
            A | AAAA)
                read -r -p "请输入IP地址: " value
                ;;
            CNAME)
                read -r -p "请输入目标域名: " value
                ;;
            MX)
                read -r -p "请输入邮件服务器域名: " value
                ;;
            TXT)
                read -r -p "请输入文本内容: " value
                ;;
            NS)
                read -r -p "请输入名称服务器域名: " value
                ;;
            SRV)
                read -r -p "请输入服务记录值: " value
                ;;
            CAA)
                read -r -p "请输入CAA记录值: " value
                ;;
            *)
                read -r -p "请输入记录值: " value
                ;;
            esac
            if [ -z "$value" ]; then
                echo "错误：记录值不能为空。" >&2
                return 1
            fi
        fi
    fi

    if ! validate_required_params "$domain" "$rr" "$type" "$value" "错误：域名、主机记录、类型和值不能为空。"; then
        echo "用法：dns create <域名> <主机记录> <类型> <值>" >&2
        return 1
    fi

    echo "创建 DNS 记录："
    local result
    result=$(call_aliyun_api alidns AddDomainRecord \
        --DomainName "$domain" \
        --RR "$rr" \
        --Type "$type" \
        --Value "$value")

    if [ $? -eq 0 ]; then
        echo "DNS 记录创建成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "dns" "create" "$result"
    else
        echo "错误：DNS 记录创建失败。"
        echo "$result"
        return 1
    fi
}

# 使用新框架的更新函数
dns_update() {
    local record_id=$1 rr=$2 type=$3 value=$4

    if ! validate_required_params "$record_id" "$rr" "$type" "$value" "错误：记录ID、主机记录、类型和值不能为空。"; then
        echo "用法：dns update <记录ID> <主机记录> <类型> <值>" >&2
        return 1
    fi

    echo "更新 DNS 记录："
    local result
    result=$(call_aliyun_api alidns UpdateDomainRecord \
        --RecordId "$record_id" \
        --RR "$rr" \
        --Type "$type" \
        --Value "$value")

    if [ $? -eq 0 ]; then
        echo "DNS 记录更新成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "dns" "update" "$result"
    else
        echo "错误：DNS 记录更新失败。"
        echo "$result"
        return 1
    fi
}

# 使用新框架的删除函数
dns_delete() {
    local record_id=$1

    if [ -z "$record_id" ]; then
        echo "错误：记录ID不能为空。" >&2
        return 1
    fi

    if ! confirm_action "删除 DNS 记录：$record_id"; then
        return 1
    fi

    echo "删除 DNS 记录："
    local result
    result=$(call_aliyun_api alidns DeleteDomainRecord --RecordId "$record_id")

    if [ $? -eq 0 ]; then
        echo "DNS 记录删除成功。"
        log_delete_operation "${profile:-}" "$region" "dns" "$record_id" "DNS记录" "成功"
    else
        echo "DNS 记录删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "dns" "$record_id" "DNS记录" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "dns" "delete" "$result"
}

# 使用新框架的域名列表函数
dns_domain_list() {
    local format=${1:-human}

    local table_header="DomainId\tDomainName\tInstanceId\tVersionCode"
    local jq_filter=".Domains.Domain[] | [.DomainId, .DomainName, .InstanceId, .VersionCode] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-16s  %-20s  %-16s  %s\n", $1, $2, $3, $4}'

    local result
    result=$(call_aliyun_api alidns DescribeDomains)

    if [ $? -ne 0 ]; then
        echo "错误：无法获取域名列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "domain" \
        "list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到域名。" \
        "列出所有域名："
}
