# 在 K8s 中构建镜像（规划）

现状：`lib/build.sh` 已迁移到 `docker buildx bake`，`ensure_buildx_builder()` 用
`ENV_BUILDX_REMOTE_HOSTS`（ssh:// 数组）创建 docker-container driver 的多节点
builder `deploy-builder`，配合 registry cache（`cache-from/cache-to type=registry`）
跨节点复用 layer cache。

本文档记录两个 K8s 构建方案，供后续实现。两者都完整保留现有 bake HCL /
registry cache / 多平台能力，改动点集中在 `ensure_buildx_builder()`。

## 方案 1：buildx kubernetes driver（轻量）

buildx 直接在 K8s 里拉起 buildkit Pod 作为 builder 节点：

```bash
docker buildx create --driver kubernetes --name deploy-builder \
    --driver-opt namespace=buildkit,replicas=2,rootless=true \
    --bootstrap
```

- 前提：本机有可用的 kubeconfig（builder 节点信息存在 kubeconfig 指向的集群）
- 优点：零部署，buildx 自动管理 Pod 生命周期
- 缺点：Pod 重建后 buildkit 本地状态丢失，`RUN --mount=type=cache`
  （maven ~/.m2、go mod）缓存不持久，只能靠 registry layer cache 保底

## 方案 2：常驻 buildkitd + remote driver（推荐，终局形态）

在集群内部署 buildkitd Deployment/StatefulSet，挂 PVC 持久化
`/var/lib/buildkit`，buildx 用 remote driver 连接：

```yaml
# 关键片段：buildkitd StatefulSet
containers:
  - name: buildkitd
    image: moby/buildkit:latest
    args: ["--addr", "tcp://0.0.0.0:1234"]
    securityContext: { privileged: true }   # 或 rootless 镜像 + 相应配置
    volumeMounts:
      - { name: buildkit-state, mountPath: /var/lib/buildkit }
# Service: buildkitd.buildkit.svc:1234（生产建议 mTLS，见 buildkit 文档）
```

```bash
docker buildx create --driver remote --name deploy-builder \
    tcp://buildkitd.buildkit.svc:1234
```

- 优点：buildkit 状态持久化在 PVC，**layer cache 和 `--mount=type=cache`
  的 maven/go 依赖缓存都跨构建保留**；客户端只需 buildx，无需 docker daemon
- 缺点：需维护一个 Deployment + Service（+ TLS 证书）
- 多副本时可 `--append` 多个 endpoint，或按 platform 分节点（amd64/arm64）

## ensure_buildx_builder() 扩展设计

新增环境变量 `ENV_BUILDER_DRIVER`，默认保持现状：

```bash
ENV_BUILDER_DRIVER=docker-container   # 现状：ssh 远程机器数组
ENV_BUILDER_DRIVER=kubernetes         # 方案 1
ENV_BUILDER_DRIVER=remote             # 方案 2
ENV_BUILDER_REMOTE_URL=tcp://buildkitd.buildkit.svc:1234   # 方案 2 endpoint
```

`ensure_buildx_builder()` 按 driver 分支创建 builder，统一导出
`G_BUILDER="--builder deploy-builder"`，`build_image()` 不需要感知差异。

## CI 接入架构（GitLab + K8s）

两种部署形态，可共存、可分阶段演进：

### 形态 A：集群外独立服务器（现状延续，先用这个）

一台服务器装 gitlab-runner（shell executor）+ deploy.sh + docker/buildx 客户端。

- 构建可指向 ssh 机器（现状）或集群内 buildkitd（方案 2，打通网络即可）
- deploy.sh 的本地状态（`$G_DATA`：deploy.env、hash_saved、lock）天然持久
- 改动为零，只需网络能达 buildkitd Service（NodePort/LB/内网路由）

### 形态 B：全部进 K8s（gitlab-runner kubernetes executor）

注意：**gitlab-runner 不放进 deploy.sh 镜像**。职责分离：
gitlab-runner（Helm 安装）只负责拉起 job Pod；deploy.sh 打包成工具镜像，
作为 job 的 `image:`；构建通过 remote driver 连 buildkitd。

#### B-0 前置：安装 buildkitd（方案 2）

```bash
kubectl create namespace buildkit
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: buildkitd, namespace: buildkit }
spec:
  serviceName: buildkitd
  replicas: 1
  selector: { matchLabels: { app: buildkitd } }
  template:
    metadata: { labels: { app: buildkitd } }
    spec:
      containers:
        - name: buildkitd
          image: moby/buildkit:latest
          args: ["--addr", "tcp://0.0.0.0:1234"]
          securityContext: { privileged: true }
          ports: [{ containerPort: 1234 }]
          volumeMounts:
            - { name: buildkit-state, mountPath: /var/lib/buildkit }
  volumeClaimTemplates:
    - metadata: { name: buildkit-state }
      spec:
        accessModes: [ReadWriteOnce]
        resources: { requests: { storage: 100Gi } }
---
apiVersion: v1
kind: Service
metadata: { name: buildkitd, namespace: buildkit }
spec:
  selector: { app: buildkitd }
  ports: [{ port: 1234, targetPort: 1234 }]
YAML
```

