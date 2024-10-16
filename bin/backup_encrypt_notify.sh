#!/usr/bin/env bash

_log() {
    local level=$1
    local log_file=$2
    shift 2
    local message="$*"
    local level_name
    local color

    case $level in
    "$LOG_LEVEL_ERROR")
        level_name="ERROR"
        color="$COLOR_RED"
        ;;
    "$LOG_LEVEL_WARNING")
        level_name="WARNING"
        color="$COLOR_YELLOW"
        ;;
    "$LOG_LEVEL_INFO")
        level_name="INFO"
        color="$COLOR_RESET"
        ;;
    "$LOG_LEVEL_SUCCESS")
        level_name="SUCCESS"
        color="$COLOR_GREEN"
        ;;
    *)
        level_name="UNKNOWN"
        color="$COLOR_RESET"
        ;;
    esac

    if [[ $CURRENT_LOG_LEVEL -ge $level ]]; then
        # 输出到终端时使用颜色
        echo -e "${color}[${level_name}] $(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET} - $message" >&2
        # 输出到日志文件时不使用颜色
        echo "[${level_name}] $(date '+%Y-%m-%d %H:%M:%S') - $message" >>"$log_file"
    fi
}

_load_config() {
    # 使用更安全的方法来处理可能包含空格的参数值
    while [[ $# -gt 0 ]]; do
        case $1 in
        *.env)
            _log $LOG_LEVEL_INFO "$me_log" "Loading configuration from $1"
            # shellcheck source=/dev/null
            source "$1"
            ;;
        --via-domain=*) VIA_DOMAIN="${1#*=}" ;;
        --mysql-host=*) MYSQL_HOST="${1#*=}" ;;
        --mysql-user=*) MYSQL_USER="${1#*=}" ;;
        --mysql-password=*) MYSQL_PASSWORD="${1#*=}" ;;
        --mysql-dbs=*) IFS=',' read -ra MYSQL_DBS <<<"${1#*=}" ;;
        --wechat-key=*) WECHAT_KEY="${1#*=}" ;;
        --aliyun-oss-bucket=*) ALIYUN_OSS_BUCKET="${1#*=}" ;;
        --aliyun-region=*) ALIYUN_REGION="${1#*=}" ;;
        --aliyun-access-key-id=*) ALIYUN_ACCESS_KEY_ID="${1#*=}" ;;
        --aliyun-access-key-secret=*) ALIYUN_ACCESS_KEY_SECRET="${1#*=}" ;;
        --aliyun-profile=*) ALIYUN_PROFILE="${1#*=}" ;;
        --hosts=*) IFS=',' read -ra HOSTS <<<"${1#*=}" ;;
        --paths=*) IFS=',' read -ra PATHS <<<"${1#*=}" ;;
        --redis-host=*) REDIS_HOST="${1#*=}" ;;
        --redis-port=*) REDIS_PORT="${1#*=}" ;;
        --redis-password=*) REDIS_PASSWORD="${1#*=}" ;;
        --redis-db-numbers=*) IFS=',' read -ra REDIS_DB_NUMBERS <<<"${1#*=}" ;;
        --log-level=*) LOG_LEVEL="${1#*=}" ;;
        --debug) DEBUG=true ;;
        *)
            _log $LOG_LEVEL_ERROR "$me_log" "Unknown option: $1"
            exit 1
            ;;
        esac
        shift
    done

    # Set log level
    case "${LOG_LEVEL,,}" in
    error) CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
    warning) CURRENT_LOG_LEVEL=$LOG_LEVEL_WARNING ;;
    info) CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
    *)
        _log $LOG_LEVEL_WARNING "$me_log" "Invalid log level: $LOG_LEVEL. Using default (INFO)."
        CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
        ;;
    esac

    # Set default encryption method if not specified
    ALIYUN_REGION=${ALIYUN_REGION:-cn-hangzhou}
    ALIYUN_PROFILE=${ALIYUN_PROFILE:-default}

    # Define base required parameters
    required_params=(PATHS)

    # Add OSS_BUCKET to required parameters if VIA_DOMAIN starts with "cdn"
    if [[ "${VIA_DOMAIN:-}" == cdn* ]]; then
        required_params+=(ALIYUN_OSS_BUCKET)
    fi

    # Check required parameters
    for param in "${required_params[@]}"; do
        if [[ -z "${!param}" ]]; then
            _log $LOG_LEVEL_ERROR "$me_log" "Error: Required parameter $param is missing or empty"
            exit 1
        fi
    done

    # If HOSTS is not specified, use localhost
    if [[ -z "${HOSTS[*]}" ]]; then
        HOSTS=("localhost")
        _log $LOG_LEVEL_WARNING "$me_log" "HOSTS not specified, using localhost"
    fi

    # Use a more secure method to store MySQL credentials
    if [[ -n "$MYSQL_HOST" && -n "$MYSQL_USER" && -n "$MYSQL_PASSWORD" && -n "${MYSQL_DBS[*]}" ]]; then
        MYSQL_CREDENTIALS=$(mktemp)
        trap 'rm -f "$MYSQL_CREDENTIALS"' EXIT
        printf '[client]\nhost=%s\nuser=%s\npassword=%s\n' "$MYSQL_HOST" "$MYSQL_USER" "$MYSQL_PASSWORD" >"$MYSQL_CREDENTIALS"
        chmod 600 "$MYSQL_CREDENTIALS"
    fi

    # Set debug mode if DEBUG is true
    if [[ "${DEBUG:-}" == "true" ]]; then
        set -x
        CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
        _log $LOG_LEVEL_INFO "$me_log" "Debug mode enabled"
    fi
}

