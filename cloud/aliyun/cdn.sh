#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# CDN (内容分发网络) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_cdn_help() {
    echo "CDN (内容分发网络) 操作："
    echo "  get [format]                            - 列出 CDN 域名"
    echo "  add <域名> <源站> <源站类型>           - 添加 CDN 加速域名"
    echo "  del [<域名>]                           - 删除 CDN 加速域名（域名可选，可使用fzf选择）"
    echo "  set <域名> <源站> <源站类型>           - 修改 CDN 域名配置"
    echo "  refresh <类型> <路径>                   - 刷新 CDN 目录、文件或正则（20h 冷却）"
    echo "  trigger <触发文件> [类型]               - 根据触发文件批量刷新（每行一个URL）"
    echo "  prefetch <路径>                         - 预热 CDN 文件"
    echo "  pay                                     - 购买 CDN 资源包（自动判断余量）"
    echo
    echo "示例："
    echo "  $0 cdn get                                                  # 列出所有域名"
    echo "  $0 cdn get json                                             # 以 JSON 格式列出域名"
    echo "  $0 cdn add example.com example.oss-cn-hangzhou.aliyuncs.com oss  # 添加域名加速"
    echo "  $0 cdn del example.com                                   # 删除加速域名"
    echo "  $0 cdn set example.com new-origin.com ip                 # 更新域名配置"
    echo "  $0 cdn refresh directory https://example.com/dir         # 刷新目录"
    echo "  $0 cdn refresh file https://example.com/path/to/file.jpg # 刷新文件"
    echo "  $0 cdn refresh regex 'https://example.com/[0-9]*.jpg'    # 正则刷新"
    echo "  $0 cdn trigger /tmp/trigger.cdn.refresh                    # 批量刷新触发文件中的URL"
    echo "  $0 cdn prefetch https://example.com/path/to/file.jpg     # 预热文件"
    echo "  $0 cdn pay                                                 # 购买资源包"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_cdn_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) cdn_list "$@" ;;
    add) cdn_create "$@" ;;
    del) cdn_delete "$@" ;;
    set) cdn_update "$@" ;;
    refresh) cdn_refresh "$@" ;;
    trigger) cdn_refresh_trigger "$@" ;;
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

# 解析 CDN 域名（未提供时列表选择；cdn 无需区域旗标）
_cdn_resolve_domain() {
    resolve_resource_id "$1" "${2:-选择 CDN 域名}" "错误：没有找到 CDN 域名。" \
        '.Domains.PageData[] | "\(.DomainName) (\(.Cname)) [\(.DomainStatus)]"' \
        -- cdn describe-user-domains
}

# 使用新框架的列表函数
cdn_list() {
    local format=${1:-human}

    local table_header="DomainName\tCname\tDomainStatus\tGmtCreated"
    local jq_filter=".Domains.PageData[] | [.DomainName, .Cname, .DomainStatus, .GmtCreated] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-20s  %-38s  %-6s  %s\n", $1, $2, $3, $4}'

    local result
    result=$(call_aliyun_api cdn describe-user-domains)
    ret=$?

    if [ "$ret" -ne 0 ]; then
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
    call_api_logged "cdn" "create" "错误：CDN 域名创建失败。" \
        -- cdn add-cdn-domain \
        --domain-name "$domain_name" \
        --sources "[{\"content\":\"$sources\",\"type\":\"$source_type\",\"priority\":\"20\",\"port\":80,\"weight\":\"15\"}]" \
        --cdn-type web \
        --scope domestic
}

# 使用新框架的删除函数
cdn_delete() {
    local domain_name
    domain_name=$(_cdn_resolve_domain "$1" "选择要删除的 CDN 域名") || return 1

    if ! confirm_action "删除 CDN 加速域名：$domain_name"; then
        return 1
    fi

    echo "删除 CDN 加速域名："
    call_api_del_logged "cdn" "$domain_name" "CDN域名" "错误：CDN 域名删除失败。" \
        -- cdn delete-cdn-domain --domain-name "$domain_name"
}

# 使用新框架的更新函数
cdn_update() {
    local domain_name sources=$2 source_type=$3
    domain_name=$(_cdn_resolve_domain "$1" "选择要更新的 CDN 域名") || return 1

    # 如果没有提供源站地址或源站类型，则使用交互式输入
    if [ -z "$sources" ] || [ -z "$source_type" ]; then
        echo "使用交互式模式更新 CDN 域名配置"

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
        echo "用法：cdn set <域名> <源站> <源站类型>" >&2
        return 1
    fi

    echo "修改 CDN 域名配置："
    call_api_logged "cdn" "update" "错误：CDN 域名更新失败。" \
        -- cdn modify-cdn-domain \
        --domain-name "$domain_name" \
        --sources "[{\"content\":\"$sources\",\"type\":\"$source_type\",\"priority\":\"20\",\"port\":80,\"weight\":\"15\"}]"
}