#### B-1 deploy.sh 工具镜像

`docs/Dockerfile.deploy`（示例）：

```dockerfile
FROM debian:12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash git curl jq rsync openssh-client ca-certificates \
        docker.io docker-buildx kubectl \
    && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash \
    && rm -rf /var/lib/apt/lists/*
COPY . /opt/deploy.sh/
WORKDIR /opt/deploy.sh
ENTRYPOINT ["bash"]
```

```bash
docker buildx build -t ${ENV_DOCKER_REGISTRY}/deploy-sh:latest --push \
    -f docs/Dockerfile.deploy .
```

说明：
- 镜像内不需要 docker daemon，`docker.io` 只为 docker CLI + buildx 插件
- deploy.sh 位于 `/opt/deploy.sh`，则 `G_DATA=/opt/deploy.sh/data`——
  这个目录由 PVC 挂载（见 B-2），**不要 COPY data/ 进镜像**（含密钥）

#### B-2 状态 PVC（挂载 G_DATA）

```bash
kubectl create namespace gitlab-runner
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: deploy-data, namespace: gitlab-runner }
spec:
  # 多个 job Pod 并发挂载需要 RWX（NFS/CephFS/云盘 NAS）；
  # 若 StorageClass 只有 RWO，则 runner 需限制并发或固定节点
  accessModes: [ReadWriteMany]
  storageClassName: nfs-client   # 按集群实际情况修改
  resources: { requests: { storage: 5Gi } }
YAML
```

初始化数据（首次一次性，把现有服务器的 data/ 拷入 PVC）：

```bash
kubectl -n gitlab-runner run pvc-init --rm -it --image=busybox \
    --overrides='{"spec":{"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"deploy-data"}}],"containers":[{"name":"pvc-init","image":"busybox","stdin":true,"tty":true,"volumeMounts":[{"name":"d","mountPath":"/data"}]}]}}'
# 另开终端: kubectl cp data/ gitlab-runner/pvc-init:/data/
```

`deploy.env` 等含密钥文件也可改用 Secret 挂载覆盖：
`kubectl -n gitlab-runner create secret generic deploy-env --from-file=data/deploy.env`

#### B-3 Helm 安装 gitlab-runner（job Pod 挂 PVC）

`runner-values.yaml`：

```yaml
gitlabUrl: https://gitlab.example.com/
# GitLab 15.10+ 用 Runner Authentication Token（gitlab 界面创建 runner 后获取）
runnerToken: "glrt-xxxxxxxxxxxxxxxx"
rbac:
  create: true
runners:
  config: |
    [[runners]]
      executor = "kubernetes"
      [runners.kubernetes]
        namespace = "gitlab-runner"
        image = "registry.example.com/deploy-sh:latest"   # 默认 job 镜像
        privileged = false
        [[runners.kubernetes.volumes.pvc]]
          name = "deploy-data"
          mount_path = "/opt/deploy.sh/data"
        # deploy.env 用 Secret 时（与 PVC 二选一或叠加）：
        # [[runners.kubernetes.volumes.secret]]
        #   name = "deploy-env"
        #   mount_path = "/opt/deploy.sh/data-secret"
```

```bash
helm repo add gitlab https://charts.gitlab.io
helm upgrade --install gitlab-runner gitlab/gitlab-runner \
    -n gitlab-runner -f runner-values.yaml
```

kubeconfig 不用挂：job Pod 用 ServiceAccount，按需给 RBAC
（helm 部署目标 namespace 的读写权限）。

#### B-4 .gitlab-ci.yml 示例

```yaml
deploy:
  stage: deploy
  image: registry.example.com/deploy-sh:latest
  variables:
    ENV_BUILDER_DRIVER: remote
    ENV_BUILDER_REMOTE_URL: tcp://buildkitd.buildkit.svc:1234
  script:
    - bash /opt/deploy.sh/deploy.sh   # 无参数=自动模式（检测 CI 环境变量）
```

#### B-5 验证清单

- [ ] buildkitd Pod Running，`buildctl --addr tcp://... debug workers` 正常
- [ ] job Pod 内 `docker buildx create --driver remote ...` 可连通
- [ ] PVC 内 deploy.env 可读，hash_saved 跨 job 保留
- [ ] 二次构建命中 layer cache（buildkitd PVC）与 maven/go mount cache

### 演进路径建议

1. 先落地方案 2（buildkitd + PVC），形态 A 的服务器直连它——立即获得
   持久缓存，deploy.sh 侧只加 `ENV_BUILDER_DRIVER=remote`
2. 需要弹性/多 runner 时再做形态 B 的工具镜像和 Helm 部署
