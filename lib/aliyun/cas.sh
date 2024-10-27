#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 证书服务（Certificate Authority Service）相关函数

# 使用通用数据目录
CAS_CERT_FILE="${SCRIPT_DATA}/cas/cas_certs.json"

show_cas_help() {
    echo "证书服务 (Certificate Authority Service) 操作："
    echo "  list                                    - 列出所有已上传的证书"
    echo "  create <证书名称> <证书文件> <私钥文件>    - 上传并创建新证书"
    echo "  delete <证书ID>                          - 删除指定证书"
    echo "  detail <证书ID>                          - 获取证书详情"
    echo
    echo "示例："
    echo "  $0 cas list"
    echo "  $0 cas create my-cert /path/to/cert.pem /path/to/key.pem"
    echo "  $0 cas delete 15246052"
    echo "  $0 cas detail 15246052"
}

handle_cas_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) cas_list "$@" ;;
    create) cas_create "$@" ;;
    delete) cas_delete "$@" ;;
    detail) cas_detail "$@" ;;
    *)
        echo "错误：未知的证书服务操作：$operation" >&2
        show_cas_help
        exit 1
        ;;
    esac
}

cas_list() {
    local format=${1:-human}
    local result

    if [ -f "$CAS_CERT_FILE" ]; then
        result=$(jq -r '.[] | [.CertId, .Name, .UploadTime] | @tsv' "$CAS_CERT_FILE")
    else
        result=""
    fi

    case "$format" in
        json)  ##此处非标准化数据不需要变更代码
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
                echo "$result" | jq -r '.[] | [.CertId, .Name, .UploadTime] | @tsv'
            fi
            ;;
        human|*)
            echo "列出所有已上传的证书："
            if [ -n "$result" ]; then
                echo "证书ID            名称                          上传时间"
                echo "----------------  ----------------------------  -------------------------"
                echo "$result" | jq -r '.[] | [.CertId, .Name, .UploadTime] | @tsv' |
                    awk 'BEGIN {FS="\t"; OFS="\t"}
                    {printf "%-16s  %-28s  %s\n", $1, $2, $3}'
            else
                echo "没有找到已上传的证书记录。"
            fi
            ;;
    esac
    log_result "${profile:-}" "${region:-}" "cas" "list" "$result" "$format"
}

cas_create() {
    local name=$1
    local cert_file=$2
    local key_file=$3

    if [ -z "$name" ] || [ -z "$cert_file" ] || [ -z "$key_file" ]; then
        echo "错误：缺少必要参数。用法：$0 cas create <证书名称> <证书文件> <私钥文件>" >&2
        return 1
    fi

    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        echo "错误：证书文件或私钥文件不存在。" >&2
        return 1
    fi

    echo "上传并创建新证书："
    local result
    result=$(aliyun --profile "${profile:-}" cas UploadUserCertificate \
        --Name "$name" \
        --Cert "$(cat "$cert_file")" \
        --Key "$(cat "$key_file")")

    if [ $? -eq 0 ]; then
        echo "证书创建成功："
        echo "$result" | jq '.'
        local cert_id
        cert_id=$(echo "$result" | jq -r '.CertId')
        local upload_time
        upload_time=$($CMD_DATE "+%Y-%m-%d %H:%M:%S")

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

cas_delete() {
    local cert_id=$1

    if [ -z "$cert_id" ]; then
        echo "错误：缺少证书ID。用法：$0 cas delete <证书ID>" >&2
        return 1
    fi

    echo "警告：您即将删除证书 ID: $cert_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除证书："
    local result
    result=$(aliyun --profile "${profile:-}" cas DeleteUserCertificate --CertId "$cert_id")

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
    fi

    log_result "${profile:-}" "${region:-}" "cas" "delete" "$result"
}

cas_detail() {
    local cert_id=$1

    if [ -z "$cert_id" ]; then
        echo "错误：缺少证书ID。用法：$0 cas detail <证书ID>" >&2
        return 1
    fi

    echo "获取证书详情："
    local result
    result=$(aliyun --profile "${profile:-}" cas GetUserCertificateDetail --CertId "$cert_id")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
    else
        echo "错误：无法获取证书详情。"
        echo "$result"
    fi
    log_result "${profile:-}" "${region:-}" "cas" "detail" "$result"
}
