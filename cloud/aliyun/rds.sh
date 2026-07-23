#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# RDS (关系型数据库) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_rds_help() {
    echo "RDS (关系型数据库) 操作："
    echo "  get [<域名>] [format]                    - 列出 RDS 实例（域名可选，支持fzf选择）"
    echo "  add <名称> <引擎> <版本> <规格> [地域]  - 创建 RDS 实例"
    echo "  set [<实例ID>] [<新名称>] [地域]        - 更新 RDS 实例（实例ID和新名称都是可选的，可使用fzf选择）"
    echo "  del [<实例ID>] [地域]                   - 删除 RDS 实例（实例ID可选，可使用fzf选择）"
    echo "  add-acc <实例ID> <账号> <密码> [描述] - 创建数据库账号"
    echo "  del-acc <实例ID> <账号>             - 删除数据库账号"
    echo "  get-acc <实例ID> [format]           - 列出数据库账号"
    echo "  set-acc <实例ID> <账号> <数据库名> [权限]  - 设置账号数据库权限（只读/读写）"
    echo "  get-db <实例ID> [format]                - 列出数据库"
    echo "  add-db <实例ID> <数据库名> [字符集]     - 创建数据库"
    echo "  del-db <实例ID> <数据库名>              - 删除数据库"
    echo "  get-bak [<实例ID>] [format]          - 列出实例备份集"
    echo "  del-bak [<实例ID>] [<备份ID>]        - 删除备份集（可用 fzf 选择；自动备份保留期内不可删）"
    echo "  recovery-time [<实例ID>]                - 查询可恢复时间范围（需开启日志备份，显示本地时间）"
    echo "  restore-clone [实例ID] [备份ID|时间点] [新实例名] - 克隆实例恢复（Serverless）"
    echo "  restore-table <实例ID> <备份ID|时间点> <TableMeta> - 库表恢复到原实例（MySQL/PostgreSQL）"
    echo
    echo "示例："
    echo "  $0 rds get"
    echo "  $0 rds get example.com"
    echo "  $0 rds get example.com json"
    echo "  $0 rds add my-rds MySQL 8.0 rds.mysql.x4.large"
    echo "  $0 rds set rm-xxx new-name"
    echo "  $0 rds del rm-xxx"
    echo "  $0 rds add-acc rm-xxx myuser mypassword '测试账号'"
    echo "  $0 rds del-acc rm-xxx myuser"
    echo "  $0 rds get-acc rm-xxx"
    echo "  $0 rds set-acc rm-xxx myuser mydb ReadWrite"
    echo "  $0 rds set-acc rm-xxx myuser mydb 只读"
    echo "  $0 rds get-db rm-xxx"
    echo "  $0 rds add-db rm-xxx mydb utf8mb4"
    echo "  $0 rds del-db rm-xxx mydb"
    echo "  $0 rds get-bak rm-xxx"
    echo "  $0 rds del-bak rm-xxx 902xxxx"
    echo "  $0 rds recovery-time rm-xxx"
    echo "  $0 rds restore-clone                    # 交互选择实例、备份、可省略新实例名"
    echo "  $0 rds restore-table rm-xxx 902xxxx '[{\"type\":\"db\",\"name\":\"mydb\",\"newname\":\"mydb_restored\"}]'"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_rds_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) rds_list "$@" ;;
    add) rds_create "$@" ;;
    set) rds_update "$@" ;;
    del) rds_delete "$@" ;;
    add-acc) rds_account_create "$@" ;;
    del-acc) rds_account_delete "$@" ;;
    get-acc) rds_account_list "$@" ;;
    set-acc) rds_account_grant "$@" ;;
    get-db) rds_db_list "$@" ;;
    add-db) rds_db_create "$@" ;;
    del-db) rds_db_delete "$@" ;;
    get-bak | get-backup | backup-list) rds_backup_list "$@" ;;
    del-bak | del-backup) rds_backup_delete "$@" ;;
    recovery-time) rds_recovery_time "$@" ;;
    restore-clone) rds_restore_clone "$@" ;;
    restore-table) rds_restore_table "$@" ;;
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
        "describe-db-instances" \
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

    # 如果没有提供参数，则使用 fzf 交互式选择
    if [ -z "$name" ] || [ -z "$engine" ] || [ -z "$version" ] || [ -z "$class" ]; then
        echo "使用 fzf 交互式模式创建 RDS 实例"

        # 输入名称
        if [ -z "$name" ]; then
            read -r -p "请输入 RDS 实例名称: " name
            if [ -z "$name" ]; then
                echo "错误：实例名称不能为空。" >&2
                return 1
            fi
        fi

        # 选择引擎
        if [ -z "$engine" ]; then
            echo "正在获取可用的数据库引擎..."
            local engine_result
            engine_result=$(call_aliyun_api rds describe-regions 2>/dev/null)

            if [ $? -eq 0 ] && [ -n "$engine_result" ]; then
                # 获取支持的数据库引擎
                local engine_list="MySQL
