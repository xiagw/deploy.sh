#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 通用工具函数

check_dependencies() {
    if ! command -v aliyun &>/dev/null; then
        echo "错误：未安装阿里云 CLI。请先安装阿里云 CLI。" >&2
        exit 1
    fi

    if ! aliyun configure list &>/dev/null; then
        echo "错误：未设置阿里云凭证。请先运行 'aliyun configure' 设置凭证。" >&2
        exit 1
    fi
}

show_help() {
    echo "用法: $0 [--profile <配置名>] [--region <地域>] <服务> <操作> [参数...]"
    echo
    echo "可用服务:"
    echo "  list-all - 列出所有服务的资源"
    echo "  ecs      - 弹性计算服务"
    echo "  dns      - 域名解析服务"
    echo "  oss      - 对象存储服务"
    echo "  domain   - 域名服务"
    echo "  cdn      - 内容分发网络"
    echo "  lbs      - 负载均衡服务"
    echo "  rds      - 关系型数据库服务"
    echo "  kvstore  - 键值存储服务(Redis)"
    echo "  vpc      - 专有网络"
    echo "  nat      - NAT网关"
    echo "  eip      - 弹性公网IP"
    echo "  config   - 配置管理"
    echo "  cost     - 费用查询"
    echo "  cas      - 证书服务"
    echo "  ram      - 访问控制"
    echo "  nas      - 文件存储"
    echo "  ack      - 容器服务 Kubernetes 版"
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

    local data_dir="${SCRIPT_DATA:? ERR: SCRIPT_DATA empty}/${profile}/${region}/data/${service}"
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

    local log_dir="${SCRIPT_DATA}/${profile}/${region}/logs"
    local log_file="${log_dir}/${service}.log"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local unique_id
    unique_id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$$")

    mkdir -p "$log_dir"
    {
        echo -e "\n==== Execution: $timestamp - $unique_id - Operation: $operation ===="
        echo "Format: $format"
        if [ "$format" = "json" ]; then
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
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    local log_dir="${SCRIPT_DATA}/${profile}/${region}/logs"
    local log_file="${log_dir}/${service}.log"

    mkdir -p "$log_dir"
    echo "$timestamp | $resource_id | $resource_name | $status" >>"$log_file"
    echo "删除操作日志已保存到 $log_file"
}

validate_params() {
    local service=$1
    local operation=$2
    shift 2
    local params=("$@")

    case "$service" in
    ecs)
        case "$operation" in
        list) [[ ${#params[@]} -ge 0 ]] || {
            echo "错误：参数错误。用法：$0 ecs list [region]" >&2
            return 1
        } ;;
        create) [[ ${#params[@]} -ge 3 ]] || {
            echo "错误：缺少参数。用法：$0 ecs create <名称> <类型> <镜像ID> [region]" >&2
            return 1
        } ;;
        update) [[ ${#params[@]} -ge 2 ]] || {
            echo "错误：缺少参数。用法：$0 ecs update <实例ID> <新名称> [region]" >&2
            return 1
        } ;;
        delete) [[ ${#params[@]} -ge 1 ]] || {
            echo "错误：缺少参数。用法：$0 ecs delete <实例ID> [region]" >&2
            return 1
        } ;;
        *)
            echo "错误：未知的 ECS 操作：$operation" >&2
            return 1
            ;;
        esac
        ;;
    dns)
        case "$operation" in
        list) [[ ${#params[@]} -le 1 ]] || {
            echo "错误：参数错误。用法：$0 dns list [域名]" >&2
            return 1
        } ;;
        create) [[ ${#params[@]} -ge 4 ]] || {
            echo "错误：缺少参数。用法：$0 dns create <域名> <主机记录> <类型> <值>" >&2
            return 1
        } ;;
        update) [[ ${#params[@]} -ge 4 ]] || {
            echo "错误：缺少参数。用法：$0 dns update <记录ID> <主机记录> <类型> <值>" >&2
            return 1
        } ;;
        delete) [[ ${#params[@]} -ge 1 ]] || {
            echo "错误：缺少参数。用法：$0 dns delete <记录ID>" >&2
            return 1
        } ;;
        *)
            echo "错误：未知的 DNS 操作：$operation" >&2
            return 1
            ;;
        esac
        ;;
    domain)
        case "$operation" in
        list) [[ ${#params[@]} -eq 0 ]] || {
            echo "错误：list 操作不需要参数。用法：$0 domain list" >&2
            return 1
        } ;;
        *)
            echo "错误：未知的 Domain 操作：$operation" >&2
            return 1
            ;;
        esac
        ;;
    oss)
        case "$operation" in
        list) [[ ${#params[@]} -ge 0 ]] || {
            echo "错误：参数错误。用法：$0 oss list [region]" >&2
            return 1
        } ;;
        create) [[ ${#params[@]} -ge 1 ]] || {
            echo "错误：缺少参数。用法：$0 oss create <存储桶名称> [region]" >&2
            return 1
        } ;;
        delete) [[ ${#params[@]} -ge 1 ]] || {
            echo "错误：缺少参数。用法：$0 oss delete <存储桶名称> [region]" >&2
            return 1
        } ;;
        *)
            echo "错误：未知的 OSS 操作：$operation" >&2
            return 1
            ;;
        esac
        ;;
    cdn)
        case "$operation" in
        list) [[ ${#params[@]} -eq 0 ]] || {
            echo "错误：list 操作不需要参数。用法：$0 cdn list" >&2
            return 1
        } ;;
        create) [[ ${#params[@]} -eq 3 ]] || {
            echo "错误：缺少参数。用法：$0 cdn create <域名> <源站> <源站类型>" >&2
            return 1
        } ;;
        delete) [[ ${#params[@]} -eq 1 ]] || {
            echo "错误：缺少参数。用法：$0 cdn delete <域名>" >&2
            return 1
        } ;;
        update) [[ ${#params[@]} -eq 3 ]] || {
            echo "错误：缺少参数。用法：$0 cdn update <域名> <源站> <源站类型>" >&2
            return 1
        } ;;
        *)
            echo "错误：未知的 CDN 操作：$operation" >&2
            return 1
            ;;
        esac
        ;;
    lbs)
        case "$operation" in
        list) [[ ${#params[@]} -le 1 ]] || {
            echo "错误：参数错误。用法：$0 lbs list [type]" >&2
            return 1
        } ;;
        create)
            [[ ${#params[@]} -ge 2 ]] || {
                echo "错误：缺少参数。用法：$0 lbs create <type> <名称> [其他参数...]" >&2
                return 1
            }
            local lb_type=${params[0]}
            case "$lb_type" in
            slb) [[ ${#params[@]} -ge 4 ]] || {
                echo "错误：缺少参数。用法：$0 lbs create slb <名称> <规格> <付费类型> [地域]" >&2
                return 1
            } ;;
            nlb | alb) [[ ${#params[@]} -ge 4 ]] || {
                echo "错误：缺少参数。用法：$0 lbs create $lb_type <名称> <VPC-ID> <交换机ID> [地域]" >&2
                return 1
            } ;;
            *)
                echo "错误：未知的负载均衡类型：$lb_type" >&2
                return 1
                ;;
            esac
            ;;
        update) [[ ${#params[@]} -ge 3 ]] || {
            echo "错误：缺少参数。用法：$0 lbs update <type> <实例ID> <新名称> [地域]" >&2
            return 1
        } ;;
        delete) [[ ${#params[@]} -ge 2 ]] || {
            echo "错误：缺少参数。用法：$0 lbs delete <type> <实例ID> [地域]" >&2
            return 1
        } ;;
        *)
            echo "错误：未知的 LBS 操作：$operation" >&2
            return 1
            ;;
        esac
        ;;
    rds)
        case "$operation" in
        list) [[ ${#params[@]} -ge 0 ]] || {
            echo "错误：参数错误。用法：$0 rds list [region]" >&2
            return 1
        } ;;
        create) [[ ${#params[@]} -ge 4 ]] || {
            echo "错误：缺少参数。用法：$0 rds create <名称> <引擎> <版本> <规格> [地域]" >&2
            return 1
        } ;;
        update) [[ ${#params[@]} -ge 2 ]] || {
            echo "错误：缺少参数。用法：$0 rds update <实例ID> <新名称> [地域]" >&2
            return 1
        } ;;
        delete) [[ ${#params[@]} -ge 1 ]] || {
            echo "错误：缺少参数。用法：$0 rds delete <实例ID> [地域]" >&2
            return 1
        } ;;
        *)
            echo "错误：未知的 RDS 操作：$operation" >&2
            return 1
            ;;
        esac
        ;;
    nlb)
        case "$operation" in
        list) [[ ${#params[@]} -ge 0 ]] || {
            echo "错误：参数错误。用法：$0 nlb list [region]" >&2
            return 1
        } ;;
        create) [[ ${#params[@]} -ge 4 ]] || {
            echo "错误：缺少参数。用法：$0 nlb create <名称> <VPC-ID> <交换机ID> [地域]" >&2
            return 1
        } ;;
        update) [[ ${#params[@]} -ge 2 ]] || {
            echo "错误：缺少参数。用法：$0 nlb update <实例ID> <新名称> [地域]" >&2
            return 1
        } ;;
        delete) [[ ${#params[@]} -ge 1 ]] || {
            echo "错误：缺少参数。用法：$0 nlb delete <实例ID> [地域]" >&2
            return 1
        } ;;
        *)
            echo "错误：未知的 NLB 操作：$operation" >&2
            return 1
            ;;
        esac
        ;;
    alb)
        case "$operation" in
        list) [[ ${#params[@]} -ge 0 ]] || {
            echo "错误：参数错误。用法：$0 alb list [region]" >&2
            return 1
        } ;;
        create) [[ ${#params[@]} -ge 4 ]] || {
            echo "错误：缺少参数。用法：$0 alb create <名称> <VPC-ID> <交换机ID> [地域]" >&2
            return 1
        } ;;
        update) [[ ${#params[@]} -ge 2 ]] || {
            echo "错误：缺少参数。用法：$0 alb update <实例ID> <新名称> [地域]" >&2
            return 1
        } ;;
        delete) [[ ${#params[@]} -ge 1 ]] || {
            echo "错误：缺少参数。用法：$0 alb delete <实例ID> [地域]" >&2
            return 1
        } ;;
        *)
            echo "错误：未知的 ALB 操作：$operation" >&2
            return 1
            ;;
        esac
        ;;
    eip)
        case "$operation" in
        list) [[ ${#params[@]} -ge 0 ]] || {
            echo "错误：参数错误。用法：$0 eip list [region]" >&2
            return 1
        } ;;
        create) [[ ${#params[@]} -ge 1 ]] || {
            echo "错误：缺少参数。用法：$0 eip create <带宽> [region]" >&2
            return 1
        } ;;
        update) [[ ${#params[@]} -ge 2 ]] || {
            echo "错误：缺少参数。用法：$0 eip update <EIP-ID> <新带宽> [region]" >&2
            return 1
        } ;;
        delete) [[ ${#params[@]} -ge 1 ]] || {
            echo "错误：缺少参数。用法：$0 eip delete <EIP-ID> [region]" >&2
            return 1
        } ;;
        *)
            echo "错误：未知的 EIP 操作：$operation" >&2
            return 1
            ;;
        esac
        ;;
    kvstore)
        case "$operation" in
        list) [[ ${#params[@]} -ge 0 ]] || {
            echo "错误：参数错误。用法：$0 kvstore list [region]" >&2
            return 1
        } ;;
        create) [[ ${#params[@]} -ge 3 ]] || {
            echo "错误：缺少参数。用法：$0 kvstore create <名称> <实例类型> <容量> [region]" >&2
            return 1
        } ;;
        update) [[ ${#params[@]} -ge 2 ]] || {
            echo "错误：缺少参数。用法：$0 kvstore update <实例ID> <新名称> [region]" >&2
            return 1
        } ;;
        delete) [[ ${#params[@]} -ge 1 ]] || {
            echo "错误：缺少参数。用法：$0 kvstore delete <实例ID> [region]" >&2
            return 1
        } ;;
        *)
            echo "错误：未知的 KVStore 操作：$operation" >&2
            return 1
            ;;
        esac
        ;;
    *)
        echo "错误：未知的服务：$service" >&2
        return 1
        ;;
    esac
}

# 在 utils.sh 文件中添加以下函数

check_fzf() {
    if ! command -v fzf &>/dev/null; then
        echo "错误：fzf 未安装。请安装 fzf 或直接提供参数。" >&2
        exit 1
    fi
}

select_with_fzf() {
    local prompt=$1
    local options=$2

    check_fzf

    local selected
    selected=$(echo "$options" | fzf --height=50% --prompt="$prompt: ")
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

    # 输出凭证信息
    # echo "$access_key_id"
    # echo "$access_key_secret"
    # echo "$region"
}

# 在文件末尾添加以下函数

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
    result=$(aliyun --profile "${profile:-}" bssopenapi QueryAccountBalance --region "${region:-cn-hangzhou}")

    if [ $? -eq 0 ]; then
        case "$format" in
        json)
            # JSON 格式不显示提示信息，直接输出结果
            echo "$result"
            ;;
        tsv)
            echo "查询账户余额："
            echo -e "可用余额\t货币单位"
            echo "$result" | jq -r '[.Data.AvailableAmount, .Data.Currency] | @tsv'
            ;;
        human | *)
            echo "查询账户余额："
            local available_amount=$(echo "$result" | jq -r '.Data.AvailableAmount')
            local currency=$(echo "$result" | jq -r '.Data.Currency')
            echo "可用余额: $available_amount $currency"
            ;;
        esac
    else
        echo "错误：无法查询账户余额。"
        echo "$result"
    fi
    log_result "${profile:-}" "${region:-}" "account" "balance" "$result" "$format"
}

# 在文件末尾添加以下函数

show_balance_help() {
    echo "账户余额操作："
    echo "  list [format]            - 查询账户余额，format 可选 human/json/tsv"
    echo
    echo "示例："
    echo "  $0 balance list          # 人类可读格式"
    echo "  $0 balance list json     # JSON 格式"
    echo "  $0 balance list tsv      # TSV 格式"
}

handle_balance_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) query_account_balance "$@" ;;
    *)
        echo "错误：未知的余额操作：$operation" >&2
        show_balance_help
        exit 1
        ;;
    esac
}

list_all_services() {
    echo "列出所有服务的资源："
    echo "================================"

    echo "账户余额："
    handle_balance_commands list

    echo "================================"
    echo "ECS 实例："
    handle_ecs_commands list

    echo "================================"
    echo "VPC："
    handle_vpc_commands list

    echo "================================"
    echo "交换机（VSwitch）："
    local vpc_ids=$(vpc_list json | jq -r '.Vpcs.Vpc[].VpcId')
    for vpc_id in $vpc_ids; do
        echo "VPC ID: $vpc_id 的交换机："
        handle_vpc_commands vswitch-list "$vpc_id"
    done

    echo "================================"
    echo "安全组（Security Group）："
    for vpc_id in $vpc_ids; do
        echo "VPC ID: $vpc_id 的安全组："
        handle_vpc_commands sg-list "$vpc_id"
    done

    echo "================================"
    echo "DNS 记录："
    handle_dns_commands list

    echo "================================"
    echo "OSS 存储桶："
    handle_oss_commands list

    echo "================================"
    echo "CDN 域名："
    handle_cdn_commands list

    echo "================================"
    echo "负载均衡实例："
    handle_lbs_commands list

    echo "================================"
    echo "RDS 实例："
    handle_rds_commands list

    echo "================================"
    echo "KVStore (Redis) 实例："
    handle_kvstore_commands list

    echo "================================"
    echo "NAT 网关："
    handle_nat_commands list

    echo "================================"
    echo "弹性公网 IP："
    handle_eip_commands list

    echo "================================"
    echo "证书服务："
    handle_cas_commands list

    echo "================================"
    echo "RAM 用户："
    handle_ram_commands list

    echo "================================"
    echo "SSH 密钥："
    handle_ecs_commands key-list

    # 可以根据需要添加更多服务
}

query_daily_cost() {
    local query_date=${1:-$(date -d "yesterday" +%Y-%m-%d)}
    local current_month=$(date -d "$query_date" +%Y-%m)
    local format=${2:-human}

    local result
    result=$(aliyun --profile "${profile:-}" bssopenapi QueryAccountBill \
        --BillingCycle "$current_month" \
        --BillingDate "$query_date" \
        --Granularity DAILY)

    if [ $? -eq 0 ]; then
        case "$format" in
        json)
            # JSON 格式不显示提示信息，直接输出结果
            echo "$result"
            ;;
        tsv)
            echo "查询 $query_date 的消费总额："
            echo -e "日期\t消费金额\t货币单位"
            echo "$result" | jq -r '.Data.Items.Item[] | [.BillingDate, .CashAmount, "CNY"] | @tsv'
            ;;
        human | *)
            echo "查询 $query_date 的消费总额："
            local total_amount=$(echo "$result" | jq -r '.Data.Items.Item[0].CashAmount')
            local currency=$(echo "$result" | jq -r '.Data.Items.Item[0].Currency')
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

