#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# EIP (弹性公网IP) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_eip_help() {
    echo "EIP (弹性公网IP) 操作："
    echo "  get [format]                           - 列出 EIP"
    echo "  add <带宽>                            - 创建 EIP"
    echo "  set <EIP-ID> <新带宽>                 - 更新 EIP 带宽"
    echo "  del [<EIP-ID>]                        - 删除 EIP（EIP-ID可选，可使用fzf选择）"
    echo
    echo "示例："
    echo "  $0 eip get"
    echo "  $0 eip get json"
    echo "  $0 eip add 5"
    echo "  $0 eip set eip-bp1v8dxgd9wqjb2g**** 10"
    echo "  $0 eip del eip-bp1v8dxgd9wqjb2g****"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_eip_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) eip_list "$@" ;;
    add) eip_create "$@" ;;
    set) eip_update "$@" ;;
    del) eip_delete "$@" ;;
    help) show_eip_help ;;
    *)
        echo "错误：未知的 EIP 操作：$operation" >&2
        show_eip_help
        exit 1
        ;;
    esac
}

# 使用新框架的列表函数
eip_list() {
    local format=${1:-human}

    local table_header="AllocationId\tIpAddress\tStatus\tBandwidth\tInstanceId\tAllocationTime"
    local jq_filter=".EipAddresses.EipAddress[] | [.AllocationId, .IpAddress, .Status, .Bandwidth, .InstanceId, .AllocationTime] | @tsv"
    # 使用单行 awk 脚本，避免多行字符串的转义问题
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-14s  %-7s  %-10s  %-18s  %s\n", $1, $2, $3, $4, $5, $6}'

    local result
    result=$(call_aliyun_api vpc describe-eip-addresses --biz-region-id "${region:-}" --region "${region:-}" 2>/dev/null)
    ret=$?
    if [ $ret -eq 0 ]; then
        format_output "$result" "$format" "eip" "list" "$table_header" "$jq_filter" "$status_mapper" "没有找到 EIP。" "列出 EIP："
    else
        echo "错误：无法获取 EIP 列表。" >&2
        return 1
    fi
}

# 使用新框架的创建函数
eip_create() {
    local bandwidth=$1

    # 如果没有提供带宽，则使用 fzf 交互式选择
    if [ -z "$bandwidth" ]; then
        echo "使用 fzf 交互式模式创建 EIP"

        echo "正在获取可用的 EIP 带宽选项..."
        local bandwidth_result bandwidth_list
        bandwidth_result=$(call_aliyun_api vpc describe-common-bandwidth-packages --biz-region-id "${region:-}" --region "${region:-}" 2>/dev/null)
        ret=$?
        if [ $ret -eq 0 ] && [ -n "$bandwidth_result" ]; then
            bandwidth_list="1
2
5
10
20
50
100
200
500
1000
2000
5000"
            echo "使用可用带宽列表。"
        else
            echo "警告：无法从 API 获取带宽选项，使用默认列表。" >&2
            bandwidth_list="1
2
5
10
20
50
100
200
500
1000"
        fi

        if type select_with_fzf >/dev/null 2>&1; then
            bandwidth=$(select_with_fzf "选择 EIP 带宽 (Mbps)" "$bandwidth_list")
        else
            read -r -p "请输入 EIP 带宽 (Mbps): " bandwidth
        fi

        if [ -z "$bandwidth" ]; then
            echo "错误：带宽不能为空。" >&2
            return 1
        fi
    fi

    # 验证带宽是否为数字
    if ! [[ "$bandwidth" =~ ^[0-9]+$ ]]; then
        echo "错误：带宽必须是数字。" >&2
        return 1
    fi

    local api_args=(
        "--bandwidth" "$bandwidth"
        "--internet-charge-type" "PayByTraffic"
    )

    generic_create \
        "vpc" \
        "AllocateEipAddress" \
        "eip" \
        "EIP-${bandwidth}Mbps" \
        "${api_args[@]}"
}