_check_commands() {
    # 检查必要的命令是否可用
    for cmd in "${@}"; do
        if ! command -v "$cmd" &>/dev/null; then
            _log $LOG_LEVEL_ERROR "$me_log" "$cmd command not found. Please install $cmd."
            return 1
        fi
    done
}

_check_disk_space() {
    # 检查磁盘空间
    local available_space
    available_space=$(df -k . | awk 'NR==2 {print $4}')
    local required_space=$((5 * 1024 * 1024)) # 假设需要 5GB 空间
    if [[ $available_space -lt $required_space ]]; then
        _log $LOG_LEVEL_ERROR "$me_log" "Not enough disk space. Required: 5GB, Available: $((available_space / 1024 / 1024))GB"
        return 1
    fi
}

_dump_redis() {
    if [[ -z "${REDIS_HOST:-}" || -z "${REDIS_PORT:-}" || -z "${REDIS_DB_NUMBERS[*]:-}" ]]; then
        _log $LOG_LEVEL_WARNING "$me_log" "Redis backup skipped: Redis parameters not provided"
        return
    fi
    _check_commands redis-cli || return 1

    local path="$1/$2/redis"
    local file="$2"
    mkdir -p "$path"

    for db in "${REDIS_DB_NUMBERS[@]}"; do
        local backup_file="$path/redis_db${db}_${file}.rdb"
        _log $LOG_LEVEL_INFO "$me_log" "Backing up Redis database $db to $backup_file"

        if [ -n "$REDIS_PASSWORD" ]; then
            redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --rdb "$backup_file" --db "$db"
        else
            redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --rdb "$backup_file" --db "$db"
        fi

        if [ $? -eq 0 ]; then
            _log $LOG_LEVEL_SUCCESS "$me_log" "Redis database $db backup completed successfully"
        else
            _log $LOG_LEVEL_ERROR "$me_log" "Error: Redis database $db backup failed"
        fi
    done
}

_dump_mysql() {
    if [[ -z "${MYSQL_HOST:-}" || -z "${MYSQL_USER:-}" || -z "${MYSQL_PASSWORD:-}" || -z "${MYSQL_DBS[*]:-}" ]]; then
        _log $LOG_LEVEL_WARNING "$me_log" "MySQL backup skipped: MySQL parameters not provided"
        return
    fi
    # 修复：检查 MYSQL_CREDENTIALS 是否存在
    if [[ ! -f "$MYSQL_CREDENTIALS" ]]; then
        _log $LOG_LEVEL_ERROR "$me_log" "MySQL credentials file not found"
        return 1
    fi

    _check_commands mysqldump || return 1

    local path="$1/$2/mysql"
    local file="$2"
    mkdir -p "$path"

    for db in "${MYSQL_DBS[@]}"; do
        local backup_file="$path/${db}_${file}.sql"
        _log $LOG_LEVEL_INFO "$me_log" "Backing up MySQL database $db to $backup_file"

        if mysqldump --defaults-extra-file="$MYSQL_CREDENTIALS" --single-transaction --quick --lock-tables=false --set-gtid-purged=OFF --triggers --routines --events --databases "$db" --result-file="$backup_file"; then
            _log $LOG_LEVEL_SUCCESS "$me_log" "MySQL database $db backup completed successfully"
        else
            _log $LOG_LEVEL_ERROR "$me_log" "MySQL database $db backup failed"
            return
        fi
    done
}

