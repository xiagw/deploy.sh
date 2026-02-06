#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# PolarDB (云数据库 PolarDB) 相关函数

show_polardb_help() {
    echo "PolarDB (云数据库 PolarDB) 操作："
    echo "  get                                    - 列出 PolarDB 集群"
    echo "  add <名称> <引擎> <版本> <规格> [地域]  - 创建 PolarDB 集群"
    echo "  set [<集群ID>] [<新名称>] [地域]       - 更新 PolarDB 集群（集群ID和新名称都是可选的，可使用fzf选择）"
    echo "  del [<集群ID>] [地域]                  - 删除 PolarDB 集群（集群ID可选，可使用fzf选择）"
    echo "  account-add <集群ID> <账号> <密码> [描述] - 创建数据库账号"
    echo "  account-del <集群ID> <账号>            - 删除数据库账号"
    echo "  account-get <集群ID>                   - 列出数据库账号"
    echo "  account-set <集群ID> <账号> <数据库名> [权限]  - 设置账号数据库权限"
    echo "  db-get <集群ID>                        - 列出数据库"
    echo "  db-add <集群ID> <数据库名> [字符集]    - 创建数据库"
    echo "  db-del <集群ID> <数据库名>             - 删除数据库"
    echo "  ip-get <集群ID>                        - 列出集群IP白名单"
    echo "  ip-set <集群ID> <IP列表>               - 设置集群IP白名单（覆盖模式）"
    echo "  ip-append <集群ID> <IP列表>            - 追加IP到白名单"
    echo "  ip-clear <集群ID>                      - 清空集群IP白名单"
    echo

    echo "示例："
    echo "  $0 polardb get"
    echo "  $0 polardb add my-polardb MySQL 8.0 polar.mysql.x4.large"
    echo "  $0 polardb set pc-xxxxxxxxxxxxx new-name"
    echo "  $0 polardb del pc-xxxxxxxxxxxxx"
    echo "  $0 polardb account-add pc-xxxxxxxxxxxxx myuser mypassword '测试账号'"
    echo "  $0 polardb account-del pc-xxxxxxxxxxxxx myuser"
    echo "  $0 polardb account-get pc-xxxxxxxxxxxxx"
    echo "  $0 polardb account-set pc-xxxxxxxxxxxxx myuser mydb ReadWrite"
    echo "  $0 polardb db-get pc-xxxxxxxxxxxxx"
    echo "  $0 polardb db-add pc-xxxxxxxxxxxxx mydb utf8mb4"
    echo "  $0 polardb db-del pc-xxxxxxxxxxxxx mydb"
    echo "  $0 polardb ip-get pc-xxxxxxxxxxxxx"
    echo "  $0 polardb ip-set pc-xxxxxxxxxxxxx '192.168.1.1,10.0.0.0/8'"
    echo "  $0 polardb ip-append pc-xxxxxxxxxxxxx '192.168.2.1'"
    echo "  $0 polardb ip-clear pc-xxxxxxxxxxxxx"
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
    account-add) polardb_account_create "$@" ;;
    account-del) polardb_account_delete "$@" ;;
    account-get) polardb_account_list "$@" ;;
    db-get) polardb_db_list "$@" ;;
    db-add) polardb_db_create "$@" ;;
    db-del) polardb_db_delete "$@" ;;
    account-set) polardb_account_grant "$@" ;;
    ip-get) polardb_ip_get "$@" ;;
    ip-set) polardb_ip_set "$@" ;;
    ip-append) polardb_ip_append "$@" ;;
    ip-clear) polardb_ip_clear "$@" ;;
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
    if ! result=$(aliyun --profile "${profile:-}" polardb DescribeDBClusters --RegionId "${region:-}"); then
        echo "错误：无法获取 PolarDB 集群列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果，不做任何处理
        echo "$result"
        ;;
    tsv)
        # TSV 格式
        echo -e "DBClusterId\tDBClusterDescription\tDBClusterStatus\tDBType\tDBVersion\tDBNodeClass\tRegionId\tCreateTime"
        echo "$result" | jq -r '.Items.DBCluster[] | [.DBClusterId, .DBClusterDescription, .DBClusterStatus, .DBType, .DBVersion, .DBNodeClass, .RegionId, .CreateTime] | @tsv'
        ;;
    human | *)
        # 人类可读格式
        echo "列出 PolarDB 集群："
        if [[ $(echo "$result" | jq '.Items.DBCluster | length') -eq 0 ]]; then
            echo "没有找到 PolarDB 集群。"
        else
            echo "集群ID            名称                状态    引擎    版本   规格               地域          创建时间"
            echo "----------------  ------------------  ------  ------  -----  -----------------  ------------  -------------------------"
            echo "$result" | jq -r '.Items.DBCluster[] | [.DBClusterId, .DBClusterDescription, .DBClusterStatus, .DBType, .DBVersion, .DBNodeClass, .RegionId, .CreateTime] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
            {
                status = $3;
                if (status == "Running") status = "运行中";
                else if (status == "Creating") status = "创建中";
                else if (status == "Deleting") status = "删除中";
                else if (status == "Stopped") status = "已停止";
                else status = "未知";
                printf "%-16s  %-18s  %-6s  %-6s  %-5s  %-17s  %-12s  %s\n", $1, $2, status, $4, $5, $6, $7, $8
            }'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "polardb" "list" "$result" "$format"
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
            class_result=$(call_aliyun_api polardb DescribeDBNodeClasses \
                --RegionId "$region" \
                --DBType "$db_type" \
                --DBVersion "$db_version" \
                --PayType "Postpaid" 2>/dev/null)

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
    local result
    result=$(aliyun --profile "${profile:-}" polardb CreateDBCluster \
        --RegionId "$region" \
        --DBType "$db_type" \
        --DBVersion "$db_version" \
        --DBNodeClass "$db_node_class" \
        --DBClusterDescription "$name" \
        --PayType Postpaid \
        --DBNodeNum 1)
    echo "$result" | jq '.'
    log_result "$profile" "$region" "polardb" "create" "$result"
}

