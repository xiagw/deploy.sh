#!/usr/bin/env bash
# shellcheck disable=2086

_load_config() {
    # 使用更安全的方法来处理可能包含空格的参数值
    while [[ $# -gt 0 ]]; do
        case $1 in
        *.env)
            _log $LOG_LEVEL_INFO "Loading configuration from $1"
            # shellcheck disable=SC1090
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
        --log-level=*) LOG_LEVEL="${1#*=}" ;;
        --debug) DEBUG=true ;;
        *)
            _log $LOG_LEVEL_ERROR "Unknown option: $1"
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
        _log $LOG_LEVEL_WARNING "Invalid log level: $LOG_LEVEL. Using default (INFO)."
        CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
        ;;
    esac

    # Set default encryption method if not specified
    ALIYUN_REGION=${ALIYUN_REGION:-cn-hangzhou}
    ALIYUN_PROFILE=${ALIYUN_PROFILE:-default}

    # Define base required parameters
    required_params=(PATHS)

    # Add OSS_BUCKET to required parameters if VIA_DOMAIN starts with "cdn"
    if [[ -n "${ALIYUN_OSS_BUCKET:-}" ]]; then
        required_params+=(ALIYUN_REGION ALIYUN_ACCESS_KEY_ID ALIYUN_ACCESS_KEY_SECRET)
    fi

    # Check required parameters
    for param in "${required_params[@]}"; do
        if [[ -z "${!param}" ]]; then
            _log $LOG_LEVEL_ERROR "Error: Required parameter $param is missing or empty"
            exit 1
        fi
    done

    # If HOSTS is not specified, use localhost
    if [[ -z "${HOSTS[*]}" ]]; then
        HOSTS=("localhost")
        _log $LOG_LEVEL_WARNING "HOSTS not specified, using localhost"
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
        _log $LOG_LEVEL_INFO "Debug mode enabled"
    fi
}

_dump_redis() {
    if [[ -z "${REDIS_HOST:-}" || -z "${REDIS_PORT:-}" ]]; then
        _log $LOG_LEVEL_WARNING "Redis backup skipped: Redis parameters not provided"
        return
    fi
    _check_commands redis-cli || return 1

    local path="$1/$2/redis"
    local file="$2"
    mkdir -p "$path"

    local backup_file="$path/redis_${file}.rdb"
    _log $LOG_LEVEL_INFO "Backing up Redis to $backup_file"

    if [ -n "$REDIS_PASSWORD" ]; then
        if redis-cli --no-auth-warning -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --rdb "$backup_file"; then
            local result=true
        else
            local result=false
        fi
    else
        if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --rdb "$backup_file"; then
            local result=true
        else
            local result=false
        fi
    fi
    ${result:-false} && _log $LOG_LEVEL_SUCCESS "Redis backup completed successfully"
    ${result:-false} || _log $LOG_LEVEL_ERROR "Error: Redis backup failed"

}

_dump_mysql() {
    if [[ -z "${MYSQL_HOST:-}" || -z "${MYSQL_USER:-}" || -z "${MYSQL_PASSWORD:-}" || -z "${MYSQL_DBS[*]:-}" ]]; then
        _log $LOG_LEVEL_WARNING "MySQL backup skipped: MySQL parameters not provided"
        return
    fi
    # 修复：检查 MYSQL_CREDENTIALS 是否存在
    if [[ ! -f "$MYSQL_CREDENTIALS" ]]; then
        _log $LOG_LEVEL_ERROR "MySQL credentials file not found"
        return 1
    fi

    _check_commands mysqldump || return 1

    local path="$1/$2/mysql"
    local file="$2"
    mkdir -p "$path"

    for db in "${MYSQL_DBS[@]}"; do
        local backup_file="$path/${db}_${file}.sql"
        _log $LOG_LEVEL_INFO "Backing up MySQL database $db to $backup_file"

        if mysqldump --defaults-extra-file="$MYSQL_CREDENTIALS" --single-transaction --quick --lock-tables=false --set-gtid-purged=OFF --triggers --routines --events --databases "$db" --result-file="$backup_file"; then
            _log $LOG_LEVEL_SUCCESS "MySQL database $db backup completed successfully"
        else
            _log $LOG_LEVEL_ERROR "MySQL database $db backup failed"
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
            _log $LOG_LEVEL_INFO "Backing up $host:$dir to $host_path/${path_right}_${file}"

            if [[ $host == "localhost" ]]; then
                tar -C "${path_left}" -czf "${host_path}/${path_right}_${file}" "${path_right}"
                _log $LOG_LEVEL_SUCCESS "Backup successful localhost:$dir to $host_path/${path_right}_${file}"
                continue
            fi

            if ssh -o StrictHostKeyChecking=no "$host" "tar -C ${path_left} -czf - ${path_right}" >"$host_path/${path_right}_${file}"; then
                _log $LOG_LEVEL_SUCCESS "Backup successful $host:$dir to $host_path/${path_right}_${file}"
            else
                _log $LOG_LEVEL_ERROR "Backup failed $host:$dir to $host_path/${path_right}_${file}"
                return 1
            fi
        done
    done
}

