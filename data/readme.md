### ./
说明：存放 deploy.sh 所需的数据文件，排除版本管理
权限：运维部门/管理者

### .acme.sh/
说明：使用 acme.sh 自动生产/更新 ssl 证书的程序和配置文件，例如 dns api

https://github.com/acmesh-official/acme.sh

### .aws/
说明：aws Access Key 管理配置文件机密
权限：运维部门/管理者

### .kube/
说明：k8s集群 机密配置文件
权限：运维部门/管理者

### project_conf/
说明：需要注入到各个 Git 项目的配置文件，例如 .env/config 等机密文件
权限：运维部门/管理者

### .ssh/
说明：gitlab-runner login 所有服务器需要的config ， ssh private key 等文件
权限：运维部门/管理者

### helm/
说明：各个业务 Git 项目基于 helm 自动发布部署到 k8s 集群的配置文件
权限：运维部门/管理者/研发部门 可配置

### .cloudflare.conf
说明：acme.sh 自动配置 cloudflare dns 的 config 文件
权限：运维部门/管理者

### .aliyun.dnsapi.conf
说明：acme.sh 自动配置 aliyun DNS api config file, [aliyun]
权限：运维部门/管理者

```
# .aliyun.dnsapi.conf example:
case "$1" in
# ~/acme.sh/account.conf.1
1)
    export Ali_Key="LTAIxxxxxxxxxxxxxxxxxxxxx"
    export Ali_Secret="yyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"
    export Ali_region='cn-hangzhou'
    ;;
# ~/acme.sh/account.conf.2
2)
    export Ali_Key="LTAIxxxxxxxxxxxxxxxxxxxxx"
    export Ali_Secret="yyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"
    export Ali_region='cn-hangzhou'
    ;;
esac
```

### .qcloud.dnspod.conf
说明：acme.sh 自动配置 qcloud/dnspod DNS api config file, [qcloud/dnspod]
权限：运维部门/管理者

### .python-gitlab.cfg
说明：python-gitlab config 文件，用于 deploy notify, 通过 gitlab API 获取 gitlab 服务器 项目/用户等信息
权限：运维部门/管理者

### gitlab-server/config.toml
说明：服务器开机自启动 gitlab-runner config 文件
权限：运维部门/管理者

### gitlab-server/gitlab-runner.service
说明：服务器开机自启动 gitlab-runner systemctl config 文件 （自定义路径/非默认配置）
权限：运维部门/管理者

### deploy.conf
说明：deploy.sh 的业务 git 项目配置文件
权限：运维部门/管理者/研发部门 可配置

### deploy.env
说明：deploy.sh 的机密配置文件
权限：运维部门/管理者

### microk8s 自定义配置
说明：若使用 microk8s，需要修改一下配置文件，文件路径：/var/snap/microk8s/current/args/containerd-template.toml
权限：运维部门/管理者

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