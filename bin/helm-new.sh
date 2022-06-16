#!/usr/bin/env bash

set -xe

script_path="$(dirname "$(readlink -f "$0")")"
cd "$script_path" || exit 1

if [[ -z "$1" ]]; then
    ## 获取 release名称 端口 协议信息
    read -rp "release name? " -e -i 'nginx' release_name
    read -rp "port number? " -e -i '80' port_number
    read -rp "http or tcp? " -e -i 'tcp' protocol
else
    release_name="${1:-nginx}"
    port_number="${2:-80}"
    protocol="${3:-http}"
fi

## 创建 helm chart
helm create "${release_name:?empty var}"

## change values.yaml
sed -i \
    -e "s@port: 80@port: ${port_number:-80}@" \
    "$release_name/values.yaml"
## change service.yaml
sed -i \
    -e "s@targetPort: http@targetPort: {{ .Values.service.port }}@" \
    "$release_name/templates/service.yaml"
## change serviceaccount.yaml
sed -i \
    -e "/serviceAccountName/s/^/#/" "$release_name/templates/deployment.yaml"
## remove serviceaccount.yaml
rm -f "$release_name/templates/serviceaccount.yaml"

if [[ "${protocol:-http}" == 'http' ]]; then
    sed -i \
        -e "s@containerPort: 80@containerPort: {{ .Values.service.port }}@" \
        -e "s@port: http@port: {{ .Values.service.port }}@g" \
        "$release_name/templates/deployment.yaml"
else
    sed -i \
        -e "s@containerPort: 80@containerPort: {{ .Values.service.port }}@" \
        -e "s@port: http@port: {{ .Values.service.port }}@g" \
        -e "s@httpGet:@tcpSocket:@g" \
        -e "s@path: /@# path: /@g" \
        "$release_name/templates/deployment.yaml"
fi
