#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=SC2154

# 工单 (Workorder) 相关函数

# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_ticket_help() {
    echo "工单操作："
    echo "  get [format]                                    - 列出工单"
    echo "  add <分类ID> <描述> <严重程度> [标题]            - 创建工单"
    echo "  reply <工单ID> <内容>                           - 回复工单"
    echo "  close [<工单ID>]                               - 关闭工单"
    echo "  get-note <工单ID>                                - 查看工单沟通记录"
    echo "  get-product [名称]                              - 查询产品列表"
    echo "  get-cat <产品ID>                                - 查询问题分类"
    echo
    echo "示例："
    echo "  $0 ticket get"
    echo "  $0 ticket add 12345 'ECS实例无法启动' 1"
    echo "  $0 ticket add 12345 'ECS实例无法启动' 1 '紧急：ECS故障'"
    echo "  $0 ticket reply 20240101000001 '已尝试重启，仍然失败'"
    echo "  $0 ticket close 20240101000001"
    echo "  $0 ticket get-note 20240101000001"
    echo "  $0 ticket get-product ECS"
    echo "  $0 ticket get-cat 7160"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_ticket_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) ticket_list "$@" ;;
    add) ticket_create "$@" ;;
    reply) ticket_reply "$@" ;;
    close) ticket_close "$@" ;;
    get-note) ticket_notes "$@" ;;
    get-product) ticket_products "$@" ;;
    get-cat) ticket_categories "$@" ;;
    help) show_ticket_help ;;
    *)
        echo "错误：未知的工单操作：$operation" >&2
        show_ticket_help
        exit 1
        ;;
    esac
}

_ticket_resolve_ticket_id() {
    resolve_resource_id "$1" "${2:-选择工单}" "错误：没有找到工单。" \
        '.Data[] | "\(.TicketId) (\(.Title // "无标题")) [\(.Status.Label)]"' \
        -- workorder list-tickets --page-number 1 --page-size 100 --start-date "$(($(date -d '3 months ago' +%s) * 1000))" --end-date "$(($(date +%s) * 1000))"
}

ticket_list() {
    local format=${1:-human}
    local start_date end_date
    start_date=$(($(date -d '3 months ago' +%s) * 1000))
    end_date=$(($(date +%s) * 1000))

    local table_header="TicketId\tTitle\tStatus\tCreateTime"
    local jq_filter=".Data[] | [.TicketId, .Title, .Status.Label, .CreateTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-30s  %-8s  %s\n", $1, $2, $3, $4}'

    local result
    result=$(call_aliyun_api workorder list-tickets --page-number 1 --page-size 100 --start-date "$start_date" --end-date "$end_date" 2>/dev/null)
    ret=$?
    if [ $ret -eq 0 ]; then
        format_output "$result" "$format" "ticket" "list" "$table_header" "$jq_filter" "$status_mapper" "没有找到工单。" "列出工单（最近 3 个月）："
    else
        echo "错误：无法获取工单列表。" >&2
        return 1
    fi
}

ticket_create() {
    local category_id=$1 description=$2 severity=$3 title=$4

    if [ -z "$category_id" ]; then
        echo "正在获取产品列表..."
        local product_result
        product_result=$(call_aliyun_api workorder list-products 2>/dev/null)
        ret=$?
        if [ $ret -ne 0 ] || [ -z "$product_result" ]; then
            echo "错误：无法获取产品列表。" >&2
            return 1
        fi

        local product_list
        product_list=$(echo "$product_result" | jq -r '.Data[].ProductList[] | "\(.ProductId) \(.ProductName)"')
        if [ -z "$product_list" ]; then
            echo "错误：没有找到产品。" >&2
            return 1
        fi

        local selected_product
        if type select_with_fzf >/dev/null 2>&1; then
            selected_product=$(select_with_fzf "选择产品" "$product_list")
        else
            echo "产品列表："
            echo "$product_list" | awk '{printf "  %-6s %s\n", $1, substr($0, index($0,$2))}'
            read -r -p "请输入产品ID: " selected_product
        fi
        if [ -z "$selected_product" ]; then
            echo "错误：未选择产品。" >&2
            return 1
        fi
        local product_id
        product_id=$(echo "$selected_product" | awk '{print $1}')

        echo "正在获取 $product_id 的问题分类..."
        local cat_result
        cat_result=$(call_aliyun_api workorder list-categories --product-id "$product_id" 2>/dev/null)
        ret=$?
        if [ $ret -ne 0 ] || [ -z "$cat_result" ]; then
            echo "错误：无法获取分类列表。" >&2
            return 1
        fi

        local cat_list
        cat_list=$(echo "$cat_result" | jq -r '.Data[] | "\(.CategoryId) \(.CategoryName)"')
        if [ -z "$cat_list" ]; then
            echo "错误：没有找到问题分类。" >&2
            return 1
        fi

        if type select_with_fzf >/dev/null 2>&1; then
            category_id=$(select_with_fzf "选择问题分类" "$cat_list" | awk '{print $1}')
        else
            echo "分类列表："
            echo "$cat_list" | awk '{printf "  %-6s %s\n", $1, substr($0, index($0,$2))}'
            read -r -p "请输入分类ID: " category_id
        fi
        if [ -z "$category_id" ]; then
            echo "错误：未选择分类。" >&2
            return 1
        fi
    fi

    if [ -z "$description" ]; then
        read -r -p "请输入问题描述: " description
        if [ -z "$description" ]; then
            echo "错误：描述不能为空。" >&2
            return 1
        fi
    fi

    if [ -z "$severity" ]; then
        local severity_list="1 (普通)
2 (紧急)"
        if type select_with_fzf >/dev/null 2>&1; then
            severity=$(select_with_fzf "选择严重程度" "$severity_list" | awk '{print $1}')
        else
            read -r -p "请输入严重程度 (1=普通, 2=紧急): " severity
        fi
        severity=${severity:-1}
    fi

    if [ -z "$title" ]; then
        read -r -p "请输入工单标题 (可选): " title
    fi

    local api_args=(
        "--category-id" "$category_id"
        "--description" "$description"
        "--severity" "$severity"
    )
    [ -n "$title" ] && api_args+=("--title" "$title")

    echo "创建工单："
    call_api_logged "ticket" "create" "错误：工单创建失败。" \
        -- workorder create-ticket "${api_args[@]}"
}