_compress_file() {
    local path="$1"
    local file="$2"
    local file_tgz="${file}.tar.gz"

    _log $LOG_LEVEL_INFO "Compressing: tar -czf $path/${file_tgz} $file"
    tar -czf "$path/${file_tgz}" "$file"
}

_encrypt_file() {
    local path="$1"
    local file="${2}.tar.gz"
    local file_enc="${file}.enc"
    local pass_rand

    if _check_commands gpg; then
        pass_rand=$(gpg --gen-random --armor 1 32 | tr -d '=' | tr '+-/' '_')
        g_gpg_opt=(gpg --batch --yes --cipher-algo AES256 --passphrase "$pass_rand")
        _log $LOG_LEVEL_INFO "Encrypting: ${g_gpg_opt[*]} --symmetric ${path}/$file"
        "${g_gpg_opt[@]}" --symmetric "${path}/$file"
        mv "${path}/${file}.gpg" "${path}/$file_enc"
    elif _check_commands openssl; then
        pass_rand=$(openssl rand -base64 32 | tr -d '=' | tr '+-/' '_')
        g_openssl_opt=(openssl aes-256-cbc -salt -pbkdf2 -iter 10000 -k "$pass_rand")
        _log $LOG_LEVEL_INFO "Encrypting: ${g_openssl_opt[*]} -in ${path}/$file -out ${path}/$file_enc"
        "${g_openssl_opt[@]}" -in "${path}/$file" -out "${path}/$file_enc"
    else
        _log $LOG_LEVEL_ERROR "Unsupported encryption method."
        return 1
    fi
    _log $LOG_LEVEL_INFO "Generating sha256sum: sha256sum ${file_enc} > ${file_enc}.sha256sum"
    pushd "$path"
    sha256sum "$file_enc" >"${file_enc}.sha256sum"
    popd
}

_configure_aliyun_cli() {
    _check_commands aliyun || return 1
    if [[ -n "$ALIYUN_ACCESS_KEY_ID" && -n "$ALIYUN_ACCESS_KEY_SECRET" ]]; then
        if ! aliyun sts GetCallerIdentity --profile "$ALIYUN_PROFILE"; then
            _log $LOG_LEVEL_INFO "Configuring Aliyun CLI with profile: $ALIYUN_PROFILE"
            aliyun configure set \
                --profile "$ALIYUN_PROFILE" \
                --mode AK \
                --region "$ALIYUN_REGION" \
                --access-key-id "$ALIYUN_ACCESS_KEY_ID" \
                --access-key-secret "$ALIYUN_ACCESS_KEY_SECRET"
        fi
    else
        _log $LOG_LEVEL_INFO "Using existing Aliyun CLI profile: $ALIYUN_PROFILE"
    fi
    # 检查配置是否成功
    if ! aliyun sts GetCallerIdentity --profile "$ALIYUN_PROFILE"; then
        _log $LOG_LEVEL_ERROR "Failed to authenticate with Aliyun. Please check your credentials."
        return 1
    fi
}

