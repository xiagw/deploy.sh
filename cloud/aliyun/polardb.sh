#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# PolarDB (云数据库 PolarDB) 相关函数

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_polardb_help() {
    echo "PolarDB (云数据库 PolarDB) 操作："
    echo "  get                                    - 列出 PolarDB 集群"
    echo "  add <名称> <引擎> <版本> <规格> [地域]  - 创建 PolarDB 集群"
    echo "  set [<集群ID>] [<新名称>] [地域]       - 更新 PolarDB 集群（集群ID和新名称都是可选的，可使用fzf选择）"
    echo "  del [<集群ID>] [地域]                  - 删除 PolarDB 集群（集群ID可选，可使用fzf选择）"
    echo "  add-acc <集群ID> <账号> <密码> [描述] - 创建数据库账号"
    echo "  del-acc <集群ID> <账号>            - 删除数据库账号"
    echo "  get-acc <集群ID>                   - 列出数据库账号"
    echo "  set-acc <集群ID> <账号> <数据库名> [权限]  - 设置账号数据库权限"
    echo "  get-db <集群ID>                        - 列出数据库"
    echo "  add-db <集群ID> <数据库名> [字符集]    - 创建数据库"
    echo "  del-db [<集群ID> <数据库名>]         - 删除数据库（参数可选，可用 fzf 选择）"
    echo "  get-ip <集群ID>                        - 列出集群IP白名单"
    echo "  set-ip <集群ID> <IP列表>               - 设置集群IP白名单（覆盖模式）"
    echo "  ip-append <集群ID> <IP列表>            - 追加IP到白名单"
    echo "  ip-clear <集群ID>                      - 清空集群IP白名单"
    echo "  get-bak [<集群ID>] [format]         - 列出备份集（默认最近30天）"
    echo "  del-bak [<集群ID>] [<备份ID>]       - 删除备份集（可用 fzf 选择）"
    echo

    echo "示例："
    echo "  $0 polardb get"
    echo "  $0 polardb add my-polardb MySQL 8.0 polar.mysql.x4.large"
    echo "  $0 polardb set pc-xxxxxxxxxxxxx new-name"
    echo "  $0 polardb del pc-xxxxxxxxxxxxx"
    echo "  $0 polardb add-acc pc-xxxxxxxxxxxxx myuser mypassword '测试账号'"
    echo "  $0 polardb del-acc pc-xxxxxxxxxxxxx myuser"
    echo "  $0 polardb get-acc pc-xxxxxxxxxxxxx"
    echo "  $0 polardb set-acc pc-xxxxxxxxxxxxx myuser mydb ReadWrite"
    echo "  $0 polardb get-db pc-xxxxxxxxxxxxx"
    echo "  $0 polardb add-db pc-xxxxxxxxxxxxx mydb utf8mb4"
    echo "  $0 polardb del-db pc-xxxxxxxxxxxxx mydb"
    echo "  $0 polardb get-ip pc-xxxxxxxxxxxxx"
    echo "  $0 polardb set-ip pc-xxxxxxxxxxxxx '192.168.1.1,10.0.0.0/8'"
    echo "  $0 polardb ip-append pc-xxxxxxxxxxxxx '192.168.2.1'"
    echo "  $0 polardb ip-clear pc-xxxxxxxxxxxxx"
    echo "  $0 polardb get-bak pc-xxxxxxxxxxxxx"
    echo "  $0 polardb del-bak pc-xxxxxxxxxxxxx cb-xxxx"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_polardb_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) polardb_list "$@" ;;
    add) polardb_create "$@" ;;
    set) polardb_update "$@" ;;
    del) polardb_delete "$@" ;;
    add-acc) polardb_account_create "$@" ;;
    set-acc) polardb_account_grant "$@" ;;
    del-acc) polardb_account_delete "$@" ;;
    get-acc) polardb_account_list "$@" ;;
    get-db) polardb_db_list "$@" ;;
    add-db) polardb_db_create "$@" ;;
    del-db) polardb_db_delete "$@" ;;
    get-ip) polardb_ip_get "$@" ;;
    set-ip) polardb_ip_set "$@" ;;
    ip-append) polardb_ip_append "$@" ;;
    ip-clear) polardb_ip_clear "$@" ;;
    get-bak | get-backup) polardb_backup_list "$@" ;;
    del-bak | del-backup) polardb_backup_delete "$@" ;;
    help) show_polardb_help ;;
    *)
        echo "错误：未知的 PolarDB 操作：$operation" >&2
        show_polardb_help
        exit 1
        ;;
    esac
}

