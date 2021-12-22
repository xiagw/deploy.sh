#!/usr/bin/env bash

set -xe

script_path="$(cd "$(dirname "$0")" && pwd)"
# script_path="$(dirname "$(readlink -f "$0")")"
[ -d "$script_path/../data/helm" ] || mkdir -p "$script_path/../data/helm"
cd "$script_path/../data/helm" || exit 1

read -rp "release name? " -e -i 'backend-' release_name
# read -rp "prefix name? " -e prefix_name
read -rp "port number? " -e -i '8080' port_number
read -rp "http or tcp? " -e -i 'http' protocol

## create helm chart
helm create "$release_name"
## change helm chart values
sed -i \
    -e "s@port: 80@port: ${port_number}@" \
    "$release_name/values.yaml"
sed -i \
    -e "s@targetPort: http@targetPort: {{ .Values.service.port }}@" \
    "$release_name/templates/service.yaml"

if [[ $protocol == 'http' ]]; then
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
