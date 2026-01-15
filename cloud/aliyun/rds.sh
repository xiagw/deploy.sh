#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# RDS (关系型数据库) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_rds_help() {
    echo "RDS (关系型数据库) 操作："
    echo "  list                                    - 列出 RDS 实例"
    echo "  create <名称> <引擎> <版本> <规格>      - 创建 RDS 实例"
    echo "  update <实例ID> <新名称>                - 更新 RDS 实例"
    echo "  delete <实例ID>                         - 删除 RDS 实例"
    echo "  account-create <实例ID> <账号> <密码> [描述] - 创建数据库账号"
    echo "  account-delete <实例ID> <账号>           - 删除数据库账号"
    echo "  account-list <实例ID> [format]          - 列出数据库账号"
    echo "  account-grant <实例ID> <账号> <数据库名> [权限]  - 设置账号数据库权限"
    echo "  db-list <实例ID> [format]               - 列出数据库"
    echo "  db-create <实例ID> <数据库名> [字符集]  - 创建数据库"
    echo "  db-delete <实例ID> <数据库名>           - 删除数据库"
    echo
    echo "示例："
    echo "  $0 rds list"
    echo "  $0 rds create my-rds MySQL 8.0 rds.mysql.t1.small"
    echo "  $0 rds update rm-xxx new-name"
    echo "  $0 rds delete rm-xxx"
    echo "  $0 rds account-create rm-xxx myuser mypassword '测试账号'"
    echo "  $0 rds account-delete rm-xxx myuser"
    echo "  $0 rds account-list rm-xxx"
    echo "  $0 rds account-grant rm-xxx myuser mydb ReadWrite"
    echo "  $0 rds db-list rm-xxx"
    echo "  $0 rds db-create rm-xxx mydb utf8mb4"
    echo "  $0 rds db-delete rm-xxx mydb"
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
    account-grant) rds_account_grant "$@" ;;
    db-list) rds_db_list "$@" ;;
    db-create) rds_db_create "$@" ;;
    db-delete) rds_db_delete "$@" ;;
    help) show_rds_help ;;
    *)
        echo "错误：未知的 RDS 操作：$operation" >&2
        show_rds_help
        exit 1
        ;;
    esac
}

# 使用新框架的列表函数
rds_list() {
    local format=${1:-human}
    
    local table_header="DBInstanceId\tDBInstanceDescription\tDBInstanceStatus\tEngine\tEngineVersion\tDBInstanceClass\tRegionId\tCreateTime"
    local jq_filter=".Items.DBInstance[] | [.DBInstanceId, .DBInstanceDescription, .DBInstanceStatus, .Engine, .EngineVersion, .DBInstanceClass, .RegionId, .CreateTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"}
    {
        status = $3;
        if (status == "Running") status = "运行中";
        else if (status == "Stopped") status = "已停止";
        else status = "未知";
        printf "%-16s  %-18s  %-6s  %-6s  %-5s  %-17s  %-12s  %s\n", $1, $2, status, $4, $5, $6, $7, $8
    }'
    
    generic_list \
        "rds" \
        "DescribeDBInstances" \
        "rds" \
        "$format" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 RDS 实例。" \
        "列出 RDS 实例："
}

# 使用新框架的创建函数
rds_create() {
    local name=$1 engine=$2 version=$3 class=$4

    if ! validate_required_params "$name" "$engine" "$version" "$class" "错误：名称、引擎、版本和规格不能为空。"; then
        return 1
    fi

    echo "创建 RDS 实例："
    local result
    result=$(call_aliyun_api rds CreateDBInstance \
        --RegionId "$region" \
        --Engine "$engine" \
        --EngineVersion "$version" \
        --DBInstanceClass "$class" \
        --DBInstanceStorage 20 \
        --DBInstanceNetType Internet \
        --SecurityIPList "0.0.0.0/0" \
        --PayType Postpaid \
        --DBInstanceDescription "$name")
    
    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "rds" "create" "$result"
    else
        echo "错误：RDS 实例创建失败。"
        echo "$result"
        return 1
    fi
}

# 使用新框架的更新函数
rds_update() {
    local instance_id=$1 new_name=$2

    if ! validate_required_params "$instance_id" "$new_name" "错误：实例ID和新名称不能为空。"; then
        return 1
    fi

    echo "更新 RDS 实例："
    local result
    result=$(call_aliyun_api rds ModifyDBInstanceDescription \
        --DBInstanceId "$instance_id" \
        --DBInstanceDescription "$new_name")
    
    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "rds" "update" "$result"
    else
        echo "错误：RDS 实例更新失败。"
        echo "$result"
        return 1
    fi
}

