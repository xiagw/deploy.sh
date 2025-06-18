#!/bin/bash
# -*- coding: utf-8 -*-

set -Eeo pipefail

log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [backup] $message" | tee -a "${G_LOG}"
}

init_config() {
    # Define script variables
    G_NAME=$(basename "$0")
    G_PATH=$(dirname "$(readlink -f "$0")")
    BACKUP_DIR="/backup"
    G_LOG="$BACKUP_DIR/${G_NAME}.log"

    # Check backup directory permissions
    echo "init dir $G_PATH" >/dev/null
    if [ ! -w "${BACKUP_DIR}" ]; then
        mkdir -m 755 "${BACKUP_DIR}"
    fi

    if [ -f /healthcheck.sh ]; then
        sed -i '/mysqladmin --defaults-extra-file=/i \  mysqladmin ping' /healthcheck.sh
        sed -i '/mysqladmin --defaults-extra-file=/d' /healthcheck.sh
    else
        log "not found /healthcheck.sh"
    fi
    my_ver=$(mysqld --version | awk '{print $3}' | cut -d. -f1)
    # Check required environment variables
    if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
        log "Error: MYSQL_ROOT_PASSWORD is not set"
        return 1
    fi

    # 等待数据文件存在且MySQL服务可用
    while ! { [ -f "/var/lib/mysql/ibdata1" ] && mysqladmin ping -h"localhost" --silent; }; do
        sleep 1
    done

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
        echo "password=$MYSQL_ROOT_PASSWORD"
    } >"$my_cnf"
    chmod 600 "$my_cnf"

    # Configure mysqldump command
    MYSQL_CLI="mysql --defaults-file=$my_cnf"
    MYSQLDUMP="mysqldump --defaults-file=$my_cnf --set-gtid-purged=OFF -E -R --triggers $dump_opt"
}

# Add disk space check
check_disk_space() {
    local required_space=5120 # Assume 5GB space needed
    local available_space
    available_space=$(df -m "${BACKUP_DIR}" | awk 'NR==2 {print $4}')
    if [ "${available_space}" -lt "${required_space}" ]; then
        log "Error: Not enough disk space. Required: ${required_space}MB, Available: ${available_space}MB"
        return 1
    fi
    return 0
}

backup_mysql() {
    local backup_time backup_file databases
    backup_date="$(date +%F)"
    backup_time="$(date +%s)"

    # Get current timezone and hour
    local timezone current_hour
    timezone=$(date +%Z)
    current_hour=$(date +%H)

    # Determine start hour based on timezone
    local start_hour
    if [ "$timezone" = "UTC" ]; then
        start_hour=17 ## Beijing time 1:00 AM
    else
        start_hour=1
    fi

    # Check if within 5 hours after start time
    log "Current timezone: ${timezone}, current hour: ${current_hour}, start hour: ${start_hour}"
    if [ "$current_hour" -ge "$start_hour" ] && [ "$current_hour" -lt "$((start_hour + 3))" ]; then
        log "Good time to backup (starting from ${start_hour}:00, within 3 hours)"
    else
        # log "Not good time($current_hour) to backup"
        return
    fi

    if compgen -G "${BACKUP_DIR}/${backup_date}."* >/dev/null 2>&1; then
        log "Warning: Found backup file for today, skipping this backup"
        return
    fi

    check_disk_space

    # Get all database lists (excluding system databases)
    databases="$($MYSQL_CLI -Ne 'show databases' | grep -vE 'information_schema|performance_schema|^sys$|^mysql$')"

    for db in ${databases}; do
        log "Starting backup for database: ${db}"
        backup_file="${BACKUP_DIR}/${backup_date}.${backup_time}.full.${db}.sql"
        if $MYSQL_CLI "${db}" -e 'select now()' >/dev/null; then
            if ${MYSQLDUMP} "${db}" -r "${backup_file}"; then
                command -v gzip && gzip -f "${backup_file}"
                log "Database ${db} backup successful: ${backup_file}"
            else
                log "Database ${db} backup failed"
            fi
        else
            log "Database ${db} does not exist"
        fi
    done

    # Clean old backups
    if [ -f "${BACKUP_DIR}/.clean" ]; then
        local days
        days="$(grep -oE '[0-9]+' "${BACKUP_DIR}/.clean" | head -n1)"
        if [ -z "$days" ]; then
            log "Not found NUMBERS in ${BACKUP_DIR}/.clean, skip clean"
            return
        fi
        log "Cleaning backup files older than $days days"
        find "${BACKUP_DIR}" -type f -iname "*.sql" -mtime +"$days" -delete
        find "${BACKUP_DIR}" -type f -iname "*.sql.gz" -mtime +"$days" -delete
    else
        log "Not found ${BACKUP_DIR}/.clean, skip clean backup files"
    fi
}

main() {
    if [ "$UID" -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [backup] daemon running"
    else
        return 0
    fi

    # Initialize configuration
    init_config

    # Start backup daemon process
    while true; do
        backup_mysql
        sleep 1h
    done
}

# Execute main function
main "$@"
