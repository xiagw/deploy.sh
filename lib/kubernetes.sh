#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# Kubernetes management module for deployment script
# Handles Kubernetes cluster operations using Terraform

# kubectl config 配置初始化
kube_config_init() {
  local ns="$1" kubectl_conf
  _install_kubectl
  _install_helm
  ## 当 deploy.env 已配置则返回
  if [[ -n "${KUBECTL_OPT:-}" ]] && [[ -n "${HELM_OPT:-}" ]]; then
    return 0
  fi

  # 按优先级依次检查配置文件路径
  local config_paths=(
    "$HOME/.kube/${ns}.config"
    "$HOME/.kube/${ns}/config"
    "$HOME/.config/kube/${ns}.config"
    "$HOME/.config/kube/${ns}/config"
    "$G_DATA/.kube/${ns}.config"
    "$G_DATA/.kube/${ns}/config"
    "$G_DATA/.kube/config"
  )

  for path in "${config_paths[@]}"; do
    if [[ -f "$path" ]]; then
      kubectl_conf="$path"
      break
    fi
  done

  if [[ -n "$kubectl_conf" ]]; then
    KUBECTL_OPT="kubectl --kubeconfig $kubectl_conf"
    HELM_OPT="helm --kubeconfig $kubectl_conf"
  else
    KUBECTL_OPT="kubectl"
    HELM_OPT="helm"
  fi
  # export KUBECTL_OPT HELM_OPT
  echo "$KUBECTL_OPT $HELM_OPT" >/dev/null
}

# Create Helm chart with customized configuration
# @param $1 helm_chart_path The path where to create the Helm chart
create_helm_chart() {
  local helm_chart_path="$1" protocol port port2 pvc_name mount_path dockerfile

  # 从 Dockerfile 读取端口配置
  dockerfile="${G_REPO_DIR}/Dockerfile"
  if [ -f "${dockerfile}" ]; then
    read -ra ports <<<"$(grep -i "^EXPOSE" "${dockerfile}" | cut -d' ' -f2-)"
    if [ "${#ports[@]}" -ge 1 ]; then
      port="${ports[0]}"
      port2="${ports[1]}"
    fi
    # while IFS= read -r vol; do
    #   mount_path="$(echo "$vol" | tr '/' '-' | sed 's/^-//')"
    # done < <(grep -i "^VOLUME" "${dockerfile}" | tr -d '[]"' | cut -d' ' -f2-)
  fi
  pvc_name="${ENV_HELM_VALUES_CNFS:-pvc-www}"
  mount_path="${ENV_HELM_VALUES_MOUNT_PATH:-/app2}"
  protocol="${protocol:-tcp}"
  port="${port:-8080}"
  port2="${port2:-8081}"

  # Create helm chart
  helm create "$helm_chart_path"
  _msg "helm create $helm_chart_path" >>"$G_LOG"

  # Configuration files to modify
  local file_values="$helm_chart_path/values.yaml"
  local file_svc="$helm_chart_path/templates/service.yaml"
  local file_deploy="$helm_chart_path/templates/deployment.yaml"
  ## remove serviceaccount.yaml
  # rm -f "$helm_chart_path/templates/serviceaccount.yaml"

  # Modify values.yaml
  sed -i -e "s@port: 80@port: ${port}@" "$file_values"
  [ -n "${port2}" ] && sed -i "/port: ${port}/ a \  port2: ${port2}" "$file_values"

  # Disable serviceAccount
  sed -i -e "/create: true/s/true/false/" "$file_values"
  ## resources limit
  # sed -i -e "/^resources: {}/s//resources:/" "$file_values"
  # sed -i -e "/^resources:/ a \    cpu: 500m" "$file_values"
  # sed -i -e "/^resources:/ a \  requests:" "$file_values"

  # sed -i -e '/autoscaling:/,$ s/enabled: false/enabled: true/' "$file_values"
  sed -i -e '/autoscaling:/,$ s/maxReplicas: 100/maxReplicas: 9/' "$file_values"

  # Configure volumes
  sed -i -e "/volumes: \[\]/s//volumes:/" "$file_values"
  sed -i -e "/volumes:/ a \      claimName: ${pvc_name}" "$file_values"
  sed -i -e "/volumes:/ a \    persistentVolumeClaim:" "$file_values"
  sed -i -e "/volumes:/ a \  - name: volume-cnfs" "$file_values"

  # Configure volumeMounts
  sed -i -e "/volumeMounts: \[\]/s//volumeMounts:/" "$file_values"
  sed -i -e "/volumeMounts:/ a \    mountPath: \"${mount_path}\"" "$file_values"
  sed -i -e "/volumeMounts:/ a \  - name: volume-cnfs" "$file_values"

  ## set livenessProbe, spring delay 30s
  sed -i \
    -e '/livenessProbe/ a \  initialDelaySeconds: 30' \
    -e '/readinessProbe/a \  initialDelaySeconds: 30' \
    "$file_values"
  if [[ "${protocol}" == 'tcp' ]]; then
    sed -i \
      -e "s/httpGet:/#httpGet:/" \
      -e "/httpGet:/ a \  tcpSocket:" \
      -e "s@\ \ \ \ path: /@#     path: /@g" \
      -e "s/port: http/port: ${port}/" \
      "$file_values"
  else
    sed -i -e "s@port: http@port: ${port}@g" "$file_values"
  fi

  # Modify service.yaml
  sed -i -e "s@targetPort: http@targetPort: {{ .Values.service.port }}@" "$file_svc"
  sed -i -e '/name: http$/ a \    {{- end }}' "$file_svc"
  sed -i -e '/name: http$/ a \      name: http2' "$file_svc"
  sed -i -e '/name: http$/ a \      protocol: TCP' "$file_svc"
  sed -i -e '/name: http$/ a \      targetPort: {{ .Values.service.port2 }}' "$file_svc"
  sed -i -e '/name: http$/ a \    - port: {{ .Values.service.port2 }}' "$file_svc"
  sed -i -e '/name: http$/ a \    {{- if .Values.service.port2 }}' "$file_svc"

  # Modify deployment.yaml
  sed -i -e '/  protocol: TCP/ a \            {{- end }}' "$file_deploy"
  sed -i -e '/  protocol: TCP/ a \              containerPort: {{ .Values.service.port2 }}' "$file_deploy"
  sed -i -e '/  protocol: TCP/ a \            - name: http2' "$file_deploy"
  sed -i -e '/  protocol: TCP/ a \            {{- if .Values.service.port2 }}' "$file_deploy"
  sed -i -e '/name: http2/ a \              protocol: TCP' "$file_deploy"

  # Configure DNS
  cat <<EOF >>"$file_deploy"
      dnsConfig:
        options:
        - name: ndots
          value: "2"
EOF

  # sed -i -e "/serviceAccountName/s/^/#/" "$file_deploy"
}