polardb_list() {
    local format=${1:-human}
    local result
    if ! result=$(call_aliyun_api polardb describe-db-clusters --biz-region-id "${region:-}"); then
        echo "错误：无法获取 PolarDB 集群列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    local table_header="DBClusterId\tDBClusterDescription\tDBClusterStatus\tDBType\tDBVersion\tDBNodeClass\tRegionId\tCreateTime"
    local jq_filter='.Items.DBCluster[] | [.DBClusterId, .DBClusterDescription, .DBClusterStatus, .DBType, .DBVersion, .DBNodeClass, .RegionId, .CreateTime] | @tsv'
    local status_mapper='BEGIN {FS="\t"; OFS="\t"}
    {
        status = $3;
        if (status == "Running") status = "运行中";
        else if (status == "Creating") status = "创建中";
        else if (status == "Deleting") status = "删除中";
        else if (status == "Stopped") status = "已停止";
        else status = "未知";
        printf "%-16s  %-18s  %-6s  %-6s  %-5s  %-17s  %-12s  %s\n", $1, $2, status, $4, $5, $6, $7, $8
    }'

    format_output "$result" "$format" "polardb" "list" \
        "$table_header" "$jq_filter" "$status_mapper" \
        "没有找到 PolarDB 集群。" "列出 PolarDB 集群："
}

polardb_create() {
    local name=$1 db_type=$2 db_version=$3 db_node_class=$4

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$name" ] || [ -z "$db_type" ] || [ -z "$db_version" ] || [ -z "$db_node_class" ]; then
        echo "使用 fzf 交互式模式创建 PolarDB 集群"

        # 输入名称
        if [ -z "$name" ]; then
            read -r -p "请输入 PolarDB 集群名称: " name
            if [ -z "$name" ]; then
                echo "错误：集群名称不能为空。" >&2
                return 1
            fi
        fi

        # 选择数据库类型
        if [ -z "$db_type" ]; then
            echo "正在获取可用的 PolarDB 数据库类型..."
            local db_type_list="MySQL
PostgreSQL"
            if type select_with_fzf >/dev/null 2>&1; then
                db_type=$(select_with_fzf "选择 PolarDB 数据库类型" "$db_type_list")
            else
                echo "错误：需要选择数据库类型，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi

        # 选择版本
        if [ -z "$db_version" ]; then
            echo "正在获取 $db_type 的可用 PolarDB 版本..."
            local version_list
            case "$db_type" in
            MySQL)
                version_list="8.0
8.0.1
8.0.2
5.7
5.6"
                ;;
            PostgreSQL)
                version_list="15.0
14.0
13.0
11.0"
                ;;
            *)
                echo "错误：不支持的数据库类型：$db_type" >&2
                return 1
                ;;
            esac
            if type select_with_fzf >/dev/null 2>&1; then
                db_version=$(select_with_fzf "选择 PolarDB 版本" "$version_list")
            else
                echo "错误：需要选择数据库版本，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi

        # 选择节点规格
        if [ -z "$db_node_class" ]; then
            echo "正在获取 $db_type $db_version 的可用 PolarDB 节点规格..."
            local class_result
            class_result=$(call_aliyun_api polardb describe-db-node-classes \
                --biz-region-id "${region:-}" \
                --db-type "$db_type" \
                --db-version "$db_version" \
                --pay-type "Postpaid")

            local class_list
            if [ $? -eq 0 ] && [ -n "$class_result" ]; then
                class_list=$(echo "$class_result" | jq -r '.Items[] | select(.ZoneId != null) | .SupportedDBNodeClasses[] | "\(.DBNodeClass)"' | sort -u)

                if [ -z "$class_list" ]; then
                    echo "警告：无法从 API 获取节点规格，使用备用列表。" >&2
                    case "$db_type" in
                    MySQL)
                        class_list="polar.mysql.x8.small
polar.mysql.x8.medium
polar.mysql.x8.large
polar.mysql.c1.medium
polar.mysql.c2.large"
                        ;;
                    PostgreSQL)
                        class_list="polar.pg.x8.small
