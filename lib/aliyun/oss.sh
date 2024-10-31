#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=SC2016

# OSS (对象存储服务) 相关函数

show_oss_help() {
    echo "OSS (对象存储服务) 操作："
    echo "  list   [region]             - 列出 OSS 存储桶"
    echo "  create <存储桶名称> [region] - 创建 OSS 存储桶"
    echo "  delete <存储桶名称> [region] - 删除 OSS 存储桶"
    echo "  bind-domain <存储桶名称> <域名> - 为存储桶绑定自定义域名"
    echo "  upload-cert <证书名称> <证书文件> <私钥文件> [region] - 上传SSL证书"
    echo "  delete-cert <证书ID> [region] - 删除SSL证书"
    echo "  deploy-cert <存储桶名称> <域名> <证书ID> [region] - 部署证书到OSS域名"
    echo "  batch-copy [-in | --internal] <源存储桶/路径> <目标存储桶/路径> [包含文件类型列表的文件] [存储类型] - 批量复制对象并设置存储类型"
    echo "  batch-delete [-in | --internal] <存储桶/路径> [包含文件类型列表的文件] [存储类型] - 批量删除指定存储类型的对象"
    echo "  logs <存储桶路径> [选项...]    - 查询存储桶访问日志"
    echo "    选项："
    echo "      -s, --start-date DATE    开始日期 (YYYY-MM-DD)"
    echo "      -e, --end-date DATE      结束日期 (YYYY-MM-DD)"
    echo "      -f, --format FORMAT      输出格式 (human/json/tsv)"
    echo "      -d, --domain DOMAIN      指定要查询的域名"
    echo "      --status CODE           分析指定HTTP状态码的记录(如: 404,500,403)"
    echo "      --file-types TYPES       指定要分析的文件类型（用逗号分隔，如：jpg,png,pdf）"
    echo
    echo "选项："
    echo "  -in | --internal    使用内网 endpoint 进行操作（仅在阿里云 ECS 等内网环境中使用）"
    echo
    echo "示例："
    echo "  $0 oss list"
    echo "  $0 oss create my-bucket"
    echo "  $0 oss delete my-bucket"
    echo "  $0 oss bind-domain my-bucket example.com"
    echo "  $0 oss upload-cert my-cert path/to/cert.pem path/to/key.pem"
    echo "  $0 oss delete-cert cert-1234567890abcdef"
    echo "  $0 oss deploy-cert my-bucket example.com cert-1234567890abcdef"
    echo "  $0 oss batch-copy flynew/e/ flyh5/e/                    # 使用默认文件类型列表和IA存储类型"
    echo "  $0 oss batch-copy flynew/e/ flyh5/e/ file-list.txt IA   # 使用自定义文件类型列表"
    echo "  $0 oss batch-delete flyh5/e/                           # 使用默认文件类型列表和IA存储类型"
    echo "  $0 oss batch-delete flyh5/e/ file-list.txt IA          # 使用自定义文件类型列表"
    echo "  $0 oss batch-copy -in flynew/e/ flyh5/e/                 # 使用内网进行复制"
    echo "  $0 oss batch-delete -in flyh5/e/                        # 使用内网进行删除"
    echo "  $0 oss logs my-bucket/cdn_log/"
    echo "  $0 oss logs my-bucket/cdn_log/ -s 2024-03-01 -e 2024-03-10 -f json"
    echo "  $0 oss logs my-bucket/cdn_log/ --start-date 2024-03-01 --404"
    echo "  $0 oss logs my-bucket/cdn_log/ --404 --file-types jpg,png,pdf  # 只分析图片和PDF文件的404记录"
    echo "  $0 oss logs my-bucket/cdn_log/ --domain flyh5.cn --404  # 分析指定域名的404记录"
    echo "  $0 oss logs my-bucket/cdn_log/ --status 404,500  # 分析404和500错误记录"
    echo "  $0 oss logs my-bucket/cdn_log/ --status 404 --file-types jpg,png,pdf  # 只分析图片和PDF文件的404记录"
    echo "  $0 oss logs my-bucket/cdn_log/ --domain flyh5.cn --status 404  # 分析指定域名的404记录"
}

