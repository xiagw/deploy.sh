#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 通用工具函数

# 比较语义化版本：$1 >= $2 时返回 0
_version_ge() {
    local left=$1
    local right=$2
    [[ "$(printf '%s\n' "$right" "$left" | sort -V | head -1)" == "$right" ]]
}

check_dependencies() {
    if ! command -v aliyun &>/dev/null; then
        echo "错误：未安装阿里云 CLI。请先安装阿里云 CLI。" >&2
        exit 1
    fi

    local aliyun_version
    aliyun_version=$(aliyun version 2>/dev/null | head -1 | tr -d '[:space:]')
    if [ -z "$aliyun_version" ] || ! _version_ge "$aliyun_version" "3.4.0"; then
        echo "错误：需要阿里云 CLI >= 3.4.0（当前：${aliyun_version:-未知}）。" >&2
        echo "请执行 'aliyun upgrade' 或重新安装：https://help.aliyun.com/zh/cli/install-update-alibaba-cloud-cli" >&2
        exit 1
    fi

    # CLI 3.4 的产品插件默认仍需要在非交互环境中显式开启自动安装。
    export ALIBABA_CLOUD_CLI_PLUGIN_AUTO_INSTALL=true
    # 与 base.sh 中的 --auto-plugin-install-enable-pre 保持一致。
    export ALIBABA_CLOUD_CLI_PLUGIN_AUTO_INSTALL_ENABLE_PRE=true

    if ! aliyun configure list &>/dev/null; then
        echo "错误：未设置阿里云凭证。请先运行 'aliyun configure' 设置凭证。" >&2
        exit 1
    fi
}

show_help() {
    echo "用法: $0 [--profile <配置名>] [--region <地域>] <服务> <操作> [参数...]"
    echo
    echo "可用服务:"
    echo "  get-all - 列出所有服务的资源"
    echo "  ecs      - 弹性计算服务"
    echo "  oss      - 对象存储服务"
    echo "  domain   - 域名服务"
    echo "  dns      - 域名解析服务"
    echo "  cdn      - 内容分发网络"
    echo "  lbs      - 负载均衡服务"
    echo "  rds      - 关系型数据库服务"
    echo "  polardb  - 云数据库 PolarDB"
    echo "  kvstore  - 云数据库 Redis(KVStore)"
    echo "  vpc      - 专有网络"
    echo "  nat      - NAT网关"
    echo "  eip      - 弹性公网IP"
    echo "  cas      - 证书服务"
    echo "  ram      - 访问控制"
    echo "  nas      - 文件存储"
    echo "  ack      - 容器服务 Kubernetes 版"
    echo "  config   - 配置管理"
    echo "  region   - 地域列表查询"
    echo "  balance  - 账户余额查询"
    echo "  cost     - 费用查询"
    echo
    echo "每个服务的具体操作和参数，请使用 '$0 <服务>' 查看"
    echo
    echo "全局选项:"
    echo "  --profile <配置名>  使用指定的配置文件"
    echo "  --region <地域>     指定操作的地域"
}

save_data_file() {
    local profile=$1
    local region=$2
    local service=$3
    local operation=$4
    local data=$5
    local filename=$6

    local data_dir="${SCRIPT_DATA:? ERR: SCRIPT_DATA empty}/cache/${profile}/${region}/${service}"
    local data_file="${data_dir}/${filename}"

    mkdir -p "$data_dir"
    echo "$data" >"$data_file"
    echo "数据已保存到文件: $data_file"
}

log_result() {
    local profile=$1
    local region=$2
    local service=$3
    local operation=$4
    local result=$5
    local format=${6:-human}

    local log_dir="${SCRIPT_DATA}/logs/aliyun/${profile}/${region}"
    local log_file="${log_dir}/${service}.log"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local unique_id
    unique_id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$$")

    mkdir -p "$log_dir"
    {
        echo -e "\n==== Execution: $timestamp - $unique_id - Operation: $operation ===="
        echo "Format: $format"
        if [ -z "$result" ]; then
            echo "(无返回内容)"
        elif [ "$format" = "json" ]; then
            echo "$result" | jq '.' 2>/dev/null || echo "$result"
        elif [ "$service" = "oss" ] && [ "$operation" = "list" ]; then
            echo "$result"
        elif [ "$service" = "ram" ] && [ "$operation" = "grant-permission" ]; then
            echo "${result//\\n/$'\n'}" # 将 \n 替换为实际的换行
        else
            echo "$result" | jq '.' 2>/dev/null || echo "$result"
        fi
        echo -e "==== End of Execution: $timestamp - $unique_id - Operation: $operation ====\n"
    } >>"$log_file"
}

