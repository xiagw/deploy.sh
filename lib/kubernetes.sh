#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2154
#
# Kubernetes management module for deployment script
# Handles Kubernetes cluster operations using Terraform

kube_config_init() {
    # 初始化 kubectl config
  local ns="${G_NAMESPACE}" kubectl_conf
  _install_kubectl
  _install_helm
  ## 工具选择：本机有命令直接用（快），没有则 docker run 容器化（免安装）
  ## 容器化时以相同绝对路径挂载 $HOME/.kube 与 $G_DATA，保证 --kubeconfig 路径在容器内一致
  local kubectl_cmd helm_cmd
  if command -v kubectl &>/dev/null; then
    kubectl_cmd="kubectl"
  else
    kubectl_cmd="docker run --rm -i -v ${HOME}/.kube:${HOME}/.kube -v ${G_DATA}:${G_DATA} bitnami/kubectl:latest"
  fi
  if command -v helm &>/dev/null; then
    helm_cmd="helm"
  else
    helm_cmd="docker run --rm -i -v ${HOME}/.kube:${HOME}/.kube -v ${G_DATA}:${G_DATA} alpine/helm:latest"
  fi
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
    KUBECTL_OPT="${kubectl_cmd} --kubeconfig $kubectl_conf"
    HELM_OPT="${helm_cmd} --kubeconfig $kubectl_conf"
  else
    KUBECTL_OPT="${kubectl_cmd}"
    HELM_OPT="${helm_cmd}"
  fi
  # export KUBECTL_OPT HELM_OPT
  echo "$KUBECTL_OPT $HELM_OPT" >/dev/null
}

create_helm_chart() {
    # 生成带自定义配置的 Helm chart
    # @param $1 helm_chart_path The path where to create the Helm chart
  local helm_chart_path="$1" protocol port port2 pvc_name mount_path dockerfile

  # 从 Dockerfile 读取端口配置
  dockerfile="${G_REPO_DIR}/Dockerfile"
  if [ -f "${dockerfile}" ]; then
    ## EXPOSE 行含 $ 变量时跳过（构建时才展开，源文件无法读取实际端口）
    local expose_line
    expose_line="$(grep -i "^EXPOSE" "${dockerfile}" | cut -d' ' -f2- || true)"
    if [[ -n "$expose_line" && "$expose_line" != *'$'* ]]; then
      read -ra ports <<<"$expose_line"
      if [ "${#ports[@]}" -ge 1 ]; then
        port="${ports[0]}"
        port2="${ports[1]}"
      fi
    fi
  fi
  pvc_name="${ENV_HELM_VALUES_PVC:-pvc-www}"
  mount_path="${ENV_HELM_PVC_MOUNT_PATH:-/data}"
  protocol="${protocol:-tcp}"
  port="${port:-8080}"
  port2="${port2:-8081}"

  # Create helm chart
  helm create "$helm_chart_path"

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

  ## set livenessProbe, spring delay 60s
  sed -i \
    -e '/livenessProbe/ a \  initialDelaySeconds: 60' \
    -e '/readinessProbe/a \  initialDelaySeconds: 60' \
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

  ## Modify resources
  sed -i -e '/^resources: {}/c\resources:\n  requests:\n    cpu: 10m\n    memory: 8Mi\n  limits:\n    cpu: 2\n    memory: 4Gi' "$file_values"

  # Configure DNS
  cat <<EOF >>"$file_deploy"
      dnsConfig:
        options:
        - name: ndots
          value: "2"
EOF

  # sed -i -e "/serviceAccountName/s/^/#/" "$file_deploy"
}