# Setup Kubernetes cluster using Terraform
# This function is independent and non-blocking for the main process
kube_setup_terraform() {
  local terraform_dir="${G_DATA}/terraform"
  [[ -d "$terraform_dir" ]] || return 0
  _install_terraform

  _msg step "[PaaS] create k8s cluster"
  cd "$terraform_dir" || return 1

  if terraform init -input=false && terraform apply -auto-approve; then
    echo "Kubernetes cluster created successfully"
  else
    _msg error "Failed to create Kubernetes cluster"
    return 1
  fi
}

# Create CNFS storage class and related resources
# @param $1 namespace The namespace to create resources in
kube_create_storage_class() {
  local cnfs_name="cnfs01"
  local sc_name="alicloud-cnfs-nas"
  local namespace="${G_NAMESPACE}"
  local nas_url="${ENV_NAS_URL}"

  if [ -z "$nas_url" ]; then
    _msg error "ENV_NAS_URL is required but not set"
    return 1
  fi

  _msg step "[k8s] Creating CNFS storage class resources"

  # Check if CNFS exists
  if ! $KUBECTL_OPT get cnfs "$cnfs_name" &>/dev/null; then
    # Create ContainerNetworkFileSystem
    $KUBECTL_OPT apply -f - <<EOF
apiVersion: storage.alibabacloud.com/v1beta1
kind: ContainerNetworkFileSystem
metadata:
  name: $cnfs_name
spec:
  description: "cnfs"
  type: nas
  reclaimPolicy: Retain
  parameters:
    server: $nas_url
EOF
  fi
  # Check if storageclasses exists
  if ! $KUBECTL_OPT get sc "$sc_name" &>/dev/null; then
    # Create StorageClass
    $KUBECTL_OPT apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $sc_name
mountOptions:
  - vers=3,nolock,proto=tcp,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport
parameters:
  volumeAs: subpath
  containerNetworkFileSystem: $cnfs_name
  path: "/"
provisioner: nasplugin.csi.alibabacloud.com
reclaimPolicy: Retain
allowVolumeExpansion: true
EOF
  fi
}