PostgreSQL
SQLServer
MariaDB"
                echo "使用可用引擎列表。"
            else
                echo "警告：无法获取可用引擎，使用默认列表。" >&2
                local engine_list="MySQL
PostgreSQL
SQLServer"
            fi

            if type select_with_fzf >/dev/null 2>&1; then
                engine=$(select_with_fzf "选择数据库引擎" "$engine_list")
            else
                echo "错误：需要选择数据库引擎，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi

        # 选择版本
        if [ -z "$version" ]; then
            echo "正在获取 $engine 引擎的可用版本..."
            local version_result
            version_result=$(call_aliyun_api rds describe-regions 2>/dev/null)

            local version_list
            case "$engine" in
            MySQL)
                if [ $? -eq 0 ] && [ -n "$version_result" ]; then
                    version_list="8.0
5.7
5.6"
                else
                    version_list="8.0
5.7
5.6"
                fi
                ;;
            PostgreSQL)
                if [ $? -eq 0 ] && [ -n "$version_result" ]; then
                    version_list="16.0
15.0
14.0
13.0"
                else
                    version_list="14.0
13.0
12.0"
                fi
                ;;
            SQLServer)
                if [ $? -eq 0 ] && [ -n "$version_result" ]; then
                    version_list="2022
2019
2017
2016"
                else
                    version_list="2019
2017
2016"
                fi
                ;;
            MariaDB)
                if [ $? -eq 0 ] && [ -n "$version_result" ]; then
                    version_list="10.11
10.6
10.5
10.4"
                else
                    version_list="10.5
10.4
10.3"
                fi
                ;;
            *)
                echo "错误：不支持的数据库引擎：$engine" >&2
                return 1
                ;;
            esac
            if type select_with_fzf >/dev/null 2>&1; then
                version=$(select_with_fzf "选择数据库版本" "$version_list")
            else
                echo "错误：需要选择数据库版本，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi

        # 选择规格
        if [ -z "$class" ]; then
            echo "正在获取 $engine $version 的可用实例规格..."
            local class_result
            class_result=$(call_aliyun_api rds describe-available-classes \
                --biz-region-id "${region:-}" \
                --engine "$engine" \
                --engine-version "$version" \
                --instance-charge-type "PostPaid" \
                --category "Basic" \
                --db-instance-storage-type "cloud_essd" \
                --zone-id "$(call_aliyun_api rds describe-zones 2>/dev/null | jq -r '.Zones.Zone[0].ZoneId')" 2>/dev/null)

            local class_list
            if [ $? -eq 0 ] && [ -n "$class_result" ]; then
                class_list=$(echo "$class_result" | jq -r '.Items.DBInstanceClass[].DBInstanceClass' | sort -u)

                if [ -z "$class_list" ]; then
                    echo "警告：无法从 API 获取实例规格，使用备用列表。" >&2
                    case "$engine" in
                    MySQL | PostgreSQL)
                        class_list="rds.mysql.c1.small
rds.mysql.c1.medium
rds.mysql.c2.large
rds.mysql.c3.xlarge
rds.mysql.c4.2xlarge
rds.pg.c1.small
rds.pg.c1.medium
rds.pg.c2.large
rds.pg.c3.xlarge
rds.pg.c4.2xlarge"
                        ;;
                    SQLServer)
                        class_list="rds.mssql.c1.small
rds.mssql.c1.medium
rds.mssql.c2.large
rds.mssql.c3.xlarge
rds.mssql.c4.2xlarge"
                        ;;
                    MariaDB)
                        class_list="rds.maria.c1.small
rds.maria.c1.medium
rds.maria.c2.large
rds.maria.c3.xlarge"
                        ;;
                    esac
                fi
            else
                echo "警告：调用 DescribeAvailableClasses API 失败，使用备用列表。" >&2
                case "$engine" in
                MySQL | PostgreSQL)
                    class_list="rds.mysql.c1.small
rds.mysql.c1.medium
rds.mysql.c2.large
rds.mysql.c3.xlarge
rds.mysql.c4.2xlarge
rds.pg.c1.small
rds.pg.c1.medium
rds.pg.c2.large
rds.pg.c3.xlarge
rds.pg.c4.2xlarge"
                    ;;
                SQLServer)
                    class_list="rds.mssql.c1.small
rds.mssql.c1.medium
rds.mssql.c2.large
rds.mssql.c3.xlarge
rds.mssql.c4.2xlarge"
                    ;;
                MariaDB)
                    class_list="rds.maria.c1.small