kube_setup_terraform() {
    # 用 Terraform 搭建 k8s 集群
    # This function is independent and non-blocking for the main process
  ## RUN 单数组成员（-K/--create-k8s 触发，parse 组装），无守卫直接执行
  local terraform_dir="${G_DATA}/terraform"
  [[ -d "$terraform_dir" ]] || exit 0
  if ${G_DRY_RUN:-false}; then
    _msg note "[dry-run] kube_setup_terraform:"
    _msg note "  cd ${terraform_dir} && terraform init -input=false && terraform apply -auto-approve"
    exit 0
  fi
  _install_terraform

  _msg task "Creating k8s cluster"
  cd "$terraform_dir" || exit 1
  ## 本机有 terraform 直接用（快），否则容器化（免安装）
  local tf_cmd
  if command -v terraform &>/dev/null; then
    tf_cmd="terraform"
  else
    tf_cmd="docker run --rm -i -v ${G_DATA}/terraform:/workspace -w /workspace hashicorp/terraform:latest"
  fi

  if $tf_cmd init -input=false && $tf_cmd apply -auto-approve; then
    echo "Kubernetes cluster created successfully"
  else
    _msg error "Failed to create Kubernetes cluster"
    exit 1
  fi
  exit 0
}

kube_create_storage_class() {
    # 创建 CNFS StorageClass 及相关资源
    # @param $1 namespace The namespace to create resources in
  ## RUN 单数组成员（--create-storage-class 触发，parse 组装），无守卫直接执行
  local cnfs_name="cnfs01"
  local sc_name="alicloud-cnfs-nas"
  local namespace="${G_NAMESPACE}"
  local nas_url="${ENV_NAS_URL}"

  if [ -z "$nas_url" ]; then
    _msg error "ENV_NAS_URL is required but not set"
    exit 1
  fi

  _msg task "Creating CNFS storage class resources"

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
  exit $?
}

kube_create_pv_pvc() {
    # 为指定子路径创建 PV/PVC（已存在则复用）
    # @param $1 namespace The namespace to create resources in
    # @param $2 subpath The NAS subpath to use (optional)
  ## RUN 单数组成员（-P/--kube-pvc 触发，parse 组装并必填校验 arg_sub_path）
  ## 守卫: 依赖 kube_config_init 设置的 KUBECTL_OPT；防御性校验 arg_sub_path
  [[ -n "${arg_sub_path:-}" ]] || return 0
  local subpath="${arg_sub_path}" namespace="${arg_pvc_namespace:-${G_NAMESPACE:-default}}" pvc_name pv_name cnfs_name sc_name
  # Remove pvc- prefix if it exists in the input
  subpath="${subpath#pvc-}"
  pvc_name="pvc-${subpath}" pv_name="pv-${subpath}-${namespace}"
  cnfs_name="cnfs01" sc_name="alicloud-cnfs-nas"

  _msg task "Creating PVC [$pvc_name] in namespace [$namespace]"

  if ${G_DRY_RUN:-false}; then
    _msg note "[dry-run] kube_create_pv_pvc:"
    _msg note "  ${KUBECTL_OPT} apply -f - <<EOF (PV ${pv_name} / PVC ${pvc_name} / storageClass ${sc_name})"
    exit 0
  fi

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
  exit $?
}

