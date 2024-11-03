#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# RDS (关系型数据库) 相关函数

show_rds_help() {
    echo "RDS (关系型数据库) 操作："
    echo "  list                                    - 列出 RDS 实例"
    echo "  create <名称> <引擎> <版本> <规格> [地域] - 创建 RDS 实例"
    echo "  update <实例ID> <新名称> [地域]          - 更新 RDS 实例"
    echo "  delete <实例ID> [地域]                   - 删除 RDS 实例"
    echo "  account-create <实例ID> <账号> <密码> [描述] [权限]  - 创建数据库账号"
    echo "  account-delete <实例ID> <账号>           - 删除数据库账号"
    echo "  account-list <实例ID>                    - 列出数据库账号"
    echo "  db-list <实例ID>                         - 列出数据库"
    echo "  db-create <实例ID> <数据库名> [字符集]    - 创建数据库"
    echo "  db-delete <实例ID> <数据库名>            - 删除数据库"
    echo
    echo "示例："
    echo "  $0 rds list"
    echo "  $0 rds create my-rds MySQL 8.0 rds.mysql.t1.small"
    echo "  $0 rds update rm-uf6wjk5xxxxxxx new-name"
    echo "  $0 rds delete rm-uf6wjk5xxxxxxx"
    echo "  $0 rds account-create rm-uf6wjk5xxxxxxx myuser mypassword '测试账号' ReadWrite"
    echo "  $0 rds account-delete rm-uf6wjk5xxxxxxx myuser"
    echo "  $0 rds account-list rm-uf6wjk5xxxxxxx"
    echo "  $0 rds db-list rm-uf6wjk5xxxxxxx"
    echo "  $0 rds db-create rm-uf6wjk5xxxxxxx mydb utf8mb4"
    echo "  $0 rds db-delete rm-uf6wjk5xxxxxxx mydb"
}

handle_rds_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) rds_list "$@" ;;
    create) rds_create "$@" ;;
    update) rds_update "$@" ;;
    delete) rds_delete "$@" ;;
    account-create) rds_account_create "$@" ;;
    account-delete) rds_account_delete "$@" ;;
    account-list) rds_account_list "$@" ;;
    db-list) rds_db_list "$@" ;;
    db-create) rds_db_create "$@" ;;
    db-delete) rds_db_delete "$@" ;;
    *)
        echo "错误：未知的 RDS 操作：$operation" >&2
        show_rds_help
        exit 1
        ;;
    esac
}

rds_list() {
    local format=${1:-human}
    local result
    if ! result=$(aliyun --profile "${profile:-}" rds DescribeDBInstances --RegionId "${region:-}"); then
        echo "错误：无法获取 RDS 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果，不做任何处理
        echo "$result"
        ;;
    tsv)
        # TSV 格式保持不变
        echo -e "DBInstanceId\tDBInstanceDescription\tDBInstanceStatus\tEngine\tEngineVersion\tDBInstanceClass\tRegionId\tCreateTime"
        echo "$result" | jq -r '.Items.DBInstance[] | [.DBInstanceId, .DBInstanceDescription, .DBInstanceStatus, .Engine, .EngineVersion, .DBInstanceClass, .RegionId, .CreateTime] | @tsv'
        ;;
    human | *)
        # 人类可读格式保持不变
        echo "列出 RDS 实例："
        if [[ $(echo "$result" | jq '.Items.DBInstance | length') -eq 0 ]]; then
            echo "没有找到 RDS 实例。"
        else
            echo "实例ID            名称                状态    引擎    版本   规格               地域          创建时间"
            echo "----------------  ------------------  ------  ------  -----  -----------------  ------------  -------------------------"
            echo "$result" | jq -r '.Items.DBInstance[] | [.DBInstanceId, .DBInstanceDescription, .DBInstanceStatus, .Engine, .EngineVersion, .DBInstanceClass, .RegionId, .CreateTime] | @tsv' |
            awk 'BEGIN {FS="\t"; OFS="\t"}
            {
                status = $3;
                if (status == "Running") status = "运行中";
                else if (status == "Stopped") status = "已停止";
                else status = "未知";
                printf "%-16s  %-18s  %-6s  %-6s  %-5s  %-17s  %-12s  %s\n", $1, $2, status, $4, $5, $6, $7, $8
            }'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "rds" "list" "$result" "$format"
}

