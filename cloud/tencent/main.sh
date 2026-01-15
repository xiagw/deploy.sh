#!/usr/bin/env bash
# shellcheck disable=SC2034
# -*- coding: utf-8 -*-

## 定义执行所在目录
SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
## 定义上一级 cloud/ 目录
SCRIPT_CLOUD=$(dirname "${SCRIPT_DIR}")
## 定义项目根目录
PROJECT_ROOT=$(dirname "${SCRIPT_CLOUD}")
# 定义通用数据目录
SCRIPT_DATA="${PROJECT_ROOT}/data"

# 在文件开头添加模块加载相关变量
declare -A LOADED_MODULES
DEV_MODE=${DEV_MODE:-false}

# 添加模块加载函数
load_module() {
    local service=$1
    local module_file="${SCRIPT_DIR}/${service}.sh"

    # 检查模块文件是否存在
    if [[ ! -f "$module_file" ]]; then
        echo "错误：未找到服务模块：$service" >&2
        return 1
    fi

    # 开发模式或文件更新时重新加载
    if [[ "${DEV_MODE}" == "true" ]] ||
        [[ ! -v LOADED_MODULES[$service] ]] ||
        [[ $(stat -c %Y "$module_file" 2>/dev/null || stat -f %m "$module_file" 2>/dev/null) -gt ${LOADED_MODULES[$service]:-0} ]]; then
        # shellcheck source=/dev/null
        source "$module_file"
        LOADED_MODULES[$service]=$(date +%s)
        [[ "${DEV_MODE}" == "true" ]] && echo "模块 $service 已重新加载"
    fi
}

# 主函数
main() {
    # 先加载基础服务框架
    # shellcheck source=/dev/null
    [[ -f "${SCRIPT_DIR}/base_service.sh" ]] && source "${SCRIPT_DIR}/base_service.sh"

    # 导入其他脚本
    for file in "${SCRIPT_DIR}"/*.sh; do
        case "$file" in
        */main.sh | */base_service.sh | */service_template.sh | */test_*.sh) continue ;;
        *.sh)
            # shellcheck source=/dev/null
            [[ -f "$file" ]] && source "$file"
            ;;
        esac
    done
    # shellcheck source=/dev/null
    [ -f "${SCRIPT_DATA}/tencent.sh.env" ] && source "${SCRIPT_DATA}/tencent.sh.env"

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

    # 如果没有指定 region，则从配置文件中读取，如果配置文件中也没有则使用默认值 "ap-guangzhou"
    region=${region:-$(read_config "$profile")}
    region=${region:-"ap-guangzhou"}

    local service=${args[0]}
    unset 'args[0]'
    args=("${args[@]}") # 重新索引数组

    # 显示当前配置
    # echo "当前配置： Profile==$profile , Region==$region"

    # 根据服务类型加载对应模块
    case "$service" in
    list-all) list_all_services ;;
    config) handle_config_commands "${args[@]}" ;;
    cvm) handle_cvm_commands "${args[@]}" ;;
    vpc) handle_vpc_commands "${args[@]}" 2>/dev/null || echo "错误：VPC 服务模块尚未实现" >&2 ;;
    cdb) handle_cdb_commands "${args[@]}" 2>/dev/null || echo "错误：CDB 服务模块尚未实现" >&2 ;;
    cos) handle_cos_commands "${args[@]}" 2>/dev/null || echo "错误：COS 服务模块尚未实现" >&2 ;;
    clb) handle_clb_commands "${args[@]}" 2>/dev/null || echo "错误：CLB 服务模块尚未实现" >&2 ;;
    cam) handle_cam_commands "${args[@]}" 2>/dev/null || echo "错误：CAM 服务模块尚未实现" >&2 ;;
    *) echo "错误：未知的服务：$service" >&2 && show_help && exit 1 ;;
    esac
}

# 运行主函数
main "$@"
