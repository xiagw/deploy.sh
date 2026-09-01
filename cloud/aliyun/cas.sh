#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2016

# 证书服务（Certificate Authority Service）相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

# 使用通用数据目录
CAS_CERT_FILE="${SCRIPT_DATA:? ERR: SCRIPT_DATA empty}/cas/cas_certs.json"

show_cas_help() {
    echo "证书服务 (Certificate Authority Service) 操作："
    echo "  get [类型] [format]                      - 列出证书。类型: all=全部证书(默认), upload=仅上传, order=仅订单(购买/免费)"
    echo "  add <证书名称> <证书文件> <私钥文件>    - 上传并创建新证书"
    echo "  del [<证书ID>]                          - 删除指定证书（证书ID可选，可使用fzf选择）"
    echo "  get-detail [<证书ID>]                   - 获取证书详情（证书ID可选，可使用fzf选择）"
    echo "  batch-upload [domain...]                 - 批量上传证书并部署到CDN"
    echo
    echo "示例："
    echo "  $0 cas get                  # 全部证书（签发+上传）"
    echo "  $0 cas get upload           # 仅用户上传的证书"
    echo "  $0 cas get order            # 仅订单（购买/免费证书）"
    echo "  $0 cas get all json         # 全部证书，JSON 格式"
    echo "  $0 cas add my-cert /path/to/cert.pem /path/to/key.pem"
    echo "  $0 cas del 15246052"
    echo "  $0 cas get-detail 15246052"
    echo "  $0 cas batch-upload                # 自动处理所有CDN域名的证书"
    echo "  $0 cas batch-upload example.com    # 处理指定域名的证书"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_cas_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) cas_list "$@" ;;
    add) cas_create "$@" ;;
    set) cas_update "$@" ;;  # 虽然实际不支持更新，但保留以符合ECS模式
    del) cas_delete "$@" ;;
    get-detail) cas_detail "$@" ;;
    batch-upload) cas_batch_upload_deploy "$@" ;;
    help) show_cas_help ;;
    *)
        echo "错误：未知的证书服务操作：$operation" >&2
        show_cas_help
        exit 1
        ;;
    esac
}

# 解析证书 ID（未提供时列表选择；cas 为中心化服务，固定 --region cn-hangzhou）
_cas_resolve_cert_id() {
    resolve_resource_id "$1" "${2:-选择证书}" "错误：没有找到证书。" \
        '.CertificateOrderList[]? | "\(.CertificateId) (\(.Name)) [\(.Status)] \(if .Upload then "上传" else "签发" end)"' \
        -- cas list-user-certificate-order --api-version 2020-04-07 --region cn-hangzhou --order-type CERT --show-size 100
}

# CAS 列表：使用 ListUserCertificateOrder（官网文档：买的证书、免费证书、用户上传证书均由此接口查询）
# OrderType: CERT=签发+上传证书, UPLOAD=仅上传证书, CPACK=资源/购买订单, BUY=售卖订单
cas_list() {
    local list_type=${1:-all}
    local format=${2:-human}
    local order_type="CERT"
    case "$list_type" in
    all)     order_type="CERT" ;;   # 同时返回签发证书和上传证书
    upload)  order_type="UPLOAD" ;; # 只返回上传证书
    order)   order_type="CPACK" ;;  # 只返回订单（购买/免费等）
    json|tsv|human) format="$list_type"; list_type="all"; order_type="CERT" ;;
    *)       format="$list_type"; list_type="all"; order_type="CERT" ;;
    esac
    # 若 format 被误解析为 list_type，再校正一次
    case "$format" in
    json|tsv|human) ;;
    *) format="human" ;;
    esac
    # aliyun cas list-user-certificate-order --api-version 2020-04-07 --region cn-hangzhou
    local result
    if ! result=$(call_aliyun_api cas list-user-certificate-order --api-version 2020-04-07 --region cn-hangzhou --order-type "$order_type" --show-size 100); then
        echo "错误：无法获取证书列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    local table_header jq_filter status_mapper title human_header
    if [ "$order_type" = "CPACK" ]; then
        table_header="InstanceId\tOrderId\tProductName\tStatus\tCertType\tDomain\tBuyDate"
        jq_filter='.CertificateOrderList[]? | [.InstanceId, .OrderId, (.ProductName // .ProductCode // "-"), .Status, (.CertType // "-"), (.Domain // "-"), (.BuyDate // 0)] | @tsv'
        status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-20s  %-22s  %-10s  %-6s  %s\n", $1, substr($3,1,20), $4, $5, $6}'
        title="证书订单列表（购买/免费等）"
        human_header="InstanceId/订单ID    产品/规格              状态        类型    域名"
    else
        table_header="CertificateId\tName\t类型\tCommonName\tStartDate\tEndDate\tStatus"
        jq_filter='.CertificateOrderList[]? | [.CertificateId, (.Name // "-"), (if .Upload then "上传" else "签发" end), (.CommonName // "-"), (.StartDate // "-"), (.EndDate // "-"), (.Status // "-")] | @tsv'
        status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-10s  %-18s  %-4s  %-18s  %-10s  %-10s  %s\n", $1, substr($2,1,16), $3, substr($4,1,16), $5, $6, $7}'
        title="证书列表（签发证书 + 用户上传证书）"
        if [ "$order_type" = "UPLOAD" ]; then
            title="用户上传的证书"
        fi
        human_header="证书ID    名称                类型  主域名              开始日期    到期日期    状态"
    fi

    format_output \
        "$result" \
        "$format" \
        "cas" \
        "list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到证书记录。" \
        "$title" \
        "$human_header" \
        '.CertificateOrderList | length // 0'
}

