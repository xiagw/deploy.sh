#!/bin/bash
# -*- coding: utf-8 -*-

log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [backup] $message" | tee -a "${G_LOG}"
}

backup_mysql() {
    local backup_time backup_file databases
    backup_date="$(date +%F)"
    backup_time="$(date +%s)"
    get_hour="$(date +%H)"

    if compgen -G "${BACKUP_DIR}/${backup_date}."* >/dev/null 2>&1; then
        # log_message "警告: 找到当日的备份文件，跳过此次备份"
        return
    fi
    if [ "${get_hour}" -ge 17 ] && [ "${get_hour}" -le 21 ]; then
        log_message "Good time to backup"
    else
        return
    fi

    # 配置mysqldump命令
    my_ver=$(mysqld --version | awk '{print $3}' | cut -d. -f1)
    cmd_dump="mysqldump ${MYSQL_CONF} --set-gtid-purged=OFF -E -R --triggers"
    if [ "$my_ver" -lt 8 ]; then
        cmd_dump+=" --master-data=2"
    else
        cmd_dump+=" --source-data=2"
    fi

    # 获取所有数据库列表（排除系统数据库）
    databases="$(mysql -Ne 'show databases' | grep -vE 'information_schema|performance_schema|^sys$|^mysql$')"

    for db in ${databases}; do
        log_message "开始备份数据库: ${db}"
        backup_file="${BACKUP_DIR}/${backup_date}.${backup_time}.full.${db}.sql"
        if mysql "${db}" -e 'select now()' >/dev/null; then
            if ${cmd_dump} "${db}" -r "${backup_file}"; then
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
    log_message "清理 ${BACKUP_RETAIN_DAYS} 天前旧的备份数据库文件"
    find "${BACKUP_DIR}" -type f -iname "*.sql.gz" -mtime +"${BACKUP_RETAIN_DAYS}" -delete
}

main() {
    if [ $UID -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [backup], daemon running"
    else
        return 0
    fi
    # 定义脚本变量
    G_NAME=$(basename "$0")
    G_PATH=$(dirname "$(readlink -f "$0")")
    BACKUP_DIR="/backup"
    G_LOG="$BACKUP_DIR/${G_NAME}.log"
    BACKUP_RETAIN_DAYS=15

    # 检查备份目录权限
    if [ ! -w "${BACKUP_DIR}" ]; then
        mkdir -p "${BACKUP_DIR}"
        chmod 755 "${BACKUP_DIR}"
    fi

    my_conf=/root/.my.cnf
    echo "[client]" >$my_conf
    echo "password=$MYSQL_ROOT_PASSWORD" >>$my_conf
    # 设置MySQL备份配置
    if [ -f "$my_conf" ]; then
        MYSQL_CONF="--defaults-extra-file=$my_conf"
    else
        log_message "警告: 未找到MySQL配置文件"
        # return 1
    fi
    # 启动备份守护进程
    while true; do
        sleep 50
        backup_mysql
        sleep 1h
    done &
    # echo $! >/var/run/mysql-backup.pid
}

# 执行主函数
main "$@"