# 刷新功能（保持原有实现，但使用框架函数并添加fzf选择）
cdn_refresh() {
    local type=$1
    local path=$2

    local lock_file="/tmp/lock.cdn.refresh"
    local lock_cooldown_hours=20

    # 检查锁文件，防止短时间内重复刷新
    if [ -f "$lock_file" ]; then
        if [ "$(stat -c %Y "$lock_file")" -gt "$(date -d "${lock_cooldown_hours} hours ago" +%s)" ]; then
            echo "刷新冷却中，距上次刷新未满 ${lock_cooldown_hours} 小时，请稍后再试。" >&2
            return 1
        fi
        rm -f "$lock_file"
    fi

    # 如果没有提供类型，则使用 fzf 选择
    if [ -z "$type" ]; then
        local type_list="file
directory
regex"
        if type select_with_fzf >/dev/null 2>&1; then
            type=$(select_with_fzf "选择刷新类型" "$type_list")
            if [ -z "$type" ]; then
                echo "错误：未选择刷新类型。" >&2
                return 1
            fi
        else
            read -r -p "请输入刷新类型 (file/directory/regex): " type
            if [ -z "$type" ]; then
                echo "错误：刷新类型不能为空。" >&2
                return 1
            fi
        fi
    fi

    # 如果没有提供路径，则使用交互式输入
    if [ -z "$path" ]; then
        read -r -p "请输入要刷新的路径: " path
        if [ -z "$path" ]; then
            echo "错误：刷新路径不能为空。" >&2
            return 1
        fi
    fi

    if ! validate_required_params "$type" "$path" "错误：刷新操作需要指定类型（directory/file/regex）和路径。"; then
        return 1
    fi

    local object_type
    case "$type" in
    directory) object_type="Directory" ;;
    file) object_type="File" ;;
    regex) object_type="Regex" ;;
    *)
        echo "错误：无效的刷新类型。请使用 'directory'、'file' 或 'regex'。" >&2
        return 1
        ;;
    esac

    echo "刷新 CDN $type ：$path"
    call_api_logged "cdn" "refresh" "错误：CDN $type 刷新请求失败。" \
        -- cdn refresh-object-caches \
        --biz-force true \
        --object-path "$path" \
        --object-type "$object_type" || return 1
    echo "CDN $type 刷新请求已提交。"
    touch "$lock_file"
}

