#!/bin/bash
# -*- coding: utf-8 -*-
# =============================================================================
# MySQL 备份脚本（在 MySQL 容器内以后台任务方式运行）
# 功能：等待 MySQL 就绪后，在指定时间窗口内执行全库 mysqldump，输出到 /backup，
#       并可根据 BACKUP_DIR/.clean 中写的天数清理过期备份。
#
# 使用：由 MySQL 镜像的 Dockerfile 在 entrypoint 中注入并后台执行，例如
#       (exec /opt/mbk.sh) &
#
# 依赖环境变量：MYSQL_ROOT_PASSWORD
# 备份目录：/backup；清理规则：在 /backup/.clean 中写数字 N 表示删除 N 天前的备份
# =============================================================================

# set -Eeo pipefail

# Define script variables
G_NAME=$(basename "$0")
G_PATH=$(dirname "$(readlink -f "$0")")
BACKUP_DIR="/backup"
G_LOG="$BACKUP_DIR/${G_NAME}.log"

log() {
    echo "[$(date +%Y%m%d_%u_%T.%3N)] $*" | tee -a "${G_LOG}"
}

init_config() {
    # Check backup directory permissions
    echo "$G_PATH" >/dev/null
    if [ ! -w "${BACKUP_DIR}" ]; then
        mkdir -m 755 "${BACKUP_DIR}"
    fi

    if [ -f /healthcheck.sh ]; then
        sed -i '/mysqladmin --defaults-extra-file=/i \  mysqladmin ping' /healthcheck.sh
        sed -i '/mysqladmin --defaults-extra-file=/d' /healthcheck.sh
    fi

    # 等待数据文件存在且MySQL服务可用
    local c=0
    while ! {
        [ -f "/var/lib/mysql/ibdata1" ] &&
            [ -e "/var/lib/mysql/mysql.sock" ] &&
            mysqladmin ping -h"localhost" --silent >/dev/null
    }; do
        c=$((c + 1))
        sleep 1
        if [ "$c" -gt 60 ]; then
            return 1
        fi
    done

    local my_ver
    my_ver=$(mysqld --version | awk '{print $3}' | cut -d. -f1)
    # Check required environment variables
    if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
        log "ERR: MYSQL_ROOT_PASSWORD is not set"
        return 1
    fi
    # MySQL versions below 8 need to set root password first
    if [ "$my_ver" -lt 8 ]; then
        # Check if root password is already set
        if mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
            log "Initial password for root@localhost"
            mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
        elif mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
            log "Root user connection successful"
        else
            log "Root user connection failed"
            return 1
        fi
        dump_opt="--master-data=2"
    else
        dump_opt="--source-data=2"
    fi

    my_cnf=/root/.my.cnf
    {
        echo "[client]"
        echo "user=root"
        echo "password=$MYSQL_ROOT_PASSWORD"
    } >"$my_cnf"
    chmod 600 "$my_cnf"

    # Configure mysqldump command
    MYSQL_CLI="mysql --defaults-file=$my_cnf"
    MYSQLDUMP="mysqldump --defaults-file=$my_cnf --set-gtid-purged=OFF -E -R --triggers $dump_opt"

    local space_used # 80% space used will exit
    local space_thread=80
    space_summary=$(df -m "${BACKUP_DIR}" | awk 'NR==2 {print}')
    space_used=$(echo "${space_summary}" | awk '{print int($5)}')
    if [ "${space_used}" -gt "${space_thread}" ]; then
        log "ERR: Not enough disk space. Space used: ${space_summary}"
        return 1
    else
        return 0
    fi
}

backup_mysql() {
    # Get current timezone and hour
    local timezone
    timezone=$(date +%Z)

    # Determine start hour based on timezone, 1:00-6:00 CST, 17:00-22:00 UTC
    local start_hour=1
    if [ "$timezone" = "UTC" ]; then
        start_hour=17 ## Asia/Shanghai 1:00 AM
    fi
    local end_hour=$((start_hour + 5))

    # Check if within 5 hours after start time
    local current_hour
    current_hour=$(date +%H)
    # log "Check timezone: ${timezone}, current hour: ${current_hour}:00, start hour: ${start_hour}:00"
    if [ "$current_hour" -ge "$start_hour" ] && [ "$current_hour" -le "${end_hour}" ]; then
        log "Good time to backup (starting from ${start_hour}:00, within 5 hours)"
    else
        # log "WARN: Not good time($current_hour) to backup"
        return 0
    fi

    local backup_time backup_file databases
    backup_date="$(date +%Y%m%d)"
    backup_time="$(date +%s)"
    if compgen -G "${BACKUP_DIR}/${backup_date}."* >/dev/null 2>&1; then
        log "WARN: Found backup file for today, skip."
        return
    fi

    # Get all database lists (excluding system databases)
    databases="$($MYSQL_CLI -Ne 'show databases' | grep -vE 'information_schema|performance_schema|^sys$|^mysql$')"

    for db in ${databases}; do
        if $MYSQL_CLI "${db}" -e 'select now()' >/dev/null; then
            log "Database ${db} exist"
        else
            log "Database ${db} does not exist"
            continue
        fi
        backup_file="${BACKUP_DIR}/${backup_date}.${backup_time}.full.${db}.sql"
        if command -v gzip; then
            backup_file="${backup_file}.gz"
            if ${MYSQLDUMP} "${db}" | gzip -c >"${backup_file}"; then
                log "Database ${db} backup successful: ${backup_file}"
            else
                log "Database ${db} backup failed"
            fi
        else
            if ${MYSQLDUMP} "${db}" -r "${backup_file}"; then
                log "Database ${db} backup successful: ${backup_file}"
            else
                log "Database ${db} backup failed"
            fi
        fi
    done

    # Clean old backups，在clean文件中写一个数字就删除多少天前的文件，按修改时间
    if [ -f "${BACKUP_DIR}/.clean" ]; then
        local days
        days="$(grep -oE '[0-9]+' "${BACKUP_DIR}/.clean" | head -n1)"
        if [ -z "$days" ]; then
            log "Not found NUMBERS in ${BACKUP_DIR}/.clean, skip clean"
            return 0
        fi
        log "Cleaning backup files older than $days days"
        find "${BACKUP_DIR}" -type f -iname "*.sql*" -mtime +"$days" -delete
    else
        log "Not found ${BACKUP_DIR}/.clean, skip clean backup files"
    fi
    log "============cut line============"
}

main() {
    if [ "$UID" -eq 0 ]; then
        log "Daemon running"
    else
        return 0
    fi
    log "Create daemon of backup_mysql..."
    while true; do
        # Initialize configuration
        if init_config; then
            # Start backup daemon process 等待mysql启动完成
            sleep 30
            backup_mysql
        else
            log "ERR: init_config fail, skip backup_mysql"
        fi
        sleep 1h
    done
}

main "$@"

#     $MYSQL_CLI <<'EOF'
# START TRANSACTION;
# CREATE DATABASE IF NOT EXISTS `test2`;
# USE `test2`;
# CREATE TABLE IF NOT EXISTS `test2` (
#     id INT AUTO_INCREMENT PRIMARY KEY,
#     name VARCHAR(255),
#     time DATETIME
# );
# INSERT INTO `test2` (name, time) VALUES ('test', NOW());
# COMMIT;
# EOF
