#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 服务模块模板
# 使用方法：
# 1. 复制此文件为新的服务文件（如 new_service.sh）
# 2. 替换 SERVICE_NAME, SERVICE_DISPLAY_NAME, API_SERVICE 等占位符
# 3. 根据实际 API 调整函数实现

# 服务配置（需要根据实际情况修改）
SERVICE_NAME="new_service"           # 服务名称（小写，用于命令）
SERVICE_DISPLAY_NAME="新服务"        # 服务显示名称（中文）
API_SERVICE="newservice"            # 阿里云 API 服务名称

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

# 显示帮助信息
show_${SERVICE_NAME}_help() {
    echo "${SERVICE_DISPLAY_NAME} 操作："
    echo "  list [format]                    - 列出资源"
    echo "  create <名称> [参数...]           - 创建资源"
    echo "  update <资源ID> <新名称>         - 更新资源"
    echo "  delete <资源ID>                 - 删除资源"
    echo
    echo "示例："
    echo "  $0 ${SERVICE_NAME} list"
    echo "  $0 ${SERVICE_NAME} create my-resource"
    echo "  $0 ${SERVICE_NAME} update res-123 new-name"
    echo "  $0 ${SERVICE_NAME} delete res-123"
}

# 处理命令
handle_${SERVICE_NAME}_commands() {
    local operation=${1:-list}
    shift
    
    case "$operation" in
    list) ${SERVICE_NAME}_list "$@" ;;
    create) ${SERVICE_NAME}_create "$@" ;;
    update) ${SERVICE_NAME}_update "$@" ;;
    delete) ${SERVICE_NAME}_delete "$@" ;;
    help) show_${SERVICE_NAME}_help ;;
    *)
        echo "错误：未知的 ${SERVICE_DISPLAY_NAME} 操作：$operation" >&2
        show_${SERVICE_NAME}_help
        exit 1
        ;;
    esac
}

# 列出资源
${SERVICE_NAME}_list() {
    local format=${1:-human}
    
    # 配置列表输出
    local table_header="资源ID\t名称\t状态\t创建时间"
    local jq_filter=".Items.Resource[] | [.ResourceId, .ResourceName, .Status, .CreateTime] | @tsv"
    local status_mapper="BEGIN {FS=\"\\t\"; OFS=\"\\t\"}
    {
        status = \$3;
        if (status == \"Running\") status = \"运行中\";
        else if (status == \"Stopped\") status = \"已停止\";
        else status = \"未知\";
        printf \"%-16s  %-18s  %-6s  %s\\n\", \$1, \$2, status, \$4
    }"
    
    generic_list \
        "$API_SERVICE" \
        "DescribeResources" \
        "$SERVICE_NAME" \
        "$format" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 ${SERVICE_DISPLAY_NAME} 资源。" \
        "列出 ${SERVICE_DISPLAY_NAME} 资源："
}

# 创建资源
${SERVICE_NAME}_create() {
    local name=$1
    shift
    local extra_args=("$@")
    
    if [ -z "$name" ]; then
        echo "错误：资源名称不能为空。" >&2
        echo "用法：${SERVICE_NAME} create <名称> [参数...]" >&2
        return 1
    fi
    
    # 构建 API 参数
    local api_args=(
        "--ResourceName" "$name"
        "${extra_args[@]}"
    )
    
    generic_create \
        "$API_SERVICE" \
        "CreateResource" \
        "$SERVICE_NAME" \
        "$name" \
        "${api_args[@]}"
}

# 更新资源
${SERVICE_NAME}_update() {
    local resource_id=$1
    local new_name=$2
    
    if [ -z "$resource_id" ] || [ -z "$new_name" ]; then
        echo "错误：资源ID和新名称不能为空。" >&2
        echo "用法：${SERVICE_NAME} update <资源ID> <新名称>" >&2
        return 1
    fi
    
    generic_update \
        "$API_SERVICE" \
        "ModifyResourceDescription" \
        "$SERVICE_NAME" \
        "$resource_id" \
        "$new_name"
}

# 删除资源
${SERVICE_NAME}_delete() {
    local resource_id=$1
    
    if [ -z "$resource_id" ]; then
        echo "错误：资源ID不能为空。" >&2
        echo "用法：${SERVICE_NAME} delete <资源ID>" >&2
        return 1
    fi
    
    generic_delete \
        "$API_SERVICE" \
        "DeleteResource" \
        "$SERVICE_NAME" \
        "$resource_id" \
        "资源"
}