log_delete_operation() {
    local profile=$1
    local region=$2
    local service=$3
    local resource_id=$4
    local resource_name=$5
    local status=$6
    local result=${7:-}
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local unique_id
    unique_id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$$")

    local log_dir="${SCRIPT_DATA}/logs/aliyun/${profile}/${region}"
    local log_file="${log_dir}/${service}.log"

    mkdir -p "$log_dir"
    {
        echo -e "\n==== Execution: $timestamp - $unique_id - Operation: delete ===="
        echo "Delete: $service | $resource_id | $resource_name | $status"
        if [ -z "$result" ]; then
            echo "(无返回内容)"
        else
            echo "$result" | jq '.' 2>/dev/null || echo "$result"
        fi
        echo -e "==== End of Execution: $timestamp - $unique_id - Operation: delete ====\n"
    } >>"$log_file"
    echo "删除操作日志已保存到 $log_file"
}

check_fzf() {
    if ! command -v fzf &>/dev/null; then
        echo "错误：fzf 未安装。请安装 fzf 或直接提供参数。" >&2
        exit 1
    fi
}

select_with_fzf() {
    local prompt=$1
    local options=$2
    shift 2
    local args=("$@") # 获取额外的参数，比如 -m

    check_fzf

    local selected
    selected=$(echo "$options" | fzf --height=50% --prompt="$prompt: " "${args[@]}")
    if [ -z "$selected" ]; then
        echo "未选择选项，操作取消。" >&2
        exit 1
    fi
    echo "$selected"
}

get_credentials() {
    local profile=$1
    local config_file="$HOME/.aliyun/config.json"
    local access_key_id=""
    local access_key_secret=""
    local region=""

    # 首先检查环境变量
    if [ -n "$ALICLOUD_ACCESS_KEY_ID" ] && [ -n "$ALICLOUD_ACCESS_KEY_SECRET" ]; then
        access_key_id=$ALICLOUD_ACCESS_KEY_ID
        access_key_secret=$ALICLOUD_ACCESS_KEY_SECRET
        region=${ALICLOUD_REGION_ID:-}
    fi

    # 如果环境变量中没有凭证，则从 config.json 文件中读取
    if [ -z "$access_key_id" ] || [ -z "$access_key_secret" ]; then
        if [ -f "$config_file" ]; then
            access_key_id=$(jq -r ".profiles[] | select(.name == \"$profile\") | .access_key_id" "$config_file")
            access_key_secret=$(jq -r ".profiles[] | select(.name == \"$profile\") | .access_key_secret" "$config_file")
            region=$(jq -r ".profiles[] | select(.name == \"$profile\") | .region_id" "$config_file")
        fi
    fi

    # 如果仍然没有找到凭证，则报错
    if [ -z "$access_key_id" ] || [ -z "$access_key_secret" ]; then
        echo "错误：无法获取 Aliyun 凭证。请确保设置了正确的环境变量或 config.json 文件。" >&2
        exit 1
    fi

    # 如果没有找到 region，使用默认值
    if [ -z "$region" ]; then
        region="cn-hangzhou"
    fi

    # 将凭证信息存入 config.json 文件（如果文件不存在或信息不完整）
    if [ ! -f "$config_file" ] || [ "$(jq ".profiles | length" "$config_file")" -eq 0 ]; then
        mkdir -p "$(dirname "$config_file")"
        echo '{
            "current": "",
            "profiles": [
                {
                    "name": "'"$profile"'",
                    "mode": "AK",
                    "access_key_id": "'"$access_key_id"'",
                    "access_key_secret": "'"$access_key_secret"'",
                    "region_id": "'"$region"'"
                }
            ]
        }' >"$config_file"
    fi
}

create_profile() {
    local name=$1
    local access_key_id=$2
    local access_key_secret=$3
    local region_id=${4:-cn-hangzhou}
    local config_file="$HOME/.aliyun/config.json"

    if [ -f "$config_file" ]; then
        jq --arg name "$name" \
            --arg key "$access_key_id" \
            --arg secret "$access_key_secret" \
            --arg region "$region_id" \
            '.profiles += [{"name": $name, "mode": "AK", "access_key_id": $key, "access_key_secret": $secret, "region_id": $region}]' "$config_file" >"${config_file}.tmp" &&
            mv "${config_file}.tmp" "$config_file"
    else
        mkdir -p "$(dirname "$config_file")"
        echo '{
            "current": "",
            "profiles": [
                {
                    "name": "'"$name"'",
                    "mode": "AK",
                    "access_key_id": "'"$access_key_id"'",
                    "access_key_secret": "'"$access_key_secret"'",
                    "region_id": "'"$region_id"'"
                }
            ]
        }' >"$config_file"
    fi
    echo "配置文件已创建/更新。"
}