_upload_file() {
    if [[ -z "${ALIYUN_OSS_BUCKET:-}" ]]; then
        _log $LOG_LEVEL_WARNING "ALIYUN_OSS_BUCKET not set. Skipping file upload."
        return
    fi

    local path="$1"
    local file_enc="${2}.tar.gz.enc"
    local files=("${file_enc}" "${file_enc}.sha256sum")

    for file in "${files[@]}"; do
        case "${VIA_DOMAIN:-cdn.example.com}" in
        cdn*)
            _configure_aliyun_cli
            _log $LOG_LEVEL_INFO "Uploading ${file} to OSS bucket oss://${ALIYUN_OSS_BUCKET}/${file}"
            if aliyun oss cp "${path}/${file}" "oss://${ALIYUN_OSS_BUCKET}/${file}" --profile "$ALIYUN_PROFILE"; then
                _log $LOG_LEVEL_SUCCESS "Upload successful ${file} to OSS bucket oss://${ALIYUN_OSS_BUCKET}/${file}"
            else
                _log $LOG_LEVEL_ERROR "Failed to upload ${file} to OSS bucket oss://${ALIYUN_OSS_BUCKET}/${file}"
                return 1
            fi
            ;;
        api*)
            _log $LOG_LEVEL_INFO "upload to ${HOSTS[0]}:$HOME/docker/html/${file}"
            if [[ "${HOSTS[0]}" == "localhost" ]]; then
                cp "${path}/${file}" "$HOME/docker/html/${file}"
                _log $LOG_LEVEL_SUCCESS "Upload successful ${file} to localhost:$HOME/docker/html/${file}"
            else
                if scp "${path}/${file}" "${HOSTS[0]}:$HOME/docker/html/${file}"; then
                    _log $LOG_LEVEL_SUCCESS "Upload successful ${file} to ${HOSTS[0]}:$HOME/docker/html/${file}"
                else
                    _log $LOG_LEVEL_ERROR "Failed to upload ${file} to ${HOSTS[0]}:$HOME/docker/html/${file}"
                    return 1
                fi
            fi
            ;;
        *)
            _log $LOG_LEVEL_ERROR "Unsupported domain: $VIA_DOMAIN"
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
        _log $LOG_LEVEL_ERROR "Unsupported encryption method."
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

    echo "$msg_body" | tee -a "$LOG_FILE"

    if [[ -z "${WECHAT_KEY:-}" ]]; then
        _log $LOG_LEVEL_WARNING "WECHAT_KEY not provided, WeChat notification skipped."
        return
    fi

    # Notify to weixin_work 企业微信
    local wechat_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$WECHAT_KEY"
    local response
    response=$(curl -fsS -X POST -H 'Content-Type: application/json' \
        -d '{"msgtype": "text", "text": {"content": "'"$msg_body"'"}}' "$wechat_api") || {
        _log $LOG_LEVEL_ERROR "Failed to send WeChat notification. Check your network connection."
        return 1
    }
    if ! echo "$response" | grep -q 'errcode.*0'; then
        _log $LOG_LEVEL_ERROR "Error: Failed to send WeChat notification. Response: $response"
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

    _log $LOG_LEVEL_INFO "Waiting $sleep_time before refreshing CDN cache..."
    sleep "$sleep_time"
    _log $LOG_LEVEL_INFO "aliyun cdn RefreshObjectCaches --region $ALIYUN_REGION --ObjectType File --ObjectPath $url"
    ## remove object from oss
    aliyun oss rm "$bucket_path" -f -r --all-versions ||
        _log $LOG_LEVEL_WARNING "Warning: Failed to remove $bucket_path"
    ## refresh cdn cache
    aliyun cdn RefreshObjectCaches --region "$ALIYUN_REGION" --ObjectType File --ObjectPath "$url" ||
        _log $LOG_LEVEL_WARNING "Warning: Failed to refresh CDN cache $url"
}

_securely_remove_files() {
    if [[ -z "${VIA_DOMAIN:-}" || "${VIA_DOMAIN:-}" != cdn.* ]]; then
        _log $LOG_LEVEL_WARNING "VIA_DOMAIN not set. Skipping secure removal."
        return
    fi

    local path="$1"
    local stamp="$2"
    local file="${stamp}.tar.gz"

    # Check if shred is available
    if ! command -v shred &>/dev/null; then
        _log $LOG_LEVEL_WARNING "shred command not found. Using rm instead."
        local remove_cmd="rm -f"
    else
        local remove_cmd="shred -u"
    fi

    # Remove files in the path
    _log $LOG_LEVEL_INFO "Securely removing sensitive files in $path/${stamp}"
    if [[ -d "$path/${stamp:?}" ]]; then
        find "$path/${stamp:?}" -type f -print0 | xargs -0 $remove_cmd
        rm -rf "${path:?}/${stamp:?}"
    fi
    _log $LOG_LEVEL_INFO "Securely removing sensitive files in $path/${file}"
    $remove_cmd "${path:?}/$file"*
}

main() {
    set -eo pipefail

    # 导入通用函数
    # shellcheck disable=SC1091
    source "$(dirname "$0")/../lib/common.sh"

    local me_name
    local me_path
    local me_env
    local me_log
    local timestamp

    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_env="${me_path}/../data/${me_name}.env"
    me_log="${me_path}/../data/${me_name}.log"

    # 初始化 CURRENT_LOG_LEVEL
    export CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
    export LOG_FILE=$me_log

    # 设置日期格式
    timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p "${me_path}/${timestamp}"

    _log $LOG_LEVEL_INFO "Backup start"

    # Load configuration
    [ -f "${me_env}" ] || cp "${me_path}/../conf/${me_name}.env" "${me_env}"
    _load_config "$me_env" "$@"

    ## 检查必要的命令
    _check_commands openssl curl tar gzip || return 1

    ## 检查磁盘空间
    _check_disk_space 5 || return 1

    # 备份Redis数据库
    _dump_redis "${me_path}" "$timestamp"

    # 备份MySQL数据库
    _dump_mysql "${me_path}" "$timestamp"

    # 备份服务器文件目录
    _backup_directories "${me_path}" "${timestamp}"

    ## 打包压缩文件
    _compress_file "$me_path" "${timestamp}"

    # 加密压缩文件, 生成sha256sum
    _encrypt_file "$me_path" "${timestamp}"

    # 上传文件
    _upload_file "${me_path}" "${timestamp}"

    # 通知
    sleep=2h
    _notify_wechat_work "${me_path}" "${timestamp}" $sleep

    # 刷新CDN
    _refresh_cdn "${me_path}" "${timestamp}" $sleep &

    # 删除文件
    _securely_remove_files "$me_path" "${timestamp}"

    _log $LOG_LEVEL_SUCCESS "Backup completed."
}

# while true; do [[ $(date +%H%M) == 0858 ]] && bash y.sh; sleep 30; done
main "$@"
