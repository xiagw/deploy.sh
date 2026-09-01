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
    echo "  logs [<域名>] [-s 开始] [-e 结束] [-f 格式] [--status 状态码] [-t 文件类型]"
    echo "                                         - 拉取 CDN 离线日志并分析（域名可选，可使用fzf选择；默认昨天）"
    echo "  prune [--days N] [--domain <域名>] [--bucket <桶名>] [--dry-run]"
    echo "                                         - 每日评估：按 CDN 日志找出 OSS 源站近 N 天无访问的目录，"
    echo "                                           自动备份到本地并生成删除脚本（不自动执行；默认 N=30）"
    echo "  pay [--dry-run]                         - 购买 CDN 资源包（自动判断余量；--dry-run 只展示不购买）"
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
    echo "  $0 cdn logs example.com                                 # 查昨天离线日志"
    echo "  $0 cdn logs example.com -s 2026-08-01 -e 2026-08-10 --status 404  # 按状态码分析"
    echo "  $0 cdn prune                                            # 每日评估：未访问目录 -> 备份 + 生成删除脚本"
    echo "  $0 cdn prune --dry-run                                  # 只分析不出手（首次运行先看）"
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
    logs) cdn_logs "$@" ;;
    prune) cdn_prune "$@" ;;
    pay) cdn_pay "$@" ;;
    help) show_cdn_help ;;
    *)
        echo "错误：未知的 CDN 操作：$operation" >&2
        show_cdn_help
        exit 1
        ;;
    esac
}

# 解析 CDN 域名（未提供时列表选择；cdn 为中心化服务，固定 --region cn-hangzhou）
_cdn_resolve_domain() {
    resolve_resource_id "$1" "${2:-选择 CDN 域名}" "错误：没有找到 CDN 域名。" \
        '.Domains.PageData[] | "\(.DomainName) (\(.Cname)) [\(.DomainStatus)]"' \
        -- cdn describe-user-domains --region cn-hangzhou
}

# 使用新框架的列表函数
cdn_list() {
    local format=${1:-human}

    local table_header="DomainName\tCname\tDomainStatus\tGmtCreated"
    local jq_filter=".Domains.PageData[] | [.DomainName, .Cname, .DomainStatus, .GmtCreated] | @tsv"
    # shellcheck disable=SC2016  # awk 程序需保留 $1..$4 字面量
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-20s  %-38s  %-6s  %s\n", $1, $2, $3, $4}'

    local result
    result=$(call_aliyun_api cdn describe-user-domains --region cn-hangzhou)
    local ret=$?

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
        -- cdn add-cdn-domain --region cn-hangzhou \
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
        -- cdn delete-cdn-domain --region cn-hangzhou --domain-name "$domain_name"
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
        -- cdn modify-cdn-domain --region cn-hangzhou \
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
        -- cdn refresh-object-caches --region cn-hangzhou \
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
            -- cdn refresh-object-caches --region cn-hangzhou \
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
        -- cdn push-object-cache --region cn-hangzhou \
        --object-path "$path" || return 1
    echo "CDN 文件预热请求已提交。"
}