# 根据触发文件批量刷新 CDN
# 触发文件每行一个 URL，支持空行和 # 注释；执行后自动删除触发文件
cdn_refresh_trigger() {
    local trigger_file=${1:-/tmp/trigger.cdn.refresh}
    local type=${2:-directory}

    if [ ! -f "$trigger_file" ]; then
        return 0
    fi

    local object_type
    case "$type" in
    directory) object_type="Directory" ;;
    file) object_type="File" ;;
    regex) object_type="Regex" ;;
    *)
        echo "错误：无效的刷新类型。请使用 'directory'、'file' 或 'regex'。" >&2
        return 1
        ;;
    esac

    local count=0 path
    while IFS= read -r path || [ -n "$path" ]; do
        [[ -z "$path" || "$path" == \#* ]] && continue
        echo "刷新 CDN $type ：$path"
        call_api_logged "cdn" "refresh" "错误：CDN $type 刷新请求失败。" \
            -- cdn refresh-object-caches \
            --biz-force true \
            --object-path "$path" \
            --object-type "$object_type" || echo "警告：$path 刷新失败，继续处理下一行" >&2
        ((count++))
    done <"$trigger_file"

    rm -f "$trigger_file"

    if [ "$count" -eq 0 ]; then
        echo "触发文件中没有有效的刷新路径。"
        return 0
    fi
    echo "共刷新 $count 条记录。"
}

# 预热功能（保持原有实现，但使用框架函数并添加fzf选择）
cdn_prefetch() {
    local path=$1

    # 如果没有提供路径，则使用交互式输入
    if [ -z "$path" ]; then
        read -r -p "请输入要预热的路径: " path
        if [ -z "$path" ]; then
            echo "错误：预热操作需要指定路径。" >&2
            return 1
        fi
    fi

    echo "预热 CDN 文件："
    call_api_logged "cdn" "prefetch" "错误：CDN 文件预热请求失败。" \
        -- cdn push-object-cache \
        --object-path "$path" || return 1
    echo "CDN 文件预热请求已提交。"
}

# 购买资源包功能（保持原有实现，但使用框架函数）
cdn_pay() {
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
        query_result=$(call_aliyun_api bssopenapi query-resource-package-instances \
            --product-code dcdn \
            --page-num "$page_num" \
            --page-size 100 2>/dev/null) || {
            echo -e "[CDN] ${color_red}查询资源包失败${color_reset}"
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

    # 检查是否获取到有效的剩余容量值
    if [ "$remaining_amount" = "-1" ]; then
        echo -e "[$(date +'%F %T')] ${color_red}无法获取资源包剩余容量信息${color_reset}"
        return 1
    fi

    # 显示剩余容量信息并判断是否需要购买
    local traffic_color_code="${color_red}" # 默认红色
    if (($(echo "$remaining_amount > $remaining_threshold" | bc -l))); then
        traffic_color_code="${color_green}" # 充足时显示绿色
    fi
    echo -e "[$(date +'%F %T')] 剩余下行流量: ${traffic_color_code}${remaining_amount:-0}TB${color_reset}"

    # 如果剩余容量充足，则跳过购买
    if (($(echo "$remaining_amount > $remaining_threshold" | bc -l))); then
        echo -e "[$(date +'%F %T')] ${color_green}剩余流量充足，跳过购买资源包${color_reset}"
        return 0
    fi

    # 查询账户可用余额（处理逗号分隔的数字）
    local available_balance
    local balance_result
    balance_result=$(call_aliyun_api bssopenapi query-account-balance)
    ret=$?
    if [ "$ret" -ne 0 ]; then
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
    log_result "${profile:-}" "${region:-}" "cdn" "pay" "当前剩余: ${remaining_amount:-0}TB，准备购买 $((package_size / package_unit_size))TB 资源包..."
    ## 特殊方式，修改为只买1TB时长1月的（1月的单价108¥，6-12月的单价126¥）
    echo -e "[$(date +'%F %T')] 购买 1TB 资源包..."
    echo "CDN 资源包购买："

    local _result
    _result=$(call_api_logged "cdn" "pay" "错误：CDN 资源包购买失败。" \
        -- bssopenapi CreateResourcePackage \
        --endpoint business.aliyuncs.com --force --version 2017-12-14 \
        --ProductCode dcdn \
        --PackageType FPT_dcdnpaybag_deadlineAcc_1541405199 \
        --Duration 1 \
        --PricingCycle Month \
        --Specification "$package_unit_size" 2>&1)

    # CLI 插件未实现此子命令时，fallback 到 curl 直调 RPC API
    if echo "$_result" | grep -q "unknown command"; then
        echo "CLI 插件暂不支持 create-resource-package，切换到 curl 直调..."
    else
        echo "$_result" >&2
        return
    fi

    # 从 aliyun 配置读取凭证
    local _prof_name="${profile:-$(jq -r '.current' "$HOME/.aliyun/config.json" 2>/dev/null)}"
    local _ak_id _ak_secret
    _ak_id=$(jq -r --arg p "$_prof_name" '.profiles[] | select(.name==$p) | .access_key_id' "$HOME/.aliyun/config.json")
    _ak_secret=$(jq -r --arg p "$_prof_name" '.profiles[] | select(.name==$p) | .access_key_secret' "$HOME/.aliyun/config.json")
    if [ -z "$_ak_id" ] || [ -z "$_ak_secret" ]; then
        echo "错误：无法从配置中获取凭证（profile: ${_prof_name}）" >&2
        return 1
    fi

    # 构建 RPC 请求参数
    local _nonce _timestamp
    _nonce=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null)
    _timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local -a _rp=()
    _rp+=(Action CreateResourcePackage)
    _rp+=(Version 2017-12-14)
    _rp+=(Format JSON)
    _rp+=(AccessKeyId "$_ak_id")
    _rp+=(SignatureMethod HMAC-SHA1)
    _rp+=(SignatureVersion 1.0)
    _rp+=(SignatureNonce "$_nonce")
    _rp+=(Timestamp "$_timestamp")
    _rp+=(ProductCode dcdn)
    _rp+=(PackageType FPT_dcdnpaybag_deadlineAcc_1541405199)
    _rp+=(Duration 1)
    _rp+=(PricingCycle Month)
    _rp+=(Specification "$package_unit_size")

    # 构造规范化查询字符串、计算 HMAC-SHA1 签名（一次 Python 调用）
    local _sign_result _qs _sig_enc
    _sign_result=$(python3 -c "
import urllib.parse, hmac, hashlib, base64, sys
params = sys.argv[1:]
pairs = sorted((urllib.parse.quote(k, safe=''), urllib.parse.quote(v, safe=''))
               for k, v in zip(params[::2], params[1::2]))
qs = '&'.join(k+'='+v for k, v in pairs)
sts = 'GET&' + urllib.parse.quote('/', safe='') + '&' + urllib.parse.quote(qs, safe='')
sig = base64.b64encode(hmac.new(
    (sys.argv[-1]+'&').encode(), sts.encode(), hashlib.sha1).digest()).decode()
print(qs)
print(urllib.parse.quote(sig, safe=''))
" "${_rp[@]}" "$_ak_secret")
    _qs=$(echo "$_sign_result" | head -1)
    _sig_enc=$(echo "$_sign_result" | tail -1)

    # 发起请求
    curl -s "https://business.aliyuncs.com/?${_qs}&Signature=${_sig_enc}" 2>&1 | jq '.'
}