polardb_update() {
    local cluster_id=$1 new_name=$2

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$cluster_id" ] || [ -z "$new_name" ]; then
        echo "使用 fzf 交互式模式更新 PolarDB 集群"

        # 选择集群ID
        if [ -z "$cluster_id" ]; then
            local cluster_list
            cluster_list=$(aliyun --profile "${profile:-}" polardb DescribeDBClusters --RegionId "$region" 2>/dev/null | jq -r '.DBClusters[] | "\(.DBClusterId) (\(.DBClusterDescription)) [\(.DBType)]"')

            if [ -z "$cluster_list" ]; then
                echo "错误：没有找到 PolarDB 集群。" >&2
                return 1
            elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
                cluster_id=$(echo "$cluster_list" | awk '{print $1}')
                echo "自动选择唯一的 PolarDB 集群: $cluster_id"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    cluster_id=$(select_with_fzf "选择 PolarDB 集群" "$cluster_list" | awk '{print $1}')
                else
                    echo "错误：需要选择 PolarDB 集群，但未找到交互式选择工具。" >&2
                    return 1
                fi
            fi
        fi

        # 输入新名称
        if [ -z "$new_name" ]; then
            read -r -p "请输入新的集群名称: " new_name
            if [ -z "$new_name" ]; then
                echo "错误：新名称不能为空。" >&2
                return 1
            fi
        fi
    fi

    echo "更新 PolarDB 集群："
    local result
    result=$(aliyun --profile "${profile:-}" polardb ModifyDBClusterDescription \
        --DBClusterId "$cluster_id" \
        --DBClusterDescription "$new_name")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "polardb" "update" "$result"
}

