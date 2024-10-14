#!/usr/bin/env bash

me_name="$(basename "$0")"
me_path="$(dirname "$(readlink -f "$0")")"
me_path_data=$me_path/../data/helm
me_log="${me_path_data}/${me_name}.log"

[ -d "$me_path_data" ] || mkdir -p "$me_path_data"

## 获取 release 名称/端口/协议等信息
if [[ -z "$1" ]]; then
    read -rp "helm release name? " -e -i fly-demo$RANDOM release_name
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
path_release="$me_path_data/${release_name}"
helm create "$path_release"
echo "$(date), helm create $path_release" >>"$me_log"
## 需要修改的配置文件
values_file="$path_release/values.yaml"
svc_file="$path_release/templates/service.yaml"
deploy_file="$path_release/templates/deployment.yaml"
## remove serviceaccount.yaml
# rm -f "$path_release/templates/serviceaccount.yaml"

## change values.yaml
sed -i \
    -e "/port: 80/ a \ \ #port2: ${port_number2:-8081}" \
    -e "s@port: 80@port: ${port_number:-8080}@" \
    -e "s/create: true/create: false/" \
    "$values_file"
sed -i -e '4 a #cnfs: cnfs-nas-pvc-www' "$values_file"

## change service.yaml
sed -i -e "s@targetPort: http@targetPort: {{ .Values.service.port }}@" "$svc_file"
sed -i -e '13 a \    {{- if .Values.service.port2 }}' "$svc_file"
sed -i -e '14 a \    - port: {{ .Values.service.port2 }}' "$svc_file"
sed -i -e '15 a \      targetPort: {{ .Values.service.port2 }}' "$svc_file"
sed -i -e '16 a \      protocol: TCP' "$svc_file"
sed -i -e '17 a \      name: http2' "$svc_file"
sed -i -e '18 a \    {{- end }}' "$svc_file"

## change deployment.yaml
sed -i -e '39 a \            {{- if .Values.service.port2 }}' "$deploy_file"
sed -i -e '40 a \            - name: http2' "$deploy_file"
sed -i -e '41 a \              containerPort: {{ .Values.service.port2 }}' "$deploy_file"
sed -i -e '42 a \              protocol: TCP' "$deploy_file"
sed -i -e '43 a \            {{- end }}' "$deploy_file"
## add volume
sed -i -e '54 a \          {{- if or .Values.cnfs .Values.nas .Values.nfs }}' "$deploy_file"
sed -i -e '55 a \          volumeMounts:' "$deploy_file"
sed -i -e '56 a \          {{- end }}' "$deploy_file"
sed -i -e '57 a \          {{- if .Values.cnfs }}' "$deploy_file"
sed -i -e '58 a \            - name: volume-cnfs' "$deploy_file"
sed -i -e '59 a \              mountPath: "/app"' "$deploy_file"
sed -i -e '60 a \          {{- end }}' "$deploy_file"

cat >>"$deploy_file" <<EOF
      {{- if or .Values.cnfs .Values.nas .Values.nfs }}
      volumes:
      {{- end }}
      {{- if .Values.cnfs }}
        - name: volume-cnfs
          persistentVolumeClaim:
            claimName: {{ .Values.cnfs }}
      {{- end }}
EOF

## set port
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

sed -i \
    -e '/livenessProbe/a \            initialDelaySeconds: 30' \
    -e '/readinessProbe/a \            initialDelaySeconds: 30' \
    "$deploy_file"