polar.pg.x8.medium
polar.pg.x8.large
polar.pg.c1.medium
polar.pg.c2.large"
                        ;;
                    esac
                fi
            else
                echo "警告：调用 DescribeDBNodeClasses API 失败，使用备用列表。" >&2
                case "$db_type" in
                MySQL)
                    class_list="polar.mysql.x8.small
polar.mysql.x8.medium
polar.mysql.x8.large
polar.mysql.c1.medium
polar.mysql.c2.large"
                    ;;
                PostgreSQL)
                    class_list="polar.pg.x8.small
polar.pg.x8.medium
polar.pg.x8.large
polar.pg.c1.medium
polar.pg.c2.large"
                    ;;
                esac
            fi

            if type select_with_fzf >/dev/null 2>&1; then
                db_node_class=$(select_with_fzf "选择 PolarDB 节点规格" "$class_list")
            else
                echo "错误：需要选择节点规格，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    echo "创建 PolarDB 集群："
    call_api_logged "polardb" "create" "错误：PolarDB 集群创建失败。" \
        -- polardb create-db-cluster \
        --biz-region-id "$region" \
        --db-type "$db_type" \
        --db-version "$db_version" \
        --db-node-class "$db_node_class" \
        --db-cluster-description "$name" \
        --pay-type Postpaid \
        --db-node-num 1
}

