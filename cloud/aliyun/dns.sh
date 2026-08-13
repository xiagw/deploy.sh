#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# DNS (域名解析服务) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_dns_help() {
    echo "DNS 操作："
    echo "  get <域名> [format]                    - 列出 DNS 记录"
    echo "  add <域名> <主机记录> <类型> <值>     - 创建 DNS 记录"
    echo "  set <记录ID> <主机记录> <类型> <值>   - 更新 DNS 记录"
    echo "  del <记录ID>                          - 删除 DNS 记录（记录ID可选，可使用fzf选择）"
    echo
    echo "示例："
    echo "  $0 dns get example.com"
    echo "  $0 dns get example.com json"
    echo "  $0 dns add example.com www A 192.168.0.1"
    echo "  $0 dns set 123456 www A 192.168.0.2"
    echo "  $0 dns del 123456"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

show_domain_help() {
    echo "域名操作："
    echo "  get [format]                           - 列出所有域名"
    echo
    echo "示例："
    echo "  $0 domain get"
    echo "  $0 domain get json"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_dns_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) dns_list "$@" ;;
    add) dns_create "$@" ;;
    set) dns_update "$@" ;;
    del) dns_delete "$@" ;;
    help) show_dns_help ;;
    *)
        echo "错误：未知的 DNS 操作：$operation" >&2
        show_dns_help
        return 1
        ;;
    esac
}

handle_domain_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) dns_domain_list "$@" ;;
    help) show_domain_help ;;
    *)
        echo "错误：未知的 Domain 操作：$operation" >&2
        show_domain_help
        return 1
        ;;
    esac
}

# 解析域名（未提供时列表选择；alidns 为中心化服务，固定 --region public）
_dns_resolve_domain() {
    resolve_resource_id "$1" "${2:-选择域名}" "错误：没有找到域名。" \
        '.Domains.Domain[] | "\(.DomainName) (\(.DomainId))"' \
        -- alidns describe-domains --region public --pager
}

# 使用新框架的 DNS 列表函数
dns_list() {
    local domain=$1
    local format=${2:-human}

    if is_output_format "$domain"; then
        format=$domain
        domain=""
    fi

    domain=$(_dns_resolve_domain "$domain" "选择域名查看DNS记录") || return 1

    local table_header="RecordId\tRR\tType\tValue\tStatus"
    local jq_filter=".DomainRecords.Record[] | [.RecordId, .RR, .Type, .Value, .Status] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-16s  %-10s  %-6s  %-22s  %s\n", $1, $2, $3, $4, $5}'

    local result
    result=$(call_aliyun_api alidns describe-domain-records --region "public" --domain-name "$domain" --pager 2>/dev/null)
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：无法获取 DNS 记录列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output "$result" "$format" "dns" "list" "$table_header" "$jq_filter" "$status_mapper" "没有找到 DNS 记录。" "列出 DNS 记录："
}

# 使用新框架的创建函数
dns_create() {
    local domain=$1 rr=$2 type=$3 value=$4

    # 如果没有提供参数，则使用交互式输入
    if [ -z "$domain" ] || [ -z "$rr" ] || [ -z "$type" ] || [ -z "$value" ]; then
        echo "使用交互式模式创建 DNS 记录"

        # 选择域名：从已有域名中选择
        if [ -z "$domain" ]; then
            domain=$(_dns_resolve_domain "" "选择域名") || return 1
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
    call_api_logged "dns" "create" "错误：DNS 记录创建失败。" \
        -- alidns add-domain-record --region public \
        --domain-name "$domain" \
        --rr "$rr" \
        --type "$type" \
        --value "$value"
}