rds.maria.c1.medium
rds.maria.c2.large
rds.maria.c3.xlarge"
                    ;;
                esac
            fi

            if type select_with_fzf >/dev/null 2>&1; then
                class=$(select_with_fzf "选择实例规格" "$class_list")
            else
                echo "错误：需要选择实例规格，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    if ! validate_required_params "$name" "$engine" "$version" "$class" "错误：名称、引擎、版本和规格不能为空。"; then
        echo "用法：rds add <名称> <引擎> <版本> <规格> [地域]" >&2
        return 1
    fi

    echo "创建 RDS 实例："
    call_api_logged "rds" "create" "错误：RDS 实例创建失败。" \
        -- rds create-db-instance \
        --biz-region-id "$region" \
        --engine "$engine" \
        --engine-version "$version" \
        --db-instance-class "$class" \
        --db-instance-storage 20 \
        --db-instance-net-type Internet \
        --security-ip-list "0.0.0.0/0" \
        --pay-type Postpaid \
        --db-instance-description "$name"
}

# 使用新框架的更新函数
rds_update() {
    local instance_id new_name=$2

    instance_id=$(_rds_resolve_instance_id "$1" "选择要更新的 RDS 实例") || return 1

    # 输入新名称
    if [ -z "$new_name" ]; then
        read -r -p "请输入新的实例名称: " new_name
        if [ -z "$new_name" ]; then
            echo "错误：新名称不能为空。" >&2
            return 1
        fi
    fi

    echo "更新 RDS 实例："
    call_api_logged "rds" "update" "错误：RDS 实例更新失败。" \
        -- rds modify-db-instance-description \
        --biz-region-id "$region" \
        --db-instance-id "$instance_id" \
        --db-instance-description "$new_name"
}

# 使用新框架的删除函数
rds_delete() {
    local instance_id
    instance_id=$(_rds_resolve_instance_id "$1" "选择要删除的 RDS 实例") || return 1

    if ! confirm_action "删除 RDS 实例：$instance_id"; then
        return 1
    fi

    call_api_del_logged "rds" "$instance_id" "RDS实例" "错误：RDS 实例删除失败。" \
        -- rds delete-db-instance \
        --db-instance-id "$instance_id" \
        --biz-region-id "$region"
}