handle_oss_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) oss_list "$@" ;;
    create) oss_create "$@" ;;
    delete) oss_delete "$@" ;;
    bind-domain) oss_bind_domain "$@" ;;
    upload-cert) oss_upload_cert "$@" ;;
    delete-cert) oss_delete_cert "$@" ;;
    deploy-cert) oss_deploy_cert "$@" ;;
    batch-copy) oss_batch_copy "$@" ;;
    batch-delete) oss_batch_delete "$@" ;;
    logs) handle_oss_logs_commands "$@" ;;
    *)
        echo "错误：未知的 OSS 操作：$operation" >&2
        show_oss_help
        exit 1
        ;;
    esac
}

# 添加新的函数处理日志相关命令
handle_oss_logs_commands() {
    local bucket_path=""
    local start_date=""
    local end_date=""
    local format="human"
    local status_codes=""
    local file_types=""
    local domain=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -s | --start-date)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--start-date 选项需要指定日期" >&2
                return 1
            fi
            start_date="$2"
            shift
            ;;
        -e | --end-date)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--end-date 选项需要指定日期" >&2
                return 1
            fi
            end_date="$2"
            shift
            ;;
        -f | --format)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--format 选项需要指定格式(human/json/tsv)" >&2
                return 1
            fi
            format="$2"
            shift
            ;;
        --status)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--status 选项需要指定HTTP状态码（用逗号分隔）" >&2
                return 1
            fi
            status_codes="$2"
            shift
            ;;
        -t | --file-types)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--file-types 选项需要指定文件类型列表（用逗号分隔）" >&2
                return 1
            fi
            file_types="$2"
            shift
            ;;
        -d | --domain)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "错误：--domain 选项需要指定域名" >&2
                return 1
            fi
            domain="$2"
            shift
            ;;
        -*)
            echo "错误：未知的选项：$1" >&2
            return 1
            ;;
        *)
            if [ -z "$bucket_path" ]; then
                bucket_path="$1"
            else
                echo "错误：多余的参数：$1" >&2
                return 1
            fi
            ;;
        esac
        shift
    done

    # 检查必需参数
    if [ -z "$bucket_path" ]; then
        echo "错误：请指定存储桶路径" >&2
        echo "用法：$0 oss logs <存储桶路径> [选项...]" >&2
        echo "选项："
        echo "  -s, --start-date DATE    开始日期 (YYYY-MM-DD)"
        echo "  -e, --end-date DATE      结束日期 (YYYY-MM-DD)"
        echo "  -f, --format FORMAT      输出格式 (human/json/tsv)"
        echo "  -d, --domain DOMAIN      指定要查询的域名"
        echo "  --status CODE           分析指定HTTP状态码的记录(如: 404,500,403)"
        echo "  --file-types TYPES       指定要分析的文件类型（用逗号分隔，如：jpg,png,pdf）"
        echo
        echo "示例："
        echo "  $0 oss logs my-bucket/cdn_log/"
        echo "  $0 oss logs my-bucket/cdn_log/ -s 2024-03-01 -e 2024-03-10 -f json"
        echo "  $0 oss logs my-bucket/cdn_log/ --status 404,500  # 分析404和500错误记录"
        echo "  $0 oss logs my-bucket/cdn_log/ --status 404 --file-types jpg,png,pdf  # 只分析图片和PDF文件的404记录"
        echo "  $0 oss logs my-bucket/cdn_log/ --domain flyh5.cn --status 404  # 分析指定域名的404记录"
        return 1
    fi

    # 设置默认日期为今天
    start_date=${start_date:-$("$CMD_DATE" +%Y-%m-%d)}
    end_date=${end_date:-$start_date}

    # 调用日志查询函数
    oss_get_logs "$bucket_path" "$start_date" "$end_date" "$format" "$status_codes" "$file_types" "$domain"
}

