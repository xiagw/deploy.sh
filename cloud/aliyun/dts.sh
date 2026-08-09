#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# DTS (Data Transmission Service) 相关函数 - 阿里云数据传输服务

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_dts_help() {
    echo "DTS (数据传输服务) 操作："
    echo "  get                                    - 获取 DTS 迁移任务列表"
    echo "  get-all                                - 获取 DTS 所有任务列表（迁移、同步、订阅）"
    echo "  get-sync                               - 获取 DTS 同步任务列表"
    echo "  get-subscribe                          - 获取 DTS 订阅任务列表"
    echo "  add <任务名称> <源库类型> <目标库类型> - 添加 DTS 迁移任务"
    echo "  add-sync <任务名称> <源库类型> <目标库类型> - 添加 DTS 同步任务"
    echo "  set [<任务ID>] [<新名称>]             - 设置 DTS 迁移任务（任务ID和新名称可选，可使用fzf选择）"
    echo "  del [<任务ID>]                        - 删除 DTS 任务（迁移/同步/订阅，任务ID可选；无参数时用 fzf 选择）"
    echo "  start [<任务ID>]                      - 启动 DTS 迁移任务（任务ID可选，可使用fzf选择）"
    echo "  stop [<任务ID>]                       - 停止 DTS 迁移任务（任务ID可选，可使用fzf选择）"
    echo "  status [<任务ID>]                     - 查看 DTS 迁移任务状态（任务ID可选，可使用fzf选择）"
    echo "  get-job [<任务ID>]                    - 获取 DTS 迁移任务详情（任务ID可选，可使用fzf选择）"
    echo ""
    echo "示例："
    echo "  $0 dts get"
    echo "  $0 dts get-all"
    echo "  $0 dts get-sync"
    echo "  $0 dts get-subscribe"
    echo "  $0 dts add my-task mysql mysql"
    echo "  $0 dts add-sync my-sync-task mysql mysql"
    echo "  $0 dts start dtstask-bp12qk2qf65xxxxxx"
    echo "  $0 dts stop dtstask-bp12qk2qf65xxxxxx"
    echo "  $0 dts status dtstask-bp12qk2qf65xxxxxx"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_dts_commands() {
    local operation=${1:-get-all}
    shift

    case "$operation" in
    get) dts_list "$@" ;;
    get-all) dts_list_all "$@" ;;
    get-sync) dts_sync_list "$@" ;;
    get-subscribe) dts_subscribe_list "$@" ;;
    add) dts_create "$@" ;;
    add-sync) dts_sync_create "$@" ;;
    set) dts_update "$@" ;;
    del) dts_delete "$@" ;;
    start) dts_start "$@" ;;
    stop) dts_stop "$@" ;;
    status) dts_status "$@" ;;
    get-job) dts_job_get "$@" ;;
    help) show_dts_help ;;
    *)
        echo "错误：未知的 DTS 操作：$operation" >&2
        show_dts_help
        exit 1
        ;;
    esac
}

# 解析 DTS 迁移任务 ID（未提供时列表选择）
# 用法: _dts_resolve_job_id <当前值> [提示语] [jq select 条件] [空列表消息]
_dts_resolve_job_id() {
    resolve_resource_id "$1" "${2:-选择 DTS 迁移任务}" "${4:-错误：没有找到任何 DTS 迁移任务。}" \
        ".MigrationJobs.MigrationJob[]? ${3:+| select($3)} | \"\(.MigrationJobId) (\(.MigrationJobName)) [\(.Status)]\"" \
        -- dts describe-migration-jobs --api-version 2020-01-01
}

