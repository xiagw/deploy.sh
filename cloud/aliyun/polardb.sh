#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# PolarDB (云数据库 PolarDB) 相关函数

show_polardb_help() {
    echo "PolarDB (云数据库 PolarDB) 操作："
    echo "  list                                    - 列出 PolarDB 集群"
    echo "  create <名称> <引擎> <版本> <规格> [地域] - 创建 PolarDB 集群"
    echo "  update <集群ID> <新名称> [地域]          - 更新 PolarDB 集群"
    echo "  delete <集群ID> [地域]                   - 删除 PolarDB 集群"
    echo "  account-create <集群ID> <账号> <密码> [描述] - 创建数据库账号"
    echo "  account-delete <集群ID> <账号>           - 删除数据库账号"
    echo "  account-list <集群ID>                    - 列出数据库账号"
    echo "  account-grant <集群ID> <账号> <数据库名> [权限]  - 设置账号数据库权限"
    echo "  db-list <集群ID>                         - 列出数据库"
    echo "  db-create <集群ID> <数据库名> [字符集]    - 创建数据库"
    echo "  db-delete <集群ID> <数据库名>            - 删除数据库"
    echo
    echo "示例："
    echo "  $0 polardb list"
    echo "  $0 polardb create my-polardb MySQL 8.0 polar.mysql.x4.large"
    echo "  $0 polardb update pc-xxxxxxxxxxxxx new-name"
    echo "  $0 polardb delete pc-xxxxxxxxxxxxx"
    echo "  $0 polardb account-create pc-xxxxxxxxxxxxx myuser mypassword '测试账号'"
    echo "  $0 polardb account-delete pc-xxxxxxxxxxxxx myuser"
    echo "  $0 polardb account-list pc-xxxxxxxxxxxxx"
    echo "  $0 polardb account-grant pc-xxxxxxxxxxxxx myuser mydb ReadWrite"
    echo "  $0 polardb db-list pc-xxxxxxxxxxxxx"
    echo "  $0 polardb db-create pc-xxxxxxxxxxxxx mydb utf8mb4"
    echo "  $0 polardb db-delete pc-xxxxxxxxxxxxx mydb"
}

handle_polardb_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) polardb_list "$@" ;;
    create) polardb_create "$@" ;;
    update) polardb_update "$@" ;;
    delete) polardb_delete "$@" ;;
    account-create) polardb_account_create "$@" ;;
    account-delete) polardb_account_delete "$@" ;;
    account-list) polardb_account_list "$@" ;;
    db-list) polardb_db_list "$@" ;;
    db-create) polardb_db_create "$@" ;;
    db-delete) polardb_db_delete "$@" ;;
    account-grant) polardb_account_grant "$@" ;;
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
        echo "用法：polardb account-create <集群ID> <账号> <密码> [描述]" >&2
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
        echo "用法：polardb account-delete <集群ID> <账号>" >&2
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
        echo "用法：polardb account-list <集群ID> [format]" >&2
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
        ;;
    human | *)
        if [[ $(echo "$result" | jq '.Accounts | length') -eq 0 ]]; then
            echo "没有找到账号。"
        else
            echo "账号名              账号类型    状态      描述                  数据库              权限        权限详情"
            echo "----------------    --------    --------  --------------------  ----------------    --------    --------------------"
            echo "$result" | jq -r '.Accounts[] |
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
                        (.AccountPrivilegeDetail // "" | if . != "" then (split(",")[0:3] | join(",") + "...") else "-" end)
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
        echo "用法：polardb db-list <集群ID> [format]" >&2
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
        echo "用法：polardb db-create <集群ID> <数据库名> [字符集]" >&2
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
        echo "用法：polardb db-delete <集群ID> <数据库名>" >&2
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

    if [ -z "$cluster_id" ] || [ -z "$account_name" ] || [ -z "$db_name" ]; then
        echo "错误：集群ID、账号名和数据库名不能为空。" >&2
        echo "用法：polardb account-grant <集群ID> <账号> <数据库名> [权限]" >&2
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

    log_result "${profile:-}" "$region" "polardb" "account-grant" "$result"
}
