#!/bin/bash
# -*- coding: utf-8 -*-

set -Eeuo pipefail

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

    # Wait for MySQL socket file to be ready
    mysql_sock=/var/lib/mysql/mysql.sock
    start_time=$(date +%s)
    while [ ! -S "$mysql_sock" ]; do
        current_time=$(date +%s)
        if [ $((current_time - start_time)) -gt 300 ]; then
            log_message "Error: Timeout waiting for MySQL socket"
            return 1
        fi
        log_message "Waiting for MySQL socket file: $mysql_sock"
        sleep 3
    done
    log_message "MySQL socket file is ready"
    if [ -f /healthcheck.sh ]; then
        sed -i '/mysqladmin --defaults-extra-file=/i \  mysqladmin ping' /healthcheck.sh
        sed -i '/mysqladmin --defaults-extra-file=/d' /healthcheck.sh
    else
        log_message "not found /healthcheck.sh"
    fi
    my_ver=$(mysqld --version | awk '{print $3}' | cut -d. -f1)
    # Check required environment variables
    if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
        log_message "Error: MYSQL_ROOT_PASSWORD is not set"
        return 1
    fi
    # MySQL versions below 8 need to set root password first
    if [ "$my_ver" -lt 8 ]; then
        if mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
            log_message "Root user connection successful"
        elif mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
            # Check if root password is already set
            log_message "MySQL root user password not set, starting password setup"
            mysqladmin -u root -p"${MYSQL_ROOT_PASSWORD}" password "${MYSQL_ROOT_PASSWORD}" >/dev/null 2>&1
            log_message "MySQL root password setup successful"
        else
            log_message "Root user connection failed"
            return 1
        fi

        dump_opt="--master-data=2"
    else
        dump_opt="--source-data=2"
    fi

    my_conf=/root/.my.cnf
    (
        echo "[client]"
        echo "password=$MYSQL_ROOT_PASSWORD"
    ) >"$my_conf"
    chmod 600 "$my_conf"

    # Configure mysqldump command
    MYSQLDUMP="mysqldump --defaults-extra-file=$my_conf --set-gtid-purged=OFF -E -R --triggers $dump_opt"
}

log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [backup] $message" | tee -a "${G_LOG}"
}

backup_mysql() {
    local backup_time backup_file databases
    backup_date="$(date +%F)"
    backup_time="$(date +%s)"

    # Get current timezone and hour
    local timezone get_hour
    timezone=$(date +%Z)
    get_hour=$(date +%H)

    # Determine start hour based on timezone
    local start_hour
    if [ "$timezone" = "UTC" ]; then
        start_hour=17 ## Beijing time 1:00 AM
    else
        start_hour=1
    fi

    # Check if within 5 hours after start time
    if [ "$get_hour" -ge "$start_hour" ] && [ "$get_hour" -lt "$((start_hour + 5))" ]; then
        log_message "Good time to backup (starting from $start_hour:00, within 5 hours)"
    else
        return
    fi

    if compgen -G "${BACKUP_DIR}/${backup_date}."* >/dev/null 2>&1; then
        # log_message "Warning: Found backup file for today, skipping this backup"
        return
    fi

    check_disk_space
    # Get all database lists (excluding system databases)
    databases="$(mysql -Ne 'show databases' | grep -vE 'information_schema|performance_schema|^sys$|^mysql$')"

    for db in ${databases}; do
        log_message "Starting backup for database: ${db}"
        backup_file="${BACKUP_DIR}/${backup_date}.${backup_time}.full.${db}.sql"
        if mysql "${db}" -e 'select now()' >/dev/null; then
            if ${MYSQLDUMP} "${db}" -r "${backup_file}"; then
                gzip -f "${backup_file}"
                log_message "Database ${db} backup successful: ${backup_file}.gz"
            else
                log_message "Database ${db} backup failed"
            fi
        else
            log_message "Database ${db} does not exist"
        fi
    done

    # Clean old backups
    log_message "Cleaning backup files older than 15 days"
    find "${BACKUP_DIR}" -type f -iname "*.sql.gz" -mtime +15 -delete
}

# Add disk space check
check_disk_space() {
    local required_space=5120 # Assume 5GB space needed
    local available_space
    available_space=$(df -m "${BACKUP_DIR}" | awk 'NR==2 {print $4}')
    if [ "${available_space}" -lt "${required_space}" ]; then
        log_message "Error: Not enough disk space. Required: ${required_space}MB, Available: ${available_space}MB"
        return 1
    fi
    return 0
}

main() {
    if [ "$UID" -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [backup], daemon running"
    else
        return 0
    fi

    sleep 15
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