# DTS 迁移任务列表
dts_list() {
    local format=${1:-human}

    local result
    if ! result=$(call_aliyun_api dts describe-migration-jobs --api-version 2020-01-01); then
        echo "错误：无法获取 DTS 迁移任务列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    local table_header="MigrationJobId\tMigrationJobName\tStatus\tSourceType\tDestinationType\tCreateTime"
    local jq_filter='.MigrationJobs.MigrationJob[]? | [.MigrationJobId, .MigrationJobName, .Status, .SourceType, .DestinationType, .CreateTime] | @tsv'
    local status_mapper='BEGIN {FS="\t"; OFS="\t"}
    {
        printf "%-30s %-18s %-8s %-9s %-9s %-20s\n",
        substr($1, 1, 28), substr($2, 1, 16), $3, $4, $5, $6
    }'
    local human_header="任务ID                           任务名称             状态      源类型      目标类型    创建时间
------------------------------ ------------------ -------- --------- --------- --------------------"

    format_output \
        "$result" \
        "$format" \
        "dts" \
        "list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 DTS 迁移任务。" \
        "DTS 迁移任务列表：" \
        "$human_header" \
        '.MigrationJobs.MigrationJob | length'
}

# DTS 所有任务列表（迁移、同步、订阅）
dts_list_all() {
    local format=${1:-human}

    echo "=== DTS 迁移任务 ==="
    dts_list "$format"

    echo ""
    echo "=== DTS 同步任务 ==="
    dts_sync_list "$format"

    echo ""
    echo "=== DTS 订阅任务 ==="
    dts_subscribe_list "$format"
}

# DTS 同步任务列表
dts_sync_list() {
    local format=${1:-human}

    local result
    if ! result=$(call_aliyun_api dts describe-synchronization-jobs --api-version 2020-01-01); then
        echo "错误：无法获取 DTS 同步任务列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    local table_header="SynchronizationJobId\tSynchronizationJobName\tStatus\tSourceType\tDestinationType\tCreateTime"
    local jq_filter='.SynchronizationInstances[]? | [
        .SynchronizationJobId // .InstanceId // .Id,
        .SynchronizationJobName // .InstanceName // .Name // .SynchronizationObject,
        .Status // .DataSynchronizationStatus.Status,
        .SourceType // .SourceEndpoint.InstanceType,
        .DestinationType // .DestinationEndpoint.InstanceType,
        .CreateTime
    ] | @tsv'
    local status_mapper='BEGIN {FS="\t"; OFS="\t"}
    {
        printf "%-30s %-18s %-8s %-9s %-9s %-20s\n",
        substr($1, 1, 28), substr($2, 1, 16), $3, $4, $5, $6
    }'
    local human_header="任务ID                           任务名称             状态      源类型      目标类型    创建时间
------------------------------ ------------------ -------- --------- --------- --------------------"

    format_output \
        "$result" \
        "$format" \
        "dts" \
        "sync-list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 DTS 同步任务。" \
        "DTS 同步任务列表：" \
        "$human_header" \
        '.SynchronizationInstances | length'
}

# DTS 订阅任务列表
dts_subscribe_list() {
    local format=${1:-human}

    local result
    if ! result=$(call_aliyun_api dts describe-subscription-instances --api-version 2020-01-01); then
        echo "错误：无法获取 DTS 订阅任务列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    local table_header="SubscriptionInstanceId\tSubscriptionInstanceName\tStatus\tSourceEndpointInstanceType\tCreateTime"
    local jq_filter='.SubscriptionInstanceInfos.SubscriptionInstanceInfo[]? | [
        .SubscriptionInstanceId,
        .SubscriptionInstanceName,
        .Status,
        .SourceEndpoint.InstanceType,
        .CreateTime
    ] | @tsv'
    local status_mapper='BEGIN {FS="\t"; OFS="\t"}
    {
        printf "%-30s %-18s %-8s %-11s %-20s\n",
        substr($1, 1, 28), substr($2, 1, 16), $3, $4, $5
    }'
    local human_header="任务ID                           任务名称             状态      源端点类型    创建时间
------------------------------ ------------------ -------- ----------- --------------------"

    format_output \
        "$result" \
        "$format" \
        "dts" \
        "subscribe-list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 DTS 订阅任务。" \
        "DTS 订阅任务列表：" \
        "$human_header" \
        '.SubscriptionInstanceInfos.SubscriptionInstanceInfo | length'
}