rds_create() {
    local name=$1 engine=$2 version=$3 class=$4
    echo "创建 RDS 实例："
    local result
    result=$(aliyun --profile "${profile:-}" rds CreateDBInstance \
        --RegionId "$region" \
        --Engine "$engine" \
        --EngineVersion "$version" \
        --DBInstanceClass "$class" \
        --DBInstanceStorage 20 \
        --DBInstanceNetType Internet \
        --SecurityIPList "0.0.0.0/0" \
        --PayType Postpaid \
        --DBInstanceDescription "$name")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "rds" "create" "$result"
}

rds_update() {
    local instance_id=$1 new_name=$2
    echo "更新 RDS 实例："
    local result
    result=$(aliyun --profile "${profile:-}" rds ModifyDBInstanceDescription \
        --DBInstanceId "$instance_id" \
        --DBInstanceDescription "$new_name")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "rds" "update" "$result"
}

rds_delete() {
    local instance_id=$1
    echo "删除 RDS 实例："
    local result
    result=$(aliyun --profile "${profile:-}" rds DeleteDBInstance --DBInstanceId "$instance_id")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "rds" "delete" "$result"
}

# 修改：创建数据库账号
rds_account_create() {
    local instance_id=$1
    local account_name=$2
    local password=${3:-$(_get_random_password 2>/dev/null)}
    local description=${4:-"Created by CLI"}
    local privilege=${5:-ReadWrite}

    if [ -z "$instance_id" ] || [ -z "$account_name" ] || [ -z "$password" ]; then
        echo "错误：实例ID、账号名和密码不能为空。" >&2
        echo "用法：rds account-create <实例ID> <账号> <密码> [描述] [权限]" >&2
        return 1
    fi

    # 验证密码复杂度
    echo "$password"
    if [ "${#password}" -lt 8 ] || [ "${#password}" -gt 32 ]; then
        echo "错误：密码长度必须在8-32位之间。" >&2
        return 1
    fi

    echo "$password" | $CMD_GREP -q "[A-Z]" || {
        echo "错误：密码必须包含大写字母。" >&2
        return 1
    }

    echo "$password" | $CMD_GREP -q "[a-z]" || {
        echo "错误：密码必须包含小写字母。" >&2
        return 1
    }

    echo "$password" | $CMD_GREP -q "[0-9]" || {
        echo "错误：密码必须包含数字。" >&2
        return 1
    }

    echo "$password" | $CMD_GREP -q '[^[:alnum:]]' || {
        password="${password}@"
    }

    # 先创建同名数据库（使用 rds_db_create 函数）
    echo "创建同名数据库..."
    if ! rds_db_create "$instance_id" "$account_name" "utf8mb4"; then
        echo "错误：数据库创建失败。"
        return 1
    fi

    echo "创建 RDS 账号："
    echo "实例ID: $instance_id"
    echo "账号名: $account_name"
    echo "描述: $description"
    echo "权限: $privilege"
    echo "数据库: $account_name"

    local result
    result=$(aliyun --profile "${profile:-}" rds CreateAccount \
        --DBInstanceId "$instance_id" \
        --AccountName "$account_name" \
        --AccountPassword "$password" \
        --AccountDescription "$description" \
        --AccountType Normal)

    if [ $? -eq 0 ]; then
        echo "账号创建成功："
        echo "$result" | jq '.'

        # 等待账号创建完成
        echo "等待账号创建完成..."
        sleep 5

        # 设置账号权限（只授权同名数据库）
        echo "设置账号权限..."
        local grant_result
        grant_result=$(aliyun --profile "${profile:-}" rds GrantAccountPrivilege \
            --DBInstanceId "$instance_id" \
            --AccountName "$account_name" \
            --DBName "$account_name" \
            --AccountPrivilege "$privilege")

        if [ $? -eq 0 ]; then
            echo "权限设置成功。"
            echo "账号 $account_name 已被授予 $privilege 权限，可访问数据库 $account_name"
        else
            echo "警告：权限设置失败。"
            echo "$grant_result"
        fi
    else
        echo "错误：账号创建失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "rds" "account-create" "$result"
}