ticket_reply() {
    local ticket_id=$1 content=$2

    if [ -z "$ticket_id" ]; then
        ticket_id=$(_ticket_resolve_ticket_id "" "选择要回复的工单") || return 1
        ticket_id=$(echo "$ticket_id" | awk '{print $1}')
    fi

    if [ -z "$content" ]; then
        read -r -p "请输入回复内容: " content
        if [ -z "$content" ]; then
            echo "错误：回复内容不能为空。" >&2
            return 1
        fi
    fi

    echo "回复工单："
    call_api_logged "ticket" "reply" "错误：工单回复失败。" \
        -- workorder reply-ticket --ticket-id "$ticket_id" --content "$content" --encrypt false
}

ticket_close() {
    local ticket_id=$1

    ticket_id=$(_ticket_resolve_ticket_id "$ticket_id" "选择要关闭的工单") || return 1
    ticket_id=$(echo "$ticket_id" | awk '{print $1}')

    if ! confirm_action "关闭工单：$ticket_id"; then
        return 1
    fi

    echo "关闭工单："
    call_api_del_logged "ticket" "$ticket_id" "工单" "错误：工单关闭失败。" \
        -- workorder close-ticket --ticket-id "$ticket_id"
}

ticket_notes() {
    local ticket_id=$1

    if [ -z "$ticket_id" ]; then
        ticket_id=$(_ticket_resolve_ticket_id "" "选择要查看沟通记录的工单") || return 1
        ticket_id=$(echo "$ticket_id" | awk '{print $1}')
    fi

    echo "工单沟通记录："
    local result
    result=$(call_aliyun_api workorder list-ticket-notes --ticket-id "$ticket_id" 2>/dev/null)
    ret=$?
    if [ $ret -eq 0 ]; then
        if [[ $(echo "$result" | jq '.Data | length') -eq 0 ]]; then
            echo "没有找到沟通记录。"
        else
            echo "时间                 类型    内容"
            echo "$result" | jq -r '.Data[] | [.CreateTime, .Type, .Content] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"} {printf "%-20s %-6s %s\n", $1, $2, $3}'
        fi
        log_result "${profile:-}" "$region" "ticket" "get-note" "$result"
    else
        echo "错误：无法获取沟通记录。" >&2
        return 1
    fi
}

ticket_products() {
    local name=$1

    echo "产品列表："
    local extra_args=()
    [ -n "$name" ] && extra_args=(--name "$name")

    local result
    result=$(call_aliyun_api workorder list-products "${extra_args[@]}" 2>/dev/null)
    ret=$?
    if [ $ret -eq 0 ]; then
        echo "产品ID              产品名称"
        echo "$result" | jq -r '.Data[].ProductList[] | [.ProductId, .ProductName] | @tsv' |
            awk 'BEGIN {FS="\t"; OFS="\t"} {printf "%-20s %s\n", $1, $2}'
        log_result "${profile:-}" "$region" "ticket" "get-product" "$result"
    else
        echo "错误：无法获取产品列表。" >&2
        return 1
    fi
}

ticket_categories() {
    local product_id=$1

    if [ -z "$product_id" ]; then
        read -r -p "请输入产品ID (用 ticket get-product 查询): " product_id
        if [ -z "$product_id" ]; then
            echo "错误：产品ID不能为空。" >&2
            return 1
        fi
    fi

    echo "问题分类列表："
    local result
    result=$(call_aliyun_api workorder list-categories --product-id "$product_id" 2>/dev/null)
    ret=$?
    if [ $ret -eq 0 ]; then
        echo "分类ID              分类名称"
        echo "$result" | jq -r '.Data[] | [.CategoryId, .CategoryName] | @tsv' |
            awk 'BEGIN {FS="\t"; OFS="\t"} {printf "%-20s %s\n", $1, $2}'
        log_result "${profile:-}" "$region" "ticket" "get-cat" "$result"
    else
        echo "错误：无法获取分类列表。" >&2
        return 1
    fi
}