# CDN 离线日志拉取与分析（数据源为 CDN API describe-cdn-domain-logs，无 --status 时仅列文件清单）
# 用法: cdn logs [<域名>] [-s YYYY-MM-DD] [-e YYYY-MM-DD] [-f human|json|tsv] [--status 404,500] [-t jpg,png]
cdn_logs() {
    local domain="" start_day="" end_day="" format="human" status_codes="" file_types=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -s | --start-date)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--start-date 选项需要指定日期" >&2
                return 1
            fi
            start_day="$2"
            shift 2
            ;;
        -e | --end-date)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--end-date 选项需要指定日期" >&2
                return 1
            fi
            end_day="$2"
            shift 2
            ;;
        -f | --format)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--format 选项需要指定格式（human/json/tsv）" >&2
                return 1
            fi
            format="$2"
            shift 2
            ;;
        --status)
            if [[ -z "$2" || "$2" == -* ]]; then
                status_codes="200,206,301,302,304,400,403,404,500,502,503,504"
            else
                status_codes="$2"
                shift 2
            fi
            ;;
        -t | --file-types | --types)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--file-types 选项需要指定文件类型（如 jpg,png,pdf）" >&2
                return 1
            fi
            file_types="$2"
            shift 2
            ;;
        -*)
            echo "错误：未知的选项：$1" >&2
            return 1
            ;;
        *)
            if [ -z "$domain" ]; then
                domain="$1"
                shift
            else
                echo "错误：多余的参数：$1" >&2
                return 1
            fi
            ;;
        esac
    done

    domain=$(_cdn_resolve_domain "$domain" "选择要查日志的 CDN 域名") || return 1

    # 业务日统一按上海时区（UTC+8）口径：昨天 = 上海昨天，cdn 日志窗口由其换算（见 _cdn_fetch_log_rows）
    if [ -z "$start_day" ]; then
        local today_epoch
        today_epoch=$(date +%s)
        start_day=$(_cdn_epoch_to_sh_day $((today_epoch - 86400)))
    fi
    end_day=${end_day:-$start_day}
    if ! _cdn_day_to_utc_epoch "$start_day" >/dev/null 2>&1 || ! _cdn_day_to_utc_epoch "$end_day" >/dev/null 2>&1; then
        echo "错误：日期格式无效，请使用 YYYY-MM-DD 格式" >&2
        return 1
    fi
    if [[ "$start_day" > "$end_day" ]]; then
        echo "错误：开始日期不能晚于结束日期" >&2
        return 1
    fi

    echo "CDN 离线日志：域名=$domain 日期=$start_day ~ $end_day"
    local rows
    rows=$(_cdn_fetch_log_rows "$domain" "$start_day" "$end_day") || return 1

    if [ -z "$rows" ]; then
        case "$format" in
        json) echo "[]" ;;
        tsv) echo -e "StartTime\tEndTime\tLogSize\tLogName" ;;
        *) echo "该时间段没有 CDN 离线日志。" ;;
        esac
        log_result "${profile:-}" "${region:-}" "cdn" "logs" "$rows" "$format"
        return 0
    fi

    case "$format" in
    json)
        echo "$rows" | jq -R -s '
            split("\n") | map(select(length > 0)) | map(split("\t") | {
                StartTime: .[0], EndTime: .[1], LogSize: .[2], LogName: .[3]
            })'
        ;;
    tsv)
        echo -e "StartTime\tEndTime\tLogSize\tLogName"
        echo "$rows"
        ;;
    human | *)
        echo "CDN 离线日志清单（$start_day ~ $end_day ）："
        echo "$rows" | awk -F'\t' '{printf "%-22s  %-22s  %-10s  %s\n", $1, $2, $3, $4}'
        if [ -n "$status_codes" ]; then
            echo
            echo "正在分析状态码 $status_codes 的记录 ..."
            local size name path
            while IFS=$'\t' read -r _ _ size name path; do
                echo "--------------------------------------------------"
                _cdn_analyze_log "$path" "$name" "$status_codes" "$file_types" "$domain" || continue
            done < <(echo "$rows")
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "cdn" "logs" "$rows" "$format"
}

# ---------- 时区工具：业务日统一按 UTC+8（上海）计算，纯 epoch 算术，不依赖系统 TZ ----------
# 日期字符串（YYYY-MM-DD）当 UTC 日零点解析成 epoch（这是确定性换算，非"本地时间"）
_cdn_day_to_utc_epoch() {
    local day=$1
    if [ "$(uname -s)" = "Darwin" ] && [ -x /usr/bin/date ]; then
        TZ=UTC /usr/bin/date -j -f "%Y-%m-%d" "$day" +%s 2>/dev/null && return 0
    fi
    if command -v gdate >/dev/null 2>&1; then
        gdate -u -d "$day" +%s 2>/dev/null && return 0
    fi
    TZ=UTC date -d "$day" +%s 2>/dev/null
}