oss_list() {
    local format=${1:-human}
    local result
    result=$(aliyun --profile "${profile:-}" oss ls --region "${region:-}")

    case "$format" in
    json)
        ## - aliyun的oss list 输出格式不是json格式，**此处不要变更**
        if [ -n "$result" ]; then
            echo "$result" | awk -F/ '/oss:/ {print $NF}' | jq -R -s 'split("\n") | map(select(length > 0)) | map({BucketName: .})'
        else
            echo "[]"
        fi
        ;;
    tsv)
        echo -e "BucketName"
        if [ -n "$result" ]; then
            echo "$result" | awk -F/ '/oss:/ {print $NF}'
        fi
        ;;
    human | *)
        echo "列出 OSS 存储桶："
        if echo "$result" | $CMD_GREP -q 'Bucket Number.*0'; then
            echo "没有找到 OSS 存储桶。"
        else
            echo "存储桶名称"
            echo "----------------"
            echo "$result" | awk -F/ '/oss:/ {print $NF}'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "oss" "list" "$result" "$format"
}

oss_create() {
    local bucket_name=$1
    echo "创建 OSS 存储桶："
    local result
    result=$(aliyun --profile "${profile:-}" oss mb "oss://$bucket_name" --region "$region")
    echo "$result"
    log_result "$profile" "$region" "oss" "create" "$result"
}

oss_delete() {
    local bucket_name=$1
    echo "警告：您即将删除 OSS 存储桶：$bucket_name"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 OSS 存储桶："

    # 首先检查存储桶是否存在
    if ! aliyun --profile "${profile:-}" oss ls "oss://$bucket_name" --region "$region" &>/dev/null; then
        echo "错误：存储桶 $bucket_name 不存在。"
        return 1
    fi

    # 先删除存储桶中的所有对象
    echo "正在删除存储桶中的所有对象..."
    local delete_objects_result
    delete_objects_result=$(aliyun --profile "${profile:-}" oss rm "oss://$bucket_name" --region "$region" --recursive --force)
    local delete_objects_status=$?

    if [ $delete_objects_status -ne 0 ]; then
        echo "错误：删除存储桶中的对象失败。"
        echo "$delete_objects_result"
        return 1
    fi

    # 删除存储桶本身
    echo "正在删除存储桶..."
    local delete_bucket_result
    delete_bucket_result=$(aliyun --profile "${profile:-}" oss rm "oss://$bucket_name" --region "$region" --bucket --force)
    local delete_bucket_status=$?

    if [ $delete_bucket_status -eq 0 ]; then
        echo "OSS 存储桶删除成功。"
        log_delete_operation "$profile" "$region" "oss" "$bucket_name" "$bucket_name" "成功"
    else
        echo "错误：存储桶删除失败。"
        echo "$delete_bucket_result"
        log_delete_operation "$profile" "$region" "oss" "$bucket_name" "$bucket_name" "失败"
        return 1
    fi

    # 验证存储桶是否真的被删除
    sleep 5 # 增加等待时间，因为删除操作可能需要更长时间生效
    local max_retries=3
    local retry=0
    local deleted=false

    while [ $retry -lt $max_retries ]; do
        if ! aliyun --profile "${profile:-}" oss ls "oss://$bucket_name" --region "$region" &>/dev/null; then
            deleted=true
            break
        fi
        echo "等待删除操作生效..."
        sleep 5
        ((retry++))
    done

    if [ "$deleted" = false ]; then
        echo "错误：存储桶删除验证失败，存储桶似乎仍然存在。"
        return 1
    fi

    log_result "$profile" "$region" "oss" "delete" "$delete_bucket_result"
}

