#!/bin/bash
# -*- coding: utf-8 -*-

read_credentials() {
    local credentials_file="${HOME}/.tencentcloud/credentials"
    local section="${1:-default}"  # 默认读取 default 配置段

    if [[ ! -f "$credentials_file" ]]; then
        echo "错误：找不到配置文件 ${credentials_file}" >&2
        return 1
    fi

    # 读取指定配置段的密钥信息
    local in_section=0
    local secret_id=""
    local secret_key=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 去除行首尾空格
        line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        # 跳过空行和注释
        echo "$line" | grep -E '^$|^[#;]' >/dev/null && continue

        # 检查配置段
        if [[ "$line" =~ ^\[(.*)\]$ ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$section" ]]; then
                in_section=1
            else
                in_section=0
            fi
            continue
        fi

        # 在目标配置段中读取配置项
        if [[ $in_section -eq 1 ]]; then
            if [[ "$line" =~ ^secret_id[[:space:]]*=[[:space:]]*(.*)$ ]]; then
                secret_id="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^secret_key[[:space:]]*=[[:space:]]*(.*)$ ]]; then
                secret_key="${BASH_REMATCH[1]}"
            fi
        fi
    done < "$credentials_file"

    # 检查是否成功读取到密钥
    if [[ -z "$secret_id" || -z "$secret_key" ]]; then
        echo "错误：在配置文件中未找到有效的密钥信息" >&2
        return 1
    fi

    # 输出密钥信息（用制表符分隔）
    echo -e "${secret_id}\t${secret_key}"
}

generate_signature() {
    local secret_id="$1"
    local secret_key="$2"
    local timestamp="$3"
    local payload="$4"
    local host="billing.tencentcloudapi.com"
    local service="billing"
    local algorithm="TC3-HMAC-SHA256"
    local date=$(date -u -d @$timestamp +%Y-%m-%d)

    # 1. 拼接规范请求串
    local http_request_method="POST"
    local canonical_uri="/"
    local canonical_querystring=""
    local canonical_headers="content-type:application/json\nhost:${host}\n"
    local signed_headers="content-type;host"

    # 计算请求体哈希
    local hashed_request_payload
    hashed_request_payload=$(echo -n "$payload" | openssl dgst -sha256 -hex | sed 's/^.* //')

    local canonical_request="${http_request_method}\n${canonical_uri}\n${canonical_querystring}\n${canonical_headers}\n${signed_headers}\n${hashed_request_payload}"

    # 调试信息
    if [[ "${DEBUG:-}" == "true" ]]; then
        echo "===== Debug Info =====" >&2
        echo "Canonical Request:" >&2
        echo -e "$canonical_request" >&2
        echo "Hashed Payload: $hashed_request_payload" >&2
        echo "===================" >&2
    fi

    # 2. 拼接待签名字符串
    local credential_scope="${date}/${service}/tc3_request"
    local hashed_canonical_request
    hashed_canonical_request=$(echo -n "$canonical_request" | openssl dgst -sha256 -hex | sed 's/^.* //')
    local string_to_sign="${algorithm}\n${timestamp}\n${credential_scope}\n${hashed_canonical_request}"

    if [[ "${DEBUG:-}" == "true" ]]; then
        echo "String to Sign:" >&2
        echo -e "$string_to_sign" >&2
        echo "===================" >&2
    fi

    # 3. 计算签名
    local secret_date
    secret_date=$(echo -n "$date" | openssl dgst -sha256 -hmac "TC3${secret_key}" -hex | sed 's/^.* //')
    local secret_service
    secret_service=$(echo -n "$service" | openssl dgst -sha256 -hmac "$secret_date" -hex | sed 's/^.* //')
    local secret_signing
    secret_signing=$(echo -n "tc3_request" | openssl dgst -sha256 -hmac "$secret_service" -hex | sed 's/^.* //')
    local signature
    signature=$(echo -n "$string_to_sign" | openssl dgst -sha256 -hmac "$secret_signing" -hex | sed 's/^.* //')

    # 4. 拼接 Authorization
    echo "${algorithm} Credential=${secret_id}/${credential_scope}, SignedHeaders=${signed_headers}, Signature=${signature}"
}

query_balance() {
    # 优先从配置文件读取密钥
    local credentials
    if credentials=$(read_credentials default); then
        IFS=$'\t' read -r secret_id secret_key <<< "$credentials"
    else
        # 如果配置文件读取失败，尝试从环境变量获取
        secret_id="${TENCENT_SECRET_ID}"
        secret_key="${TENCENT_SECRET_KEY}"
    fi

    if [[ -z "$secret_id" ]] || [[ -z "$secret_key" ]]; then
        echo "错误：未能获取到有效的密钥信息"
        echo "请确保以下任一条件满足："
        echo "1. 配置文件 ~/.tencentcloud/credentials 存在且包含有效的密钥信息"
        echo "2. 环境变量 TENCENT_SECRET_ID 和 TENCENT_SECRET_KEY 已正确设置"
        return 1
    fi

    local timestamp=$(date +%s)
    local payload="{}"
    local authorization
    authorization=$(generate_signature "$secret_id" "$secret_key" "$timestamp" "$payload")

    if [[ "${DEBUG:-}" == "true" ]]; then
        echo "Authorization: $authorization" >&2
        echo "Timestamp: $timestamp" >&2
    fi

    local response
    response=$(curl -v -s -X POST "https://billing.tencentcloudapi.com/" \
        -H "Authorization: $authorization" \
        -H "Content-Type: application/json" \
        -H "X-TC-Timestamp: $timestamp" \
        -H "X-TC-Action: DescribeAccountBalance" \
        -H "X-TC-Version: 2018-07-09" \
        -H "X-TC-Region: ap-guangzhou" \
        -d "$payload" 2>&1)

    if [[ -z "$response" ]]; then
        echo "错误：查询请求失败，无响应。"
        return 1
    fi

    # Check for errors in response
    if echo "$response" | jq -e '.Response.Error' >/dev/null; then
        local error_code
        local error_message
        error_code=$(echo "$response" | jq -r '.Response.Error.Code')
        error_message=$(echo "$response" | jq -r '.Response.Error.Message')
        echo "错误：查询失败 (代码: $error_code) - $error_message"
        return 1
    fi

    # 解析并显示余额信息
    local balance
    local credit
    local real_balance
    balance=$(echo "$response" | jq -r '.Response.Balance')
    credit=$(echo "$response" | jq -r '.Response.Credit')
    real_balance=$(echo "$response" | jq -r '.Response.RealBalance')

    echo "账户余额信息："
    echo "--------------------------------"
    echo "账户余额：￥${balance}"
    echo "账户可用信用额度：￥${credit}"
    echo "现金余额：￥${real_balance}"
    return 0
}

query_balance "$@"