# 创建数据库账号（保持原有逻辑，但使用框架函数）
rds_account_create() {
    local instance_id=$1
    local account_name=$2
    local password=$3
    local description=${4:-"Created by CLI"}
    local instance_desc=""

    instance_id=$(_rds_resolve_instance_id "$instance_id" "选择要创建账号的 RDS 实例") || return 1

    # 如果没有提供账号名，则交互式输入
    if [ -z "$account_name" ]; then
        read -r -p "请输入账号名称: " account_name
        if [ -z "$account_name" ]; then
            echo "错误：账号名不能为空。" >&2
            return 1
        fi
    fi

    # 如果没有提供密码，则生成或交互式输入
    if [ -z "$password" ]; then
        read -r -p "请输入密码 (回车生成随机密码): " password_input
        if [ -z "$password_input" ]; then
            local try_count=0
            local candidate_password=""
            password=""
            while [ $try_count -lt 10 ]; do
                try_count=$((try_count + 1))
                candidate_password=$(_get_random_password 14 2>/dev/null)
                [ -z "$candidate_password" ] && continue
                echo "$candidate_password" | grep -q "[A-Z]" || continue
                echo "$candidate_password" | grep -q "[a-z]" || continue
                echo "$candidate_password" | grep -q "[0-9]" || continue
                password="$candidate_password"
                break
            done
            if [ -z "$password" ]; then
                echo "错误：无法生成密码，请手动指定密码。" >&2
                return 1
            fi
            echo "生成的密码: $password"
        else
            password="$password_input"
        fi
    fi

    # 如果没有提供描述，则交互式输入
    if [ -z "$description" ]; then
        read -r -p "请输入描述 (回车使用默认描述): " desc_input
        description=${desc_input:-"Created by CLI"}
    fi

    if ! validate_required_params "$instance_id" "$account_name" "错误：实例ID和账号名不能为空。"; then
        echo "用法：rds add-acc <实例ID> <账号> [密码] [描述]" >&2
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

    # 先创建同名数据库（使用 rds_db_create 函数）
    echo "创建同名数据库..."
    if ! rds_db_create "$instance_id" "$account_name" "utf8mb4"; then
        echo "错误：数据库创建失败。"
        return 1
    fi

    echo "创建 RDS 账号："
    echo "实例ID: $instance_id"
    echo "实例名称: $instance_desc"
    echo "账号/密码: $account_name  /  $password"
    echo "描述: $description"

    local result
    result=$(call_aliyun_api rds create-account \
        --biz-region-id "$region" \
        --db-instance-id "$instance_id" \
        --account-name "$account_name" \
        --account-password "$password" \
        --account-description "$description" \
        --account-type Normal)

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

# 私有解析器：RDS 账号名（需传入 instance_id）
_rds_resolve_account_name() {
    resolve_resource_id "$1" "${2:-选择 RDS 账号}" "错误：没有找到 RDS 账号。" \
        '.Accounts.DBInstanceAccount[] | "\(.AccountName) (\(.AccountDescription)) [\(.AccountStatus)]"' \
        -- rds describe-accounts --db-instance-id "$3" --biz-region-id "${region:-}"
}

# 私有解析器：RDS 数据库名（需传入 instance_id）
_rds_resolve_db_name() {
    resolve_resource_id "$1" "${2:-选择数据库}" "错误：没有找到数据库。" \
        '.Databases.Database[] | "\(.DBName) [\(.CharacterSetName)] [\(.DBStatus)]"' \
        -- rds describe-databases --db-instance-id "$3" --biz-region-id "${region:-}"
}

# 删除数据库账号（使用框架函数）
rds_account_delete() {
    local instance_id account_name=$2

    instance_id=$(_rds_resolve_instance_id "$1" "选择 RDS 实例") || return 1
    account_name=$(_rds_resolve_account_name "$account_name" "选择要删除的 RDS 账号" "$instance_id") || return 1
    account_name=$(echo "$account_name" | awk '{print $1}')

    if ! confirm_action "删除 RDS 账号：$account_name"; then
        return 1
    fi

    call_api_del_logged "rds" "$account_name" "RDS账号" "错误：账号删除失败。" \
        -- rds delete-account \
        --db-instance-id "$instance_id" \
        --account-name "$account_name" \
        --biz-region-id "$region"
}

# 列出数据库账号（使用框架函数）
rds_account_list() {
    local instance_id=$1
    local format=${2:-human}

    if is_output_format "$instance_id"; then
        format=$instance_id
        instance_id=""
    fi

    instance_id=$(_rds_resolve_instance_id "$instance_id" "选择要查看账号的 RDS 实例") || return 1

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
    result=$(call_aliyun_api rds describe-accounts --db-instance-id "$instance_id" --biz-region-id "$region" 2>/dev/null)

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

    if is_output_format "$instance_id"; then
        format=$instance_id
        instance_id=""
    fi

    instance_id=$(_rds_resolve_instance_id "$instance_id" "选择要查看数据库的 RDS 实例") || return 1

    local table_header="DBName\tCharacterSetName\tDBStatus\tDBDescription"
    local jq_filter=".Databases.Database[] | [.DBName, .CharacterSetName, .DBStatus, .DBDescription] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-15s  %-8s  %s\n", $1, $2, $3, substr($4, 1, 20)}'

    local result
    result=$(call_aliyun_api rds describe-databases --db-instance-id "$instance_id" --biz-region-id "$region" 2>/dev/null)

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

    instance_id=$(_rds_resolve_instance_id "$instance_id" "选择要创建数据库的 RDS 实例") || return 1

    # 如果没有提供数据库名，则交互式输入
    if [ -z "$db_name" ]; then
        read -r -p "请输入数据库名: " db_name
        if [ -z "$db_name" ]; then
            echo "错误：数据库名不能为空。" >&2
            return 1
        fi
    fi

    # 如果没有提供字符集，则交互式选择
    if [ -z "$charset" ]; then
        local charset_list="utf8mb4
utf8
gbk
latin1"
        if type select_with_fzf >/dev/null 2>&1; then
            charset=$(select_with_fzf "选择字符集" "$charset_list")
        else
            read -r -p "请输入字符集 (utf8mb4/utf8/gbk/latin1): " charset
            charset=${charset:-utf8mb4}
        fi
    fi

    if ! validate_required_params "$instance_id" "$db_name" "错误：实例ID和数据库名不能为空。"; then
        echo "用法：rds add-db <实例ID> <数据库名> [字符集]" >&2
        return 1
    fi

    echo "创建数据库："
    echo "实例ID: $instance_id"
    echo "数据库名: $db_name"
    echo "字符集: $charset"

    call_api_logged "rds" "db-create" "错误：数据库创建失败。" \
        -- rds create-database \
        --db-instance-id "$instance_id" \
        --db-name "$db_name" \
        --character-set-name "$charset" \
        --db-description "Created by CLI" \
        --biz-region-id "$region"
}

# 删除数据库（使用框架函数）
rds_db_delete() {
    local instance_id db_name=$2

    instance_id=$(_rds_resolve_instance_id "$1" "选择 RDS 实例") || return 1

    local raw_db
    raw_db=$(_rds_resolve_db_name "$db_name" "选择要删除的数据库" "$instance_id") || return 1
    db_name=$(echo "$raw_db" | awk '{print $1}')

    if ! confirm_action "删除数据库：$db_name"; then
        return 1
    fi

    call_api_del_logged "rds" "$db_name" "数据库" "错误：数据库删除失败。" \
        -- rds delete-database \
        --db-instance-id "$instance_id" \
        --db-name "$db_name" \
        --biz-region-id "$region"
}