# 使用框架的创建函数（但需要特殊处理文件读取）
cas_create() {
    local name=$1
    local cert_file=$2
    local key_file=$3

    # 如果没有提供参数，则使用交互式输入
    if [ -z "$name" ] || [ -z "$cert_file" ] || [ -z "$key_file" ]; then
        echo "使用交互式模式创建证书"

        # 输入证书名称
        if [ -z "$name" ]; then
            read -r -p "请输入证书名称: " name
            if [ -z "$name" ]; then
                echo "错误：证书名称不能为空。" >&2
                return 1
            fi
        fi

        # 输入证书文件
        if [ -z "$cert_file" ]; then
            read -r -p "请输入证书文件路径: " cert_file
            if [ -z "$cert_file" ]; then
                echo "错误：证书文件路径不能为空。" >&2
                return 1
            fi
        fi

        # 输入私钥文件
        if [ -z "$key_file" ]; then
            read -r -p "请输入私钥文件路径: " key_file
            if [ -z "$key_file" ]; then
                echo "错误：私钥文件路径不能为空。" >&2
                return 1
            fi
        fi
    fi

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
    result=$(call_aliyun_api cas upload-user-certificate --api-version 2020-04-07 --region cn-hangzhou \
        --name "$name" \
        --cert "$(cat "$cert_file")" \
        --key "$(cat "$key_file")")
    local ret=$?
    if [ $ret -eq 0 ]; then
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
                '. += [{"CertId": $id, "Name": $name, "UploadTime": $time}]' "$CAS_CERT_FILE" >"${CAS_CERT_FILE}.tmp" &&
                mv "${CAS_CERT_FILE}.tmp" "$CAS_CERT_FILE"
        else
            echo '[{"CertId": "'"$cert_id"'", "Name": "'"$name"'", "UploadTime": "'"$upload_time"'"}]' >"$CAS_CERT_FILE"
        fi
    else
        echo "错误：证书创建失败。"
        echo "$result"
        return 1
    fi
    log_result "${profile:-}" "${region:-}" "cas" "create" "$result"
}

# 使用框架的删除函数
cas_delete() {
    local cert_id
    cert_id=$(_cas_resolve_cert_id "$1" "选择要删除的证书") || return 1

    if ! confirm_action "删除证书 ID: $cert_id"; then
        return 1
    fi

    echo "删除证书："
    call_api_del_logged "cas" "$cert_id" "证书" "错误：证书删除失败。" \
        -- cas delete-user-certificate --api-version 2020-04-07 --region cn-hangzhou --cert-id "$cert_id" || return 1
    echo "证书删除成功。"
    # 从本地文件中删除证书信息
    if [ -f "$CAS_CERT_FILE" ]; then
        jq --arg id "$cert_id" 'map(select(.CertId != $id))' "$CAS_CERT_FILE" >"${CAS_CERT_FILE}.tmp" &&
            mv "${CAS_CERT_FILE}.tmp" "$CAS_CERT_FILE"
    fi
}

# 使用框架的详情函数
cas_detail() {
    local cert_id
    cert_id=$(_cas_resolve_cert_id "$1" "选择要查看详情的证书") || return 1

    echo "获取证书详情："
    call_api_logged "cas" "detail" "错误：无法获取证书详情。" \
        -- cas get-user-certificate-detail --api-version 2020-04-07 --region cn-hangzhou --cert-id "$cert_id"
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
        cdn_result=$(call_aliyun_api cdn describe-user-domains --api-version 2018-05-10 --region cn-hangzhou 2>/dev/null)
        local ret=$?
        if [ $ret -eq 0 ]; then
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
        result=$(call_aliyun_api cas upload-user-certificate --api-version 2020-04-07 --region cn-hangzhou \
            --name "$upload_name" \
            --cert "$(cat "$file_pem")" \
            --key "$(cat "$file_key")")
        local status=$?

        # 创建日志目录
        mkdir -p "$(dirname "$upload_log")"
        echo "$result" >"$upload_log"

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
                    '. += [{"CertId": $id, "Name": $name, "UploadTime": $time}]' "$CAS_CERT_FILE" >"${CAS_CERT_FILE}.tmp" &&
                    mv "${CAS_CERT_FILE}.tmp" "$CAS_CERT_FILE"
            else
                echo '[{"CertId": "'"$cert_id"'", "Name": "'"$upload_name"'", "UploadTime": "'"$upload_time"'"}]' >"$CAS_CERT_FILE"
            fi
        else
            echo "错误：证书上传失败" >&2
            continue
        fi
    done

    # 为CDN域名部署证书
    echo "正在为CDN域名部署证书..."
    local cdn_result
    cdn_result=$(call_aliyun_api cdn describe-user-domains --api-version 2018-05-10 --region cn-hangzhou 2>/dev/null)
    local ret=$?
    if [ $ret -eq 0 ]; then
        local cdn_domains
        readarray -t cdn_domains < <(echo "$cdn_result" | jq -r '.Domains.PageData[].DomainName')

        for domain_cdn in "${cdn_domains[@]}"; do
            local domain="${domain_cdn#*.}"
            local upload_name="${domain//./-}-$today"
            echo "CDN域名: ${domain_cdn}"
            echo "设置证书: ${upload_name}"

            call_aliyun_api cdn batch-set-cdn-domain-server-certificate --api-version 2018-05-10 --region cn-hangzhou \
                --ssl-protocol on \
                --cert-type cas \
                --domain-name "${domain_cdn}" \
                --cert-name "${upload_name}" >/dev/null 2>&1
        done
    fi
}
