#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# DNS (域名解析服务) 相关函数

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
    result=$(aliyun --profile "${profile:-}" alidns DescribeDomains)
    echo "$result" | jq -r '.Domains.Domain[] | .DomainName'
}

dns_list() {
    local domain=$1
    local format=${2:-human}

    if [ -z "$domain" ]; then
        echo "列出所有域名："
        dns_domain_list "$format"
        return
    fi

    echo "列出 DNS 记录："
    local result
    result=$(aliyun --profile "${profile:-}" alidns DescribeDomainRecords --DomainName "$domain")

    if [ $? -ne 0 ]; then
        echo "错误：无法获取 DNS 记录列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        echo -e "RecordId\tRR\tType\tValue\tStatus"
        echo "$result" | jq -r '.DomainRecords.Record[] | [.RecordId, .RR, .Type, .Value, .Status] | @tsv'
        ;;
    human | *)
        if [[ $(echo "$result" | jq '.DomainRecords.Record | length') -eq 0 ]]; then
            echo "没有找到 DNS 记录。"
        else
            echo "记录ID            主机记录    类型    记录值                  状态"
            echo "----------------  ----------  ------  ----------------------  ------"
            echo "$result" | jq -r '.DomainRecords.Record[] | [.RecordId, .RR, .Type, .Value, .Status] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    printf "%-16s  %-10s  %-6s  %-22s  %s\n", $1, $2, $3, $4, $5
                }'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "dns" "list" "$result" "$format"
}

dns_create() {
    local domain=$1 rr=$2 type=$3 value=$4

    if [ -z "$domain" ] || [ -z "$rr" ] || [ -z "$type" ] || [ -z "$value" ]; then
        echo "错误：所有参数都不能为空。" >&2
        echo "用法：dns create <域名> <主机记录> <类型> <值>" >&2
        return 1
    fi

    echo "创建 DNS 记录："
    local result
    result=$(aliyun --profile "${profile:-}" alidns AddDomainRecord \
        --DomainName "$domain" \
        --RR "$rr" \
        --Type "$type" \
        --Value "$value")

    if [ $? -eq 0 ]; then
        echo "DNS 记录创建成功："
        echo "$result" | jq '.'
    else
        echo "错误：DNS 记录创建失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "dns" "create" "$result"
}

dns_update() {
    local record_id=$1 rr=$2 type=$3 value=$4

    if [ -z "$record_id" ] || [ -z "$rr" ] || [ -z "$type" ] || [ -z "$value" ]; then
        echo "错误：所有参数都不能为空。" >&2
        echo "用法：dns update <记录ID> <主机记录> <类型> <值>" >&2
        return 1
    fi

    echo "更新 DNS 记录："
    local result
    result=$(aliyun --profile "${profile:-}" alidns UpdateDomainRecord \
        --RecordId "$record_id" \
        --RR "$rr" \
        --Type "$type" \
        --Value "$value")

    if [ $? -eq 0 ]; then
        echo "DNS 记录更新成功："
        echo "$result" | jq '.'
    else
        echo "错误：DNS 记录更新失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "dns" "update" "$result"
}

dns_delete() {
    local record_id=$1

    if [ -z "$record_id" ]; then
        echo "错误：记录ID不能为空。" >&2
        echo "用法：dns delete <记录ID>" >&2
        return 1
    fi

    echo "警告：您即将删除 DNS 记录：$record_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 DNS 记录："
    local result
    result=$(aliyun --profile "${profile:-}" alidns DeleteDomainRecord --RecordId "$record_id")

    if [ $? -eq 0 ]; then
        echo "DNS 记录删除成功。"
        log_delete_operation "${profile:-}" "$region" "dns" "$record_id" "DNS记录" "成功"
    else
        echo "DNS 记录删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "dns" "$record_id" "DNS记录" "失败"
    fi

    log_result "${profile:-}" "$region" "dns" "delete" "$result"
}

dns_domain_list() {
    local format=${1:-human}
    echo "列出所有域名："
    local result
    result=$(aliyun --profile "${profile:-}" alidns DescribeDomains)

    if [ $? -ne 0 ]; then
        echo "错误：无法获取域名列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
        json)
            echo "$result" | jq '.Domains.Domain'
            ;;
        tsv)
            echo -e "DomainId\tDomainName\tInstanceId\tVersionCode"
            echo "$result" | jq -r '.Domains.Domain[] | [.DomainId, .DomainName, .InstanceId, .VersionCode] | @tsv'
            ;;
        human|*)
            if [[ $(echo "$result" | jq '.Domains.Domain | length') -eq 0 ]]; then
                echo "没有找到域名。"
            else
                echo "域名ID            域名                  实例ID            版本代码"
                echo "----------------  --------------------  ----------------  ----------"
                echo "$result" | jq -r '.Domains.Domain[] | [.DomainId, .DomainName, .InstanceId, .VersionCode] | @tsv' |
                    awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    printf "%-16s  %-20s  %-16s  %s\n", $1, $2, $3, $4
                }'
            fi
            ;;
    esac
    log_result "${profile:-}" "$region" "domain" "list" "$result" "$format"
}

