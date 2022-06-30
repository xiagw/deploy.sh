### 文件说明
gitops，密码/密钥/机密信息 （运维部门/管理者）

### .acme.sh/
自动更新证书配置/dns api/部署程序

https://github.com/acmesh-official/acme.sh


### .aws/
aws Access Key 管理配置文件机密（运维部门/管理者）

### .kube/
k8s集群 机密配置文件（运维部门/管理者）

### project_conf/
各个业务 Git 项目的配置 .env/config 等机密文件 （运维部门/管理者）

### .ssh/
gitlab-runner login 所有服务器需要的 ssh private key 文件（运维部门/管理者）

### helm/
各个业务 Git 项目基于 helm 自动发布部署到 k8s 集群的配置文件（运维部门/研发部门可配置）

### .cloudflare.conf
自动配置 cloudflare dns 的 config 文件

### .python-gitlab.cfg
config 文件 （python-gitlab），用于 deploy notify, 通过 gitlab API 获取 gitlab 服务器 项目/用户等信息

### .cloudflare.conf
DNS api config file, [cloudflare]

### .aliyun.dnsapi.conf
DNS api config file, [aliyun]

### .qcloud.dnspod.conf
DNS api config file, [qcloud/dnspod]

### gitlab-server/config.toml
自动启动 gitlab-runner config 文件

### gitlab-server/gitlab-runner.service
自动启动 gitlab-runner  systemctl config 文件 （自定义路径/非默认配置）

### deploy.conf
deploy.sh 的项目配置文件 （运维部门/研发部门可配置）

### deploy.env
deploy.sh 的秘密配置文件 （运维部门/管理者）

### microk8s 自定义配置
文件路径：/var/snap/microk8s/current/args/containerd-template.toml

修改内容：

  sandbox_image = "registry.cn-shenzhen.aliyuncs.com/namespace/repo:pause-3.1"

  [plugins."io.containerd.grpc.v1.cri".registry]

    # 'plugins."io.containerd.grpc.v1.cri".registry.mirrors' are namespace to mirror mapping for all namespaces.
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        endpoint = ["https://registry-1.docker.io", ]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:32000"]
        endpoint = ["http://localhost:32000"]
    [plugins."io.containerd.grpc.v1.cri".registry.configs]
      [plugins."io.containerd.grpc.v1.cri".registry.configs."registry.cn-shenzhen.aliyuncs.com".auth]
        username = "name001"
        password = 'password001'
      [plugins."io.containerd.grpc.v1.cri".registry.configs."registry.cn-shenzhen.aliyuncs.com".auth]
        username = "name002"
        password = 'password002'