get_cname_token() {
    local bucket_name=$1
    local domain=$2
    echo "获取 CNAME 令牌："
    local result
    result=$(aliyun --profile "${profile:-}" oss bucket-cname --method get --item token oss://"$bucket_name" "$domain" --region "$region")
    echo "$result"
    local token
    token=$(echo "$result" | "${CMD_GREP}" -oP '(?<=<Token>)[^<]+')
    echo "成功获取 CNAME 令牌：$token"

    echo "请在您的 DNS 服务商处添加以下 TXT 记录："
    echo "记录名：$domain"
    echo "记录值：$token"
    echo "请在添加 TXT 记录后按回车键继续..."
    read -r
}

oss_bind_domain() {
    local bucket_name=$1
    local domain=$2
    echo "为 OSS 存储桶绑定自定义域名："

    # 绑定域名
    echo "正在绑定域名..."
    local result
    result=$(aliyun --profile "${profile:-}" oss bucket-cname --method put --item token "oss://${bucket_name}" "${domain}" --region "$region")

    echo "绑定域名响应："
    echo "$result"
    log_result "$profile" "$region" "oss" "bind-domain" "$result"

    local token
    token=$(echo "$result" | "${CMD_GREP}" -oP '(?<=<Token>)[^<]+')
    if [ -z "$token" ]; then
        echo "错误：无法获取 CNAME 令牌。响应内容：" >&2
        echo "$result" >&2
        return 1
    fi

    echo "成功获取 CNAME 令牌：$token"

    echo "正在自动添加 TXT 记录..."
    set -x
    dns_create "${domain#*.}" "${domain%%.*}" "TXT" "$token"

    echo "请等待 DNS 记录生效，这可能需要几分钟时间..."
    echo "生效后，请按回车键继续..."
    local max_wait_time=600 # 10 minutes in seconds
    local start_time
    start_time=$("$CMD_DATE" +%s)
    local current_time
    local elapsed_time

    while true; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $max_wait_time ]; then
            echo "已等待10分钟，DNS记录可能未生效。请手动验证并重试。"
            return 1
        fi

        echo "正在检查DNS记录..."
        local dig_result
        dig_result=$(dig +short TXT "$domain")

        if [ "$dig_result" = "\"$token\"" ]; then
            echo "DNS记录已生效！"
            break
        else
            echo "DNS记录尚未生效，等待15秒后重试..."
            sleep 15
        fi
    done

    read -r

    # 验证域名所有权
    echo "验证域名所有权..."
    local verify_result
    verify_result=$(aliyun --profile "${profile:-}" oss bucket-cname --method put --item cname "oss://${bucket_name}" "${domain}" --region "$region")
    echo "验证结果："
    echo "$verify_result"
    log_result "$profile" "$region" "oss" "verify-domain" "$verify_result"

    if echo "$verify_result" | $CMD_GREP -q "<Code>NoSuchCnameInDns</Code>"; then
        echo "错误：DNS 验证失败。请确保 TXT 记录已经生效，然后重试。" >&2
        return 1
    fi

    echo "域名绑定和验证完成。"
}

generate_oss_signature() {
    local method=$1
    local bucket=$2
    local resource=$3
    local access_key_id=$4
    local access_key_secret=$5
    local date
    date=$("${CMD_DATE}" -u "+%Y-%m-%dT%H:%M:%SZ")
    local host="${bucket}.oss-${region}.aliyuncs.com"

    # Construct the canonical request
    local canonical_headers="content-type:${content_type}\nhost:${host}\nx-oss-date:${date}\n"
    local signed_headers="content-type;host;x-oss-date"
    local canonical_resource="/${bucket}${resource}"
    local canonical_request="${method}\n${canonical_resource}\n\n${canonical_headers}\n${signed_headers}\n"

    # Calculate the hash of the canonical request
    local hashed_canonical_request
    hashed_canonical_request=$(echo -n "$canonical_request" | openssl dgst -sha256 -hex | "$CMD_SED" 's/^.* //')

    # Construct the string to sign
    local string_to_sign="OSS4-HMAC-SHA256\n${date}\n${hashed_canonical_request}"

    echo "Debug: String to sign: $string_to_sign" >&2

    # Generate the signature
    local signature
    signature=$(echo -n "$string_to_sign" | openssl dgst -sha256 -hmac "$access_key_secret" -binary | base64)

    echo "Debug: Generated signature: $signature" >&2
    echo "$signature"
}