update_profile() {
    local name=$1
    local access_key_id=$2
    local access_key_secret=$3
    local region_id=${4:-cn-hangzhou}
    local config_file="$HOME/.aliyun/config.json"

    if [ -f "$config_file" ]; then
        jq --arg name "$name" \
            --arg key "$access_key_id" \
            --arg secret "$access_key_secret" \
            --arg region "$region_id" \
            '(.profiles[] | select(.name == $name)) |= {"name": $name, "mode": "AK", "access_key_id": $key, "access_key_secret": $secret, "region_id": $region}' "$config_file" >"${config_file}.tmp" &&
            mv "${config_file}.tmp" "$config_file"
        echo "配置文件已更新。"
    else
        echo "配置文件不存在，无法更新。"
    fi
}

delete_profile() {
    local name=$1
    local config_file="$HOME/.aliyun/config.json"

    if [ -f "$config_file" ]; then
        jq --arg name "$name" 'del(.profiles[] | select(.name == $name))' "$config_file" >"${config_file}.tmp" &&
            mv "${config_file}.tmp" "$config_file"
        echo "配置文件已删除。"
    else
        echo "配置文件不存在，无法删除。"
    fi
}

query_account_balance() {
    local format=${1:-human}

    local result
    result=$(call_aliyun_api bssopenapi query-account-balance)
    ret=$?
    if [ $ret -eq 0 ]; then
        case "$format" in
        json)
            # JSON 格式不显示提示信息，直接输出结果
            echo "$result"
            ;;
        tsv)
            echo "查询账户余额tsv："
            echo -e "可用余额\t货币单位"
            echo "$result" | jq -r '[.Data.AvailableAmount, .Data.Currency] | @tsv'
            ;;
        human | *)
            echo "查询账户余额："
            local available_amount currency
            available_amount=$(echo "$result" | jq -r '.Data.AvailableAmount')
            currency=$(echo "$result" | jq -r '.Data.Currency')
            echo "可用余额: $available_amount $currency"
            ;;
        esac
    else
        echo "错误：无法查询账户余额。"
        echo "$result"
    fi
    log_result "${profile:-}" "${region:-}" "account" "balance" "$result" "$format"
}

show_balance_help() {
    echo "账户余额操作："
    echo "  get [format]            - 查询账户余额，format 可选 human/json/tsv"
    echo "  warn [daily 150] [balance 3000] - 检查账户余额并在低于阈值时发出告警"
    echo
    echo "示例："
    echo "  $0 balance get          # 人类可读格式"
    echo "  $0 balance get json     # JSON 格式"
    echo "  $0 balance get tsv      # TSV 格式"
    echo "  $0 balance warn           # 检查余额并告警"
    echo "  $0 balance warn daily 150 balance 3000 # 检查余额并告警，设置阈值"
}

handle_balance_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) query_account_balance "$@" ;;
    warn) balance_check "$@" ;;
    *)
        echo "错误：未知的余额操作：$operation" >&2
        show_balance_help
        exit 1
        ;;
    esac
}

balance_check() {
    local current_balance alarm_balance alarm_daily yesterday current_month daily_spending msg_body

    alarm_balance=${ALARM_ALIYUN_BALANCE:-3000}
    alarm_daily=${ALARM_ALIYUN_DAILY:-150}

    while [[ $# -gt 0 ]]; do
        case "$1" in
        daily)
            alarm_daily="$2"
            shift 2
            ;;
        balance)
            alarm_balance="$2"
            shift 2
            ;;
        *)
            echo "错误：未知的参数：$1" >&2
            return 1
            ;;
        esac
    done

    yesterday=$(date +%F -d yesterday)
    current_month=$(date +%Y-%m -d yesterday)

    # 检查当前余额
    current_balance=$(call_aliyun_api bssopenapi query-account-balance 2>/dev/null |
        jq -r '.Data.AvailableAmount | gsub(","; "")')

    if [[ -z "$current_balance" ]]; then
        echo "Warning: Failed to retrieve balance for aliyun profile $profile"
        return 1
    else
        echo "[$profile]当前余额: $current_balance"
        if ((${current_balance%.*} < ${alarm_balance%.*})); then
            msg_body="[$profile]余额: $current_balance 过低需要充值"
            _notify_wecom "${WECOM_KEY_ALARM}" "$msg_body"
        fi
    fi

    # 检查昨日消费
    daily_spending=$(call_aliyun_api bssopenapi query-account-bill --api-version 2017-12-14 --billing-cycle "$current_month" --billing-date "$yesterday" --granularity DAILY |
        jq -r '.Data.Items.Item[].PretaxAmount | tostring | gsub(","; "")')

    if [[ -z "$daily_spending" ]]; then
        echo "Warning: Failed to retrieve yesterday's spending"
        return 1
    else
        echo "[$profile]昨日消费: $daily_spending"
        if ((${daily_spending%.*} > ${alarm_daily%.*})); then
            msg_body=$(printf "[%s]昨日消费金额: %.2f , 超过告警阈值：%.2f" "$profile" "$daily_spending" "${alarm_daily}")
            _notify_wecom "${WECOM_KEY_ALARM}" "$msg_body"
        fi
    fi
}