# 设置账号数据库权限（使用框架函数）
rds_account_grant() {
    local instance_id=$1
    local account_name=$2
    local db_name=$3
    local privilege=${4:-ReadWrite}

    instance_id=$(_rds_resolve_instance_id "$instance_id" "选择 RDS 实例") || return 1

    local raw_acc
    raw_acc=$(_rds_resolve_account_name "$account_name" "选择 RDS 账号" "$instance_id") || return 1
    account_name=$(echo "$raw_acc" | awk '{print $1}')

    local raw_db
    raw_db=$(_rds_resolve_db_name "$db_name" "选择数据库" "$instance_id") || return 1
    db_name=$(echo "$raw_db" | awk '{print $1}')

    # 如果没有提供权限，则使用 fzf 选择（仅只读/读写）
    if [ -z "$privilege" ]; then
        local privilege_list="读写 (ReadWrite)
只读 (ReadOnly)"
        if type select_with_fzf >/dev/null 2>&1; then
            privilege=$(select_with_fzf "选择权限级别" "$privilege_list")
            if [ -z "$privilege" ]; then
                privilege="ReadWrite"
            elif [[ "$privilege" == *"ReadOnly"* ]]; then
                privilege="ReadOnly"
            else
                privilege="ReadWrite"
            fi
        else
            read -r -p "请输入权限 (读写/只读 或 ReadWrite/ReadOnly) [默认: 读写]: " privilege_input
            privilege=${privilege_input:-ReadWrite}
        fi
    fi

    # 兼容中文权限输入
    case "$privilege" in
    读写 | readwrite | Readwrite | READWRITE)
        privilege="ReadWrite"
        ;;
    只读 | readonly | Readonly | READONLY)
        privilege="ReadOnly"
        ;;
    esac

    if [ "$privilege" != "ReadWrite" ] && [ "$privilege" != "ReadOnly" ]; then
        echo "错误：权限仅支持 读写/只读（或 ReadWrite/ReadOnly）。" >&2
        return 1
    fi

    echo "设置账号权限："
    echo "实例ID: $instance_id"
    echo "账号名: $account_name"
    echo "数据库: $db_name"
    echo "权限: $privilege"

    local result
    if call_api_logged "rds" "account-set" "错误：权限设置失败。" \
        -- rds grant-account-privilege \
        --db-instance-id "$instance_id" \
        --biz-region-id "$region" \
        --account-name "$account_name" \
        --db-name "$db_name" \
        --account-privilege "$privilege"; then
        echo "账号 $account_name 已被授予 $privilege 权限，可访问数据库 $db_name"
    fi
}

# 解析 RDS 实例 ID（未传入时用 fzf 选择）
_rds_resolve_instance_id() {
    resolve_resource_id "$1" "${2:-选择 RDS 实例}" "错误：没有找到 RDS 实例。" \
        '.Items.DBInstance[] | "\(.DBInstanceId) (\(.DBInstanceDescription // .DBInstanceId)) [\(.Engine) \(.EngineVersion)]"' \
        -- rds describe-db-instances --biz-region-id "$region"
}

# 列出实例备份集（DescribeBackups）
rds_backup_list() {
    local instance_id
    instance_id=$(_rds_resolve_instance_id "$1" "选择要查看备份的 RDS 实例")
    [ $? -ne 0 ] && return 1
    local format=${2:-human}

    local table_header="BackupId\tBackupMode\tBackupStatus\tBackupStartTime\tBackupEndTime\tBackupType\tBackupMethod\tBackupSize\tMetaStatus"
    local jq_filter='.Items.Backup[]? | [.BackupId, .BackupMode, .BackupStatus, .BackupStartTime, .BackupEndTime, .BackupType, .BackupMethod, (.BackupSize // 0 | tostring), (.MetaStatus // "-")] | @tsv'
    local result
    result=$(call_aliyun_api rds describe-backups \
        --db-instance-id "$instance_id" \
        --biz-region-id "$region" \
        --page-size 30 \
        --page-number 1)

    if [ $? -ne 0 ]; then
        echo "错误：无法获取备份列表。" >&2
        echo "$result" >&2
        return 1
    fi

    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {
        mode=$2; if(mode=="Manual") mode="手动"; else if(mode=="Automated") mode="自动";
        status=$3; if(status=="Success") status="成功"; else if(status=="Failed") status="失败";
        printf "%-12s  %-6s  %-6s  %s  %s  %-12s  %-8s  %s  %s\n", $1, mode, status, $4, $5, $6, $7, $8, $9
    }'
    format_output "$result" "$format" "rds" "get-bak" "$table_header" "$jq_filter" \
        "$status_mapper" "没有找到备份集。" "列出 RDS 实例备份：$instance_id" \
        "" '.Items.Backup | length'
}

