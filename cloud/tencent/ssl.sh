#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# SSL (SSL证书) 相关函数

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

show_ssl_help() {
    echo "SSL (SSL证书) 操作："
    echo "  list [format]                           - 列出 SSL 证书"
    echo "  describe <证书ID>                       - 获取证书详细信息"
    echo "  create <域名> [项目ID]                  - 申请 SSL 证书"
    echo "  upload <证书公钥> <私钥> <别名>         - 上传 SSL 证书"
    echo "  delete <证书ID>                         - 删除 SSL 证书"
    echo "  deploy <证书ID> <资源类型> <资源ID>     - 部署 SSL 证书到资源"
    echo "  download <证书ID> <目录>                - 下载 SSL 证书"
    echo "  update-alias <证书ID> <别名>            - 更新证书别名"
    echo
    echo "示例："
    echo "  $0 ssl list"
    echo "  $0 ssl list json"
    echo "  $0 ssl describe cert-123456"
    echo "  $0 ssl create example.com"
    echo "  $0 ssl upload /path/to/cert.crt /path/to/key.key \"我的证书\""
    echo "  $0 ssl delete cert-123456"
    echo "  $0 ssl deploy cert-123456 clb lb-123456"
    echo "  $0 ssl download cert-123456 ./certs/"
    echo "  $0 ssl update-alias cert-123456 \"新别名\""
}

handle_ssl_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) ssl_list "$@" ;;
    describe) ssl_describe "$@" ;;
    create) ssl_create "$@" ;;
    upload) ssl_upload "$@" ;;
    delete) ssl_delete "$@" ;;
    deploy) ssl_deploy "$@" ;;
    download) ssl_download "$@" ;;
    update-alias) ssl_update_alias "$@" ;;
    help) show_ssl_help ;;
    *)
        echo "错误：未知的 SSL 操作：$operation" >&2
        show_ssl_help
        exit 1
        ;;
    esac
}

# SSL 证书列表
ssl_list() {
    local format=${1:-human}
    local result

    result=$(call_tencent_api ssl DescribeCertificates)
    if [ $? -ne 0 ]; then
        echo "错误：无法获取 SSL 证书列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "CertificateId\tAlias\tStatus\tType\tExpireTime"
        echo "$result" | jq -r '.Response.Certificates[]? |
            [
                .CertificateId,
                .Alias,
                .Status,
                .Type,
                .ExpireTime
            ] | @tsv'
        ;;
    human | *)
        echo "列出 SSL 证书："
        local temp_output
        temp_output=$(echo "$result" | jq -r '.Response.Certificates[]? |
            [
                .CertificateId,
                .Alias,
                .Status,
                .Type,
                .ExpireTime
            ] | @tsv')

        local count
        if [ -n "$temp_output" ] && [ "$temp_output" != "null" ] && [ "$temp_output" != "" ]; then
            count=$(echo "$temp_output" | grep -c . || echo "0")
        else
            count="0"
        fi

        if [ "$count" = "0" ] || [ -z "$count" ]; then
            echo "没有找到 SSL 证书。"
        else
            echo -e "CertificateId\t\tAlias\t\tStatus\tType\tExpireTime"
            echo "$temp_output" | awk 'BEGIN {FS="\t"; OFS="\t"} {
                printf "%-25s  %-20s  %-8s  %-8s  %s\n", $1, $2, $3, $4, $5
            }'
        fi
        ;;
    esac

    log_result "${profile:-}" "${region:-}" "ssl" "list" "$result" "$format"
}