polardb_delete() {
    local cluster_id=$1

    # 如果没有提供集群ID，则使用 fzf 交互式选择
    if [ -z "$cluster_id" ]; then
        echo "使用 fzf 交互式模式删除 PolarDB 集群"

        local cluster_list
        cluster_list=$(aliyun --profile "${profile:-}" polardb DescribeDBClusters --RegionId "$region" 2>/dev/null | jq -r '.DBClusters[] | "\(.DBClusterId) (\(.DBClusterDescription)) [\(.DBType)]"')

        if [ -z "$cluster_list" ]; then
            echo "错误：没有找到 PolarDB 集群。" >&2
            return 1
        elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            cluster_id=$(echo "$cluster_list" | awk '{print $1}')
            echo "自动选择唯一的 PolarDB 集群: $cluster_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                cluster_id=$(select_with_fzf "选择要删除的 PolarDB 集群" "$cluster_list" | awk '{print $1}')
            else
                echo "错误：需要选择 PolarDB 集群，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    echo "警告：您即将删除 PolarDB 集群：$cluster_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 PolarDB 集群："
    local result
    result=$(aliyun --profile "${profile:-}" polardb DeleteDBCluster --DBClusterId "$cluster_id")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "polardb" "delete" "$result"
}

# 创建数据库账号
polardb_account_create() {
    local cluster_id=$1
    local account_name=$2
    local password=${3:-$(_get_random_password 2>/dev/null)}
    local description=${4:-"Created by CLI"}

    if [ -z "$cluster_id" ] || [ -z "$account_name" ] || [ -z "$password" ]; then
        echo "错误：集群ID、账号名和密码不能为空。" >&2
        echo "用法：polardb account-add <集群ID> <账号> <密码> [描述]" >&2
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
    result=$(aliyun --profile "${profile:-}" polardb CreateAccount \
        --DBClusterId "$cluster_id" \
        --AccountName "$account_name" \
        --AccountPassword "$password" \
        --AccountDescription "$description" \
        --AccountType Normal)

    ret=$?
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
        echo "用法：polardb account-del <集群ID> <账号>" >&2
        return 1
    fi

    echo "警告：您即将删除 PolarDB 账号：$account_name"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 PolarDB 账号："
    local result
    result=$(aliyun --profile "${profile:-}" polardb DeleteAccount \
        --DBClusterId "$cluster_id" \
        --AccountName "$account_name")

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "账号删除成功。"
        log_delete_operation "${profile:-}" "$region" "polardb" "$account_name" "PolarDB账号" "成功"
    else
        echo "账号删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "polardb" "$account_name" "PolarDB账号" "失败"
    fi

    log_result "${profile:-}" "$region" "polardb" "account-delete" "$result"
}

# 列出数据库账号
polardb_account_list() {
    local cluster_id=$1
    local format=${2:-human}

    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        echo "用法：polardb account-get <集群ID> [format]" >&2
        return 1
    fi

    echo "列出 PolarDB 账号："
    local result
    result=$(aliyun --profile "${profile:-}" polardb DescribeAccounts --DBClusterId "$cluster_id")

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        # TSV 格式
        echo -e "账号名\t账号类型\t状态\t描述\t数据库\t权限\t权限详情"
        echo "$result" | jq -r '.Accounts[] |
            . as $account |
            (.DatabasePrivileges.DatabasePrivilege // []) |
            if length > 0 then
                .[] | [
                    $account.AccountName,
                    $account.AccountType,
                    $account.AccountStatus,
                    $account.AccountDescription,
                    .DBName,
                    .AccountPrivilege,
                    .AccountPrivilegeDetail
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
        ;;
    human | *)
        if [[ $(echo "$result" | jq '.Accounts | length') -eq 0 ]]; then
            echo "没有找到账号。"
        else
            echo "账号名              账号类型    状态      描述                  数据库              权限        权限详情"
            echo "----------------    --------    --------  --------------------  ----------------    --------    --------------------"
            echo "$result" | jq -r '.Accounts[] |
                . as $account |
                (.DatabasePrivileges.DatabasePrivilege // []) |
                if length > 0 then
                    .[] | [
                        $account.AccountName,
                        $account.AccountType,
                        $account.AccountStatus,
                        $account.AccountDescription,
                        .DBName,
                        .AccountPrivilege,
                        (.AccountPrivilegeDetail | split(",")[0:3] | join(",") + "...")
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
                end' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    printf "%-18s  %-10s  %-8s  %-20s  %-16s  %-10s  %s\n",
                        $1, $2, $3, substr($4, 1, 18), $5, $6, $7
                }'
        fi
        ;;
    esac
    log_result "${profile:-}" "$region" "polardb" "account-list" "$result" "$format"
}

# 列出数据库
polardb_db_list() {
    local cluster_id=$1
    local format=${2:-human}

    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        echo "用法：polardb db-get <集群ID> [format]" >&2
        return 1
    fi

    echo "列出数据库："
    local result
    result=$(aliyun --profile "${profile:-}" polardb DescribeDatabases --DBClusterId "$cluster_id")

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        # TSV 格式
        echo -e "数据库名\t字符集\t状态\t描述"
        echo "$result" | jq -r '.Databases.Database[] | [.DBName, .CharacterSetName, .DBStatus, .DBDescription] | @tsv'
        ;;
    human | *)
        if [[ $(echo "$result" | jq '.Databases.Database | length') -eq 0 ]]; then
            echo "没有找到数据库。"
        else
            echo "数据库名            字符集             状态      描述"
            echo "----------------    ---------------    --------  --------------------"
            echo "$result" | jq -r '.Databases.Database[] | [.DBName, .CharacterSetName, .DBStatus, .DBDescription] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    printf "%-18s  %-15s  %-8s  %s\n", $1, $2, $3, substr($4, 1, 20)
                }'
        fi
        ;;
    esac
    log_result "${profile:-}" "$region" "polardb" "db-list" "$result" "$format"
}