# 使用新框架的更新函数（EIP 更新需要特殊处理）
eip_update() {
    local eip_id=$1
    local new_bandwidth=$2

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$eip_id" ] || [ -z "$new_bandwidth" ]; then
        echo "使用 fzf 交互式模式更新 EIP"

        # 选择 EIP ID
        if [ -z "$eip_id" ]; then
            eip_id=$(resolve_resource_id "" "选择 EIP" "错误：没有找到 EIP。" \
                '.EipAddresses.EipAddress[] | "\(.AllocationId) (\(.IpAddress)) [\(.Bandwidth)Mbps] [\(.Status)]"' \
                -- vpc describe-eip-addresses --biz-region-id "${region:-}" --region "${region:-}") || return 1
        fi

        # 选择新带宽
        if [ -z "$new_bandwidth" ]; then
            echo "正在获取可用的 EIP 带宽选项..."
            local bandwidth_result bandwidth_list
            bandwidth_result=$(call_aliyun_api vpc describe-common-bandwidth-packages --biz-region-id "${region:-}" --region "${region:-}" 2>/dev/null)
            ret=$?
            if [ $ret -eq 0 ] && [ -n "$bandwidth_result" ]; then
                bandwidth_list="1
2
5
10
20
50
100
200
500
1000
2000
5000"
                echo "使用可用带宽列表。"
            else
                echo "警告：无法从 API 获取带宽选项，使用默认列表。" >&2
                bandwidth_list="1
2
5
10
20
50
100
200
500
1000"
            fi

            if type select_with_fzf >/dev/null 2>&1; then
                new_bandwidth=$(select_with_fzf "选择新的 EIP 带宽 (Mbps)" "$bandwidth_list")
            else
                read -r -p "请输入新的 EIP 带宽 (Mbps): " new_bandwidth
            fi
        fi
    fi

    if [ -z "$eip_id" ] || [ -z "$new_bandwidth" ]; then
        echo "错误：EIP ID 和新带宽不能为空。" >&2
        echo "用法：eip set <EIP-ID> <新带宽>" >&2
        return 1
    fi

    # 验证带宽是否为数字
    if ! [[ "$new_bandwidth" =~ ^[0-9]+$ ]]; then
        echo "错误：带宽必须是数字。" >&2
        return 1
    fi

    echo "更新 EIP 带宽："
    call_api_logged "eip" "update" "错误：更新失败。" \
        -- vpc modify-eip-address-attribute --biz-region-id "${region:-}" --region "${region:-}" \
        --allocation-id "$eip_id" --bandwidth "$new_bandwidth"
}

# 删除函数需要特殊处理（需要先解绑）
eip_delete() {
    local eip_id=$1

    # 如果没有提供 EIP ID，则使用 fzf 交互式选择
    if [ -z "$eip_id" ]; then
        echo "使用 fzf 交互式模式删除 EIP"

        eip_id=$(resolve_resource_id "" "选择要删除的 EIP" "错误：没有找到 EIP。" \
            '.EipAddresses.EipAddress[] | "\(.AllocationId) (\(.IpAddress)) [\(.Bandwidth)Mbps] [\(.Status)]"' \
            -- vpc describe-eip-addresses --biz-region-id "${region:-}" --region "${region:-}") || return 1
    fi

    if [ -z "$eip_id" ]; then
        echo "错误：EIP ID 不能为空。" >&2
        return 1
    fi

    # 获取 EIP 详细信息
    local eip_info
    eip_info=$(call_aliyun_api vpc describe-eip-addresses --biz-region-id "${region:-}" --region "${region:-}" --allocation-id "$eip_id")
    local ip_address
    ip_address=$(echo "$eip_info" | jq -r '.EipAddresses.EipAddress[0].IpAddress // empty')
    local eip_status
    eip_status=$(echo "$eip_info" | jq -r '.EipAddresses.EipAddress[0].Status // "未知"')

    if [ -z "$ip_address" ]; then
        echo "错误：未找到指定的 EIP：$eip_id" >&2
        return 1
    fi

    # 确认删除
    echo "警告：您即将删除以下 EIP："
    echo "  EIP ID: $eip_id"
    echo "  IP 地址: $ip_address"
    echo "  状态: $eip_status"
    echo "  地域: $region"

    if ! confirm_action "删除 EIP $eip_id ($ip_address)"; then
        return 1
    fi

    # 如果 EIP 已绑定，先解绑
    if [[ "$eip_status" != "Available" ]]; then
        echo "解绑 EIP..."
        local unbind_result
        unbind_result=$(call_aliyun_api vpc unassociate-eip-address --biz-region-id "${region:-}" --region "${region:-}" \
            --allocation-id "$eip_id")
        ret=$?
        if [ $ret -eq 0 ]; then
            echo "$unbind_result" | jq '.'
            log_result "${profile:-}" "$region" "eip" "unbind" "$unbind_result"
            echo "等待解绑完成（10秒）..."
            sleep 10
        else
            echo "警告：解绑失败，但将继续尝试删除。" >&2
        fi
    fi

    # 删除 EIP
    echo "删除 EIP："
    call_api_del_logged "eip" "$eip_id" "$ip_address" "错误：EIP 删除失败。" \
        -- vpc release-eip-address --biz-region-id "${region:-}" --region "${region:-}" \
        --allocation-id "$eip_id" || return 1
    echo "EIP 删除成功。"
}