# DTS 迁移任务创建
dts_create() {
    local task_name=$1
    local source_type=$2
    local dest_type=$3

    if [ -z "$task_name" ] || [ -z "$source_type" ] || [ -z "$dest_type" ]; then
        echo "错误：任务名称、源库类型和目标库类型都是必需的参数。" >&2
        echo "用法: $0 dts add <任务名称> <源库类型> <目标库类型>"
        echo "例如: $0 dts add my-task mysql mysql"
        return 1
    fi

    echo "创建 DTS 迁移任务："

    local result
    result=$(call_aliyun_api dts create-migration-job --api-version 2020-01-01 \
        --migration-job-name "$task_name" \
        --source-type "$source_type" \
        --destination-type "$dest_type")

    if [ $? -eq 0 ]; then
        echo "DTS 迁移任务创建成功："
        echo "$result" | jq '.'

        # 提取任务ID
        local task_id
        task_id=$(echo "$result" | jq -r '.MigrationJobId')
        echo "迁移任务ID: $task_id"

        log_result "${profile:-}" "${region:-}" "dts" "create" "$result"
    else
        echo "错误：DTS 迁移任务创建失败。"
        echo "$result"
        return 1
    fi
}

# DTS 同步任务创建
dts_sync_create() {
    local task_name=$1
    local source_type=$2
    local dest_type=$3

    if [ -z "$task_name" ] || [ -z "$source_type" ] || [ -z "$dest_type" ]; then
        echo "错误：任务名称、源库类型和目标库类型都是必需的参数。" >&2
        echo "用法: $0 dts add-sync <任务名称> <源库类型> <目标库类型>"
        echo "例如: $0 dts add-sync my-sync-task mysql mysql"
        return 1
    fi

    echo "创建 DTS 同步任务："

    local result
    result=$(call_aliyun_api dts create-synchronization-job --api-version 2020-01-01 \
        --biz-region-id "${region:-}" \
        --synchronization-job-name "$task_name" \
        --source-type "$source_type" \
        --destination-type "$dest_type")

    if [ $? -eq 0 ]; then
        echo "DTS 同步任务创建成功："
        echo "$result" | jq '.'

        # 提取任务ID
        local task_id
        task_id=$(echo "$result" | jq -r '.SynchronizationJobId')
        echo "同步任务ID: $task_id"

        log_result "${profile:-}" "$region" "dts" "sync-create" "$result"
    else
        echo "错误：DTS 同步任务创建失败。"
        echo "$result"
        return 1
    fi
}

# DTS 任务更新（支持fzf选择任务）
dts_update() {
    local task_id new_name=$2
    task_id=$(_dts_resolve_job_id "$1" "选择 DTS 迁移任务") || return 1

    # 如果没有提供新名称，提示输入
    if [ -z "$new_name" ]; then
        echo -n "请输入新的任务名称: "
        read -r new_name
        if [ -z "$new_name" ]; then
            echo "错误：新名称不能为空。" >&2
            return 1
        fi
    fi

    echo "更新 DTS 迁移任务："
    call_api_logged "dts" "set" "错误：DTS 迁移任务更新失败。" \
        -- dts configure-migration-job --api-version 2020-01-01 \
        --migration-job-id "$task_id" \
        --migration-job-name "$new_name"
}