polardb_update() {
    local cluster_id new_name=$2

    local raw
    raw=$(_polardb_resolve_cluster_id "$1" "选择要更新的 PolarDB 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    # 输入新名称
    if [ -z "$new_name" ]; then
        read -r -p "请输入新的集群名称: " new_name
        if [ -z "$new_name" ]; then
            echo "错误：新名称不能为空。" >&2
            return 1
        fi
    fi

    echo "更新 PolarDB 集群："
    call_api_logged "polardb" "update" "错误：PolarDB 集群更新失败。" \
        -- polardb modify-db-cluster-description \
        --db-cluster-id "$cluster_id" \
        --db-cluster-description "$new_name"
}

polardb_delete() {
    local cluster_id

    local raw
    raw=$(_polardb_resolve_cluster_id "$1" "选择要删除的 PolarDB 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    confirm_action "您即将删除 PolarDB 集群：$cluster_id" || return 1

    echo "删除 PolarDB 集群："
    call_api_del_logged "polardb" "$cluster_id" "PolarDB集群" "错误：PolarDB 集群删除失败。" \
        -- polardb delete-db-cluster --db-cluster-id "$cluster_id"
}

# 创建数据库账号
polardb_account_create() {
    local cluster_id=$1
    local account_name=$2
    local password=${3:-$(_get_random_password 2>/dev/null)}
    local description=${4:-"Created by CLI"}

    if [ -z "$cluster_id" ] || [ -z "$account_name" ] || [ -z "$password" ]; then
        echo "错误：集群ID、账号名和密码不能为空。" >&2
        echo "用法：polardb add-acc <集群ID> <账号> <密码> [描述]" >&2
        return 1
    fi

    # 验证密码复杂度
    if [ "${#password}" -lt 8 ] || [ "${#password}" -gt 32 ]; then
        echo "错误：密码长度必须在8-32位之间。" >&2
        return 1
    fi

    echo "$password" | grep -q "[A-Z]" || {
        echo "错误：密码必须包含大写字母。" >&2
        return 1
    }

    echo "$password" | grep -q "[a-z]" || {
        echo "错误：密码必须包含小写字母。" >&2
        return 1
    }

    echo "$password" | grep -q "[0-9]" || {
        echo "错误：密码必须包含数字。" >&2
        return 1
    }

    echo "$password" | grep -q '[^[:alnum:]]' || {
        password="${password}@"
    }

    echo "创建 PolarDB 账号："
    echo "集群ID: $cluster_id"
    echo "账号: $account_name / $password"
    echo "描述: $description"

    local result
    result=$(call_aliyun_api polardb create-account \
        --db-cluster-id "$cluster_id" \
        --account-name "$account_name" \
        --account-password "$password" \
        --account-description "$description" \
        --account-type Normal \
       )

    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "账号创建成功："
        echo "$result" | jq '.'

        # 等待账号创建完成
        echo "等待账号创建完成..."
        sleep 5

        # 自动设置默认权限
        if ! polardb_account_grant "$cluster_id" "$account_name" "$account_name" "ReadWrite"; then
            echo "警告：默认权限设置失败，请手动设置权限。"
        fi
    else
        echo "错误：账号创建失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "polardb" "account-create" "$result"
}

# 删除数据库账号
polardb_account_delete() {
    local cluster_id=$1
    local account_name=$2

    if [ -z "$cluster_id" ] || [ -z "$account_name" ]; then
        echo "错误：集群ID和账号名不能为空。" >&2
        echo "用法：polardb del-acc <集群ID> <账号>" >&2
        return 1
    fi

    confirm_action "您即将删除 PolarDB 账号：$account_name" || return 1

    echo "删除 PolarDB 账号："
    call_api_del_logged "polardb" "$account_name" "PolarDB账号" "错误：PolarDB 账号删除失败。" \
        -- polardb delete-account \
        --db-cluster-id "$cluster_id" \
        --account-name "$account_name"
}

# 列出数据库账号
polardb_account_list() {
    local cluster_id=$1
    local format=${2:-human}

    if is_output_format "$cluster_id"; then
        format=$cluster_id
        cluster_id=""
    fi

    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        echo "用法：polardb get-acc <集群ID> [format]" >&2
        return 1
    fi

    local result
    result=$(call_aliyun_api polardb describe-accounts --db-cluster-id "$cluster_id")

    local table_header="账号名\t账号类型\t状态\t描述\t数据库\t权限\t权限详情"
    local jq_filter='.Accounts[] |
        . as $account |
        (.DatabasePrivileges // []) |
        if length > 0 then
            .[] | [
                $account.AccountName,
                $account.AccountType,
                $account.AccountStatus,
                $account.AccountDescription,
                .DBName,
                .AccountPrivilege,
                (.AccountPrivilegeDetail // "")
            ] | @tsv
        else
            [
                $account.AccountName,
                $account.AccountType,
                $account.AccountStatus,
                $account.AccountDescription,
                "-",
                "-",
                "-"
            ] | @tsv
        end'
    local status_mapper='BEGIN {FS="\t"; OFS="\t"}
        {
            printf "%-18s  %-10s  %-8s  %-20s  %-16s  %-10s  %s\n",
                $1, $2, $3, substr($4, 1, 18), $5, $6, $7
        }'

    format_output "$result" "$format" "polardb" "account-list" \
        "$table_header" "$jq_filter" "$status_mapper" \
        "没有找到账号。" "列出 PolarDB 账号："
}

# 列出数据库
polardb_db_list() {
    local cluster_id=$1
    local format=${2:-human}

    if is_output_format "$cluster_id"; then
        format=$cluster_id
        cluster_id=""
    fi

    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        echo "用法：polardb get-db <集群ID> [format]" >&2
        return 1
    fi

    local result
    result=$(call_aliyun_api polardb describe-databases --db-cluster-id "$cluster_id")

    local table_header="数据库名\t字符集\t状态\t描述"
    local jq_filter='.Databases.Database[] | [.DBName, .CharacterSetName, .DBStatus, .DBDescription] | @tsv'
    local status_mapper='BEGIN {FS="\t"; OFS="\t"}
        {
            printf "%-18s  %-15s  %-8s  %s\n", $1, $2, $3, substr($4, 1, 20)
        }'

    format_output "$result" "$format" "polardb" "db-list" \
        "$table_header" "$jq_filter" "$status_mapper" \
        "没有找到数据库。" "列出数据库："
}

# 创建数据库
polardb_db_create() {
    local cluster_id=$1
    local db_name=$2
    local charset=${3:-utf8mb4}

    if [ -z "$cluster_id" ] || [ -z "$db_name" ]; then
        echo "错误：集群ID和数据库名不能为空。" >&2
        echo "用法：polardb add-db <集群ID> <数据库名> [字符集]" >&2
        return 1
    fi

    echo "创建数据库："
    echo "集群ID: $cluster_id"
    echo "数据库名: $db_name"
    echo "字符集: $charset"

    call_api_logged "polardb" "db-create" "错误：数据库创建失败。" \
        -- polardb create-database \
        --db-cluster-id "$cluster_id" \
        --db-name "$db_name" \
        --character-set-name "$charset" \
        --db-description "Created by CLI"
}

# 删除数据库
polardb_db_delete() {
    local cluster_id=$1
    local db_name=$2

    if [ -n "$db_name" ] && [ -z "$cluster_id" ]; then
        echo "错误：仅提供数据库名时无法定位集群，请提供集群 ID，或使用「polardb del-db」由 fzf 依次选择集群与数据库。" >&2
        echo "用法：polardb del-db [<集群ID> <数据库名>]" >&2
        return 1
    fi

    if [ -z "$cluster_id" ] || [ -z "$db_name" ]; then
        if [ -z "$cluster_id" ]; then
            local raw
            raw=$(_polardb_resolve_cluster_id "" "选择 PolarDB 集群") || return 1
            cluster_id=$(echo "$raw" | awk '{print $1}')
        fi

        if [ -z "$db_name" ]; then
            local raw_db
            raw_db=$(resolve_resource_id "" "选择要删除的数据库" "错误：在指定集群中没有找到数据库。" \
                '.Databases.Database[] | "\(.DBName) [\(.CharacterSetName)] [\(.DBStatus)]"' \
                -- polardb describe-databases --db-cluster-id "$cluster_id") || return 1
            db_name=$(echo "$raw_db" | awk '{print $1}')
        fi
    fi

    if [ -z "$cluster_id" ] || [ -z "$db_name" ]; then
        echo "错误：集群ID和数据库名不能为空。" >&2
        echo "用法：polardb del-db [<集群ID> <数据库名>]" >&2
        return 1
    fi

    confirm_action "您即将删除数据库：$db_name" || return 1

    echo "删除数据库："
    call_api_del_logged "polardb" "$db_name" "数据库" "错误：数据库删除失败。" \
        -- polardb delete-database \
        --db-cluster-id "$cluster_id" \
        --db-name "$db_name"
}

# 设置账号数据库权限函数
polardb_account_grant() {
    local cluster_id=$1
    local account_name=$2
    local db_name=$3
    local privilege=${4:-ReadWrite}

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$cluster_id" ] || [ -z "$account_name" ] || [ -z "$db_name" ]; then
        if [ -z "$cluster_id" ]; then
            local raw
            raw=$(_polardb_resolve_cluster_id "" "选择 PolarDB 集群") || return 1
            cluster_id=$(echo "$raw" | awk '{print $1}')
        fi

        if [ -z "$account_name" ]; then
            local raw_acc
            raw_acc=$(resolve_resource_id "" "选择数据库账号" "错误：在指定集群中没有找到数据库账号。" \
                '.Accounts.Account[] | "\(.AccountName) [\(.AccountType)] [\(.AccountStatus)]"' \
                -- polardb describe-accounts --db-cluster-id "$cluster_id") || return 1
            account_name=$(echo "$raw_acc" | awk '{print $1}')
        fi

        if [ -z "$db_name" ]; then
            local raw_db
            raw_db=$(resolve_resource_id "" "选择数据库" "错误：在指定集群中没有找到数据库。" \
                '.Databases.Database[] | "\(.DBName) [\(.CharacterSetName)] [\(.DBStatus)]"' \
                -- polardb describe-databases --db-cluster-id "$cluster_id") || return 1
            db_name=$(echo "$raw_db" | awk '{print $1}')
        fi
    fi

    if [ -z "$cluster_id" ] || [ -z "$account_name" ] || [ -z "$db_name" ]; then
        echo "错误：集群ID、账号名和数据库名不能为空。" >&2
        echo "用法：polardb set-acc <集群ID> <账号> <数据库名> [权限]" >&2
        return 1
    fi

    echo "设置账号权限："
    echo "集群ID: $cluster_id"
    echo "账号名: $account_name"
    echo "数据库: $db_name"
    echo "权限: $privilege"

    if call_api_logged "polardb" "account-set" "错误：权限设置失败。" \
        -- polardb grant-account-privilege \
        --db-cluster-id "$cluster_id" \
        --account-name "$account_name" \
        --db-name "$db_name" \
        --account-privilege "$privilege"; then
        echo "账号 $account_name 已被授予 $privilege 权限，可访问数据库 $db_name"
    fi
}

# 列出IP白名单
polardb_ip_get() {
    local cluster_id

    local raw
    raw=$(_polardb_resolve_cluster_id "$1" "选择 PolarDB 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    echo "获取集群 $cluster_id 的IP白名单："

    local result
    result=$(call_aliyun_api polardb describe-db-cluster-access-whitelist --db-cluster-id "$cluster_id")

    if [ $? -ne 0 ]; then
        echo "错误：无法获取IP白名单信息。" >&2
        echo "$result"
        return 1
    fi

    # 输出人类可读格式
    echo "IP白名单组名称     IP列表"
    echo "----------------  ----------------------------------------"
    echo "$result" | jq -r '.Items.DBClusterIPArray[]? | select(. != null) | "\(.DBClusterIPArrayName // "N/A")  \(.SecurityIps // "N/A")"' |
        awk 'BEGIN {FS="  "; OFS="  "}
        {
            printf "%-16s  %s\n", $1, $2
        }'

    log_result "${profile:-}" "$region" "polardb" "get-ip" "$result"
}

# 设置IP白名单（覆盖模式）
polardb_ip_set() {
    local cluster_id=$1
    local ips=$2
    local ip_array_name=$3

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$cluster_id" ] || [ -z "$ips" ]; then
        echo "使用 fzf 交互式模式设置IP白名单（覆盖模式）"

        # 选择集群ID
        if [ -z "$cluster_id" ]; then
            local raw
            raw=$(_polardb_resolve_cluster_id "" "选择 PolarDB 集群") || return 1
            cluster_id=$(echo "$raw" | awk '{print $1}')
        fi

        # 显示当前IP白名单并让用户选择或输入新IP
        local current_whitelist
        current_whitelist=$(call_aliyun_api polardb describe-db-cluster-access-whitelist --db-cluster-id "$cluster_id" 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$current_whitelist" ]; then
            echo "当前集群的IP白名单："
            echo "$current_whitelist" | jq -r '.Items.DBClusterIPArray[]? | select(. != null) | "\(.DBClusterIPArrayName // "N/A")  \(.SecurityIps // "N/A")"' |
                awk 'BEGIN {FS="  "; OFS="  "}
                {
                    printf "%-16s  %s\n", $1, $2
                }'
            echo ""
        fi

        # 询问是否要修改现有IP白名单组或创建新组
        echo "请选择操作方式："
        local choice
        if type select_with_fzf >/dev/null 2>&1; then
            choice=$(select_with_fzf "选择操作方式" "输入新的IP列表覆盖全部
从现有白名单组中选择并修改
创建新的白名单组")
        else
            echo "1. 输入新的IP列表覆盖全部"
            echo "2. 从现有白名单组中选择并修改"
            echo "3. 创建新的白名单组"
            read -r -p "请选择 (1-3): " choice_num
            case "$choice_num" in
                1) choice="输入新的IP列表覆盖全部" ;;
                2) choice="从现有白名单组中选择并修改" ;;
                3) choice="创建新的白名单组" ;;
                *)
                    echo "错误：无效的选择。" >&2
                    return 1
                    ;;
            esac
        fi

        case "$choice" in
            *"输入新的IP列表覆盖全部"*)
                read -r -p "请输入IP列表（多个IP用逗号分隔）: " ips
                if [ -z "$ips" ]; then
                    echo "错误：IP列表不能为空。" >&2
                    return 1
                fi
                ;;
            *"从现有白名单组中选择并修改"*)
                # 获取现有白名单组
                local ip_array_list
                ip_array_list=$(echo "$current_whitelist" | jq -r '.Items.DBClusterIPArray[].DBClusterIPArrayName' 2>/dev/null)

                if [ -n "$ip_array_list" ] && [ "$ip_array_list" != "" ]; then
                    if type select_with_fzf >/dev/null 2>&1; then
                        ip_array_name=$(select_with_fzf "选择要修改的IP白名单组" "$ip_array_list")
                        if [ -z "$ip_array_name" ]; then
                            echo "错误：未选择IP白名单组。" >&2
                            return 1
                        fi
                    else
                        echo "$ip_array_list" | nl
                        read -r -p "请选择要修改的白名单组编号: " array_num
                        ip_array_name=$(echo "$ip_array_list" | sed -n "${array_num}p")
                    fi

                    # 获取当前白名单组的IP列表
                    local current_ips
                    current_ips=$(echo "$current_whitelist" | jq -r ".Items.DBClusterIPArray[] | select(.DBClusterIPArrayName == \"$ip_array_name\") | .SecurityIps" 2>/dev/null)

                    echo "当前 '$ip_array_name' 白名单组的IP列表：$current_ips"
                    read -r -p "请输入新的IP列表（多个IP用逗号分隔）: " ips
                    if [ -z "$ips" ]; then
                        echo "错误：IP列表不能为空。" >&2
                        return 1
                    fi
                else
                    echo "没有找到现有白名单组，将创建新的IP列表。"
                    read -r -p "请输入IP列表（多个IP用逗号分隔）: " ips
                    if [ -z "$ips" ]; then
                        echo "错误：IP列表不能为空。" >&2
                        return 1
                    fi
                fi
                ;;
            *"创建新的白名单组"*)
                read -r -p "请输入新的IP白名单组名称: " ip_array_name
                if [ -z "$ip_array_name" ]; then
                    echo "错误：IP白名单组名称不能为空。" >&2
                    return 1
                fi
                read -r -p "请输入IP列表（多个IP用逗号分隔）: " ips
                if [ -z "$ips" ]; then
                    echo "错误：IP列表不能为空。" >&2
                    return 1
                fi
                ;;
        esac
    fi

    if [ -z "$cluster_id" ] || [ -z "$ips" ]; then
        echo "错误：集群ID和IP列表不能为空。" >&2
        echo "用法：polardb set-ip <集群ID> <IP列表> [IP白名单组名]" >&2
        return 1
    fi

    echo "正在设置集群 $cluster_id 的IP白名单（覆盖模式）："
    echo "IP列表: $ips"
    if [ -n "$ip_array_name" ]; then
        echo "IP白名单组: $ip_array_name"
    fi

    local result
    local params=(--db-cluster-id "$cluster_id" --security-ips "$ips" --modify-mode "Cover")

    # 如果指定了IP白名单组名，需要添加相应参数
    if [ -n "$ip_array_name" ]; then
        params+=(--db-cluster-ip-array-name "$ip_array_name")
    fi

    result=$(call_aliyun_api polardb modify-db-cluster-access-whitelist "${params[@]}")

    if [ $? -ne 0 ]; then
        echo "错误：设置IP白名单失败。" >&2
        echo "$result"
        return 1
    fi

    echo "IP白名单设置成功。"
    echo "$result" | jq '.'

    log_result "${profile:-}" "$region" "polardb" "set-ip" "$result"
}

