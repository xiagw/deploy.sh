#!/usr/bin/env bash
# shellcheck disable=SC2034
# -*- coding: utf-8 -*-

# 定义全局命令变量
CMD_READLINK=$(command -v greadlink || command -v readlink)
CMD_DATE=$(command -v gdate || command -v date)
CMD_GREP=$(command -v ggrep || command -v grep)
CMD_SED=$(command -v gsed || command -v sed)
CMD_CURL=$(command -v /usr/local/opt/curl/bin/curl || command -v curl)

## 定义执行所在目录
SCRIPT_DIR=$(dirname "$($CMD_READLINK -f "${BASH_SOURCE[0]}")")
## 定义上一级目录
SCRIPT_DIR_PARENT=$(dirname "${SCRIPT_DIR}")

# 定义通用数据目录和 lib 目录
if [ -d "${SCRIPT_DIR}/lib" ]; then
    SCRIPT_LIB="${SCRIPT_DIR}/lib"
elif [ -d "${SCRIPT_DIR_PARENT}/lib" ]; then
    SCRIPT_LIB="${SCRIPT_DIR_PARENT}/lib"
fi
if [ -d "${SCRIPT_DIR}/data" ]; then
    SCRIPT_DATA="${SCRIPT_DIR}/data"
elif [ -d "${SCRIPT_DIR_PARENT}/data" ]; then
    SCRIPT_DATA="${SCRIPT_DIR_PARENT}/data"
fi

# 主函数
main() {
    # 导入其他脚本
    for file in "${SCRIPT_LIB}"/aliyun/*.sh; do
        [[ -f "$file" ]] || continue
        [[ "$file" == *run.sh ]] && continue
        # shellcheck source=/dev/null
        source "$file"
    done

    check_dependencies

    local profile="default"
    local region=""
    local args=()
    local i=0

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -p | --profile)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--profile 选项需要指定一个配置名称" >&2
                return 1
            fi
            profile="$2"
            shift
            ;;
        -r | --region)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--region 选项需要指定一个地域" >&2
                return 1
            fi
            region="$2"
            shift
            ;;
        *)
            args[i]="$1"
            ((i++))
            ;;
        esac
        shift
    done

    if [ ${#args[@]} -lt 1 ]; then
        show_help
        return 1
    fi

    # 如果没有指定 region，则从配置文件中读取，如果配置文件中也没有则使用默认值 "cn-hangzhou"
    region=${region:-$(read_config "$profile")}
    region=${region:-"cn-hangzhou"}

    local service=${args[0]}
    unset 'args[0]'
    args=("${args[@]}") # 重新索引数组

    # 显示当前配置
    # echo "当前配置： Profile==$profile , Region==$region"

    case "$service" in
    list-all) list_all_services ;;
    config) handle_config_commands "${args[@]}" || show_config_help ;;
    balance) handle_balance_commands "${args[@]}" || show_balance_help ;;
    cost) handle_cost_commands "${args[@]}" || show_cost_help ;;
    ecs) handle_ecs_commands "${args[@]}" || show_ecs_help ;;
    dns) handle_dns_commands "${args[@]}" || show_dns_help ;;
    domain) handle_domain_commands "${args[@]}" || show_domain_help ;;
    cdn) handle_cdn_commands "${args[@]}" || show_cdn_help ;;
    oss) handle_oss_commands "${args[@]}" || show_oss_help ;;
    lbs) handle_lbs_commands "${args[@]}" || show_lbs_help ;;
    rds) handle_rds_commands "${args[@]}" || show_rds_help ;;
    kvstore) handle_kvstore_commands "${args[@]}" || show_kvstore_help ;;
    vpc) handle_vpc_commands "${args[@]}" || show_vpc_help ;;
    nat) handle_nat_commands "${args[@]}" || show_nat_help ;;
    eip) handle_eip_commands "${args[@]}" || show_eip_help ;;
    cas) handle_cas_commands "${args[@]}" || show_cas_help ;;
    ram) handle_ram_commands "${args[@]}" || show_ram_help ;;
    nas) handle_nas_commands "${args[@]}" || show_nas_help ;;
    ack) handle_ack_commands "${args[@]}" || show_ack_help ;;
    *) echo "错误：未知的服务：$service" >&2 && show_help && exit 1 ;;
    esac
}

# 运行主函数
main "$@"

