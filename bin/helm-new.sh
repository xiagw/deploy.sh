#!/usr/bin/env bash

me_name="$(basename "$0")"
me_path="$(dirname "$(readlink -f "$0")")"
me_log="${me_path}/${me_name}.log"
path_data_helm=$me_path/../data/helm

[ -d "$path_data_helm" ] || mkdir -p "$path_data_helm"

if [[ -z "$1" ]]; then
    ## 获取 release名称 端口 协议信息
    read -rp "release name? " -e -i fly-$RANDOM release_name
    read -rp "port number? " -e -i '8080' port_number
    read -rp "another port number? " -e -i '8081' port_number2
    read -rp "http or tcp? " -e -i 'tcp' protocol
else
    release_name="${1:? ERR empty release_name}"
    port_number='8080'
    port_number2='8081'
    protocol='tcp'
fi

## 创建 helm chart
path_release="$path_data_helm/${release_name}"
helm create "$path_release"
echo "$(date), helm create $path_release" >>"$me_log"

## change values.yaml
sed -i \
    -e "/port: 80/ a \ \ port1: ${port_number2:-8081}" \
    -e "s@port: 80@port: ${port_number:-8080}@" \
    -e "s/create: true/create: false/" \
    "$path_release/values.yaml"
## change service.yaml
sed -i -e "s@targetPort: http@targetPort: {{ .Values.service.port }}@" \
    "$path_release/templates/service.yaml"
sed -i -e '13 a \    - port: {{ .Values.service.port1 }}' \
    "$path_release/templates/service.yaml"
sed -i -e '14 a \      targetPort: {{ .Values.service.port1 }}' \
    "$path_release/templates/service.yaml"
sed -i -e '15 a \      protocol: TCP' \
    "$path_release/templates/service.yaml"
sed -i -e '16 a \      name: http1' \
    "$path_release/templates/service.yaml"
## remove serviceaccount.yaml
rm -f "$path_release/templates/serviceaccount.yaml"
## change deployment.yaml
sed -i -e '39 a \            - name: http1' \
    "$path_release/templates/deployment.yaml"
sed -i -e '40 a \              containerPort: {{ .Values.service.port1 }}' \
    "$path_release/templates/deployment.yaml"
sed -i -e '41 a \              protocol: TCP' \
    "$path_release/templates/deployment.yaml"
if [[ "${protocol:-tcp}" == 'http' ]]; then
    sed -i \
        -e "s@containerPort: 80@containerPort: {{ .Values.service.port }}@" \
        -e "s@port: http@port: {{ .Values.service.port }}@g" \
        "$path_release/templates/deployment.yaml"
else
    sed -i \
        -e "s@containerPort: 80@containerPort: {{ .Values.service.port }}@" \
        -e "s@port: http@port: {{ .Values.service.port }}@g" \
        -e "s@httpGet:@tcpSocket:@g" \
        -e "s@path: /@# path: /@g" \
        "$path_release/templates/deployment.yaml"
fi
sed -i -e "/serviceAccountName/s/^/#/" \
    "$path_release/templates/deployment.yaml"
#                initialDelaySeconds: 50