# 获取证书详细信息
ssl_describe() {
    local certificate_id=$1

    if [ -z "$certificate_id" ]; then
        echo "错误：需要提供证书ID。" >&2
        echo "用法：$0 ssl describe <证书ID>" >&2
        return 1
    fi

    echo "获取 SSL 证书详细信息：$certificate_id"

    local result
    result=$(call_tencent_api ssl DescribeCertificate --CertificateId "$certificate_id")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ssl" "describe" "$result"
    else
        echo "错误：获取证书信息失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 申请 SSL 证书
ssl_create() {
    local domain=$1
    local project_id=${2:-0}

    if [ -z "$domain" ]; then
        echo "错误：需要提供域名。" >&2
        echo "用法：$0 ssl create <域名> [项目ID]" >&2
        return 1
    fi

    echo "申请 SSL 证书：$domain (项目ID: $project_id)"

    local result
    result=$(call_tencent_api ssl ApplyCertificate --Domains "[\"$domain\"]" --ProjectId "$project_id")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ssl" "create" "$result"
    else
        echo "错误：申请证书失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 上传 SSL 证书
ssl_upload() {
    local certificate_content=$1
    local private_key=$2
    local alias_name=$3

    if [ -z "$certificate_content" ] || [ -z "$private_key" ] || [ -z "$alias_name" ]; then
        echo "错误：需要提供证书公钥、私钥和别名。" >&2
        echo "用法：$0 ssl upload <证书公钥> <私钥> <别名>" >&2
        return 1
    fi

    # 检查文件是否存在
    if [ ! -f "$certificate_content" ]; then
        echo "错误：证书文件不存在：$certificate_content" >&2
        return 1
    fi

    if [ ! -f "$private_key" ]; then
        echo "错误：私钥文件不存在：$private_key" >&2
        return 1
    fi

    echo "上传 SSL 证书："
    echo "  证书文件：$certificate_content"
    echo "  私钥文件：$private_key"
    echo "  证书别名：$alias_name"

    # 读取文件内容
    local cert_content_b64
    local key_content_b64
    cert_content_b64=$(base64 -w 0 < "$certificate_content")
    key_content_b64=$(base64 -w 0 < "$private_key")

    local result
    result=$(call_tencent_api ssl UploadCertificate --CertificatePublicKey "$cert_content_b64" --CertificatePrivateKey "$key_content_b64" --Alias "$alias_name")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ssl" "upload" "$result"
    else
        echo "错误：上传证书失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 删除 SSL 证书
ssl_delete() {
    local certificate_id=$1

    if [ -z "$certificate_id" ]; then
        echo "错误：需要提供证书ID。" >&2
        echo "用法：$0 ssl delete <证书ID>" >&2
        return 1
    fi

    echo "警告：您即将删除 SSL 证书：$certificate_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 SSL 证书：$certificate_id"

    local result
    result=$(call_tencent_api ssl DeleteCertificate --CertificateId "$certificate_id")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ssl" "delete" "$result"
    else
        echo "错误：删除证书失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 部署 SSL 证书到资源
ssl_deploy() {
    local certificate_id=$1
    local resource_type=$2
    local resource_id=$3

    if [ -z "$certificate_id" ] || [ -z "$resource_type" ] || [ -z "$resource_id" ]; then
        echo "错误：需要提供证书ID、资源类型和资源ID。" >&2
        echo "用法：$0 ssl deploy <证书ID> <资源类型> <资源ID>" >&2
        echo "支持的资源类型：clb(CLB负载均衡), cdn(CDN), waf(WAF等)" >&2
        return 1
    fi

    echo "部署 SSL 证书 $certificate_id 到 $resource_type 资源 $resource_id"

    local result
    # 注意：这里可能需要根据不同的资源类型使用不同的API
    result=$(call_tencent_api ssl DeployCertificateInstance --CertificateId "$certificate_id" --ResourceType "$resource_type" --ResourceId "$resource_id")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ssl" "deploy" "$result"
    else
        echo "错误：部署证书失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 下载 SSL 证书
ssl_download() {
    local certificate_id=$1
    local download_dir=$2

    if [ -z "$certificate_id" ] || [ -z "$download_dir" ]; then
        echo "错误：需要提供证书ID和下载目录。" >&2
        echo "用法：$0 ssl download <证书ID> <目录>" >&2
        return 1
    fi

    # 检查目录是否存在，如果不存在则创建
    if [ ! -d "$download_dir" ]; then
        echo "目录 $download_dir 不存在，正在创建..."
        mkdir -p "$download_dir"
        if [ $? -ne 0 ]; then
            echo "错误：无法创建目录 $download_dir" >&2
            return 1
        fi
    fi

    echo "下载 SSL 证书：$certificate_id 到目录：$download_dir"

    local result
    result=$(call_tencent_api ssl DownloadCertificate --CertificateId "$certificate_id" --Format "PEM")
    local ret=$?

    if [ $ret -eq 0 ]; then
        # 解析返回的下载链接并下载文件
        local cert_filename="${download_dir}/certificate_${certificate_id}"
        echo "$result" | jq '.' > "${cert_filename}.json"

        # 尝试直接解析证书内容（如果API直接返回证书内容）
        local cert_content
        cert_content=$(echo "$result" | jq -r '.Response.Content.CertificatePublicKey // empty')
        if [ -n "$cert_content" ]; then
            echo "$cert_content" > "${cert_filename}.crt"
        fi

        local key_content
        key_content=$(echo "$result" | jq -r '.Response.Content.CertificatePrivateKey // empty')
        if [ -n "$key_content" ]; then
            echo "$key_content" > "${cert_filename}.key"
        fi

        echo "证书已下载到: $cert_filename"
        log_result "${profile:-}" "$region" "ssl" "download" "$result"
    else
        echo "错误：下载证书失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

# 更新证书别名
ssl_update_alias() {
    local certificate_id=$1
    local new_alias=$2

    if [ -z "$certificate_id" ] || [ -z "$new_alias" ]; then
        echo "错误：需要提供证书ID和新别名。" >&2
        echo "用法：$0 ssl update-alias <证书ID> <别名>" >&2
        return 1
    fi

    echo "更新 SSL 证书别名：$certificate_id -> $new_alias"

    local result
    result=$(call_tencent_api ssl ModifyCertificateAlias --CertificateId "$certificate_id" --Alias "$new_alias")
    local ret=$?

    if [ $ret -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ssl" "update-alias" "$result"
    else
        echo "错误：更新证书别名失败。" >&2
        echo "$result" >&2
        return 1
    fi
}