# 创建数据库
polardb_db_create() {
    local cluster_id=$1
    local db_name=$2
    local charset=${3:-utf8mb4}

    if [ -z "$cluster_id" ] || [ -z "$db_name" ]; then
        echo "错误：集群ID和数据库名不能为空。" >&2
        echo "用法：polardb db-add <集群ID> <数据库名> [字符集]" >&2
        return 1
    fi

    echo "创建数据库："
    echo "集群ID: $cluster_id"
    echo "数据库名: $db_name"
    echo "字符集: $charset"

    local result
    result=$(aliyun --profile "${profile:-}" polardb CreateDatabase \
        --DBClusterId "$cluster_id" \
        --DBName "$db_name" \
        --CharacterSetName "$charset" \
        --DBDescription "Created by CLI")

    if [ $? -eq 0 ]; then
        echo "数据库创建成功："
        echo "$result" | jq '.'
    else
        echo "错误：数据库创建失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "polardb" "db-create" "$result"
}

# 删除数据库
polardb_db_delete() {
    local cluster_id=$1
    local db_name=$2

    if [ -z "$cluster_id" ] || [ -z "$db_name" ]; then
        echo "错误：集群ID和数据库名不能为空。" >&2
        echo "用法：polardb db-del <集群ID> <数据库名>" >&2
        return 1
    fi

    echo "警告：您即将删除数据库：$db_name"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除数据库："
    local result
    result=$(aliyun --profile "${profile:-}" polardb DeleteDatabase \
        --DBClusterId "$cluster_id" \
        --DBName "$db_name")

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "数据库删除成功。"
        log_delete_operation "${profile:-}" "$region" "polardb" "$db_name" "数据库" "成功"
    else
        echo "数据库删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "polardb" "$db_name" "数据库" "失败"
    fi

    log_result "${profile:-}" "$region" "polardb" "db-delete" "$result"
}