# 使用新框架的更新函数
dns_update() {
    local record_id=$1 rr=$2 type=$3 value=$4

    # 如果没有提供记录ID，则使用 fzf 选择
    if [ -z "$record_id" ]; then
        local record_list
        local result
        local ret
        local domain_name=""
        local domain_list
        domain_list=$(call_aliyun_api alidns describe-domains --region public --pager 2>/dev/null | jq -r '.Domains.Domain[] | "\(.DomainName) (\(.DomainId))"')

        if [ -z "$domain_list" ]; then
            echo "错误：没有找到任何域名。" >&2
            return 1
        fi

        if [ "$(echo "$domain_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            domain_name=$(echo "$domain_list" | awk '{print $1}')
            echo "自动选择唯一的域名: $domain_name"
            result=$(call_aliyun_api alidns describe-domain-records --region public --domain-name "$domain_name" --pager 2>/dev/null)
            ret=$?
        else
            read -r -p "请输入域名以查找记录 (留空则查看所有域名): " domain_name

            if [ -n "$domain_name" ]; then
                result=$(call_aliyun_api alidns describe-domain-records --region public --domain-name "$domain_name" --pager 2>/dev/null)
                ret=$?
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    domain_name=$(select_with_fzf "选择域名以查找要更新的记录" "$domain_list" | awk '{print $1}')
                    if [ -z "$domain_name" ]; then
                        echo "错误：未选择域名。" >&2
                        return 1
                    fi
                    result=$(call_aliyun_api alidns describe-domain-records --region public --domain-name "$domain_name" --pager 2>/dev/null)
                    ret=$?
                else
                    echo "请输入域名以查找要更新的记录。" >&2
                    return 1
                fi
            fi
        fi

        if [ $ret -ne 0 ]; then
            echo "错误：无法获取 DNS 记录列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        record_list=$(echo "$result" | jq -r '.DomainRecords.Record[] | "\(.RecordId) \(.RR) \(.Type) \(.Value) [\(.Status)]"')

        if [ -z "$record_list" ]; then
            echo "错误：没有找到 DNS 记录。" >&2
            return 1
        elif [ "$(echo "$record_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            record_id=$(echo "$record_list" | awk '{print $1}')
            echo "自动选择唯一的记录: $record_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                record_id=$(select_with_fzf "选择要更新的 DNS 记录" "$record_list" | awk '{print $1}')
                if [ -z "$record_id" ]; then
                    echo "错误：未选择记录。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择记录，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 如果没有提供其他参数，则使用交互式输入
    if [ -z "$rr" ] || [ -z "$type" ] || [ -z "$value" ]; then
        echo "使用交互式模式更新 DNS 记录"

        # 获取当前记录信息
        local current_record_info
        current_record_info=$(call_aliyun_api alidns describe-domain-record-info --region public --record-id "$record_id" 2>/dev/null)
        ret=$?
        if [ $ret -eq 0 ]; then
            local current_rr current_type current_value
            current_rr=$(echo "$current_record_info" | jq -r '.RR')
            current_type=$(echo "$current_record_info" | jq -r '.Type')
            current_value=$(echo "$current_record_info" | jq -r '.Value')
        else
            echo "警告：无法获取记录的当前信息。" >&2
        fi

        # 输入主机记录
        if [ -z "$rr" ]; then
            read -r -p "请输入主机记录 (当前: $current_rr): " rr
            rr=${rr:-$current_rr}
            if [ -z "$rr" ]; then
                echo "错误：主机记录不能为空。" >&2
                return 1
            fi
        fi

        # 选择记录类型
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
                type=$(select_with_fzf "选择 DNS 记录类型 (当前: $current_type)" "$type_list")
            else
                read -r -p "请输入记录类型 (A/AAAA/CNAME/MX/TXT/NS/SRV/CAA) (当前: $current_type): " type
                type=${type:-$current_type}
                if [ -z "$type" ]; then
                    echo "错误：记录类型不能为空。" >&2
                    return 1
                fi
            fi
        fi

        # 输入记录值
        if [ -z "$value" ]; then
            case "$type" in
            A | AAAA)
                read -r -p "请输入IP地址 (当前: $current_value): " value
                ;;
            CNAME)
                read -r -p "请输入目标域名 (当前: $current_value): " value
                ;;
            MX)
                read -r -p "请输入邮件服务器域名 (当前: $current_value): " value
                ;;
            TXT)
                read -r -p "请输入文本内容 (当前: $current_value): " value
                ;;
            NS)
                read -r -p "请输入名称服务器域名 (当前: $current_value): " value
                ;;
            SRV)
                read -r -p "请输入服务记录值 (当前: $current_value): " value
                ;;
            CAA)
                read -r -p "请输入CAA记录值 (当前: $current_value): " value
                ;;
            *)
                read -r -p "请输入记录值 (当前: $current_value): " value
                ;;
            esac
            value=${value:-$current_value}
            if [ -z "$value" ]; then
                echo "错误：记录值不能为空。" >&2
                return 1
            fi
        fi
    fi

    if ! validate_required_params "$record_id" "$rr" "$type" "$value" "错误：记录ID、主机记录、类型和值不能为空。"; then
        echo "用法：dns set <记录ID> <主机记录> <类型> <值>" >&2
        return 1
    fi

    echo "更新 DNS 记录："
    call_api_logged "dns" "update" "错误：DNS 记录更新失败。" \
        -- alidns update-domain-record --region public \
        --record-id "$record_id" \
        --rr "$rr" \
        --type "$type" \
        --value "$value"
}