# 追加IP到白名单
polardb_ip_append() {
    local cluster_id ips=$2

    local raw
    raw=$(_polardb_resolve_cluster_id "$1" "选择 PolarDB 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    # 输入IP列表
    if [ -z "$ips" ]; then
        read -r -p "请输入要追加的IP列表（多个IP用逗号分隔）: " ips
        if [ -z "$ips" ]; then
            echo "错误：IP列表不能为空。" >&2
            return 1
        fi
    fi

    if [ -z "$ips" ]; then
        echo "错误：集群ID和IP列表不能为空。" >&2
        echo "用法：polardb ip-append <集群ID> <IP列表>" >&2
        return 1
    fi

    echo "正在追加IP到集群 $cluster_id 的白名单："
    echo "IP列表: $ips"

    local result
    result=$(call_aliyun_api polardb modify-db-cluster-access-whitelist \
        --db-cluster-id "$cluster_id" \
        --security-ips "$ips" \
        --modify-mode "Append" \
       )

    if [ $? -ne 0 ]; then
        echo "错误：追加IP白名单失败。" >&2
        echo "$result"
        return 1
    fi

    echo "IP白名单追加成功。"
    echo "$result" | jq '.'

    log_result "${profile:-}" "$region" "polardb" "ip-append" "$result"
}

# 清空IP白名单
polardb_ip_clear() {
    local cluster_id

    local raw
    raw=$(_polardb_resolve_cluster_id "$1" "选择要清空白名单的 PolarDB 集群") || return 1
    cluster_id=$(echo "$raw" | awk '{print $1}')

    confirm_action "您即将清空集群 $cluster_id 的IP白名单，这将阻止所有外部访问" || return 1

    echo "正在清空集群 $cluster_id 的IP白名单："

    local result
    # 将IP白名单设置为本地localhost以保留基本访问能力
    result=$(call_aliyun_api polardb modify-db-cluster-access-whitelist \
        --db-cluster-id "$cluster_id" \
        --security-ips "127.0.0.1" \
        --modify-mode "Cover" \
       )

    if [ $? -ne 0 ]; then
        echo "错误：清空IP白名单失败。" >&2
        echo "$result"
        return 1
    fi

    echo "IP白名单已清空（保留127.0.0.1以维持基本访问）。"
    echo "$result" | jq '.'

    log_result "${profile:-}" "$region" "polardb" "ip-clear" "$result"
}

# 交互式解析集群ID（fzf 选择，单个自动选中）
_polardb_resolve_cluster_id() {
    resolve_resource_id "$1" "${2:-选择 PolarDB 集群}" "错误：没有找到 PolarDB 集群。" \
        '.Items.DBCluster[] | "\(.DBClusterId) (\(.DBClusterDescription)) [\(.DBType)]"' \
        -- polardb describe-db-clusters --biz-region-id "$region"
}

# 生成 describe-backups 必填的 UTC 时间范围（最近 N 天，格式 yyyy-MM-ddTHH:mmZ）
_polardb_backup_time_range() {
    local days=${1:-30}
    local end_time start_time
    end_time=$(date -u +%Y-%m-%dT%H:%MZ)
    start_time=$(date -u -v-"${days}"d +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -d "${days} days ago" +%Y-%m-%dT%H:%MZ 2>/dev/null)
    if [ -z "$start_time" ]; then
        echo "错误：无法计算起始时间。" >&2
        return 1
    fi
    echo "$start_time $end_time"
}

# 列出备份集
polardb_backup_list() {
    local cluster_id
    cluster_id=$(_polardb_resolve_cluster_id "$1" "选择要查看备份的 PolarDB 集群")
    [ $? -ne 0 ] && return 1
    local format=${2:-human}

    local time_range start_time end_time
    time_range=$(_polardb_backup_time_range 30) || return 1
    start_time=${time_range% *}
    end_time=${time_range#* }

    local result
    result=$(call_aliyun_api polardb describe-backups \
        --db-cluster-id "$cluster_id" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --page-size 50 \
        --page-number 1)

    if [ $? -ne 0 ]; then
        echo "错误：无法获取备份列表。" >&2
        echo "$result" >&2
        return 1
    fi

    local table_header="BackupId\tBackupMode\tBackupStatus\tStartTime\tEndTime\tSize(B)\tMethod"
    local jq_filter='.Items.Backup[]? | [.BackupId, .BackupMode, .BackupStatus, .BackupStartTime, .BackupEndTime, (.BackupSetSize // 0 | tostring), (.BackupMethod // "-")] | @tsv'
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {
        mode=$2; if(mode=="Manual") mode="手动"; else if(mode=="Automated") mode="自动";
        status=$3; if(status=="OK"||status=="Success") status="成功"; else if(status=="Failed") status="失败";
        printf "%-12s  %-6s  %-6s  %s  %s  %s  %s\n", $1, mode, status, $4, $5, $6, $7
    }'
    format_output "$result" "$format" "polardb" "get-bak" "$table_header" "$jq_filter" \
        "$status_mapper" "没有找到备份集。" \
        "列出 PolarDB 集群备份（$start_time ~ $end_time）：$cluster_id" \
        "" '.Items.Backup | length'
}

# 删除备份集（仅一级手动备份等可删，具体以 API 限制为准）
polardb_backup_delete() {
    local cluster_id
    cluster_id=$(_polardb_resolve_cluster_id "$1" "选择要清理备份的 PolarDB 集群")
    [ $? -ne 0 ] && return 1
    local backup_id=$2

    if [ -z "$backup_id" ]; then
        local time_range start_time end_time
        time_range=$(_polardb_backup_time_range 30) || return 1
        start_time=${time_range% *}
        end_time=${time_range#* }

        backup_id=$(resolve_resource_id "" "选择要删除的备份集" "错误：没有找到备份集。" \
            '.Items.Backup[]? | "\(.BackupId) [\(.BackupMode)] [\(.BackupStatus)] \(.BackupEndTime) \((.BackupSetSize // 0 | tostring))B"' \
            -- polardb describe-backups --db-cluster-id "$cluster_id" \
            --start-time "$start_time" --end-time "$end_time" \
            --page-size 50 --page-number 1) || return 1
    fi

    if ! validate_required_params "$cluster_id" "$backup_id" "错误：集群ID和备份ID不能为空。"; then
        return 1
    fi

    confirm_action "您即将删除 PolarDB 集群 $cluster_id 的备份集：$backup_id" || return 1

    echo "删除备份集："
    call_api_logged "polardb" "del-bak" "错误：备份集删除失败（自动备份保留期内不可删除）。" \
        -- polardb delete-backup --db-cluster-id "$cluster_id" --backup-id "$backup_id" || return 1
    echo "备份集删除成功。"
}