# DTS 任务删除（迁移/同步/订阅；无参数时 fzf 从合并列表选择）
dts_delete() {
    local task_id=$1
    local kind=""
    local mig syn sub combined

    mig=$(call_aliyun_api dts describe-migration-jobs --api-version 2020-01-01) || {
        echo "错误：无法获取 DTS 迁移任务列表。请检查您的凭证和权限。" >&2
        return 1
    }
    syn=$(call_aliyun_api dts describe-synchronization-jobs --api-version 2020-01-01) || {
        echo "错误：无法获取 DTS 同步任务列表。请检查您的凭证和权限。" >&2
        return 1
    }
    sub=$(call_aliyun_api dts describe-subscription-instances --api-version 2020-01-01) || {
        echo "错误：无法获取 DTS 订阅任务列表。请检查您的凭证和权限。" >&2
        return 1
    }

    combined=$(
        {
            echo "$mig" | jq -r '.MigrationJobs.MigrationJob[]? | "migration \(.MigrationJobId) (\(.MigrationJobName)) [\(.Status)]"'
            echo "$syn" | jq -r '.SynchronizationInstances[]? | "sync \(.SynchronizationJobId // .InstanceId // .Id) (\(.SynchronizationJobName // .InstanceName // .Name // .SynchronizationObject)) [\(.Status // .DataSynchronizationStatus.Status)]"'
            echo "$sub" | jq -r '.SubscriptionInstanceInfos.SubscriptionInstanceInfo[]? | "subscribe \(.SubscriptionInstanceId) (\(.SubscriptionInstanceName)) [\(.Status)]"'
        } | sed '/^$/d'
    )

    if [ -z "$task_id" ]; then
        if [ -z "$combined" ]; then
            echo "错误：没有找到任何 DTS 任务（迁移、同步、订阅）。" >&2
            return 1
        fi
        local line_count
        line_count=$(echo "$combined" | grep -c '[^[:space:]]' || true)
        if [ "$line_count" -eq 1 ]; then
            kind=$(echo "$combined" | awk '{print $1}')
            task_id=$(echo "$combined" | awk '{print $2}')
            echo "自动选择唯一任务: [$kind] $task_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                local selected
                selected=$(select_with_fzf "选择要删除的 DTS 任务（迁移/同步/订阅）" "$combined")
                kind=$(echo "$selected" | awk '{print $1}')
                task_id=$(echo "$selected" | awk '{print $2}')
                if [ -z "$task_id" ] || [ -z "$kind" ]; then
                    echo "错误：未选择任务。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择任务，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    else
        kind=$(echo "$combined" | awk -v tid="$task_id" '$2 == tid { print $1; exit }')
        if [ -z "$kind" ]; then
            echo "错误：未找到 ID 为 $task_id 的 DTS 任务（迁移、同步、订阅）。" >&2
            return 1
        fi
    fi

    if [ -z "$task_id" ]; then
        echo "错误：任务 ID 不能为空。" >&2
        return 1
    fi

    local kind_cn del_label
    case "$kind" in
    migration)
        kind_cn="迁移"
        del_label="DTS迁移任务"
        ;;
    sync)
        kind_cn="同步"
        del_label="DTS同步任务"
        ;;
    subscribe)
        kind_cn="订阅"
        del_label="DTS订阅任务"
        ;;
    *)
        echo "错误：未知的任务类型：$kind" >&2
        return 1
        ;;
    esac

    if ! confirm_action "删除 DTS ${kind_cn}任务：$task_id"; then
        return 1
    fi

    echo "删除 DTS ${kind_cn}任务："
    local result
    case "$kind" in
    migration)
        result=$(call_aliyun_api dts delete-migration-job --api-version 2020-01-01 --migration-job-id "$task_id")
        ;;
    sync)
        result=$(call_aliyun_api dts delete-synchronization-job --api-version 2020-01-01 --synchronization-job-id "$task_id")
        ;;
    subscribe)
        result=$(call_aliyun_api dts delete-subscription-instance --api-version 2020-01-01 --subscription-instance-id "$task_id")
        ;;
    esac

    if [ $? -eq 0 ]; then
        echo "DTS ${kind_cn}任务删除成功。"
        log_delete_operation "${profile:-}" "$region" "dts" "$task_id" "$del_label" "成功" "$result"
    else
        echo "DTS ${kind_cn}任务删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "dts" "$task_id" "$del_label" "失败" "$result"
        return 1
    fi
}