_backup_directories() {
    local path="$1/$2"
    local file="${2}.tar.gz"

    for host in "${HOSTS[@]}"; do
        host_path="$path/${host}"
        mkdir -p "$host_path"

        for dir in "${PATHS[@]}"; do
            path_left=$(dirname "$dir")
            path_right=$(basename "$dir")
            _log $LOG_LEVEL_INFO "$me_log" "Backing up $host:$dir to $host_path/${path_right}_${file}"

            if [[ $host == "localhost" ]]; then
                tar -C "${path_left}" -czf "${host_path}/${path_right}_${file}" "${path_right}"
                _log $LOG_LEVEL_SUCCESS "$me_log" "Backup successful localhost:$dir to $host_path/${path_right}_${file}"
                continue
            fi

            if ssh -o StrictHostKeyChecking=no "$host" "tar -C ${path_left} -czf - ${path_right}" >"$host_path/${path_right}_${file}"; then
                _log $LOG_LEVEL_SUCCESS "$me_log" "Backup successful $host:$dir to $host_path/${path_right}_${file}"
            else
                _log $LOG_LEVEL_ERROR "$me_log" "Backup failed $host:$dir to $host_path/${path_right}_${file}"
                return 1
            fi
        done
    done
}

_compress_file() {
    local path="$1"
    local file="$2"
    local file_tar="${file}.tar.gz"

    _log $LOG_LEVEL_INFO "$me_log" "Compressing: tar -czf $path/${file_tar} $file"
    tar -czf "$path/${file_tar}" "$file"
}

_encrypt_file() {
    local path="$1"
    local file="${2}.tar.gz"
    local file_enc="${file}.enc"

    if _check_commands gpg; then
        _log $LOG_LEVEL_INFO "$me_log" "Encrypting: ${g_gpg_opt[*]} --symmetric ${path}/$file"
        "${g_gpg_opt[@]}" --symmetric "${path}/$file"
        mv "${path}/${file}.gpg" "${path}/$file_enc"
    elif _check_commands openssl; then
        _log $LOG_LEVEL_INFO "$me_log" "Encrypting: ${g_openssl_opt[*]} -in ${path}/$file -out ${path}/$file_enc"
        "${g_openssl_opt[@]}" -in "${path}/$file" -out "${path}/$file_enc"
    else
        _log $LOG_LEVEL_ERROR "$me_log" "Unsupported encryption method."
        return 1
    fi
    _log $LOG_LEVEL_INFO "$me_log" "Generating sha256sum: sha256sum ${file_enc} > ${file_enc}.sha256sum"
    pushd "$path"
    sha256sum "$file_enc" >"${file_enc}.sha256sum"
    popd
}

_configure_aliyun_cli() {
    _check_commands aliyun || return 1
    if [[ -n "$ALIYUN_ACCESS_KEY_ID" && -n "$ALIYUN_ACCESS_KEY_SECRET" ]]; then
        if ! aliyun sts GetCallerIdentity --profile "$ALIYUN_PROFILE"; then
            _log $LOG_LEVEL_INFO "$me_log" "Configuring Aliyun CLI with profile: $ALIYUN_PROFILE"
            aliyun configure set \
                --profile "$ALIYUN_PROFILE" \
                --mode AK \
                --region "$ALIYUN_REGION" \
                --access-key-id "$ALIYUN_ACCESS_KEY_ID" \
                --access-key-secret "$ALIYUN_ACCESS_KEY_SECRET"
        fi
    else
        _log $LOG_LEVEL_INFO "$me_log" "Using existing Aliyun CLI profile: $ALIYUN_PROFILE"
    fi
    # 检查配置是否成功
    if ! aliyun sts GetCallerIdentity --profile "$ALIYUN_PROFILE"; then
        _log $LOG_LEVEL_ERROR "$me_log" "Failed to authenticate with Aliyun. Please check your credentials."
        exit 1
    fi
}