# epoch -> UTC ISO8601
_cdn_epoch_to_utc_iso() {
    local epoch=$1
    if [ "$(uname -s)" = "Darwin" ] && [ -x /usr/bin/date ]; then
        TZ=UTC /usr/bin/date -r "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null && return 0
    fi
    if command -v gdate >/dev/null 2>&1; then
        gdate -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null && return 0
    fi
    TZ=UTC date -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

# epoch -> 上海日期（YYYY-MM-DD）
_cdn_epoch_to_sh_day() {
    local epoch=$1
    if [ "$(uname -s)" = "Darwin" ] && [ -x /usr/bin/date ]; then
        TZ=Asia/Shanghai /usr/bin/date -r "$epoch" +%F 2>/dev/null && return 0
    fi
    if command -v gdate >/dev/null 2>&1; then
        TZ=Asia/Shanghai gdate -d "@$epoch" +%F 2>/dev/null && return 0
    fi
    TZ=Asia/Shanghai date -d "@$epoch" +%F 2>/dev/null
}

# 上海时区今天
_cdn_sh_today() {
    _cdn_epoch_to_sh_day "$(date +%s)"
}

# 拉取域名指定日期范围的 CDN 离线日志清单（TSV 行：StartTime/EndTime/LogSize/LogName/LogPath）
# 日期为上海日期（UTC+8）；调用方已确保格式合法
# 输出到 stdout；失败返回非 0 且错误信息写 stderr
_cdn_fetch_log_rows() {
    local domain=$1 start_day=$2 end_day=$3
    local s_epoch e_epoch start_utc end_utc result ret
    s_epoch=$(_cdn_day_to_utc_epoch "$start_day") || { echo "错误：开始日期解析失败（$start_day）" >&2; return 1; }
    e_epoch=$(_cdn_day_to_utc_epoch "$end_day") || { echo "错误：结束日期解析失败（$end_day）" >&2; return 1; }
    start_utc=$(_cdn_epoch_to_utc_iso $((s_epoch - 28800))) || { echo "错误：开始日期转换失败" >&2; return 1; }
    end_utc=$(_cdn_epoch_to_utc_iso $((e_epoch + 57600))) || { echo "错误：结束日期转换失败" >&2; return 1; }

    result=$(call_aliyun_api cdn describe-cdn-domain-logs --region cn-hangzhou \
        --domain-name "$domain" \
        --start-time "$start_utc" \
        --end-time "$end_utc" \
        --page-size 1000 2>&1)
    ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：获取 CDN 离线日志失败（$domain）。" >&2
        echo "$result" >&2
        return 1
    fi

    echo "$result" | jq -r '
        .DomainLogDetails.DomainLogDetail[].LogInfos.LogInfoDetail[]
        | select(.LogPath != null)
        | [.StartTime, .EndTime, (.LogSize | tostring), .LogName, .LogPath] | @tsv' | sort
    return 0
}

# 下载并分析单个 CDN 离线日志（.gz）：状态码 + 文件类型过滤、排除敏感路径、URI 去重累积到本地缓存
_cdn_analyze_log() {
    local log_url=$1 log_name=$2 status_codes=$3
    local file_types=${4:-"mp3,mp4,avi,mov,wmv,flv,mkv,webm,jpg,jpeg,png,gif,bmp,tif,tiff,wof,tof,heic,webp,psd,ai,zip,rar,7z,tar,gz,iso,dmg,pdf,doc,docx,ppt,pptx,xls,xlsx,fbx"}
    local domain=$5
    local work_dir local_gz local_txt

    [[ "$log_url" != http* ]] && log_url="https://${log_url}"

    work_dir=$(mktemp -d)
    local_gz="${work_dir}/${log_name}"
    local_txt="${work_dir}/${log_name%.gz}"

    echo "正在下载日志: $log_name ..."
    if ! curl -sfL --connect-timeout 10 "$log_url" -o "$local_gz"; then
        echo "错误：下载日志失败: $log_name" >&2
        rm -rf "$work_dir"
        return 1
    fi
    echo "正在解压日志: $log_name ..."
    if ! gunzip -f "$local_gz"; then
        echo "错误：解压日志失败: $log_name" >&2
        rm -rf "$work_dir"
        return 1
    fi

    local file_regex status_regex exclude_grep filtered count uris_file
    file_regex="\.($(echo "$file_types" | tr ',' '|'))[\"' ]"
    status_regex="\" ($(echo "$status_codes" | tr ',' '|')) "
    exclude_grep='favicon.ico|robots.txt|sitemap.xml|.well-known/|apple-touch-icon|wp-login.php|wp-admin|admin.php|phpinfo.php|.git/|.env|.htaccess|shell.php|config.php|install.php|setup.php'

    filtered=$(grep -vE "$exclude_grep" "$local_txt" | grep -E "$status_regex" | grep -iE "$file_regex" || echo "")
    count=$(echo -n "$filtered" | grep -c '^')

    uris_file="${SCRIPT_DATA:-.}/cache/${profile:-}/${region:-}/cdn/global_uris_${status_codes//,/_}_${domain//./_}.txt"
    mkdir -p "$(dirname "$uris_file")"
    touch "$uris_file"

    echo "$filtered" | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /"GET|"POST/) {
                    url = $(i+1)
                    gsub(/^"|"$/, "", url)
                    sub(/^https?:\/\/[^\/]+/, "", url)
                    sub(/\?.*$/, "", url)
                    sub(/^\/+/, "/", url)
                    if (url != "" && url != "/" && url !~ /^[[:space:]]*$/) print url
                    break
                }
            }
        }' | sort -u >"${uris_file}.tmp"
    if [ -s "${uris_file}.tmp" ]; then
        sort -u "$uris_file" "${uris_file}.tmp" >"${uris_file}.merged" && mv "${uris_file}.merged" "$uris_file"
    fi
    rm -f "${uris_file}.tmp"

    echo "发现状态码 $status_codes 的记录 $count 条"
    echo "$log_name 唯一 URI 列表已累积到: $uris_file （共 $(wc -l <"$uris_file") 条）"

    rm -rf "$work_dir"
}

