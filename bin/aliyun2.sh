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

# 在文件开头添加模块加载相关变量
declare -A LOADED_MODULES
DEV_MODE=${DEV_MODE:-false}

# 添加模块加载函数
load_module() {
    local service=$1
    local module_file="${SCRIPT_LIB}/aliyun/${service}.sh"

    # 检查模块文件是否存在
    if [[ ! -f "$module_file" ]]; then
        echo "错误：未找到服务模块：$service" >&2
        return 1
    fi

    # 开发模式或文件更新时重新加载
    if [[ "${DEV_MODE}" == "true" ]] ||
        [[ ! -v LOADED_MODULES[$service] ]] ||
        [[ $(stat -c %Y "$module_file") -gt ${LOADED_MODULES[$service]:-0} ]]; then
        # shellcheck source=/dev/null
        source "$module_file"
        LOADED_MODULES[$service]=$(date +%s)
        [[ "${DEV_MODE}" == "true" ]] && echo "模块 $service 已重新加载"
    fi
}

# 主函数
main() {
    # 导入其他脚本
    for file in "${SCRIPT_LIB}"/aliyun/*.sh "${SCRIPT_LIB}"/common.sh; do
        [[ "$file" == *run.sh ]] && continue
        # shellcheck source=/dev/null
        [[ -f "$file" ]] && source "$file"
    done
    # shellcheck source=/dev/null
    [ -f "${SCRIPT_DATA}/aliyun2.sh.env" ] && source "${SCRIPT_DATA}/aliyun2.sh.env"

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
    config) handle_config_commands "${args[@]}" ;;
    balance) handle_balance_commands "${args[@]}" ;;
    cost) handle_cost_commands "${args[@]}" ;;
    ecs) handle_ecs_commands "${args[@]}" ;;
    dns) handle_dns_commands "${args[@]}" ;;
    domain) handle_domain_commands "${args[@]}" ;;
    cdn) handle_cdn_commands "${args[@]}" ;;
    oss) handle_oss_commands "${args[@]}" ;;
    lbs) handle_lbs_commands "${args[@]}" ;;
    rds) handle_rds_commands "${args[@]}" ;;
    kvstore) handle_kvstore_commands "${args[@]}" ;;
    vpc) handle_vpc_commands "${args[@]}" ;;
    nat) handle_nat_commands "${args[@]}" ;;
    eip) handle_eip_commands "${args[@]}" ;;
    cas) handle_cas_commands "${args[@]}" ;;
    ram) handle_ram_commands "${args[@]}" ;;
    nas) handle_nas_commands "${args[@]}" ;;
    ack) handle_ack_commands "${args[@]}" ;;
    *) echo "错误：未知的服务：$service" >&2 && show_help && exit 1 ;;
    esac
}

# 运行主函数
main "$@"