_upload_file() {
    if [[ -z "${ALIYUN_OSS_BUCKET:-}" ]]; then
        _log $LOG_LEVEL_WARNING "$me_log" "ALIYUN_OSS_BUCKET not set. Skipping file upload."
        return
    fi

    local path="$1"
    local file_enc="${2}.tar.gz.enc"
    local files=("${file_enc}" "${file_enc}.sha256sum")

    for file in "${files[@]}"; do
        case "$VIA_DOMAIN" in
        cdn*)
            _configure_aliyun_cli
            _log $LOG_LEVEL_INFO "$me_log" "Uploading ${file} to OSS bucket oss://${ALIYUN_OSS_BUCKET}/${file}"
            if aliyun oss cp "${path}/${file}" "oss://${ALIYUN_OSS_BUCKET}/${file}" --profile "$ALIYUN_PROFILE"; then
                _log $LOG_LEVEL_SUCCESS "$me_log" "Upload successful ${file} to OSS bucket oss://${ALIYUN_OSS_BUCKET}/${file}"
            else
                _log $LOG_LEVEL_ERROR "$me_log" "Failed to upload ${file} to OSS bucket oss://${ALIYUN_OSS_BUCKET}/${file}"
                return 1
            fi
            ;;
        api*)
            _log $LOG_LEVEL_INFO "$me_log" "upload to ${HOSTS[0]}:$HOME/docker/html/${file}"
            if [[ "${HOSTS[0]}" == "localhost" ]]; then
                cp "${path}/${file}" "$HOME/docker/html/${file}"
                _log $LOG_LEVEL_SUCCESS "$me_log" "Upload successful ${file} to localhost:$HOME/docker/html/${file}"
            else
                if scp "${path}/${file}" "${HOSTS[0]}:$HOME/docker/html/${file}"; then
                    _log $LOG_LEVEL_SUCCESS "$me_log" "Upload successful ${file} to ${HOSTS[0]}:$HOME/docker/html/${file}"
                else
                    _log $LOG_LEVEL_ERROR "$me_log" "Failed to upload ${file} to ${HOSTS[0]}:$HOME/docker/html/${file}"
                    return 1
                fi
            fi
            ;;
        *)
            _log $LOG_LEVEL_ERROR "$me_log" "Unsupported domain: $VIA_DOMAIN"
            return 1
            ;;
        esac
    done
}

_notify_wechat_work() {
    local path="$1"
    local file="${2}.tar.gz"
    local sleep_time="$3"
    local file_enc="${file}.enc"
    local download_url="https://${VIA_DOMAIN:-cdn.example.com}/${file_enc}"
    local decryption_instructions

    # 根据加密方法设置解密指令
    if _check_commands gpg; then
        decryption_instructions="${g_gpg_opt[*]} --decrypt ${file_enc} > $file"
    elif _check_commands openssl; then
        decryption_instructions="${g_openssl_opt[*]} -d -in ${file_enc} -out $file"
    else
        _log $LOG_LEVEL_ERROR "$me_log" "Unsupported encryption method."
        return 1
    fi

    # 构建备份内容列表
    local backup_contents=""
    if [[ -n "$MYSQL_HOST" && -n "$MYSQL_USER" && -n "$MYSQL_PASSWORD" && -n "${MYSQL_DBS[*]}" ]]; then
        backup_contents+=$'\n- MySQL 数据库 ('"${MYSQL_DBS[*]}"')'
    fi
    if [[ -n "$REDIS_HOST" && -n "$REDIS_PORT" && -n "${REDIS_DB_NUMBERS[*]}" ]]; then
        backup_contents+=$'\n- Redis 数据库 ('"${REDIS_DB_NUMBERS[*]}"')'
    fi
    for host in "${HOSTS[@]}"; do
        for path in "${PATHS[@]}"; do
            backup_contents+=$'\n  - '"$host:$path"
        done
    done

    local msg_body
    msg_body="
## 下载 $(date +%F_%T) 链接过期时间: ${sleep_time}
  curl -fLO ${download_url}
## 校验
  curl -fL ${download_url}.sha256sum | sha256sum -c
## 解密
  ${decryption_instructions}
## 解压
  tar -xzf ${file}
## 内容：${backup_contents}
"

    echo "$msg_body" | tee -a "$me_log"

    if [[ -z "${WECHAT_KEY:-}" ]]; then
        _log $LOG_LEVEL_WARNING "$me_log" "WECHAT_KEY not provided, WeChat notification skipped."
        return
    fi

    # Notify to weixin_work 企业微信
    local wechat_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$WECHAT_KEY"
    local response
    response=$(curl -fsS -X POST -H 'Content-Type: application/json' \
        -d '{"msgtype": "text", "text": {"content": "'"$msg_body"'"}}' "$wechat_api") || {
        _log $LOG_LEVEL_ERROR "$me_log" "Failed to send WeChat notification. Check your network connection."
        return 1
    }
    if ! echo "$response" | grep -q 'errcode.*0'; then
        _log $LOG_LEVEL_ERROR "$me_log" "Error: Failed to send WeChat notification. Response: $response"
        return 1
    fi
}