# 删除备份集（仅手动备份或超出保留期的备份可删除）
rds_backup_delete() {
    local instance_id
    instance_id=$(_rds_resolve_instance_id "$1" "选择要清理备份的 RDS 实例")
    [ $? -ne 0 ] && return 1
    local backup_id=$2

    if [ -z "$backup_id" ]; then
        backup_id=$(resolve_resource_id "" "选择要删除的备份集" "错误：没有找到备份集。" \
            '.Items.Backup[]? | "\(.BackupId) [\(.BackupMode)] [\(.BackupStatus)] \(.BackupEndTime) \((.BackupSize // 0 | tostring))B"' \
            -- rds describe-backups --db-instance-id "$instance_id" --biz-region-id "$region" \
            --page-size 50 --page-number 1) || return 1
    fi

    if ! validate_required_params "$instance_id" "$backup_id" "错误：实例ID和备份ID不能为空。"; then
        return 1
    fi

    confirm_action "您即将删除 RDS 实例 $instance_id 的备份集：$backup_id" || return 1

    echo "删除备份集："
    call_api_logged "rds" "del-bak" "错误：备份集删除失败（自动备份在保留期内不可删除）。" \
        -- rds delete-backup --db-instance-id "$instance_id" --backup-id "$backup_id" || return 1
    echo "备份集删除成功。"
}

