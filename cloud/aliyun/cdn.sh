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

    # 如果没有提供参数，则使用交互式输入
    if [ -z "$domain_name" ] || [ -z "$sources" ] || [ -z "$source_type" ]; then
        echo "使用交互式模式添加 CDN 加速域名"

        # 输入域名
        if [ -z "$domain_name" ]; then
            read -r -p "请输入域名: " domain_name
            if [ -z "$domain_name" ]; then
                echo "错误：域名不能为空。" >&2
                return 1
            fi
        fi

        # 输入源站地址
        if [ -z "$sources" ]; then
            read -r -p "请输入源站地址 (如: example.oss-cn-hangzhou.aliyuncs.com): " sources
            if [ -z "$sources" ]; then
                echo "错误：源站地址不能为空。" >&2
                return 1
            fi
        fi

        # 选择源站类型
        if [ -z "$source_type" ]; then
            local source_type_list="oss
ip
domain
oss_private"
            if type select_with_fzf >/dev/null 2>&1; then
                source_type=$(select_with_fzf "选择源站类型" "$source_type_list")
            else
                read -r -p "请输入源站类型 (oss/ip/domain/oss_private): " source_type
                if [ -z "$source_type" ]; then
                    echo "错误：源站类型不能为空。" >&2
                    return 1
                fi
            fi
        fi
    fi

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

    # 如果没有提供域名，则使用交互式输入
    if [ -z "$domain_name" ]; then
        echo "使用交互式模式删除 CDN 加速域名"

        local domain_list
        domain_list=$(call_aliyun_api cdn DescribeUserDomains 2>/dev/null | jq -r '.Domains.PageData[] | "\(.DomainName) (\(.Cname)) [\(.DomainStatus)]"')

        if [ -z "$domain_list" ]; then
            echo "错误：没有找到 CDN 域名。" >&2
            return 1
        elif [ "$(echo "$domain_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            domain_name=$(echo "$domain_list" | awk '{print $1}')
            echo "自动选择唯一的 CDN 域名: $domain_name"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                domain_name=$(select_with_fzf "选择要删除的 CDN 域名" "$domain_list" | awk '{print $1}')
            else
                read -r -p "请输入域名: " domain_name
                if [ -z "$domain_name" ]; then
                    echo "错误：域名不能为空。" >&2
                    return 1
                fi
            fi
        fi
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
    set -e
    local show_message="$1"
    local color_reset="\033[0m"
    local color_green="\033[0;32m"
    local color_red="\033[0;31m"

    # 资源包规格和价格配置
    local package_unit_size=1024 # 1TB = 1024GB
    local package_unit_price=126 # 每 TB 单价 126 元

    # 阈值配置
    local remaining_threshold=4.000 # 剩余容量阈值 4TB
    local balance_threshold=700     # 账户余额阈值 700 元

    # 查询当前资源包剩余容量
    local query_result
    local page_num=1
    local remaining_amount=0
    local remaining_https_request=0

    while true; do
        query_result=$(call_aliyun_api bssopenapi QueryResourcePackageInstances \
            --ProductCode dcdn \
            --PageNum "$page_num" \
            --PageSize 100 2>/dev/null) || {
            [[ -n "$show_message" ]] && echo -e "[CDN] ${color_red}查询资源包失败${color_reset}"
            return 1
        }

        # 直接处理当前页的数据
        remaining_amount="$(
            echo "$remaining_amount + $(
                echo "$query_result" | jq -r '.Data.Instances.Instance[] | select(.RemainingAmount != "0" and .RemainingAmountUnit != "次") | if .RemainingAmountUnit == "GB" then (. | .RemainingAmount | tonumber) / 1024 elif .RemainingAmountUnit == "TB" then (. | .RemainingAmount | tonumber) else 0 end' | awk '{s+=$1} END {printf "%.3f", s}' 2>/dev/null || echo "-1"
            )" | bc -l
        )"
        remaining_https_request="$(
            echo "$remaining_https_request + $(
                echo "$query_result" | jq -r '.Data.Instances.Instance[] | select(.RemainingAmount != "0" and .RemainingAmountUnit == "次") | .RemainingAmount' | awk '{s+=$1} END {printf "%.0f", s}' 2>/dev/null || echo "0"
            )" | bc -l
        )"

        # 如果当前页的结果数量小于 100，说明没有更多页了
        if [[ $(echo "$query_result" | jq '.Data.Instances.Instance | length') -lt 100 ]]; then
            break
        fi

        ((page_num++))
    done

    if [[ -n "$show_message" ]]; then
        local https_color_code="${color_red}" # 默认红色
        if ((remaining_https_request >= 20000000)); then
            https_color_code="${color_green}" # 大于2000万次时显示绿色
        fi
        echo -e "[$(date +'%F %T')] 剩余HTTPS请求次数: ${https_color_code}$(
            echo "$remaining_https_request" | awk '{
            if ($1 >= 100000000) {
                printf "%.6f亿", $1/100000000
            } else if ($1 >= 10000000) {
                printf "%.4f千万", $1/10000000
            } else if ($1 >= 10000) {
                printf "%.2f万", $1/10000
            } else {
                printf "%d", $1
            }
        }'
        )次${color_reset}"
    fi

    # 检查是否获取到有效的剩余容量值
    if [ "$remaining_amount" = "-1" ]; then
        if [[ -n "$show_message" ]]; then
            echo -e "[$(date +'%F %T')] ${color_red}无法获取资源包剩余容量信息${color_reset}"
        fi
        return 1
    fi

    # 显示剩余容量信息并判断是否需要购买
    if [[ -n "$show_message" ]]; then
        local traffic_color_code="${color_red}" # 默认红色
        if (($(echo "$remaining_amount > $remaining_threshold" | bc -l))); then
            traffic_color_code="${color_green}" # 充足时显示绿色
        fi
        echo -e "[$(date +'%F %T')] 剩余下行流量: ${traffic_color_code}${remaining_amount:-0}TB${color_reset}"
    fi

    # 如果剩余容量充足，则跳过购买
    if (($(echo "$remaining_amount > $remaining_threshold" | bc -l))); then
        return 0
    fi

    # 查询账户可用余额（处理逗号分隔的数字）
    local available_balance
    local balance_result
    balance_result=$(call_aliyun_api bssopenapi QueryAccountBalance 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "错误：无法查询账户余额。" >&2
        return 1
    fi

    available_balance="$(
        echo "$balance_result" | jq -r '.Data.AvailableAmount // "0"' |
            awk '{gsub(/,/,""); print int($0)}'
    )"

    # 检查账户余额是否充足
    if ((available_balance < (balance_threshold + package_unit_price))); then
        echo -e "[$(date +'%F %T')] ${color_red}账户剩余 $available_balance 元，余额不足，无法购买资源包。${color_reset}"
        return 1
    fi

    # 根据账户余额计算可购买的资源包规格
    local package_size
    for size in 200 50 10 5 1; do
        local special_discount=$((size == 200 ? 7870 : 0)) # 200TB 包有特殊优惠
        if ((available_balance > balance_threshold + package_unit_price * size - special_discount)); then
            package_size=$((package_unit_size * size))
            break
        fi
    done

    # 执行购买操作
    log_result "${profile:-}" "$region" "cdn" "pay" "当前剩余: ${remaining_amount:-0}TB，准备购买 $((package_size / package_unit_size))TB 资源包..."
    ## 特殊方式，修改为只买1TB时长1月的（1月的单价108¥，6-12月的单价126¥）
    echo -e "[$(date +'%F %T')] 购买 1TB 资源包..."
    local result
    result=$(call_aliyun_api bssopenapi CreateResourcePackage \
        --ProductCode dcdn \
        --PackageType FPT_dcdnpaybag_deadlineAcc_1541405199 \
        --Duration 1 \
        --PricingCycle Month \
        --Specification "$package_unit_size")

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