# DTS 任务启动（支持fzf选择任务）
dts_start() {
    local task_id
    task_id=$(_dts_resolve_job_id "$1" "选择要启动的 DTS 迁移任务" \
        '.Status == "Ready" or .Status == "Paused" or .Status == "Failed"' \
        "错误：没有找到可启动的 DTS 迁移任务。") || return 1

    echo "启动 DTS 迁移任务：$task_id"
    local result
    result=$(call_aliyun_api dts configure-migration-job --api-version 2020-01-01 --migration-job-id "$task_id" --migration-job-id-list "[\"$task_id\"]" --action-start)

    if [ $? -eq 0 ]; then
        echo "DTS 迁移任务启动命令已发送。"
        echo "$result" | jq '.'

        # 等待任务状态变为 Prechecking 或 Preparing 或 migrating
        echo "等待任务启动..."
        local status
        for _ in {1..30}; do
            sleep 5
            status=$(call_aliyun_api dts describe-migration-jobs --api-version 2020-01-01 --migration-job-id "$task_id" 2>/dev/null | jq -r '.MigrationJobs.MigrationJob[0].Status')
            if [[ "$status" == "Prechecking"* || "$status" == "Preparing"* || "$status" == "Migrating"* || "$status" == "NotStarted" ]]; then
                echo "任务状态: $status"
                break
            fi
            echo "当前状态: $status"
        done
        log_result "${profile:-}" "$region" "dts" "start" "$result"
    else
        echo "错误：DTS 迁移任务启动失败。"
        echo "$result"
        return 1
    fi
}

# DTS 任务停止（支持fzf选择任务）
dts_stop() {
    local task_id
    task_id=$(_dts_resolve_job_id "$1" "选择要停止的 DTS 迁移任务" \
        '.Status == "Migrating" or .Status == "Prechecking" or .Status == "Preparing"' \
        "错误：没有找到可停止的 DTS 迁移任务。") || return 1

    echo "停止 DTS 迁移任务：$task_id"
    local result
    result=$(call_aliyun_api dts suspend-migration-job --api-version 2020-01-01 --migration-job-id "$task_id")

    if [ $? -eq 0 ]; then
        echo "DTS 迁移任务停止命令已发送。"
        echo "$result" | jq '.'

        # 等待任务状态变为 Paused
        echo "等待任务停止..."
        local status
        for _ in {1..30}; do
            sleep 5
            status=$(call_aliyun_api dts describe-migration-job-status --api-version 2020-01-01 --migration-job-id "$task_id" 2>/dev/null | jq -r '.MigrationJobs.MigrationJob[0].Status')
            if [ "$status" = "Paused" ]; then
                echo "任务已成功停止。"
                break
            fi
            echo "当前状态: $status"
        done
        log_result "${profile:-}" "$region" "dts" "stop" "$result"
    else
        echo "错误：DTS 迁移任务停止失败。"
        echo "$result"
        return 1
    fi
}

# DTS 任务状态查询（支持fzf选择任务）
dts_status() {
    local task_id
    task_id=$(_dts_resolve_job_id "$1" "选择要查看状态的 DTS 迁移任务") || return 1

    echo "查询 DTS 迁移任务状态：$task_id"
    echo "DTS 迁移任务状态："
    call_api_logged "dts" "status" "错误：DTS 迁移任务状态查询失败。" \
        -- dts describe-migration-job-status --api-version 2020-01-01 --migration-job-id "$task_id"
}

# DTS 任务详情获取（支持fzf选择任务）
dts_job_get() {
    local task_id
    task_id=$(_dts_resolve_job_id "$1" "选择要查看详情的 DTS 迁移任务") || return 1

    echo "获取 DTS 迁移任务详情：$task_id"
    echo "DTS 迁移任务详情："
    call_api_logged "dts" "get-job" "错误：DTS 迁移任务详情获取失败。" \
        -- dts describe-migration-job-detail --api-version 2020-01-01 --migration-job-id "$task_id"
}
