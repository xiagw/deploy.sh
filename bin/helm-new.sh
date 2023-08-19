#!/usr/bin/env bash

me_name="$(basename "$0")"
me_path="$(dirname "$(readlink -f "$0")")"
path_data_helm=$me_path/../data/helm
me_log="${path_data_helm}/${me_name}.log"

[ -d "$path_data_helm" ] || mkdir -p "$path_data_helm"

## 获取 release 名称/端口/协议等信息
if [[ -z "$1" ]]; then
    read -rp "helm release name? " -e -i fly-$RANDOM release_name
    read -rp "service port? " -e -i '8080' port_number
    read -rp "another service port? " -e -i '8081' port_number2
    read -rp "livenessProbe http or tcp? " -e -i 'tcp' protocol
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
## 需要修改的配置文件
values_file="$path_release/values.yaml"
svc_file="$path_release/templates/service.yaml"
deploy_file="$path_release/templates/deployment.yaml"
## remove serviceaccount.yaml
rm -f "$path_release/templates/serviceaccount.yaml"
## change values.yaml
sed -i \
    -e "/port: 80/ a \ \ port1: ${port_number2:-8081}" \
    -e "s@port: 80@port: ${port_number:-8080}@" \
    -e "s/create: true/create: false/" \
    "$values_file"
## change service.yaml
sed -i -e "s@targetPort: http@targetPort: {{ .Values.service.port }}@" "$svc_file"
sed -i -e '13 a \    - port: {{ .Values.service.port1 }}' "$svc_file"
sed -i -e '14 a \      targetPort: {{ .Values.service.port1 }}' "$svc_file"
sed -i -e '15 a \      protocol: TCP' "$svc_file"
sed -i -e '16 a \      name: http1' "$svc_file"
## change deployment.yaml
sed -i -e '39 a \            - name: http1' "$deploy_file"
sed -i -e '40 a \              containerPort: {{ .Values.service.port1 }}' "$deploy_file"
sed -i -e '41 a \              protocol: TCP' "$deploy_file"
if [[ "${protocol:-tcp}" == 'tcp' ]]; then
    sed -i \
        -e "s@containerPort: 80@containerPort: {{ .Values.service.port }}@" \
        -e "s@port: http@port: {{ .Values.service.port }}@g" \
        -e "s@httpGet:@tcpSocket:@g" \
        -e "s@path: /@# path: /@g" \
        "$deploy_file"
else
    sed -i \
        -e "s@containerPort: 80@containerPort: {{ .Values.service.port }}@" \
        -e "s@port: http@port: {{ .Values.service.port }}@g" \
        "$deploy_file"
fi
sed -i -e "/serviceAccountName/s/^/#/" "$deploy_file"
#                initialDelaySeconds: 50