oss_upload_cert() {
    local cert_name=$1
    local cert_file=$2
    local key_file=$3
    echo "上传 SSL 证书："
    local result
    result=$(aliyun --profile "${profile:-}" cas UploadUserCertificate --Name "$cert_name" --Cert "$(cat "$cert_file")" --Key "$(cat "$key_file")" --region "$region")
    echo "$result"
    log_result "$profile" "$region" "oss" "upload-cert" "$result"
}

oss_delete_cert() {
    local cert_id=$1
    echo "删除 SSL 证书："
    local result
    result=$(aliyun --profile "${profile:-}" cas DeleteUserCertificate --CertId "$cert_id" --region "$region")
    echo "$result"
    log_result "$profile" "$region" "oss" "delete-cert" "$result"
}

oss_deploy_cert() {
    local bucket_name=$1
    local domain=$2
    local cert_id=$3
    echo "部署证书到 OSS 域名："
    local result
    result=$(aliyun --profile "${profile:-}" oss SetBucketCertificate --bucket "$bucket_name" --domain "$domain" --certId "$cert_id" --region "$region")
    echo "$result"
    log_result "$profile" "$region" "oss" "deploy-cert" "$result"
}

verify_domain_ownership() {
    local bucket_name=$1
    local domain=$2
    local token=$3
    echo "验证域名所有权："
    local result
    result=$(aliyun --profile "${profile:-}" oss PutCnameToken --bucket "$bucket_name" --domain "$domain" --token "$token" --region "$region")
    echo "$result"
}

# 添加一个新的函数用于生成大件类型列表
generate_large_files_list() {
    local temp_file
    temp_file=$(mktemp)

    # 常见的大文件类型
    for ext in mp3 mp4 avi mov wmv flv mkv webm jpg jpeg png gif bmp tiff webp psd ai zip rar 7z tar gz iso dmg pdf doc docx ppt pptx xls xlsx; do
        echo "*.$ext"
        echo "*.${ext^^}"
    done >"$temp_file"

    echo "$temp_file"
}

# 修改 oss_batch_copy 函数，添加内网支持
oss_batch_copy() {
    local use_internal=false
    local source=""
    local dest=""
    local file_list=""
    local storage_class="IA"
    local endpoint_url

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -in | --internal)
            use_internal=true
            ;;
        *)
            if [ -z "$source" ]; then
                source=$1
            elif [ -z "$dest" ]; then
                dest=$1
            elif [ -z "$file_list" ]; then
                file_list=$1
            else
                storage_class=$1
            fi
            ;;
        esac
        shift
    done

    if [ -z "$source" ] || [ -z "$dest" ]; then
        echo "错误：缺少必要参数" >&2
        echo "用法：$0 oss batch-copy [-in | --internal] <源存储桶/路径> <目标存储桶/路径> [包含文件列表的文件] [存储类型]" >&2
        return 1
    fi

    # 根据是否使用内网设置 endpoint
    if [ "$use_internal" = true ]; then
        endpoint_url="http://oss-${region:-cn-hangzhou}-internal.aliyuncs.com"
        echo "使用内网 endpoint: $endpoint_url"
    else
        endpoint_url="http://oss-${region:-cn-hangzhou}.aliyuncs.com"
    fi

    # 如果没有提供文件列表，则自动生成
    if [ -z "$file_list" ]; then
        echo "未指定文件类型列表，将自动生成包含常见大文件类型的列表..."
        temp_list_file=$(generate_large_files_list)
        file_list="$temp_list_file"
        echo "已生成临时文件类型列表：$file_list"
    elif [ ! -f "$file_list" ]; then
        echo "错误：指定的文件列表文件不存在：$file_list" >&2
        return 1
    fi

    echo "开始批量复制对象："
    echo "源路径： oss://$source"
    echo "目标路径： oss://$dest"
    echo "文件类型列表：$file_list"
    echo "存储类型：$storage_class"

    # 显示将要处理的文件类型
    echo "将要处理的文件类型："
    tr '\n' ' ' <"$file_list"
    echo

    local result
    result=$(ossutil --profile "${profile:-}" \
        --endpoint "$endpoint_url" \
        cp "oss://$source" "oss://$dest" \
        -r -f --update \
        --include-from "$file_list" \
        --metadata-include "x-oss-storage-class=$storage_class" \
        --storage-class "$storage_class")

    local status=$?
    echo "$result"

    # 如果使用了临时文件，则删除它
    if [ -n "$temp_list_file" ]; then
        rm -f "$temp_list_file"
    fi

    if [ $status -eq 0 ]; then
        echo "批量复制操作完成"
        log_result "$profile" "$region" "oss" "batch-copy" "成功：$result"
    else
        echo "批量复制操作失败"
        log_result "$profile" "$region" "oss" "batch-copy" "失败：$result"
        return 1
    fi
}