# 从路径流提取 <=3 层目录前缀（去末尾文件名字段）并去重
# 输入每行一个 URL 路径（/a/b/c/f.jpg）或 OSS key（a/b/c/f.jpg），两端规则一致保证可比
# 根级单段路径（无子级）视作文件，不输出
_cdn_extract_dir_prefixes() {
    awk -F/ '
        {
            k = NF
            if ($1 == "") k--
            if (k <= 1) next
            if ($NF != "") k--
            if (k > 3) k = 3
            prefix = ""
            for (i = 1; i <= NF && k > 0; i++) {
                if ($i == "") continue
                prefix = prefix "/" $i
                k--
            }
            if (prefix != "") print prefix
        }' | sort -u
}

# 查询 bucket 所在区域（从 ossutil ls 全部桶输出的 Region 列，去掉 oss- 前缀），失败回退 profile 区域
_cdn_bucket_region() {
    local bucket=$1 map
    map=$(aliyun --profile "${profile:-}" ossutil ls --endpoint "http://oss-${region:-cn-hangzhou}.aliyuncs.com" --region "${region:-cn-hangzhou}" 2>/dev/null |
        awk '$4 == "CST" {print $NF, $5}')
    local r
    r=$(echo "$map" | awk -v b="oss://$bucket" '$1 == b {print $2}' | sed 's/^oss-//')
    echo "${r:-${region:-cn-hangzhou}}"
}

# 抓取某域名某上海日期日志并归档访问目录/异常 URI 档案（覆盖写）；成功 0
# 无日志时：archive_empty=1 建空档案（主任务语义=当天已评估过）；否则不建档案返回 2（补档语义=数据不可得）
_cdn_fetch_parse_domain_day() {
    local domain=$1 day=$2 archive_empty=${3:-0}
    local prune_dir access_file abnormal_file rows log_name log_path
    prune_dir="${SCRIPT_DATA:-.}/cache/${profile:-}/${region:-}/cdn/prune"
    access_file="${prune_dir}/access/${domain}/${day}.txt"
    abnormal_file="${prune_dir}/abnormal/${domain}/${day}.txt"

    rows=$(_cdn_fetch_log_rows "$domain" "$day" "$day") || return 1
    mkdir -p "$(dirname "$access_file")" "$(dirname "$abnormal_file")"
    if [ -z "$rows" ]; then
        if [ "$archive_empty" -eq 1 ]; then
            : >"$access_file"
            : >"$abnormal_file"
            return 0
        fi
        return 2
    fi

    : >"$access_file"
    : >"$abnormal_file"
    while IFS=$'\t' read -r _ _ _ log_name log_path; do
        [ -z "$log_path" ] && continue
        [[ "$log_path" != http* ]] && log_path="https://${log_path}"
        echo "   $domain : $log_name"
        local pipe_ok
        curl -sfL --connect-timeout 10 "$log_path" 2>/dev/null |
            gunzip -c 2>/dev/null |
            awk -v af="$access_file" -v ab="$abnormal_file" '
                {
                    for (i = 1; i <= NF; i++) {
                        if ($i ~ /^"(GET|POST|HEAD)$/) {
                            url = $(i + 1)
                            gsub(/^"|"$/, "", url)
                            sub(/^https?:\/\/[^\/]+/, "", url)
                            sub(/\?.*$/, "", url)
                            status = $(i + 2)
                            if (url != "" && url != "/") {
                                n = split(url, seg, "/")
                                if (n > 1 && seg[n] != "") n--
                                if (n > 3) n = 3
                                prefix = ""
                                for (j = 1; j <= n; j++) {
                                    if (seg[j] == "") continue
                                    prefix = prefix "/" seg[j]
                                }
                                if (prefix != "") print prefix >> af
                                if (status ~ /^[45][0-9][0-9]$/) print status, url >> ab
                            }
                            break
                        }
                    }
                }'
        pipe_ok=${PIPESTATUS[0]}
        if [ "$pipe_ok" -ne 0 ]; then
            echo "警告：$log_name 下载失败，跳过" >&2
        fi
    done < <(echo "$rows")
    sort -u -o "$access_file" "$access_file"
    sort -u -o "$abnormal_file" "$abnormal_file"
    return 0
}