_refresh_cdn() {
    [[ "${VIA_DOMAIN:-}" != cdn.* ]] && return
    _check_commands aliyun || return 1
    _configure_aliyun_cli

    local path="$1"
    local file="${2}.tar.gz.enc"
    local sleep_time="$3"
    local bucket_path="oss://${ALIYUN_OSS_BUCKET:-cdn.example.com}/${file}"
    local url="https://${VIA_DOMAIN:-cdn.example.com}/${file}"

    _log $LOG_LEVEL_INFO "$me_log" "Waiting $sleep_time before refreshing CDN cache..."
    sleep "$sleep_time"
    _log $LOG_LEVEL_INFO "$me_log" "aliyun cdn RefreshObjectCaches --region $ALIYUN_REGION --ObjectType File --ObjectPath $url"
    ## remove object from oss
    aliyun oss rm "$bucket_path" -f -r --all-versions ||
        _log $LOG_LEVEL_WARNING "$me_log" "Warning: Failed to remove $bucket_path"
    ## refresh cdn cache
    aliyun cdn RefreshObjectCaches --region "$ALIYUN_REGION" --ObjectType File --ObjectPath "$url" ||
        _log $LOG_LEVEL_WARNING "$me_log" "Warning: Failed to refresh CDN cache $url"
}

_securely_remove_files() {
    if [[ -z "${VIA_DOMAIN:-}" || "${VIA_DOMAIN:-}" != cdn.* ]]; then
        _log $LOG_LEVEL_WARNING "$me_log" "VIA_DOMAIN not set. Skipping secure removal."
        return
    fi

    local path="$1"
    local timestamp="$2"
    local file="${timestamp}.tar.gz"

    # Check if shred is available
    if ! command -v shred &>/dev/null; then
        _log $LOG_LEVEL_WARNING "$me_log" "shred command not found. Using rm instead."
        local remove_cmd="rm -f"
    else
        local remove_cmd="shred -u"
    fi

    # Remove files in the path
    _log $LOG_LEVEL_INFO "$me_log" "Securely removing sensitive files in $path/${timestamp}"
    if [[ -d "$path/${timestamp:?}" ]]; then
        find "$path/${timestamp:?}" -type f -print0 | xargs -0 $remove_cmd
        rm -rf "${path:?}/${timestamp:?}"
    fi
    _log $LOG_LEVEL_INFO "$me_log" "Securely removing sensitive files in $path/${file}"
    $remove_cmd "${path:?}/$file"*
}

main() {
    set -eo pipefail

    # 定义日志级别常量
    readonly LOG_LEVEL_ERROR=0
    readonly LOG_LEVEL_WARNING=1
    readonly LOG_LEVEL_INFO=2
    readonly LOG_LEVEL_SUCCESS=3

    # 定义颜色代码
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_YELLOW='\033[0;33m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_RESET='\033[0m'

    # 初始化 CURRENT_LOG_LEVEL
    CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO

    local me_name
    local me_path
    local me_env
    local me_log
    local timestamp

    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_env="${me_path}/${me_name}.env"
    me_log="${me_path}/${me_name}.log"

    # 设置日期格式
    timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p "${me_path}/${timestamp}"

    _log $LOG_LEVEL_INFO "$me_log" "Backup start"

    # Load configuration
    _load_config "$me_env" "$@"

    ## 检查必要的命令
    _check_commands openssl curl tar gzip || return 1

    ## 检查磁盘空间
    _check_disk_space || return 1

    # 备份Redis数据库
    _dump_redis "${me_path}" "$timestamp"

    # 备份MySQL数据库
    _dump_mysql "${me_path}" "$timestamp"

    # 备份服务器文件目录
    _backup_directories "${me_path}" "${timestamp}"

    ## 打包压缩文件
    _compress_file "$me_path" "${timestamp}"

    # 加密压缩文件, 生成sha256sum
    pass_rand=$(openssl rand -base64 32 | tr -d '=' | tr '+-/' '_')
    g_openssl_opt=(openssl aes-256-cbc -salt -pbkdf2 -iter 10000 -k "$pass_rand")
    g_gpg_opt=(gpg --batch --yes --cipher-algo AES256 --passphrase "$pass_rand")
    _encrypt_file "$me_path" "${timestamp}"

    # 上传文件
    _upload_file "${me_path}" "${timestamp}"

    # 通知
    _notify_wechat_work "${me_path}" "${timestamp}" 1h

    # 刷新CDN
    _refresh_cdn "${me_path}" "${timestamp}" 2h &

    # 删除文件
    _securely_remove_files "$me_path" "${timestamp}"

    _log $LOG_LEVEL_SUCCESS "$me_log" "Backup completed."
}

# while true; do [[ $(date +%H%M) == 0858 ]] && bash y.sh; sleep 30; done
main "$@"