build_base_image() {
    # 构建项目的基础镜像
    # @param $1 image_tag The tag of the base image to build (e.g. mysql:8.0, amazoncorretto:17)
    # 环境变量 G_BAKE_PLATFORMS：逗号分隔的构建平台，默认 linux/amd64,linux/arm64；
    #   CI 只出单架构时设为 linux/amd64，省掉 QEMU 模拟（arm64 构建慢数倍）
  local image_tag="$1" mirror registry proxy_url bake_target tag_left tag_right
  local platforms platform_list p
  local bake_file="${G_DATA}/cache/base-bake.hcl"
  mkdir -p "${G_DATA}/cache"
  mirror="${ENV_DOCKER_MIRROR:+${ENV_DOCKER_MIRROR%/}/}"
  registry="${ENV_DOCKER_REGISTRY:+${ENV_DOCKER_REGISTRY%/}/}"
  proxy_url="${ENV_HTTP_PROXY:-}"
  tag_left="${image_tag%:*}"
  tag_right="${image_tag#*:}"
  bake_target="${tag_left/amazoncorretto/java}"

  ## 平台列表转 HCL 数组元素：linux/amd64,linux/arm64 -> "linux/amd64", "linux/arm64"
  platforms="${G_BAKE_PLATFORMS:-linux/amd64,linux/arm64}"
  platform_list=""
  for p in ${platforms//,/ }; do
    platform_list+="\"${p}\", "
  done
  platform_list="${platform_list%, }"

  ## 按语言生成完整 args，与 docker-bake.hcl 各 target 保持一致
  local extra_args=""
  case "${bake_target}" in
  java)
    extra_args="
        RUN_IMAGE = \"amazoncorretto\"
        RUN_TAG = \"${tag_right}\"
        MVN_PROFILE = \"base\"
        MVN_DEBUG = \"${MVN_DEBUG:-false}\"
        APP_PORTS = \"8080 8081\""
    ;;
  php)
    ## 所有版本统一 ubuntu:24.04 + ondrej PPA（该 PPA 已为 7.1/7.3/7.4/8.1 回填 PHP2Shell 补丁）
    dk_file="${G_PATH}/conf/Dockerfile.php"
    extra_args="
        PHP_VERSION = \"${tag_right}\"
        APP_PORTS = \"80 9000\""
    ;;
  node)
    extra_args="
        RUN_IMAGE = \"node\"
        RUN_TAG = \"${tag_right}-slim\"
        ONBUILD_CHOWN = \"1000:1000\"
        ONBUILD_COPY_SRC = \".\"
        ONBUILD_COPY_DEST = \"/app/\""
    ;;
  python)
    extra_args="
        RUN_IMAGE = \"python\"
        RUN_TAG = \"${tag_right}-slim\"
        APP_CMD = \"\""
    ;;
  mysql)
    extra_args="
        RUN_IMAGE = \"mysql\"
        RUN_TAG = \"${tag_right}\"
        APP_WORKDIR = \"/\"
        APP_PORTS = \"3306\"
        APP_VOLUME = \"/var/lib/mysql\"
        APP_CMD = \"\"
        MYSQL_REPLICATION = \"single\""
    ;;
  redis)
    extra_args="
        RUN_IMAGE = \"redis\"
        RUN_TAG = \"${tag_right}\"
        APP_WORKDIR = \"/data\"
        APP_PORTS = \"6379\"
        APP_VOLUME = \"/data\"
        APP_CMD = \"\""
    ;;
  nginx)
    extra_args="
        RUN_IMAGE = \"nginx\"
        RUN_TAG = \"${tag_right}\"
        APP_PORTS = \"80 443\"
        APP_CMD = \"\""
    local dk_file="${G_PATH}/conf/Dockerfile.nginx"
    if ! ${G_DRY_RUN:-false}; then
        cp -vf "${G_PATH}/conf/Dockerfile.single" "${dk_file}"
        sed -i -e "/^CMD/ s@^@#@" "$dk_file"
    fi
    ;;
  *)
    extra_args="
        RUN_TAG = \"${tag_right}\""
    ;;
  esac
  if [ -n "${proxy_url}" ]; then
    extra_args+="
        HTTP_PROXY = \"${proxy_url}\"
        HTTPS_PROXY = \"${proxy_url}\""
  fi

  cat >"${bake_file}" <<EOF
target "default" {
    context = "${G_PATH}/conf"
    dockerfile = "${dk_file:-Dockerfile.single}"
    platforms = [${platform_list}]
    args = {
        IS_CHINA = "${IS_CHINA:-true}"
        MIRROR = "${mirror}"${extra_args}
    }
    tags = ["${registry}${image_tag}-base"]
    output = ["type=image,push=true"]
}
EOF

  if ${G_DRY_RUN:-false}; then
    _msg note "[dry-run] build_base_image (${image_tag}):"
    _msg note "  bake file: ${bake_file}"
    if docker buildx version >/dev/null 2>&1; then
      docker buildx bake --file "${bake_file}" --progress=quiet --print
    else
      cat "${bake_file}"
    fi
    rm -f "${dk_file}" 2>/dev/null || true
    rm -f "${bake_file}" 2>/dev/null || true
    return
  fi

  # https://docs.docker.com/build/building/multi-platform/#build-multi-platform-images
  ## macOS 用 Docker Desktop，QEMU 已内置在 VM 中，无需 binfmt 注册
  if [[ "$(uname -s)" == "Darwin" ]]; then
    :
  elif ! ls /proc/sys/fs/binfmt_misc/qemu-aarch64 >/dev/null 2>&1; then
    local image
    if "${IS_CHINA:-false}"; then
      image="docker.m.daocloud.io/tonistiigi/binfmt:latest"
    else
      image="tonistiigi/binfmt:latest"
    fi
    docker run --privileged --rm "${image}" --install all || return 1
  fi

  docker buildx bake --file "${bake_file}" --progress=plain
  rm -f "${dk_file}" 2>/dev/null || true
  rm -f "${bake_file}" 2>/dev/null || true
}