# 新增：删除数据库账号
rds_account_delete() {
    local instance_id=$1
    local account_name=$2

    if [ -z "$instance_id" ] || [ -z "$account_name" ]; then
        echo "错误：实例ID和账号名不能为空。" >&2
        echo "用法：rds account-delete <实例ID> <账号>" >&2
        return 1
    fi

    echo "警告：您即将删除 RDS 账号：$account_name"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 RDS 账号："
    local result
    result=$(aliyun --profile "${profile:-}" rds DeleteAccount \
        --DBInstanceId "$instance_id" \
        --AccountName "$account_name")

    if [ $? -eq 0 ]; then
        echo "账号删除成功。"
        log_delete_operation "${profile:-}" "$region" "rds" "$account_name" "RDS账号" "成功"
    else
        echo "账号删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "rds" "$account_name" "RDS账号" "失败"
    fi

    log_result "${profile:-}" "$region" "rds" "account-delete" "$result"
}

# 修改：列出数据库账号
rds_account_list() {
    local instance_id=$1
    local format=${2:-human}

    if [ -z "$instance_id" ]; then
        echo "错误：实例ID不能为空。" >&2
        echo "用法：rds account-list <实例ID> [format]" >&2
        return 1
    fi

    echo "列出 RDS 账号："
    local result
    result=$(aliyun --profile "${profile:-}" rds DescribeAccounts --DBInstanceId "$instance_id")

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        # TSV 格式保持不变
        echo -e "账号名\t账号类型\t状态\t描述\t数据库\t权限\t权限详情"
        echo "$result" | jq -r '.Accounts.DBInstanceAccount[] |
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
        if [[ $(echo "$result" | jq '.Accounts.DBInstanceAccount | length') -eq 0 ]]; then
            echo "没有找到账号。"
        else
            echo "账号名              账号类型    状态      描述                  数据库              权限        权限详情"
            echo "----------------    --------    --------  --------------------  ----------------    --------    --------------------"
            echo "$result" | jq -r '.Accounts.DBInstanceAccount[] |
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
    log_result "${profile:-}" "$region" "rds" "account-list" "$result" "$format"
}

# 新增：列出数据库
rds_db_list() {
    local instance_id=$1
    local format=${2:-human}

    if [ -z "$instance_id" ]; then
        echo "错误：实例ID不能为空。" >&2
        echo "用法：rds db-list <实例ID> [format]" >&2
        return 1
    fi

    echo "列出数据库："
    local result
    result=$(aliyun --profile "${profile:-}" rds DescribeDatabases --DBInstanceId "$instance_id")

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        # TSV 格式保持不变
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
    log_result "${profile:-}" "$region" "rds" "db-list" "$result" "$format"
}

# 新增：创建数据库
rds_db_create() {
    local instance_id=$1
    local db_name=$2
    local charset=${3:-utf8mb4}

    if [ -z "$instance_id" ] || [ -z "$db_name" ]; then
        echo "错误：实例ID和数据库名不能为空。" >&2
        echo "用法：rds db-create <实例ID> <数据库名> [字符集]" >&2
        return 1
    fi

    echo "创建数据库："
    echo "实例ID: $instance_id"
    echo "数据库名: $db_name"
    echo "字符集: $charset"

    local result
    result=$(aliyun --profile "${profile:-}" rds CreateDatabase \
        --DBInstanceId "$instance_id" \
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
    log_result "${profile:-}" "$region" "rds" "db-create" "$result"
}

# 新增：删除数据库
rds_db_delete() {
    local instance_id=$1
    local db_name=$2

    if [ -z "$instance_id" ] || [ -z "$db_name" ]; then
        echo "错误：实例ID和数据库名不能为空。" >&2
        echo "用法：rds db-delete <实例ID> <数据库名>" >&2
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
    result=$(aliyun --profile "${profile:-}" rds DeleteDatabase \
        --DBInstanceId "$instance_id" \
        --DBName "$db_name")

    if [ $? -eq 0 ]; then
        echo "数据库删除成功。"
        log_delete_operation "${profile:-}" "$region" "rds" "$db_name" "数据库" "成功"
    else
        echo "数据库删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "rds" "$db_name" "数据库" "失败"
    fi

    log_result "${profile:-}" "$region" "rds" "db-delete" "$result"
}