# 设置账号数据库权限函数
polardb_account_grant() {
    local cluster_id=$1
    local account_name=$2
    local db_name=$3
    local privilege=${4:-ReadWrite}

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$cluster_id" ] || [ -z "$account_name" ] || [ -z "$db_name" ]; then
        echo "使用 fzf 交互式模式设置账号权限"

        # 选择集群ID
        if [ -z "$cluster_id" ]; then
            local cluster_list
            cluster_list=$(aliyun --profile "${profile:-}" polardb DescribeDBClusters --RegionId "$region" 2>/dev/null | jq -r '.Items.DBCluster[] | "\(.DBClusterId) (\(.DBClusterDescription)) [\(.DBType)]"')

            if [ -z "$cluster_list" ]; then
                echo "错误：没有找到 PolarDB 集群。" >&2
                return 1
            elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
                cluster_id=$(echo "$cluster_list" | awk '{print $1}')
                echo "自动选择唯一的 PolarDB 集群: $cluster_id"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    cluster_id=$(select_with_fzf "选择 PolarDB 集群" "$cluster_list" | awk '{print $1}')
                    if [ -z "$cluster_id" ]; then
                        echo "错误：未选择集群。" >&2
                        return 1
                    fi
                else
                    echo "错误：需要选择 PolarDB 集群，但未找到交互式选择工具。" >&2
                    return 1
                fi
            fi
        fi

        # 选择账号名
        if [ -z "$account_name" ]; then
            local account_list
            account_list=$(aliyun --profile "${profile:-}" polardb DescribeAccounts --DBClusterId "$cluster_id" 2>/dev/null | jq -r '.Accounts.Account[] | "\(.AccountName) [\(.AccountType)] [\(.AccountStatus)]"')

            if [ -z "$account_list" ]; then
                echo "错误：在指定集群中没有找到数据库账号。" >&2
                return 1
            elif [ "$(echo "$account_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
                account_name=$(echo "$account_list" | awk '{print $1}')
                echo "自动选择唯一的账号: $account_name"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    account_name=$(select_with_fzf "选择数据库账号" "$account_list" | awk '{print $1}')
                    if [ -z "$account_name" ]; then
                        echo "错误：未选择账号。" >&2
                        return 1
                    fi
                else
                    echo "错误：需要选择数据库账号，但未找到交互式选择工具。" >&2
                    return 1
                fi
            fi
        fi

        # 选择数据库名
        if [ -z "$db_name" ]; then
            local db_list
            db_list=$(aliyun --profile "${profile:-}" polardb DescribeDatabases --DBClusterId "$cluster_id" 2>/dev/null | jq -r '.Databases.Database[] | "\(.DBName) [\(.CharacterSetName)] [\(.DBStatus)]"')

            if [ -z "$db_list" ]; then
                echo "错误：在指定集群中没有找到数据库。" >&2
                return 1
            elif [ "$(echo "$db_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
                db_name=$(echo "$db_list" | awk '{print $1}')
                echo "自动选择唯一的数据库: $db_name"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    db_name=$(select_with_fzf "选择数据库" "$db_list" | awk '{print $1}')
                    if [ -z "$db_name" ]; then
                        echo "错误：未选择数据库。" >&2
                        return 1
                    fi
                else
                    echo "错误：需要选择数据库，但未找到交互式选择工具。" >&2
                    return 1
                fi
            fi
        fi
    fi

    if [ -z "$cluster_id" ] || [ -z "$account_name" ] || [ -z "$db_name" ]; then
        echo "错误：集群ID、账号名和数据库名不能为空。" >&2
        echo "用法：polardb account-set <集群ID> <账号> <数据库名> [权限]" >&2
        return 1
    fi

    echo "设置账号权限："
    echo "集群ID: $cluster_id"
    echo "账号名: $account_name"
    echo "数据库: $db_name"
    echo "权限: $privilege"

    local result
    result=$(aliyun --profile "${profile:-}" polardb GrantAccountPrivilege \
        --DBClusterId "$cluster_id" \
        --AccountName "$account_name" \
        --DBName "$db_name" \
        --AccountPrivilege "$privilege")

    ret=$?
    if [ $ret -eq 0 ]; then
        echo "权限设置成功。"
        echo "账号 $account_name 已被授予 $privilege 权限，可访问数据库 $db_name"
    else
        echo "错误：权限设置失败。"
        echo "$result"
        return 1
    fi

    log_result "${profile:-}" "$region" "polardb" "account-set" "$result"
}

# 列出IP白名单
polardb_ip_get() {
    local cluster_id=$1

    # 如果没有提供集群ID，则使用 fzf 交互式选择
    if [ -z "$cluster_id" ]; then
        echo "使用 fzf 交互式模式获取IP白名单"

        local cluster_list
        cluster_list=$(aliyun --profile "${profile:-}" polardb DescribeDBClusters --RegionId "$region" 2>/dev/null | jq -r '.Items.DBCluster[] | "\(.DBClusterId) (\(.DBClusterDescription)) [\(.DBType)]"')

        if [ -z "$cluster_list" ]; then
            echo "错误：没有找到 PolarDB 集群。" >&2
            return 1
        elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            cluster_id=$(echo "$cluster_list" | awk '{print $1}')
            echo "自动选择唯一的 PolarDB 集群: $cluster_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                cluster_id=$(select_with_fzf "选择 PolarDB 集群" "$cluster_list" | awk '{print $1}')
                if [ -z "$cluster_id" ]; then
                    echo "错误：未选择集群。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择 PolarDB 集群，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    echo "获取集群 $cluster_id 的IP白名单："

    local result
    result=$(aliyun --profile "${profile:-}" polardb DescribeDBClusterAccessWhitelist --DBClusterId "$cluster_id")

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

    log_result "${profile:-}" "$region" "polardb" "ip-get" "$result"
}

# 设置IP白名单（覆盖模式）
polardb_ip_set() {
    local cluster_id=$1
    local ips=$2
    local ip_array_name=$3  # 新增：指定IP白名单组名称

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$cluster_id" ] || [ -z "$ips" ]; then
        echo "使用 fzf 交互式模式设置IP白名单（覆盖模式）"

        # 选择集群ID
        if [ -z "$cluster_id" ]; then
            local cluster_list
            cluster_list=$(aliyun --profile "${profile:-}" polardb DescribeDBClusters --RegionId "$region" 2>/dev/null | jq -r '.Items.DBCluster[] | "\(.DBClusterId) (\(.DBClusterDescription)) [\(.DBType)]"')

            if [ -z "$cluster_list" ]; then
                echo "错误：没有找到 PolarDB 集群。" >&2
                return 1
            elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
                cluster_id=$(echo "$cluster_list" | awk '{print $1}')
                echo "自动选择唯一的 PolarDB 集群: $cluster_id"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    cluster_id=$(select_with_fzf "选择 PolarDB 集群" "$cluster_list" | awk '{print $1}')
                    if [ -z "$cluster_id" ]; then
                        echo "错误：未选择集群。" >&2
                        return 1
                    fi
                else
                    echo "错误：需要选择 PolarDB 集群，但未找到交互式选择工具。" >&2
                    return 1
                fi
            fi
        fi

        # 显示当前IP白名单并让用户选择或输入新IP
        local current_whitelist
        current_whitelist=$(aliyun --profile "${profile:-}" polardb DescribeDBClusterAccessWhitelist --DBClusterId "$cluster_id" 2>/dev/null)

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
        echo "用法：polardb ip-set <集群ID> <IP列表> [IP白名单组名]" >&2
        return 1
    fi

    echo "正在设置集群 $cluster_id 的IP白名单（覆盖模式）："
    echo "IP列表: $ips"
    if [ -n "$ip_array_name" ]; then
        echo "IP白名单组: $ip_array_name"
    fi

    local result
    local params=(--DBClusterId "$cluster_id" --SecurityIps "$ips" --ModifyMode "Cover")

    # 如果指定了IP白名单组名，需要添加相应参数
    if [ -n "$ip_array_name" ]; then
        params+=(--DBClusterIPArrayName "$ip_array_name")
    fi

    result=$(aliyun --profile "${profile:-}" polardb ModifyDBClusterAccessWhitelist "${params[@]}")

    if [ $? -ne 0 ]; then
        echo "错误：设置IP白名单失败。" >&2
        echo "$result"
        return 1
    fi

    echo "IP白名单设置成功。"
    echo "$result" | jq '.'

    log_result "${profile:-}" "$region" "polardb" "ip-set" "$result"
}

# 追加IP到白名单
polardb_ip_append() {
    local cluster_id=$1
    local ips=$2

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$cluster_id" ] || [ -z "$ips" ]; then
        echo "使用 fzf 交互式模式追加IP到白名单"

        # 选择集群ID
        if [ -z "$cluster_id" ]; then
            local cluster_list
            cluster_list=$(aliyun --profile "${profile:-}" polardb DescribeDBClusters --RegionId "$region" 2>/dev/null | jq -r '.Items.DBCluster[] | "\(.DBClusterId) (\(.DBClusterDescription)) [\(.DBType)]"')

            if [ -z "$cluster_list" ]; then
                echo "错误：没有找到 PolarDB 集群。" >&2
                return 1
            elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
                cluster_id=$(echo "$cluster_list" | awk '{print $1}')
                echo "自动选择唯一的 PolarDB 集群: $cluster_id"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    cluster_id=$(select_with_fzf "选择 PolarDB 集群" "$cluster_list" | awk '{print $1}')
                    if [ -z "$cluster_id" ]; then
                        echo "错误：未选择集群。" >&2
                        return 1
                    fi
                else
                    echo "错误：需要选择 PolarDB 集群，但未找到交互式选择工具。" >&2
                    return 1
                fi
            fi
        fi

        # 输入IP列表
        if [ -z "$ips" ]; then
            read -r -p "请输入要追加的IP列表（多个IP用逗号分隔）: " ips
            if [ -z "$ips" ]; then
                echo "错误：IP列表不能为空。" >&2
                return 1
            fi
        fi
    fi

    if [ -z "$cluster_id" ] || [ -z "$ips" ]; then
        echo "错误：集群ID和IP列表不能为空。" >&2
        echo "用法：polardb ip-append <集群ID> <IP列表>" >&2
        return 1
    fi

    echo "正在追加IP到集群 $cluster_id 的白名单："
    echo "IP列表: $ips"

    local result
    result=$(aliyun --profile "${profile:-}" polardb ModifyDBClusterAccessWhitelist \
        --DBClusterId "$cluster_id" \
        --SecurityIps "$ips" \
        --ModifyMode "Append")

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
    local cluster_id=$1

    # 如果没有提供集群ID，则使用 fzf 交互式选择
    if [ -z "$cluster_id" ]; then
        echo "使用 fzf 交互式模式清空白名单"

        local cluster_list
        cluster_list=$(aliyun --profile "${profile:-}" polardb DescribeDBClusters --RegionId "$region" 2>/dev/null | jq -r '.Items.DBCluster[] | "\(.DBClusterId) (\(.DBClusterDescription)) [\(.DBType)]"')

        if [ -z "$cluster_list" ]; then
            echo "错误：没有找到 PolarDB 集群。" >&2
            return 1
        elif [ "$(echo "$cluster_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            cluster_id=$(echo "$cluster_list" | awk '{print $1}')
            echo "自动选择唯一的 PolarDB 集群: $cluster_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                cluster_id=$(select_with_fzf "选择要清空白名单的 PolarDB 集群" "$cluster_list" | awk '{print $1}')
                if [ -z "$cluster_id" ]; then
                    echo "错误：未选择集群。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择 PolarDB 集群，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    if [ -z "$cluster_id" ]; then
        echo "错误：集群ID不能为空。" >&2
        echo "用法：polardb ip-clear <集群ID>" >&2
        return 1
    fi

    echo "警告：您即将清空集群 $cluster_id 的IP白名单，这将阻止所有外部访问。"
    read -r -p "请输入 'YES' 以确认清空操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "正在清空集群 $cluster_id 的IP白名单："

    local result
    # 将IP白名单设置为本地localhost以保留基本访问能力
    result=$(aliyun --profile "${profile:-}" polardb ModifyDBClusterAccessWhitelist \
        --DBClusterId "$cluster_id" \
        --SecurityIps "127.0.0.1" \
        --ModifyMode "Cover")

    if [ $? -ne 0 ]; then
        echo "错误：清空IP白名单失败。" >&2
        echo "$result"
        return 1
    fi

    echo "IP白名单已清空（保留127.0.0.1以维持基本访问）。"
    echo "$result" | jq '.'

    log_result "${profile:-}" "$region" "polardb" "ip-clear" "$result"
}