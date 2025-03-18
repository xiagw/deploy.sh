#!/bin/bash
# -*- coding: utf-8 -*-

set -Eeuo pipefail

init_config() {
    # 定义脚本变量
    G_NAME=$(basename "$0")
    G_PATH=$(dirname "$(readlink -f "$0")")
    BACKUP_DIR="/backup"
    G_LOG="$BACKUP_DIR/${G_NAME}.log"

    # 检查备份目录权限
    echo "init dir $G_PATH" >/dev/null
    if [ ! -w "${BACKUP_DIR}" ]; then
        mkdir -m 755 "${BACKUP_DIR}"
    fi

    # 等待MySQL socket文件就绪
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
    log_message "MySQL socket文件已就绪"
    if [ -f /healthcheck.sh ]; then
        sed -i '/mysqladmin --defaults-extra-file=/i \  mysqladmin ping' /healthcheck.sh
        sed -i '/mysqladmin --defaults-extra-file=/d' /healthcheck.sh
    else
        echo "not found entry point file"
    fi
    my_ver=$(mysqld --version | awk '{print $3}' | cut -d. -f1)
    # 检查必要的环境变量
    if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
        log_message "Error: MYSQL_ROOT_PASSWORD is not set"
        return 1
    fi
    # MySQL 8以下版本需要先设置root密码
    if [ "$my_ver" -lt 8 ]; then
        if mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
            log_message "root用户链接成功"
        elif mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; then
            # 检查root是否已设置密码
            log_message "MySQL root用户未设置密码，开始设置密码"
            mysqladmin -u root -p"${MYSQL_ROOT_PASSWORD}" password "${MYSQL_ROOT_PASSWORD}"
            log_message "MySQL root密码设置成功"
        else
            log_message "root用户链接失败"
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

    # 配置mysqldump命令
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

    # 获取当前时区和时间
    local timezone get_hour
    timezone=$(date +%Z)
    get_hour=$(date +%H)

    # 根据时区判断开始时间点
    local start_hour
    if [ "$timezone" = "UTC" ]; then
        start_hour=17 ## 北京时间凌晨1点
    else
        start_hour=1
    fi

    # 判断是否在开始时间后的5小时内
    if [ "$get_hour" -ge "$start_hour" ] && [ "$get_hour" -lt "$((start_hour + 5))" ]; then
        log_message "Good time to backup (starting from $start_hour:00, within 5 hours)"
    else
        return
    fi

    if compgen -G "${BACKUP_DIR}/${backup_date}."* >/dev/null 2>&1; then
        # log_message "警告: 找到当日的备份文件，跳过此次备份"
        return
    fi

    check_disk_space
    # 获取所有数据库列表（排除系统数据库）
    databases="$(mysql -Ne 'show databases' | grep -vE 'information_schema|performance_schema|^sys$|^mysql$')"

    for db in ${databases}; do
        log_message "开始备份数据库: ${db}"
        backup_file="${BACKUP_DIR}/${backup_date}.${backup_time}.full.${db}.sql"
        if mysql "${db}" -e 'select now()' >/dev/null; then
            if ${MYSQLDUMP} "${db}" -r "${backup_file}"; then
                gzip -f "${backup_file}"
                log_message "数据库 ${db} 备份成功: ${backup_file}.gz"
            else
                log_message "数据库 ${db} 备份失败"
            fi
        else
            log_message "数据库 ${db} 不存在"
        fi
    done

    # 清理旧备份
    log_message "清理 15 天前旧的备份数据库文件"
    find "${BACKUP_DIR}" -type f -iname "*.sql.gz" -mtime +15 -delete
}

# 添加磁盘空间检查
check_disk_space() {
    local required_space=5120 # 假设需要5GB空间
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
    # 初始化配置
    init_config

    # 启动备份守护进程
    while true; do
        backup_mysql
        sleep 1h
    done
}

# 执行主函数
main "$@"