# 修改 oss_batch_delete 函数，添加内网支持
oss_batch_delete() {
    local use_internal=false
    local bucket_path=""
    local file_list=""
    local storage_class="IA"
    local endpoint_url
    local temp_list_file=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -in | --internal)
            use_internal=true
            ;;
        *)
            if [ -z "$bucket_path" ]; then
                bucket_path=$1
            elif [ -z "$file_list" ]; then
                file_list=$1
            else
                storage_class=$1
            fi
            ;;
        esac
        shift
    done

    if [ -z "$bucket_path" ]; then
        echo "错误：缺少必要参数" >&2
        echo "用法：$0 oss batch-delete [-in | --internal] <存储桶/路径> [包含文件列表的文件] [存储类型]" >&2
        return 1
    fi

    # 根据是否使用内网设置 endpoint
    if [ "$use_internal" = true ]; then
        endpoint_url="http://oss-${region:-cn-hangzhou}-internal.aliyuncs.com"
        echo "使用内网 endpoint: $endpoint_url"
    else
        endpoint_url="http://oss-${region:-cn-hangzhou}.aliyuncs.com"
    fi

    # 如果没有提供文件列表，则自动生成
    if [ -z "$file_list" ]; then
        echo "未指定文件类型列表，将自动生成包含常见大文件类型的列表..."
        temp_list_file=$(generate_large_files_list)
        file_list="$temp_list_file"
        echo "已生成临时文件类型列表：$file_list"
    elif [ ! -f "$file_list" ]; then
        echo "错误：指定的文件列表文件不存在：$file_list" >&2
        return 1
    fi

    echo "警告：您即将批量删除以下内容："
    echo "存储桶/路径：$bucket_path"
    echo "文件类型列表：$file_list"
    echo "存储类型：$storage_class"

    echo "将要处理的文件类型："
    tr '\n' ' ' <"$file_list"
    echo

    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        [ -n "$temp_list_file" ] && rm -f "$temp_list_file"
        return 1
    fi

    local result
    result=$(ossutil --profile "${profile:-}" \
        --endpoint "$endpoint_url" \
        rm "oss://$bucket_path" \
        --all-versions -r -f \
        --include-from "$file_list" \
        --metadata-include "x-oss-storage-class=$storage_class")

    local status=$?
    echo "$result"

    # 如果使用了临时文件，则删除它
    if [ -n "$temp_list_file" ]; then
        rm -f "$temp_list_file"
    fi

    if [ $status -eq 0 ]; then
        echo "批量删除操作完成"
        log_result "$profile" "$region" "oss" "batch-delete" "成功：$result"
    else
        echo "批量删除操作失败"
        log_result "$profile" "$region" "oss" "batch-delete" "失败：$result"
        return 1
    fi
}

# 添加一个新的函数用于生成日期列表
generate_date_list() {
    local start_date=$1
    local end_date=$2
    local temp_file
    temp_file=$(mktemp)

    # 生成日期序列
    local current_date=$start_date
    while [ "$("$CMD_DATE" -d "$current_date" +%s)" -le "$("$CMD_DATE" -d "$end_date" +%s)" ]; do
        # 添加两种日期格式的匹配模式
        echo "*$("$CMD_DATE" -d "$current_date" +%Y-%m-%d)*"
        echo "*$("$CMD_DATE" -d "$current_date" +%Y_%m_%d)*"
        current_date=$("$CMD_DATE" -d "$current_date +1 day" +%Y-%m-%d)
    done >"$temp_file"

    echo "$temp_file"
}