# 时间解析顺序：先 macOS 原生 date，再 gdate，最后 fallback 到 date；任一成功即返回
_rds_local_to_utc() {
    local local_time="$1"
    [ -z "$local_time" ] && return 1
    local epoch out
    # 1. macOS 原生：/usr/bin/date 才支持 -j -f
    if [ "$(uname -s)" = "Darwin" ] && [ -x /usr/bin/date ]; then
        for fmt in "%Y-%m-%dT%H:%M:%S" "%Y-%m-%dT%H:%M" "%Y-%m-%d %H:%M:%S" "%Y-%m-%d %H:%M"; do
            epoch=$(/usr/bin/date -j -f "$fmt" "$local_time" +%s 2>/dev/null)
            if [ -n "$epoch" ] && [ "$epoch" -gt 0 ] 2>/dev/null; then
                out=$(/usr/bin/date -r "$epoch" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
                [ -n "$out" ] && echo "$out" && return 0
            fi
        done
    fi
    # 2. gdate（GNU coreutils）
    if command -v gdate >/dev/null 2>&1; then
        epoch=$(gdate -d "$local_time" +%s 2>/dev/null)
        if [ -n "$epoch" ] && [ "$epoch" -gt 0 ] 2>/dev/null; then
            out=$(gdate -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
            [ -n "$out" ] && echo "$out" && return 0
        fi
    fi
    # 3. fallback：系统 date（GNU date -d）
    epoch=$(date -d "$local_time" +%s 2>/dev/null)
    if [ -n "$epoch" ] && [ "$epoch" -gt 0 ] 2>/dev/null; then
        out=$(date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
        [ -n "$out" ] && echo "$out" && return 0
    fi
    return 1
}

# UTC -> 本地时间（展示用），输出 yyyy-MM-ddTHH:mm:ss（无 Z=本地）。顺序：macOS /usr/bin/date -> gdate -> date
_rds_utc_to_local() {
    local utc_time="$1"
    [ -z "$utc_time" ] && return 1
    local epoch out
    # 1. macOS 原生
    if [ "$(uname -s)" = "Darwin" ] && [ -x /usr/bin/date ]; then
        utc_time="${utc_time/Z/}"
        epoch=$(TZ=UTC /usr/bin/date -j -f "%Y-%m-%dT%H:%M:%S" "$utc_time" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(TZ=UTC /usr/bin/date -j -f "%Y-%m-%d %H:%M:%S" "${utc_time/T/ }" +%s 2>/dev/null)
        if [ -n "$epoch" ] && [ "$epoch" -gt 0 ] 2>/dev/null; then
            out=$(/usr/bin/date -r "$epoch" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null)
            [ -n "$out" ] && echo "$out" && return
        fi
    fi
    # 2. gdate
    if command -v gdate >/dev/null 2>&1; then
        epoch=$(gdate -d "$utc_time" +%s 2>/dev/null)
        if [ -n "$epoch" ] && [ "$epoch" -gt 0 ] 2>/dev/null; then
            out=$(gdate -d "@$epoch" +%Y-%m-%dT%H:%M:%S 2>/dev/null)
            [ -n "$out" ] && echo "$out" && return
        fi
    fi
    # 3. fallback：系统 date
    epoch=$(date -d "$utc_time" +%s 2>/dev/null)
    if [ -n "$epoch" ] && [ "$epoch" -gt 0 ] 2>/dev/null; then
        out=$(date -d "@$epoch" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null)
        [ -n "$out" ] && echo "$out" && return
    fi
    echo "$1"
}

# 查询可恢复时间范围（DescribeLocalAvailableRecoveryTime）
rds_recovery_time() {
    local instance_id
    instance_id=$(_rds_resolve_instance_id "$1" "选择要查询可恢复时间的 RDS 实例")
    [ $? -ne 0 ] && return 1

    local result
    result=$(call_aliyun_api rds describe-local-available-recovery-time --db-instance-id "$instance_id" --biz-region-id "$region")

    if [ $? -ne 0 ]; then
        echo "错误：无法获取可恢复时间范围。请确认实例已开启日志备份。" >&2
        echo "$result" >&2
        return 1
    fi

    local begin end begin_local end_local
    begin=$(echo "$result" | jq -r '.RecoveryBeginTime')
    end=$(echo "$result" | jq -r '.RecoveryEndTime')
    begin_local=$(_rds_utc_to_local "$begin")
    end_local=$(_rds_utc_to_local "$end")
    echo "实例: $instance_id"
    echo "可恢复时间范围（本地时间）: $begin_local ~ $end_local"
    echo "（API 用 UTC）: $begin ~ $end"
    echo "$result" | jq '.'
}

# 用 fzf 选择备份或时间点（返回选中的 BackupId 或 RestoreTime）
_rds_select_backup_or_time() {
    local instance_id=$1
    local backups_json
    backups_json=$(call_aliyun_api rds describe-backups --db-instance-id "$instance_id" --biz-region-id "$region" --page-size 50 --page-number 1 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$backups_json" ]; then
        echo "错误：无法获取备份列表。" >&2
        return 1
    fi
    local list
    list="TIME_POINT	⏱ 按时间点恢复（输入本地时间）"
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && list="$list"$'\n'"$line"
    done < <(echo "$backups_json" | jq -r '.Items.Backup[]? | "\(.BackupId)\t\(.BackupEndTime) \(.BackupMode) \(.BackupStatus)"' 2>/dev/null)
    if [ -z "$list" ] || [ "$list" = "TIME_POINT	⏱ 按时间点恢复（输入本地时间）" ]; then
        echo "没有可用备份，尝试按时间点恢复。" >&2
        list="TIME_POINT	⏱ 按时间点恢复（输入本地时间）"
    fi
    local choice
    if type select_with_fzf >/dev/null 2>&1; then
        choice=$(select_with_fzf "选择备份集或按时间点恢复" "$list")
    else
        echo "请选择备份或时间点（输入备份ID 或本地时间 yyyy-MM-dd HH:mm）：" >&2
        echo "$list" | head -20
        read -r choice
    fi
    [ -z "$choice" ] && return 1
    if [[ "$choice" == TIME_POINT* ]] || [[ "$choice" == *"按时间点恢复"* ]]; then
        local range_json
        range_json=$(call_aliyun_api rds describe-local-available-recovery-time --db-instance-id "$instance_id" --biz-region-id "$region" 2>/dev/null)
        local begin end
        begin=$(echo "$range_json" | jq -r '.RecoveryBeginTime // empty')
        end=$(echo "$range_json" | jq -r '.RecoveryEndTime // empty')
        if [ -n "$begin" ] && [ -n "$end" ]; then
            echo "可恢复时间范围（本地，无 Z）: $(_rds_utc_to_local "$begin") ~ $(_rds_utc_to_local "$end")" >&2
        fi
        read -r -p "输入恢复时间（无Z=本地 带Z=UTC，格式 yyyy-MM-ddTHH:mm:ss）: " restore_time
        if [ -z "$restore_time" ]; then
            echo "错误：未输入时间点。" >&2
            return 1
        fi
        local utc_time
        utc_time=$(_rds_local_to_utc "$restore_time")
        if [ -z "$utc_time" ]; then
            echo "错误：时间格式不正确。" >&2
            return 1
        fi
        echo "RESTORE_TIME:$utc_time"
    else
        local bid
        bid=$(echo "$choice" | awk '{print $1}')
        if [ -n "$bid" ] && [[ "$bid" =~ ^[0-9]+$ ]]; then
            echo "BACKUP_ID:$bid"
        else
            echo "错误：未识别备份ID。" >&2
            return 1
        fi
    fi
}

# 克隆实例恢复（CloneDBInstance）：按备份集或时间点恢复到新实例
rds_restore_clone() {
    local instance_id
    instance_id=$(_rds_resolve_instance_id "$1" "选择源 RDS 实例")
    [ $? -ne 0 ] && return 1
    shift

    local backup_or_time=$1
    local new_name=$2

    # 未提供备份/时间点时用 fzf 选择
    if [ -z "$backup_or_time" ]; then
        local selection
        selection=$(_rds_select_backup_or_time "$instance_id")
        [ $? -ne 0 ] && return 1
        if [[ "$selection" == RESTORE_TIME:* ]]; then
            backup_or_time="${selection#RESTORE_TIME:}"
        elif [[ "$selection" == BACKUP_ID:* ]]; then
            backup_or_time="${selection#BACKUP_ID:}"
        else
            echo "错误：未选择有效的备份或时间点。" >&2
            return 1
        fi
    fi

    # 新实例名可选：不填则自动生成（阿里云 API 的 DBInstanceDescription 为可选）
    if [ -z "$new_name" ]; then
        new_name="clone-${instance_id}-$(date +%Y%m%d-%H%M)"
        echo "未指定新实例名，使用: $new_name"
    fi

    local backup_id=""
    local restore_time=""
    if [[ "$backup_or_time" =~ ^[0-9]+$ ]]; then
        backup_id=$backup_or_time
    else
        restore_time=$backup_or_time
        # 若像本地时间（含空格或无 Z），转为 UTC
        if [[ "$restore_time" =~ [\ ] ]] || [[ "$restore_time" != *Z ]]; then
            local utc
            utc=$(_rds_local_to_utc "$restore_time")
            [ -n "$utc" ] && restore_time=$utc
        fi
    fi

    echo "克隆实例恢复：源 $instance_id -> 新实例 $new_name (Serverless)"
    if [ -n "$backup_id" ]; then
        echo "  使用备份集: $backup_id"
    else
        echo "  使用时间点: $restore_time"
    fi

    if ! confirm_action "将创建新 RDS Serverless 实例并产生费用"; then
        return 1
    fi

    # 仅需从源实例取 ZoneId（定价依赖）
    local src_json
    src_json=$(call_aliyun_api rds describe-db-instances --biz-region-id "$region" --db-instance-id "$instance_id" 2>/dev/null)
    local zone_id
    zone_id=$(echo "$src_json" | jq -r --arg id "$instance_id" '.Items.DBInstance[] | select(.DBInstanceId==$id) | .ZoneId // empty')

    # 最少参数：Serverless + VPC + ZoneId + ServerlessConfig
    local api_args=(
        --db-instance-id "$instance_id"
        --pay-type "Serverless"
        --instance-network-type "VPC"
        --db-instance-storage-type "general_essd"
        --db-instance-description "$new_name"
        --category "serverless_basic"
        --serverless-config '{"AutoPause":true,"SwitchForce":true}'
    )
    [ -n "$zone_id" ] && api_args+=(--zone-id "$zone_id")
    [ -n "$backup_id" ] && api_args+=(--backup-id "$backup_id")
    [ -n "$restore_time" ] && api_args+=(--restore-time "$restore_time")

    local result
    result=$(call_aliyun_api rds clone-db-instance --biz-region-id "$region" "${api_args[@]}")

    if [ $? -eq 0 ]; then
        echo "克隆任务已提交："
        echo "$result" | jq '.'
        local new_id
        new_id=$(echo "$result" | jq -r '.DBInstanceId')
        [ -n "$new_id" ] && [ "$new_id" != "null" ] && echo "新实例 ID: $new_id"
        log_result "${profile:-}" "$region" "rds" "restore-clone" "$result"
    else
        echo "错误：克隆实例失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 库表恢复到原实例（RestoreTable）：仅 MySQL/PostgreSQL，需开启日志备份
rds_restore_table() {
    local instance_id
    instance_id=$(_rds_resolve_instance_id "$1" "选择要恢复库表的 RDS 实例")
    [ $? -ne 0 ] && return 1
    shift

    local backup_or_time=$1
    local table_meta=$2

    if [ -z "$backup_or_time" ]; then
        echo "用法: rds restore-table <实例ID> <备份ID|时间点> <TableMeta>" >&2
        echo "  TableMeta 为 JSON，例如只恢复库:" >&2
        echo '    [{"type":"db","name":"mydb","newname":"mydb_restored"}]' >&2
        echo "  恢复库及表（MySQL）:" >&2
        echo '    [{"type":"db","name":"mydb","newname":"mydb_restored","tables":[{"type":"table","name":"t1","newname":"t1_restored"}]}]' >&2
        echo "  时间点支持本地时间（如 yyyy-MM-dd HH:mm）。先使用 backup-list / recovery-time 确认。" >&2
        return 1
    fi

    local backup_id=""
    local restore_time=""
    if [[ "$backup_or_time" =~ ^[0-9]+$ ]]; then
        backup_id=$backup_or_time
    else
        restore_time=$backup_or_time
        if [[ "$restore_time" =~ [\ ] ]] || [[ "$restore_time" != *Z ]]; then
            local utc
            utc=$(_rds_local_to_utc "$restore_time")
            [ -n "$utc" ] && restore_time=$utc
        fi
    fi

    if [ -z "$table_meta" ]; then
        read -r -p "请输入 TableMeta JSON（恢复的库/表及新名称）: " table_meta
        if [ -z "$table_meta" ]; then
            echo "错误：TableMeta 不能为空。" >&2
            return 1
        fi
    fi

    if ! echo "$table_meta" | jq . >/dev/null 2>&1; then
        echo "错误：TableMeta 必须是合法 JSON。" >&2
        return 1
    fi

    local api_args=(
        --db-instance-id "$instance_id"
        --table-meta "$table_meta"
    )
    [ -n "$backup_id" ] && api_args+=(--backup-id "$backup_id")
    [ -n "$restore_time" ] && api_args+=(--restore-time "$restore_time")

    local result
    result=$(call_aliyun_api rds restore-table --biz-region-id "$region" "${api_args[@]}")

    if [ $? -eq 0 ]; then
        echo "库表恢复任务已提交。"
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "rds" "restore-table" "$result"
    else
        echo "错误：库表恢复失败。请确认实例已开启日志备份且备份集支持库表恢复（MetaStatus=OK）。" >&2
        echo "$result" >&2
        return 1
    fi
}