list_all_services() {
    echo "列出所有服务的资源："
    echo "================================"

    echo "账户余额："
    handle_balance_commands get

    echo "================================"
    echo "ECS 实例："
    handle_ecs_commands get

    echo "================================"
    echo "VPC："
    handle_vpc_commands get

    echo "================================"
    echo "交换机（VSwitch）："
    local vpc_ids
    vpc_ids=$(handle_vpc_commands get json | jq -r '.Vpcs.Vpc[].VpcId')
    for vpc_id in $vpc_ids; do
        echo "VPC ID: $vpc_id 的交换机："
        handle_vpc_commands get-vsw "$vpc_id"
    done

    echo "================================"
    echo "安全组（Security Group）："
    for vpc_id in $vpc_ids; do
        echo "VPC ID: $vpc_id 的安全组："
        handle_vpc_commands get-sg "$vpc_id"
    done

    echo "================================"
    echo "DNS 记录："
    handle_dns_commands get

    echo "================================"
    echo "OSS 存储桶："
    handle_oss_commands get

    echo "================================"
    echo "CDN 域名："
    handle_cdn_commands get

    echo "================================"
    echo "负载均衡实例："
    handle_lbs_commands get

    echo "================================"
    echo "RDS 实例："
    handle_rds_commands get

    echo "================================"
    echo "KVStore (Redis) 实例："
    handle_kvstore_commands get

    echo "================================"
    echo "NAT 网关："
    handle_nat_commands get

    echo "================================"
    echo "弹性公网 IP："
    handle_eip_commands get

    echo "================================"
    echo "证书服务："
    handle_cas_commands get

    echo "================================"
    echo "RAM 用户："
    handle_ram_commands get

    echo "================================"
    echo "SSH 密钥："
    handle_ecs_commands get-key

    # 可以根据需要添加更多服务
}

query_daily_cost() {
    local query_date=${1:-$(date +%F -d "yesterday")}
    local current_month
    current_month=$(date +%Y-%m -d "$query_date")
    local format=${2:-human}

    local result
    result=$(
        call_aliyun_api bssopenapi query-account-bill --api-version 2017-12-14 --billing-cycle "$current_month" --billing-date "$query_date" --granularity DAILY
    )
    return_code=$?
    if [ $return_code -eq 0 ]; then
        case "$format" in
        json)
            # JSON 格式不显示提示信息，直接输出结果
            echo "$result"
            ;;
        tsv)
            echo "查询 $query_date 的消费总额："
            echo -e "日期\t消费金额\t货币单位"
            echo "$result" | jq -r '.Data.Items.Item[] | [.BillingDate, .PretaxAmount, "CNY"] | @tsv'
            ;;
        human | *)
            echo "查询 $query_date 的消费总额："
            local total_amount currency
            total_amount=$(echo "$result" | jq -r '.Data.Items.Item[0].PretaxAmount')
            currency=$(echo "$result" | jq -r '.Data.Items.Item[0].Currency')
            if [ -n "$total_amount" ] && [ "$total_amount" != "null" ]; then
                echo "$query_date 消费总额: $total_amount $currency"
            else
                echo "未找到 $query_date 的消费数据。"
            fi
            ;;
        esac
    else
        echo "错误：无法查询 $query_date 的消费总额。"
        echo "$result"
    fi
    log_result "${profile:-}" "${region:-}" "cost" "daily" "$result" "$format"
}

show_cost_help() {
    echo "费用查询操作："
    echo "  daily [YYYY-MM-DD] [format]  - 查询指定日期的消费总额（默认为昨天），format 可选 human/json/tsv"
    echo
    echo "示例："
    echo "  $0 cost daily                # 查询昨天的消费（人类可读格式）"
    echo "  $0 cost daily 2023-05-01     # 查询指定日期的消费（人类可读格式）"
    echo "  $0 cost daily 2023-05-01 json # 查询指定日期的消费（JSON格式）"
    echo "  $0 cost daily 2023-05-01 tsv  # 查询指定日期的消费（TSV格式）"
}

handle_cost_commands() {
    local operation=${1:-daily}
    shift

    case "$operation" in
    daily)
        local date=${1:-}
        local format=${2:-human}
        query_daily_cost "$date" "$format"
        ;;
    *)
        echo "错误：未知的费用查询操作：$operation" >&2
        show_cost_help
        exit 1
        ;;
    esac
}