# 使用新框架的删除函数
rds_delete() {
    local instance_id=$1

    if [ -z "$instance_id" ]; then
        echo "错误：实例ID不能为空。" >&2
        return 1
    fi

    if ! confirm_action "删除 RDS 实例：$instance_id"; then
        return 1
    fi

    echo "删除 RDS 实例："
    local result
    result=$(call_aliyun_api rds DeleteDBInstance --DBInstanceId "$instance_id")
    
    if [ $? -eq 0 ]; then
        echo "RDS 实例删除成功。"
        log_delete_operation "${profile:-}" "$region" "rds" "$instance_id" "RDS实例" "成功"
    else
        echo "错误：RDS 实例删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "rds" "$instance_id" "RDS实例" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "rds" "delete" "$result"
}

# 创建数据库账号（保持原有逻辑，但使用框架函数）
rds_account_create() {
    local instance_id=$1
    local account_name=$2
    local password=${3:-$(_get_random_password 2>/dev/null)}
    local description=${4:-"Created by CLI"}

    if ! validate_required_params "$instance_id" "$account_name" "错误：实例ID和账号名不能为空。"; then
        return 1
    fi

    if [ -z "$password" ]; then
        password=$(_get_random_password 2>/dev/null)
        if [ -z "$password" ]; then
            echo "错误：无法生成密码，请手动指定密码。" >&2
            return 1
        fi
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

    # 先创建同名数据库（使用 rds_db_create 函数）
    echo "创建同名数据库..."
    if ! rds_db_create "$instance_id" "$account_name" "utf8mb4"; then
        echo "错误：数据库创建失败。"
        return 1
    fi

    echo "创建 RDS 账号："
    echo "实例ID: $instance_id"
    echo "账号: $account_name / $password"
    echo "描述: $description"

    local result
    result=$(call_aliyun_api rds CreateAccount \
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

        # 自动设置默认权限
        if ! rds_account_grant "$instance_id" "$account_name" "$account_name" "ReadWrite"; then
            echo "警告：默认权限设置失败，请手动设置权限。"
        fi
        log_result "${profile:-}" "$region" "rds" "account-create" "$result"
    else
        echo "错误：账号创建失败。"
        echo "$result"
        return 1
    fi
}

# 删除数据库账号（使用框架函数）
rds_account_delete() {
    local instance_id=$1
    local account_name=$2

    if ! validate_required_params "$instance_id" "$account_name" "错误：实例ID和账号名不能为空。"; then
        return 1
    fi

    if ! confirm_action "删除 RDS 账号：$account_name"; then
        return 1
    fi

    echo "删除 RDS 账号："
    local result
    result=$(call_aliyun_api rds DeleteAccount \
        --DBInstanceId "$instance_id" \
        --AccountName "$account_name")
    
    if [ $? -eq 0 ]; then
        echo "账号删除成功。"
        log_delete_operation "${profile:-}" "$region" "rds" "$account_name" "RDS账号" "成功"
    else
        echo "账号删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "rds" "$account_name" "RDS账号" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "rds" "account-delete" "$result"
}

# 列出数据库账号（使用框架函数）
rds_account_list() {
    local instance_id=$1
    local format=${2:-human}

    if [ -z "$instance_id" ]; then
        echo "错误：实例ID不能为空。" >&2
        return 1
    fi

    local table_header="AccountName\tAccountType\tAccountStatus\tAccountDescription\tDBName\tAccountPrivilege\tAccountPrivilegeDetail"
    local jq_filter=".Accounts.DBInstanceAccount[] |
        . as \$account |
        (.DatabasePrivileges.DatabasePrivilege // []) |
        if length > 0 then
            .[] | [
                \$account.AccountName,
                \$account.AccountType,
                \$account.AccountStatus,
                \$account.AccountDescription,
                .DBName,
                .AccountPrivilege,
                (.AccountPrivilegeDetail | split(\",\")[0:3] | join(\",\") + \"...\")
            ] | @tsv
        else
            [
                \$account.AccountName,
                \$account.AccountType,
                \$account.AccountStatus,
                \$account.AccountDescription,
                \"-\",
                \"-\",
                \"-\"
            ] | @tsv
        end"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-10s  %-8s  %-20s  %-16s  %-10s  %s\n", $1, $2, $3, substr($4, 1, 18), $5, $6, $7}'
    
    local result
    result=$(call_aliyun_api rds DescribeAccounts --DBInstanceId "$instance_id")
    
    if [ $? -ne 0 ]; then
        echo "错误：无法获取账号列表。" >&2
        return 1
    fi
    
    format_output \
        "$result" \
        "$format" \
        "rds" \
        "account-list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到账号。" \
        "列出 RDS 账号："
}

# 列出数据库（使用框架函数）
rds_db_list() {
    local instance_id=$1
    local format=${2:-human}

    if [ -z "$instance_id" ]; then
        echo "错误：实例ID不能为空。" >&2
        return 1
    fi

    local table_header="DBName\tCharacterSetName\tDBStatus\tDBDescription"
    local jq_filter=".Databases.Database[] | [.DBName, .CharacterSetName, .DBStatus, .DBDescription] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-15s  %-8s  %s\n", $1, $2, $3, substr($4, 1, 20)}'
    
    local result
    result=$(call_aliyun_api rds DescribeDatabases --DBInstanceId "$instance_id")
    
    if [ $? -ne 0 ]; then
        echo "错误：无法获取数据库列表。" >&2
        return 1
    fi
    
    format_output \
        "$result" \
        "$format" \
        "rds" \
        "db-list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到数据库。" \
        "列出数据库："
}

# 创建数据库（使用框架函数）
rds_db_create() {
    local instance_id=$1
    local db_name=$2
    local charset=${3:-utf8mb4}

    if ! validate_required_params "$instance_id" "$db_name" "错误：实例ID和数据库名不能为空。"; then
        return 1
    fi

    echo "创建数据库："
    echo "实例ID: $instance_id"
    echo "数据库名: $db_name"
    echo "字符集: $charset"

    local result
    result=$(call_aliyun_api rds CreateDatabase \
        --DBInstanceId "$instance_id" \
        --DBName "$db_name" \
        --CharacterSetName "$charset" \
        --DBDescription "Created by CLI")
    
    if [ $? -eq 0 ]; then
        echo "数据库创建成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "rds" "db-create" "$result"
    else
        echo "错误：数据库创建失败。"
        echo "$result"
        return 1
    fi
}

# 删除数据库（使用框架函数）
rds_db_delete() {
    local instance_id=$1
    local db_name=$2

    if ! validate_required_params "$instance_id" "$db_name" "错误：实例ID和数据库名不能为空。"; then
        return 1
    fi

    if ! confirm_action "删除数据库：$db_name"; then
        return 1
    fi

    echo "删除数据库："
    local result
    result=$(call_aliyun_api rds DeleteDatabase \
        --DBInstanceId "$instance_id" \
        --DBName "$db_name")
    
    if [ $? -eq 0 ]; then
        echo "数据库删除成功。"
        log_delete_operation "${profile:-}" "$region" "rds" "$db_name" "数据库" "成功"
    else
        echo "数据库删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "rds" "$db_name" "数据库" "失败"
        return 1
    fi

    log_result "${profile:-}" "$region" "rds" "db-delete" "$result"
}

# 设置账号数据库权限（使用框架函数）
rds_account_grant() {
    local instance_id=$1
    local account_name=$2
    local db_name=$3
    local privilege=${4:-ReadWrite}

    if ! validate_required_params "$instance_id" "$account_name" "$db_name" "错误：实例ID、账号名和数据库名不能为空。"; then
        return 1
    fi

    echo "设置账号权限："
    echo "实例ID: $instance_id"
    echo "账号名: $account_name"
    echo "数据库: $db_name"
    echo "权限: $privilege"

    local result
    result=$(call_aliyun_api rds GrantAccountPrivilege \
        --DBInstanceId "$instance_id" \
        --AccountName "$account_name" \
        --DBName "$db_name" \
        --AccountPrivilege "$privilege")
    
    if [ $? -eq 0 ]; then
        echo "权限设置成功。"
        echo "账号 $account_name 已被授予 $privilege 权限，可访问数据库 $db_name"
        log_result "${profile:-}" "$region" "rds" "account-grant" "$result"
    else
        echo "错误：权限设置失败。"
        echo "$result"
        return 1
    fi
}
