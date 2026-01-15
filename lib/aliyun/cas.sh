#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 证书服务（Certificate Authority Service）相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"

# 使用通用数据目录
CAS_CERT_FILE="${SCRIPT_DATA:? ERR: SCRIPT_DATA empty}/cas/cas_certs.json"

show_cas_help() {
    echo "证书服务 (Certificate Authority Service) 操作："
    echo "  list                                    - 列出所有已上传的证书"
    echo "  create <证书名称> <证书文件> <私钥文件>    - 上传并创建新证书"
    echo "  delete <证书ID>                          - 删除指定证书"
    echo "  detail <证书ID>                          - 获取证书详情"
    echo "  batch-upload [domain...]                 - 批量上传证书并部署到CDN"
    echo
    echo "示例："
    echo "  $0 cas list"
    echo "  $0 cas create my-cert /path/to/cert.pem /path/to/key.pem"
    echo "  $0 cas delete 15246052"
    echo "  $0 cas detail 15246052"
    echo "  $0 cas batch-upload                # 自动处理所有CDN域名的证书"
    echo "  $0 cas batch-upload example.com    # 处理指定域名的证书"
}

handle_cas_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) cas_list "$@" ;;
    create) cas_create "$@" ;;
    update) cas_update "$@" ;;
    delete) cas_delete "$@" ;;
    detail) cas_detail "$@" ;;
    batch-upload) cas_batch_upload_deploy "$@" ;;
    help) show_cas_help ;;
    *)
        echo "错误：未知的证书服务操作：$operation" >&2
        show_cas_help
        exit 1
        ;;
    esac
}

# CAS 列表使用本地文件，需要特殊处理
cas_list() {
    local format=${1:-human}
    local result

    if [ -f "$CAS_CERT_FILE" ]; then
        result=$(jq -r '.[] | [.CertId, .Name, .UploadTime] | @tsv' "$CAS_CERT_FILE")
    else
        result=""
    fi

    case "$format" in
    json)
        if [ -n "$result" ]; then
            echo "$result" | jq -R -s '
                split("\n") |
                map(select(length > 0) | split("\t")) |
                map({"CertId": .[0], "Name": .[1], "UploadTime": .[2]})
            '
        else
            echo "[]"
        fi
        ;;
    tsv)
        echo -e "CertId\tName\tUploadTime"
        if [ -n "$result" ]; then
            echo "$result"
        fi
        ;;
    human | *)
        echo "列出所有已上传的证书："
        if [ -n "$result" ]; then
            echo "证书ID            名称                          上传时间"
            echo "----------------  ----------------------------  -------------------------"
            echo "$result" | awk 'BEGIN {FS="\t"; OFS="\t"}
            {printf "%-16s  %-28s  %s\n", $1, $2, $3}'
        else
            echo "没有找到已上传的证书记录。"
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "cas" "list" "$result" "$format"
}

# 使用框架的创建函数（但需要特殊处理文件读取）
cas_create() {
    local name=$1
    local cert_file=$2
    local key_file=$3

    if ! validate_required_params "$name" "$cert_file" "$key_file" "错误：证书名称、证书文件和私钥文件不能为空。"; then
        echo "用法：cas create <证书名称> <证书文件> <私钥文件>" >&2
        return 1
    fi

    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        echo "错误：证书文件或私钥文件不存在。" >&2
        return 1
    fi

    echo "上传并创建新证书："
    local result
    result=$(call_aliyun_api cas UploadUserCertificate \
        --Name "$name" \
        --Cert "$(cat "$cert_file")" \
        --Key "$(cat "$key_file")")

    if [ $? -eq 0 ]; then
        echo "证书创建成功："
        echo "$result" | jq '.'
        local cert_id
        cert_id=$(echo "$result" | jq -r '.CertId')
        local upload_time
        upload_time=$(date "+%Y-%m-%d %H:%M:%S")

        # 确保目录存在
        mkdir -p "$(dirname "$CAS_CERT_FILE")"

        # 将新证书信息添加到本地文件
        if [ -f "$CAS_CERT_FILE" ]; then
            jq --arg id "$cert_id" --arg name "$name" --arg time "$upload_time" \
                '. += [{"CertId": $id, "Name": $name, "UploadTime": $time}]' "$CAS_CERT_FILE" > "${CAS_CERT_FILE}.tmp" &&
                mv "${CAS_CERT_FILE}.tmp" "$CAS_CERT_FILE"
        else
            echo '[{"CertId": "'"$cert_id"'", "Name": "'"$name"'", "UploadTime": "'"$upload_time"'"}]' > "$CAS_CERT_FILE"
        fi
    else
        echo "错误：证书创建失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "${region:-}" "cas" "create" "$result"
}

# 使用框架的删除函数
cas_delete() {
    local cert_id=$1

    if [ -z "$cert_id" ]; then
        echo "错误：证书ID不能为空。" >&2
        echo "用法：cas delete <证书ID>" >&2
        return 1
    fi

    if ! confirm_action "删除证书 ID: $cert_id"; then
        return 1
    fi

    echo "删除证书："
    local result
    result=$(call_aliyun_api cas DeleteUserCertificate --CertId "$cert_id")

    if [ $? -eq 0 ]; then
        echo "证书删除成功。"
        # 从本地文件中删除证书信息
        if [ -f "$CAS_CERT_FILE" ]; then
            jq --arg id "$cert_id" 'map(select(.CertId != $id))' "$CAS_CERT_FILE" > "${CAS_CERT_FILE}.tmp" &&
                mv "${CAS_CERT_FILE}.tmp" "$CAS_CERT_FILE"
        fi
        log_delete_operation "${profile:-}" "${region:-}" "cas" "$cert_id" "证书" "成功"
    else
        echo "错误：证书删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "${region:-}" "cas" "$cert_id" "证书" "失败"
        return 1
    fi

    log_result "${profile:-}" "${region:-}" "cas" "delete" "$result"
}