# 备份候选目录（stdin 每行一个 /前缀）到本地并校验对象数一致，通过的追加 rm 命令到删除脚本
# 参数: bucket bregion script_file back_dir
# 校验口径：ossutil cp -r 成功且备份目录内存在文件（无全量对象清单时不再做精确计数比对）
_cdn_backup_and_script() {
    local bucket=$1 bregion=$2 script_file=$3 back_dir=$4
    local added=0 p target local_cnt
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        target="${back_dir}${p}"
        mkdir -p "$target"
        echo "    备份 -> $target ..."
        if aliyun --profile "${profile:-}" ossutil cp -r --endpoint "http://oss-${bregion}.aliyuncs.com" --region "$bregion" "oss://${bucket}${p}/" "$target/" >/dev/null 2>&1; then
            local_cnt=$(find "$target" -type f | wc -l | tr -d ' ')
            if [ "$local_cnt" -gt 0 ]; then
                {
                    echo ""
                    echo "# ${p}（本地备份 ${local_cnt} 个文件）"
                    echo "echo \"删除 oss://${bucket}${p}/\""
                    echo "aliyun --profile \"${profile:-}\" ossutil rm -r -f --endpoint \"http://oss-${bregion}.aliyuncs.com\" --region \"$bregion\" \"oss://${bucket}${p}/\""
                } >>"$script_file"
                added=$((added + 1))
            else
                echo "    警告：$p 备份后无文件（目录可能为空），不加入删除脚本" >&2
            fi
        else
            echo "    警告：$p 备份失败，不加入删除脚本" >&2
        fi
    done
    if [ "$added" -eq 0 ]; then
        rm -f "$script_file"
        echo "  备份均失败或无有效候选，未生成脚本"
    else
        echo "  生成删除脚本: $script_file （$added 条）"
    fi
}

# 递归列出 bucket 的 <=3 层目录清单（ossutil ls -d 逐层，秒级）；输出 /a/b 形式（前导斜杠、去尾斜杠）
# 每个 ls 调用带 30s 超时保护：单个目录拉取挂起/失败时跳过该目录继续（不卡死整棵树）
_cdn_bucket_dir_tree() {
    local bucket=$1 bregion=$2
    local base="oss://${bucket}/"
    local level=("")
    local depth=0 out=""
    while [ "$depth" -lt 3 ] && [ "${#level[@]}" -gt 0 ]; do
        local next=() p sub
        for p in "${level[@]}"; do
            local lsurl="${base}${p:+${p}/}"
            local dirs
            dirs=$(timeout 30 aliyun --profile "${profile:-}" ossutil ls --endpoint "http://oss-${bregion}.aliyuncs.com" --region "$bregion" "$lsurl" -d 2>/dev/null |
                awk -v pre="$lsurl" '
                    $1 ~ /^oss:\/\// && $1 ~ /\/$/ && index($1, pre) == 1 {
                        sub(/\/$/, "", $1)
                        print substr($1, length(pre) + 1)
                    }')
            while IFS= read -r sub; do
                [ -z "$sub" ] && continue
                out+="${out:+$'\n'}/${p:+${p}/}${sub}"
                next+=("${p:+${p}/}${sub}")
            done <<<"$dirs"
        done
        level=("${next[@]}")
        depth=$((depth + 1))
    done
    [ -n "$out" ] && echo -e "$out" | sort -u
}

