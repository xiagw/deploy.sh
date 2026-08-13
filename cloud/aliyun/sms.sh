#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=SC2154

# SMS (短信服务) 相关函数

# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_sms_help() {
    echo "SMS (短信服务) 操作："
    echo "  get [format]                                 - 列出短信模板和签名"
    echo "  send <签名> <模板编号> <手机号> [模板参数]   - 发送短信"
    echo "  query <消息ID>                                - 查询发送状态"
    echo
    echo "示例："
    echo "  $0 sms get"
    echo "  $0 sms send 阿里云 SMS_123456 13800138000 '{\"code\":\"1234\"}'"
    echo "  $0 sms query 1234567890"
}

handle_sms_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) sms_list "$@" ;;
    send) sms_send "$@" ;;
    query) sms_query "$@" ;;
    help) show_sms_help ;;
    *)
        echo "错误：未知的 SMS 操作：$operation" >&2
        show_sms_help
        exit 1
        ;;
    esac
}

sms_list() {
    local format=${1:-human}

    echo "短信模板："
    local template_result
    template_result=$(call_aliyun_api dysmsapi query-sms-template-list --api-version 2017-05-25)
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：查询短信模板失败。" >&2
        echo "$template_result" >&2
    elif [ "$(echo "$template_result" | jq '.SmsTemplateList | length // 0')" -gt 0 ]; then
        local table_header="TemplateCode\tTemplateName\tTemplateType\tAuditStatus\tCreateDate"
        local jq_filter=".SmsTemplateList[] | [.TemplateCode, .TemplateName, .TemplateType, .AuditStatus, .CreateDate] | @tsv"
        local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-18s  %-5s  %-8s  %s\n", $1, $2, $3, $4, $5}'
        format_output "$template_result" "$format" "sms" "template-list" "$table_header" "$jq_filter" "$status_mapper" "没有找到短信模板。" ""
    else
        echo "没有找到短信模板。"
    fi

    echo ""
    echo "短信签名："
    local sign_result
    sign_result=$(call_aliyun_api dysmsapi query-sms-sign-list --api-version 2017-05-25)
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：查询短信签名失败。" >&2
        echo "$sign_result" >&2
    elif [ "$(echo "$sign_result" | jq '.SmsSignList | length // 0')" -gt 0 ]; then
        echo "$sign_result" | jq -r '.SmsSignList[] | [.SignName, .AuditStatus, .SignType, .CreateDate] | @tsv' |
            awk 'BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-8s  %-8s  %s\n", $1, $2, $3, $4}'
        log_result "${profile:-}" "$region" "sms" "sign-list" "$sign_result"
    else
        echo "没有找到短信签名。"
    fi
}

sms_send() {
    local from=$1 template_code=$2 to=$3 template_param=$4

    if [ -z "$from" ]; then
        read -r -p "请输入短信签名: " from
    fi
    if [ -z "$template_code" ]; then
        read -r -p "请输入模板编号: " template_code
    fi
    if [ -z "$to" ]; then
        read -r -p "请输入手机号 (带国家码，如 8613800138000): " to
    fi

    if ! validate_required_params "$from" "$template_code" "$to" "错误：签名、模板编号和手机号不能为空。"; then
        echo "用法：sms send <签名> <模板编号> <手机号> [模板参数]" >&2
        return 1
    fi

    local api_args=(
        "--from" "$from"
        "--template-code" "$template_code"
        "--to" "$to"
    )
    [ -n "$template_param" ] && api_args+=("--template-param" "$template_param")

    echo "发送短信："
    call_api_logged "sms" "send" "错误：短信发送失败。" \
        -- dysmsapi send-message-with-template "${api_args[@]}"
}

sms_query() {
    local message_id=$1

    if [ -z "$message_id" ]; then
        read -r -p "请输入消息ID: " message_id
        if [ -z "$message_id" ]; then
            echo "错误：消息ID不能为空。" >&2
            return 1
        fi
    fi

    echo "查询短信发送状态："
    call_api_logged "sms" "query" "错误：查询失败。" \
        -- dysmsapi query-message --message-id "$message_id"
}