# 添加新函数用于下载和分析日志文件
analyze_logs_for_status() {
    local bucket_path=$1
    local log_file=$2
    local status_codes=$3
    local file_types=${4:-"mp3,mp4,avi,mov,wmv,flv,mkv,webm,jpg,jpeg,png,gif,bmp,tiff,webp,psd,ai,zip,rar,7z,tar,gz,iso,dmg,pdf,doc,docx,ppt,pptx,xls,xlsx"}
    local temp_dir
    temp_dir=$(mktemp -d)
    local log_filename
    log_filename=$(basename "$log_file")
    local local_gz_file="${temp_dir}/${log_filename}"
    local local_txt_file="${temp_dir}/${log_filename%.gz}"

    # 下载日志文件
    echo "正在下载日志文件: $log_file ..."
    if ! ossutil --profile "${profile:-}" cp "$log_file" "$local_gz_file"; then
        echo "错误：下载日志文件失败: $log_file" >&2
        rm -rf "$temp_dir"
        return 1
    fi

    # 解压日志文件
    echo "正在解压日志文件..."
    if ! gunzip -f "$local_gz_file"; then
        echo "错误：解压日志文件失败: $local_gz_file" >&2
        rm -rf "$temp_dir"
        return 1
    fi

    # 构建文件类型的正则表达式
    local file_types_regex
    file_types_regex=$(echo "$file_types" | tr ',' '|')
    file_types_regex="\.(${file_types_regex})[\"' ]"

    # 构建状态码的grep模式
    local status_pattern
    status_pattern=$(echo "$status_codes" | tr ',' '|')
    status_pattern=" (${status_pattern}) "

    # 定义要排除的文件模式
    local exclude_patterns=(
        'favicon.ico'
        'robots.txt'
        'sitemap.xml'
        '.well-known/'
        'apple-touch-icon'
        'wp-login.php'
        'wp-admin'
        'admin.php'
        'phpinfo.php'
        '.git/'
        '.env'
        '.htaccess'
        'shell.php'
        'config.php'
        'install.php'
        'setup.php'
    )

    # 构建 grep 排除模式
    local exclude_grep=""
    for pattern in "${exclude_patterns[@]}"; do
        exclude_grep="${exclude_grep:+${exclude_grep}|}${pattern}"
    done

    # 分析日志文件中的指定状态码记录
    echo "正在分析HTTP状态码 $status_codes 的记录..."
    local filtered_records
    filtered_records=$(
        "$CMD_GREP" -vE "$exclude_grep" "$local_txt_file" |
            "$CMD_GREP" -E "$status_pattern" |
            "$CMD_GREP" -iE "$file_types_regex" || echo ""
    )
    local count_records
    count_records=$(echo "$filtered_records" | "$CMD_GREP" -c '^' || echo "0")

    if [ "$count_records" -gt 0 ]; then
        echo "发现 $count_records 条指定类型文件的状态码 $status_codes 记录："
        echo "原始日志内容："
        echo "----------------------------------------"
        echo "$filtered_records"
    else
        echo "未发现指定类型文件的状态码 $status_codes 记录"
    fi

    # 清理临时文件
    rm -rf "$temp_dir"
    sleep 30 ## for debug
}