build_base_image_tags() {
    # 输出可构建的基础镜像 tag（每行一个），读取 conf/base-images.txt
    # 本地 `-x/-X` 与 CI workflow 共用同一份列表，避免三处各维护一份
  local file="${G_PATH}/conf/base-images.txt" line
  if [[ ! -f "${file}" ]]; then
    _msg error "缺少 ${file}" >&2
    return 1
  fi
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -n "${line}" ]] && printf '%s\n' "${line}"
  done <"${file}"
}

build_base_image_pick() {
    # 输出选中的基础镜像 tag（每行一个）
    # 有直传参数（deploy.sh -x/-X TAG...）时直接用，否则 fzf 多选；
    # 两种情况都对照 conf/base-images.txt 校验，避免拼错 tag 构建出错误镜像
  local all tag tags=()
  if [[ "${#arg_images[@]}" -gt 0 ]]; then
    tags=("${arg_images[@]}")
  else
    readarray -t tags < <(build_base_image_tags | fzf -m --header="TAB 多选，ENTER 确认")
  fi
  [[ "${#tags[@]}" -eq 0 ]] && return 0
  all="$(build_base_image_tags)"
  for tag in "${tags[@]}"; do
    if ! grep -qxF -- "${tag}" <<<"${all}"; then
      _msg error "未知镜像：${tag}（可用列表见 conf/base-images.txt）" >&2
      return 1
    fi
  done
  printf '%s\n' "${tags[@]}"
}

build_base_image_select() {
    # 构建选定的基础镜像（本机 docker buildx bake）
  ## RUN 单数组成员（-x/--build-base 触发，parse 组装），无守卫直接执行
  local i picked tags=()

  dry_run_note "select base image tags"

  picked="$(build_base_image_pick)" || exit 1
  if [[ -z "${picked//[[:space:]]/}" ]]; then
    _msg warning "未选择任何镜像，已取消"
    exit 0
  fi
  readarray -t tags <<<"${picked}"

  for i in "${tags[@]}"; do
    build_base_image "$i"
  done
  exit $?
}

build_base_image_ci_select() {
    # 触发 GitHub Actions 的 base-images.yml 在 CI 构建并推送
    # 依赖：gh 已登录（gh auth login）、当前仓库为 xiagw/deploy.sh、
    #      仓库已配置 DOCKERHUB_USERNAME / DOCKERHUB_TOKEN secret
  ## RUN 单数组成员（-X/--build-base-ci 触发，parse 组装），无守卫直接执行
  local images picked tags=()

  dry_run_note "select base image tags for GitHub Actions"

  if ! command -v gh >/dev/null 2>&1; then
    _msg error "gh CLI 未安装：brew install gh && gh auth login"
    return 1
  fi

  picked="$(build_base_image_pick)" || exit 1
  if [[ -z "${picked//[[:space:]]/}" ]]; then
    _msg warning "未选择任何镜像，已取消"
    exit 0
  fi
  readarray -t tags <<<"${picked}"

  ## workflow 的 images 输入用逗号分隔
  images="$(IFS=,; echo "${tags[*]}")"
  _msg task "触发 GitHub Actions 构建：${images}"
  if ${G_DRY_RUN:-false}; then
    _msg note "[dry-run] gh workflow run base-images.yml -f images=${images}"
    exit 0
  fi
  if ! gh workflow run base-images.yml -f "images=${images}"; then
    _msg error "触发失败：检查 gh auth status，以及 base-images.yml 是否已在默认分支"
    exit 1
  fi
  _msg info "查看进度：gh run watch"
  exit 0
}
