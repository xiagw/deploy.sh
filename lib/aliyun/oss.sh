#!/usr/bin/env bash
# -*- coding: utf-8 -*-

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
    echo
    echo "示例："
    echo "  $0 oss list"
    echo "  $0 oss create my-bucket"
    echo "  $0 oss delete my-bucket"
    echo "  $0 oss bind-domain my-bucket example.com"
    echo "  $0 oss upload-cert my-cert path/to/cert.pem path/to/key.pem"
    echo "  $0 oss delete-cert cert-1234567890abcdef"
    echo "  $0 oss deploy-cert my-bucket example.com cert-1234567890abcdef"
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
    *)
        echo "错误：未知的 OSS 操作：$operation" >&2
        show_oss_help
        exit 1
        ;;
    esac
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
    sleep 5  # 增加等待时间，因为删除操作可能需要更长时间生效
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
    result=$(aliyun --profile "${profile:-}" oss bucket-cname --method get --item token  oss://"$bucket_name" "$domain" --region "$region")
    echo "$result"
    local token=$(echo "$result" | $CMD_GREP -oP '(?<=<Token>)[^<]+')
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

    # 使用 grep 和 sed 来解析 XML 并提取 Token
    local token=$(echo "$result" | $CMD_GREP -oP '(?<=<Token>)[^<]+')
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
    local max_wait_time=600  # 10 minutes in seconds
    local start_time=$(date +%s)
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
        local dig_result=$(dig +short TXT "$domain")

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
    local date=$($CMD_DATE -u "+%Y-%m-%dT%H:%M:%SZ")
    local host="${bucket}.oss-${region}.aliyuncs.com"

    # Construct the canonical request
    local canonical_headers="content-type:${content_type}\nhost:${host}\nx-oss-date:${date}\n"
    local signed_headers="content-type;host;x-oss-date"
    local canonical_resource="/${bucket}${resource}"
    local canonical_request="${method}\n${canonical_resource}\n\n${canonical_headers}\n${signed_headers}\n"

    # Calculate the hash of the canonical request
    local hashed_canonical_request=$(echo -n "$canonical_request" | openssl dgst -sha256 -hex | sed 's/^.* //')

    # Construct the string to sign
    local string_to_sign="OSS4-HMAC-SHA256\n${date}\n${hashed_canonical_request}"

    echo "Debug: String to sign: $string_to_sign" >&2

    # Generate the signature
    local signature=$(echo -n "$string_to_sign" | openssl dgst -sha256 -hmac "$access_key_secret" -binary | base64)

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