# 修改 oss_get_logs 函数，添加 404 分析功能
oss_get_logs() {
    local bucket_path="${1%/}/"
    local start_date=${2:-$("$CMD_DATE" +%Y-%m-%d)}
    local end_date=${3:-$start_date}
    local format=${4:-human}
    local status_codes=${5:-""}
    local file_types=${6:-""}
    local domain=${7:-""}

    if [ -z "$bucket_path" ]; then
        echo "错误：请指定存储桶路径" >&2
        return 1
    fi

    # 验证日期格式
    if ! "$CMD_DATE" -d "$start_date" >/dev/null 2>&1; then
        echo "错误：开始日期格式无效，请使用 YYYY-MM-DD 格式" >&2
        return 1
    fi

    if ! "$CMD_DATE" -d "$end_date" >/dev/null 2>&1; then
        echo "错误：结束日期格式无效，请使用 YYYY-MM-DD 格式" >&2
        return 1
    fi

    # 生成日期列表文件
    local date_list_file
    date_list_file=$(generate_date_list "$start_date" "$end_date")

    # 使用日期列表文件查询日志
    local result
    result=$(ossutil --profile "${profile:-}" \
        ls "oss://${bucket_path}" \
        -r \
        --include-from "$date_list_file")

    # 如果指定了域名，则过滤指定域名的日志
    if [ -n "$domain" ]; then
        result=$(echo "$result" | "$CMD_GREP" "$domain" || echo "")
    fi

    # 删除临时文件
    rm -f "$date_list_file"

    # 过滤指定日期范围内的日志
    local filtered_result
    filtered_result=$(echo "$result" | "$CMD_AWK" -v start="$start_date" -v end="$end_date" -v cmd_date="$CMD_DATE" '
        function to_epoch(date) {
            cmd = cmd_date " -d \"" date "\" +%s"
            cmd | getline ts
            close(cmd)
            return ts
        }
        BEGIN {
            start_ts = to_epoch(start)
            end_ts = to_epoch(end) + 86400  # 加上一天的秒数以包含结束日期
        }
        /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
            # 提取文件信息
            timestamp = $1 " " $2 " " $3 " " $4
            size = $5
            storage_class = $6
            etag = $7
            path = $8

            # 从文件路径中提取日期
            if (path ~ /[0-9]{4}[-_][0-9]{2}[-_][0-9]{2}/) {
                # 将文件名中的日期格式从 YYYY_MM_DD 或 YYYY-MM-DD 转换为 YYYY-MM-DD
                log_date = gensub(/.*([0-9]{4})[-_]([0-9]{2})[-_]([0-9]{2}).*/, "\\1-\\2-\\3", 1, path)
                log_ts = to_epoch(log_date)
                if (log_ts >= start_ts && log_ts <= end_ts) {
                    printf "%s\t%s\t%s\t%s\t%s\n", timestamp, size, storage_class, etag, path
                }
            }
        }
    ')

    case "$format" in
    json)
        if [ -n "$filtered_result" ]; then
            echo "$filtered_result" | "$CMD_AWK" -F'\t' '{
                print "{"
                print "  \"timestamp\": \"" $1 "\","
                print "  \"size\": \"" $2 "\","
                print "  \"storageClass\": \"" $3 "\","
                print "  \"etag\": \"" $4 "\","
                print "  \"path\": \"" $5 "\""
                print "}"
            }' | jq -s '.'
        else
            echo "[]"
        fi
        ;;
    tsv)
        echo -e "Timestamp\tSize\tStorageClass\tETag\tPath"
        if [ -n "$filtered_result" ]; then
            echo "$filtered_result"
        fi
        ;;
    human | *)
        echo "访问日志查询结果："
        if [ -z "$filtered_result" ]; then
            echo "未找到访问日志。"
        else
            echo "日志文件列表："
            echo "--------------------------------------------------------------------------------"
            echo "时间戳                        大小      存储类型    文件路径"
            echo "--------------------------------------------------------------------------------"
            echo "$filtered_result" | "$CMD_AWK" -F'\t' '{
                printf "%-30s %-10s %-10s %s\n", $1, $2, $3, $5
            }'

            # 如果需要分析 404 记录
            if [ -n "$status_codes" ]; then
                echo
                echo "正在分析状态码 $status_codes 的记录..."
                echo "--------------------------------------------------------------------------------"
                echo "$filtered_result" | while IFS=$'\t' read -r _ _ _ _ path; do
                    echo "分析文件: $path"
                    analyze_logs_for_status "$bucket_path" "$path" "$status_codes" "$file_types"
                    echo "--------------------------------------------------------------------------------"
                done
            fi
        fi
        ;;
    esac

    log_result "${profile:-}" "${region:-}" "oss" "logs" "$filtered_result" "$format"
}