# 使用框架的详情函数
cas_detail() {
    local cert_id=$1

    if [ -z "$cert_id" ]; then
        echo "错误：证书ID不能为空。" >&2
        echo "用法：cas detail <证书ID>" >&2
        return 1
    fi

    echo "获取证书详情："
    local result
    result=$(call_aliyun_api cas GetUserCertificateDetail --CertId "$cert_id")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
    else
        echo "错误：无法获取证书详情。"
        echo "$result"
    fi
    log_result "${profile:-}" "${region:-}" "cas" "detail" "$result"
}

# 更新函数（如果存在）
cas_update() {
    echo "错误：证书服务不支持更新操作，请删除后重新创建。" >&2
    return 1
}

# 批量上传和部署证书（保持原有实现，但使用框架函数）
cas_batch_upload_deploy() {
    local domains=("$@")
    local today
    today="$(date +%m%d)"

    # 如果没有提供域名参数,则从CDN域名列表获取
    if [ ${#domains[@]} -eq 0 ]; then
        local cdn_result
        cdn_result=$(call_aliyun_api cdn DescribeUserDomains 2>/dev/null)
        if [ $? -eq 0 ]; then
            readarray -t domains < <(echo "$cdn_result" |
                jq -r '.Domains.PageData[].DomainName' |
                awk -F. '{$1=""; print $0}' | sort | uniq)
        fi
    fi

    # 遍历处理每个域名
    for domain in "${domains[@]}"; do
        domain="${domain// /.}"
        local upload_name="${domain//./-}-$today"
        local file_key="$HOME/.acme.sh/dest/${domain}.key"
        local file_pem="$HOME/.acme.sh/dest/${domain}.pem"
        local upload_log="${SCRIPT_DATA}/cas/cert_${domain}.log"

        echo "处理域名: ${domain}"
        echo "证书名称: ${upload_name}"
        echo "密钥文件: $file_key"
        echo "证书文件: $file_pem"

        # 检查证书文件是否存在
        if [ ! -f "$file_key" ] || [ ! -f "$file_pem" ]; then
            echo "错误：证书文件不存在: $file_key 或 $file_pem" >&2
            continue
        fi

        # 删除旧证书
        if [ -f "$upload_log" ]; then
            echo "找到历史证书记录: ${upload_log}"
            local remove_cert_id
            remove_cert_id=$(jq -r '.CertId' "$upload_log")
            if [ -n "$remove_cert_id" ] && [ "$remove_cert_id" != "null" ]; then
                echo "删除旧证书 ID: $remove_cert_id"
                cas_delete "$remove_cert_id" 2>/dev/null || true
            fi
        fi

        # 上传新证书
        local result
        result=$(call_aliyun_api cas UploadUserCertificate \
            --Name "$upload_name" \
            --Cert "$(cat "$file_pem")" \
            --Key "$(cat "$file_key")")
        local status=$?

        # 创建日志目录
        mkdir -p "$(dirname "$upload_log")"
        echo "$result" > "$upload_log"

        if [ $status -eq 0 ]; then
            echo "证书上传成功"
            local cert_id
            cert_id=$(echo "$result" | jq -r '.CertId')
            local upload_time
            upload_time=$(date "+%Y-%m-%d %H:%M:%S")

            # 更新本地文件
            mkdir -p "$(dirname "$CAS_CERT_FILE")"
            if [ -f "$CAS_CERT_FILE" ]; then
                jq --arg id "$cert_id" --arg name "$upload_name" --arg time "$upload_time" \
                    '. += [{"CertId": $id, "Name": $name, "UploadTime": $time}]' "$CAS_CERT_FILE" > "${CAS_CERT_FILE}.tmp" &&
                    mv "${CAS_CERT_FILE}.tmp" "$CAS_CERT_FILE"
            else
                echo '[{"CertId": "'"$cert_id"'", "Name": "'"$upload_name"'", "UploadTime": "'"$upload_time"'"}]' > "$CAS_CERT_FILE"
            fi
        else
            echo "错误：证书上传失败" >&2
            continue
        fi
    done

    # 为CDN域名部署证书
    echo "正在为CDN域名部署证书..."
    local cdn_result
    cdn_result=$(call_aliyun_api cdn DescribeUserDomains 2>/dev/null)
    if [ $? -eq 0 ]; then
        local cdn_domains
        readarray -t cdn_domains < <(echo "$cdn_result" | jq -r '.Domains.PageData[].DomainName')

        for domain_cdn in "${cdn_domains[@]}"; do
            local domain="${domain_cdn#*.}"
            local upload_name="${domain//./-}-$today"
            echo "CDN域名: ${domain_cdn}"
            echo "设置证书: ${upload_name}"

            call_aliyun_api cdn BatchSetCdnDomainServerCertificate \
                --SSLProtocol on \
                --CertType cas \
                --DomainName "${domain_cdn}" \
                --CertName "${upload_name}" >/dev/null 2>&1
        done
    fi
}