# 每日评估任务（数据源 CDN 离线日志，源站 OSS）：
#   拉昨日日志 -> 提取 <=3 层目录访问集 + 4xx/5xx 异常 URI -> 与 OSS 桶对象目录比对
#   -> 近 --days 天无访问的目录自动备份到本地 -> 生成删除脚本（不自动执行）
# 用法: cdn prune [--days N] [--domain <域名>] [--bucket <桶名>] [-s YYYY-MM-DD] [-e YYYY-MM-DD] [--dry-run]
cdn_prune() {
    local days=30 domain_filter="" bucket_filter="" start_day="" end_day="" dry_run=0
    local today_epoch today prune_dir back_root

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --days)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--days 选项需要指定天数" >&2
                return 1
            fi
            days="$2"
            shift 2
            ;;
        --domain) domain_filter="$2"; shift 2 ;;
        --bucket) bucket_filter="$2"; shift 2 ;;
        -s | --start-date) start_day="$2"; shift 2 ;;
        -e | --end-date) end_day="$2"; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        -h | --help)
            echo "用法: cdn prune [--days N] [--domain <域名>] [--bucket <桶名>] [-s 开始] [-e 结束] [--dry-run]"
            return 0
            ;;
        *)
            echo "错误：未知的选项：$1" >&2
            return 1
            ;;
        esac
    done

    if ! [ "$days" -gt 0 ] 2>/dev/null; then
        echo "错误：--days 必须是正整数" >&2
        return 1
    fi

    # 业务日统一按上海时区（UTC+8）口径：昨天 = 上海昨天（不依赖系统 TZ）
    today_epoch=$(date +%s)
    today=$(_cdn_epoch_to_sh_day "$today_epoch") || { echo "错误：无法计算今天日期" >&2; return 1; }
    start_day=${start_day:-$(_cdn_epoch_to_sh_day $((today_epoch - 86400)))}
    end_day=${end_day:-$start_day}
    if ! _cdn_day_to_utc_epoch "$start_day" >/dev/null 2>&1 || ! _cdn_day_to_utc_epoch "$end_day" >/dev/null 2>&1; then
        echo "错误：日期格式无效，请使用 YYYY-MM-DD 格式" >&2
        return 1
    fi
    if [[ "$start_day" > "$end_day" ]]; then
        echo "错误：开始日期不能晚于结束日期" >&2
        return 1
    fi

    prune_dir="${SCRIPT_DATA:-.}/cache/${profile:-}/${region:-}/cdn/prune"
    back_root="${SCRIPT_DATA:-.}/prune-backup"
    mkdir -p "$prune_dir" "$back_root"

    echo "===== CDN 日志清理评估：范围=$start_day ~ $end_day （上海时区）/ 未访问阈值=$days 天 / dry-run=$dry_run ====="

    # 1. 发现 OSS 源站域名（按源站 bucket 分组）
    local domain_info
    domain_info=$(call_aliyun_api cdn describe-user-domains --region cn-hangzhou 2>/dev/null | jq -r '
        .Domains.PageData[] | .DomainName as $d
        | .Sources.Source[]? | select(.Type == "oss")
        | [$d, (.Content | split(".")[0])] | @tsv' 2>/dev/null)
    if [ -n "$domain_filter" ]; then
        domain_info=$(echo "$domain_info" | awk -v d="$domain_filter" '$1 == d')
    fi
    if [ -n "$bucket_filter" ]; then
        domain_info=$(echo "$domain_info" | awk -v b="$bucket_filter" '$2 == b')
    fi
    if [ -z "$domain_info" ]; then
        echo "没有匹配的 OSS 源站 CDN 域名。"
        return 0
    fi
    echo "OSS 源站域名："
    echo "$domain_info" | awk -F'\t' '{printf "  %-20s -> %s\n", $1, $2}'

    # 2. 拉日志归档：主任务日期范围 + 窗口内自动补档缺失天
    local access_base="${prune_dir}/access"
    local abnormal_base="${prune_dir}/abnormal"
    mkdir -p "$access_base" "$abnormal_base"

    echo "== 拉取并解析访问日志 =="
    local d
    while IFS=$'\t' read -r d _; do
        [ -z "$d" ] && continue
        # 补档策略（应对中断）：仅当窗口内已有档案时执行（冷启动不补，反正覆盖不足只记录），
        # 从昨天往前跳过已有档案，单次运行最多补 3 天（渐进补齐，避免单次下载过量）
        local i date2 i_min
        i_min=$((days - 1))
        [ "$i_min" -gt 28 ] && i_min=28
        local have_any=0 backfilled=0
        for i in $(seq 1 "$i_min"); do
            date2=$(_cdn_epoch_to_sh_day $((today_epoch - i * 86400)))
            [ -f "${access_base}/${d}/${date2}.txt" ] && {
                have_any=1
                break
            }
        done
        if [ "$have_any" -eq 1 ]; then
            for i in $(seq 1 "$i_min"); do
                date2=$(_cdn_epoch_to_sh_day $((today_epoch - i * 86400)))
                [ -f "${access_base}/${d}/${date2}.txt" ] && continue
                [ "$backfilled" -ge 3 ] && break
                echo "  自动补档 $d $date2 ..."
                local fb_ret
                _cdn_fetch_parse_domain_day "$d" "$date2"
                fb_ret=$?
                if [ "$fb_ret" -ne 0 ] && [ "$fb_ret" -ne 2 ]; then
                    echo "    警告：$d $date2 补档失败" >&2
                fi
                backfilled=$((backfilled + 1))
            done
        fi

        # 主任务：start_day ~ end_day 建档（档案已存在则复用，同一天重复运行不重复下载）
        local day_cursor day_end_ep af_main main_ok
        day_end_ep=$(_cdn_day_to_utc_epoch "$end_day")
        day_cursor=$(_cdn_day_to_utc_epoch "$start_day")
        main_ok=1
        while [ "$day_cursor" -le "$day_end_ep" ]; do
            date2=$(_cdn_epoch_to_sh_day "$day_cursor")
            af_main="${access_base}/${d}/${date2}.txt"
            if [ ! -f "$af_main" ]; then
                local main_ret
                _cdn_fetch_parse_domain_day "$d" "$date2" 1
                main_ret=$?
                if [ "$main_ret" -ne 0 ]; then
                    echo "    警告：$d $date2 主任务日志拉取失败，跳过该天" >&2
                    main_ok=0
                fi
            fi
            day_cursor=$((day_cursor + 86400))
        done
        [ "$main_ok" -eq 0 ] && continue
        echo "  $d 覆盖 $start_day ~ $end_day，昨日访问目录 $(wc -l <"${access_base}/${d}/${start_day}.txt" | tr -d ' ') 个，异常 URI $(wc -l <"${abnormal_base}/${d}/${start_day}.txt" | tr -d ' ') 条"
    done < <(echo "$domain_info")

    # 3. 每个 bucket：对象目录前缀 与 近 N 天访问目录并集 比对
    local buckets bucket
    buckets=$(echo "$domain_info" | awk -F'\t' '{print $2}' | sort -u)
    echo "== 比对 OSS 目录（${buckets//$'\n'/ } ）=="
    for bucket in $buckets; do
        local bregion oss_prefixes union_file candidates domains_of_bucket
        bregion=$(_cdn_bucket_region "$bucket")
        domains_of_bucket=$(echo "$domain_info" | awk -F'\t' -v b="$bucket" '$2 == b {print $1}')

        # 冷启动/中断后档案不足：本轮仅记录（不拉对象清单、不比对、不备份、不生成脚本）
        local covered_days=0 i date2 d2 access_file2
        for i in $(seq 1 "$days"); do
            date2=$(_cdn_epoch_to_sh_day $((today_epoch - i * 86400)))
            for d2 in $domains_of_bucket; do
                [ -f "${access_base}/${d2}/${date2}.txt" ] && {
                    covered_days=$((covered_days + 1))
                    break
                }
            done
        done
        if [ "$covered_days" -lt "$days" ]; then
            echo "  档案覆盖 $covered_days/$days 天，数量不足：本轮仅记录不评估（自动补档已完成，剩余缺失天超出 CDN 日志保留期）"
            echo
            continue
        fi

        # 目录清单按日缓存（ossutil ls -d 逐层 ≤3 层；prune 每日一次，同日重复运行复用；tmp+mv 原子写防半截缓存）
        local objects_cache
        objects_cache="${prune_dir}/objects/${bucket}/${today}.txt"
        mkdir -p "$(dirname "$objects_cache")"
        if [ -s "$objects_cache" ]; then
            echo "-- bucket=$bucket （region=$bregion ）复用当日目录清单缓存 ..."
            oss_prefixes=$(cat "$objects_cache")
        else
            echo "-- bucket=$bucket （region=$bregion ）拉取目录清单（≤3 层）并缓存 ..."
            oss_prefixes=$(_cdn_bucket_dir_tree "$bucket" "$bregion")
            if [ -z "$oss_prefixes" ]; then
                echo "警告：$bucket 目录清单为空（权限/区域问题），跳过" >&2
                continue
            fi
            echo "$oss_prefixes" >"${objects_cache}.tmp" && mv "${objects_cache}.tmp" "$objects_cache"
        fi

        union_file=$(mktemp)
        for i in $(seq 1 "$days"); do
            date2=$(_cdn_epoch_to_sh_day $((today_epoch - i * 86400)))
            for d2 in $domains_of_bucket; do
                access_file2="${access_base}/${d2}/${date2}.txt"
                [ -f "$access_file2" ] && cat "$access_file2"
            done
        done | sort -u >"$union_file"

        # 保护：访问前缀的所有祖先链也视为已访问（防止父目录候选清掉访问过的子目录）
        local blocked
        blocked=$(cat "$union_file" | awk -F/ '{
            p = ""
            for (i = 1; i <= NF; i++) {
                if ($i == "") continue
                p = p "/" $i
                print p
            }
        }' | sort -u)
        candidates=$(comm -23 <(echo "$oss_prefixes") <(echo "$blocked"))
        rm -f "$union_file"

        local n_cand p
        n_cand=$(echo -n "$candidates" | awk 'NF {c++} END {print c+0}')
        if [ "$n_cand" -eq 0 ]; then
            echo "  无候选目录"
            continue
        fi
        echo "  候选未访问目录 $n_cand 个："
        local script_file back_dir
        back_dir="${back_root}/${today}/${bucket}"
        script_file="${prune_dir}/rm-${today}-${bucket}.sh"
        if [ "$dry_run" -eq 1 ]; then
            echo "$candidates" | awk '{print "  " $0}'
        else
            mkdir -p "$back_dir"
            cat >"$script_file" <<EOF
#!/usr/bin/env bash
# 生成时间: $today  来源: cdn prune --days $days（范围 $start_day ~ $end_day ）
# 备份目录: $back_dir   人工复核后执行删除
set -e
EOF
            chmod +x "$script_file"
            _cdn_backup_and_script "$bucket" "$bregion" "$script_file" "$back_dir" <<<"$candidates"
        fi
    done

    # 4. 异常 URI 汇总
    echo "== 异常 URI（4xx/5xx）记录 =="
    local total_ab=0 f dname n
    for f in "${abnormal_base}"/*/"${start_day}.txt"; do
        [ -f "$f" ] || continue
        dname=$(basename "$(dirname "$f")")
        n=$(wc -l <"$f" | tr -d ' ')
        total_ab=$((total_ab + n))
        echo "  $dname : $n 条 -> $f"
    done
    [ "$total_ab" -eq 0 ] && echo "  无 4xx/5xx 记录"

    echo "===== 完成：备份目录 $back_root ；脚本目录 $prune_dir ====="
}

# 购买资源包功能（保持原有实现，但使用框架函数）
# 用法: cdn_pay [--dry-run]   --dry-run 仅计算余量/价格并展示，不真正下单（便于调试）
cdn_pay() {
    local color_reset="\033[0m"
    local color_green="\033[0;32m"
    local color_red="\033[0;31m"

    local dry_run=0
    case "${1:-}" in
    --dry-run) dry_run=1 ;;
    "")
        : ;;
    *)
        echo "错误：未知参数：$1" >&2
        echo "用法：cdn pay [--dry-run]" >&2
        return 1
        ;;
    esac

    # 资源包规格和价格配置
    local package_unit_size=1024 # 1TB = 1024GB
    local package_unit_price=126 # 每 TB 单价 126 元

    # 阈值配置
    local remaining_threshold=4.000 # 剩余容量阈值 4TB
    local balance_threshold=700     # 账户余额阈值 700 元

    # 查询当前资源包剩余容量（--pager 自动合并全部分页）
    local query_result
    local remaining_amount=0
    local remaining_https_request=0

    query_result=$(call_aliyun_api bssopenapi query-resource-package-instances --region cn-hangzhou --product-code dcdn --pager path=Data.Instances.Instance 2>/dev/null) || {
        echo -e "[CDN] ${color_red}查询资源包失败${color_reset}"
        return 1
    }

    remaining_amount="$(
        echo "$query_result" | jq -r '(.Data.Instance // [])[] | select(.RemainingAmount != "0" and .RemainingAmountUnit != "次") | if .RemainingAmountUnit == "GB" then (. | .RemainingAmount | tonumber) / 1024 elif .RemainingAmountUnit == "TB" then (. | .RemainingAmount | tonumber) else 0 end' | awk '{s+=$1} END {printf "%.3f", s}' 2>/dev/null || echo "-1"
    )"
    remaining_https_request="$(
        echo "$query_result" | jq -r '(.Data.Instance // [])[] | select(.RemainingAmount != "0" and .RemainingAmountUnit == "次") | .RemainingAmount' | awk '{s+=$1} END {printf "%.0f", s}' 2>/dev/null || echo "0"
    )"

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
    balance_result=$(call_aliyun_api bssopenapi query-account-balance --region cn-hangzhou)
    local ret=$?
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
    ## 显示实际可购买量
    ## 特殊方式，修改为只买1TB时长1月的（1月的单价108¥，6-12月的单价126¥）
    local unit_price_1month=108
    echo -e "[$(date +'%F %T')] 按当前余额最多可购买 $((package_size / package_unit_size))TB，本次购买 1TB 资源包（1个月，单价 ${unit_price_1month} 元）..."

    if [ "$dry_run" -eq 1 ]; then
        echo -e "[$(date +'%F %T')] [DRY-RUN] 仅展示，未下单。确认无误后去掉 --dry-run 再执行。"
        return 0
    fi
    ## 跑在 crontab 里，不能阻止自动化
    # if ! confirm_action "确认购买 CDN 资源包（1TB / 1 个月，约 ${package_unit_price} 元）？"; then
    #     return 1
    # fi

    echo "CDN 资源包购买："

    local _result _ret
    _result=$(call_api_logged "cdn" "pay" "错误：CDN 资源包购买失败。" \
        -- bssopenapi CreateResourcePackage \
        --endpoint business.aliyuncs.com --force --version 2017-12-14 \
        --ProductCode dcdn \
        --PackageType FPT_dcdnpaybag_deadlineAcc_1541405199 \
        --Duration 1 \
        --PricingCycle Month \
        --Specification "$package_unit_size" 2>&1)
    _ret=$?

    # CLI 插件未实现此子命令时，fallback 到 curl 直调 RPC API
    if echo "$_result" | grep -q "unknown command"; then
        echo "CLI 插件暂不支持 create-resource-package，切换到 curl 直调..."
    elif [ "$_ret" -eq 0 ]; then
        echo "$_result"
        return 0
    else
        echo "$_result" >&2
        return 1
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