# Create PV and PVC for a specific subpath, or ensure PVC exists
# @param $1 namespace The namespace to create resources in
# @param $2 subpath The NAS subpath to use (optional)
kube_create_pv_pvc() {
  local subpath="$1" namespace="${2:-$G_NAMESPACE}" pvc_name cnfs_name
  # Remove pvc- prefix if it exists in the input
  subpath="${subpath#pvc-}"
  pvc_name="pvc-${subpath}" pv_name="pv-${subpath}-${namespace}"
  cnfs_name="cnfs-01" sc_name="alicloud-cnfs-nas"

  _msg step "[k8s] Creating PVC [$pvc_name] in namespace [$namespace]"

  # Check if PVC exists
  if ! $KUBECTL_OPT get pv "$pv_name" &>/dev/null; then
    $KUBECTL_OPT apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $pv_name
spec:
  accessModes:
  - ReadWriteMany
  capacity:
    storage: 50Gi
  csi:
    driver: nasplugin.csi.alibabacloud.com
    fsType: nfs
    volumeAttributes:
      containerNetworkFileSystem: $cnfs_name
      mountProtocol: nfs
      path: /$subpath
      volumeAs: subpath
      volumeCapacity: "true"
    volumeHandle: $pv_name
  mountOptions:
  - vers=3,nolock,proto=tcp,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $sc_name
  volumeMode: Filesystem
EOF
  fi

  # Create PVC using the template
  if ! $KUBECTL_OPT -n "$namespace" get pvc "$pvc_name" &>/dev/null; then
    $KUBECTL_OPT apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $pvc_name
  namespace: $namespace
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 50Gi
  storageClassName: $sc_name
  volumeMode: Filesystem
  volumeName: $pv_name
EOF
  fi
}

# Build base Docker images for the project
# @param $1 image_tag The tag of the base image to build
build_base_image() {
  local tag="$1" registry base_tag cmd
  registry=$(awk -F= '/^ENV_DOCKER_MIRROR=/ {print $2}' "${G_ENV}" | tr -d "'")
  base_tag="${registry}/${tag}-base"
  cmd=$(command -v docker || command -v podman || echo docker)
  cmd_opt=(
    "$cmd"
    build
    --pull
    --push
    --progress=plain
    --platform "linux/amd64,linux/arm64"
    --build-arg CHANGE_SOURCE=true
    --build-arg IN_CHINA=true
    --build-arg HTTP_PROXY="${http_proxy-}"
    --build-arg HTTPS_PROXY="${http_proxy-}"
  )

  case "$tag" in
  php:*)
    cmd_opt+=(
      --build-arg PHP_VERSION="${tag#*:}"
      -f "${G_PATH}/conf/dockerfile/Dockerfile.base.${tag%:*}"
    )
    ;;
  redis:*)
    cmd_opt+=(
      -f "${G_PATH}/conf/dockerfile/Dockerfile.base.${tag%:*}"
    )
    ;;
  nginx:*)
    cmd_opt+=(
      -f "${G_PATH}/conf/dockerfile/Dockerfile.base.${tag%:*}"
    )
    ;;
  mysql:5*)
    cmd_opt+=(
      --build-arg MIRROR="${registry}/"
      --build-arg MYSQL_VERSION="${tag#*:}"
      -f "${G_PATH}/conf/dockerfile/Dockerfile.base.${tag%:*}"
    )
    ;;
  mysql:*)
    cmd_opt+=(
      --build-arg MYSQL_VERSION="${tag#*:}"
      -f "${G_PATH}/conf/dockerfile/Dockerfile.base.${tag%:*}"
    )
    ;;
  amazoncorretto:*)
    cmd_opt+=(
      --build-arg MVN_PROFILE="base"
      --build-arg JDK_VERSION="${tag#*:}"
      -f "${G_PATH}/conf/dockerfile/Dockerfile.base.java"
    )
    ;;
  node:*)
    cmd_opt+=(
      --build-arg NODE_VERSION="${tag#*:}"
      -f "${G_PATH}/conf/dockerfile/Dockerfile.base.${tag%:*}"
    )
    ;;
  esac
  cmd_opt+=(--tag "${base_tag}")

  # https://docs.docker.com/build/building/multi-platform/#build-multi-platform-images
  if ! ls /proc/sys/fs/binfmt_misc/qemu-aarch64; then
    ${cmd} run --privileged --rm tonistiigi/binfmt --install all
  fi

  "${cmd_opt[@]}" "${G_PATH}/conf/dockerfile/"
}

# Build selected base images
# @param $@ Optional specific image tags to build
select_image_tags() {
  local all_tags=() tags=()

  all_tags=(
    "php:5.6" "php:7.1" "php:7.3" "php:7.4" "php:8.1" "php:8.2" "php:8.3" "php:8.4"
    "mysql:5.6" "mysql:5.7" "mysql:8.0" "mysql:8.4" "mysql:9.0"
    "amazoncorretto:8" "amazoncorretto:17" "amazoncorretto:21" "amazoncorretto:23"
    "node:18" "node:20" "node:21" "node:22"
    "redis:latest"
    "nginx:stable-alpine"
  )

  readarray -t tags < <(echo "${all_tags[@]}" | sed 's/\ /\n/g' | fzf -m --header="Use TAB to select multiple items, ENTER to confirm")

  for i in "${tags[@]}"; do
    build_base_image "$i"
  done
}