# 使用新框架的删除函数
dns_delete() {
    local record_id=$1

    # 如果没有提供记录ID，则使用 fzf 选择
    if [ -z "$record_id" ]; then
        local record_list
        local result
        local ret
        local domain_name=""
        local domain_list
        domain_list=$(call_aliyun_api alidns describe-domains --region public --pager 2>/dev/null | jq -r '.Domains.Domain[] | "\(.DomainName) (\(.DomainId))"')

        if [ -z "$domain_list" ]; then
            echo "错误：没有找到任何域名。" >&2
            return 1
        fi

        if [ "$(echo "$domain_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            domain_name=$(echo "$domain_list" | awk '{print $1}')
            echo "自动选择唯一的域名: $domain_name"
            result=$(call_aliyun_api alidns describe-domain-records --region public --domain-name "$domain_name" --pager 2>/dev/null)
            ret=$?
        else
            read -r -p "请输入域名以查找记录 (留空则查看所有域名): " domain_name

            if [ -n "$domain_name" ]; then
                result=$(call_aliyun_api alidns describe-domain-records --region public --domain-name "$domain_name" --pager 2>/dev/null)
                ret=$?
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    domain_name=$(select_with_fzf "选择域名以查找要删除的记录" "$domain_list" | awk '{print $1}')
                    if [ -z "$domain_name" ]; then
                        echo "错误：未选择域名。" >&2
                        return 1
                    fi
                    result=$(call_aliyun_api alidns describe-domain-records --region public --domain-name "$domain_name" --pager 2>/dev/null)
                    ret=$?
                else
                    echo "请输入域名以查找要删除的记录。" >&2
                    return 1
                fi
            fi
        fi

        if [ $ret -ne 0 ]; then
            echo "错误：无法获取 DNS 记录列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        record_list=$(echo "$result" | jq -r '.DomainRecords.Record[] | "\(.RecordId) \(.RR) \(.Type) \(.Value) [\(.Status)]"')

        if [ -z "$record_list" ]; then
            echo "错误：没有找到 DNS 记录。" >&2
            return 1
        elif [ "$(echo "$record_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            record_id=$(echo "$record_list" | awk '{print $1}')
            echo "自动选择唯一的记录: $record_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                record_id=$(select_with_fzf "选择要删除的 DNS 记录" "$record_list" | awk '{print $1}')
                if [ -z "$record_id" ]; then
                    echo "错误：未选择记录。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择记录，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 检查记录 ID 是否为空
    if [ -z "$record_id" ]; then
        echo "错误：记录ID不能为空。" >&2
        return 1
    fi

    if ! confirm_action "删除 DNS 记录：$record_id"; then
        return 1
    fi

    echo "删除 DNS 记录："
    call_api_del_logged "dns" "$record_id" "DNS记录" "错误：DNS 记录删除失败。" \
        -- alidns delete-domain-record --region public --record-id "$record_id" || return 1
    echo "DNS 记录删除成功。"
}

# 使用新框架的域名列表函数
dns_domain_list() {
    local format=${1:-human}

    local table_header="DomainId\tDomainName\tInstanceId\tVersionCode"
    local jq_filter=".Domains.Domain[] | [.DomainId, .DomainName, .InstanceId, .VersionCode] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-16s  %-20s  %-16s  %s\n", $1, $2, $3, $4}'

    local result
    result=$(call_aliyun_api alidns describe-domains --region "public" --pager 2>/dev/null)
    local ret=$?
    if [ $ret -ne 0 ]; then
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
