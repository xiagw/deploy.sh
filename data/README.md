### ./
说明：存放 deploy.sh 所需的数据文件，不进入版本管理。使用Docker方式时，本目录作为数据目录挂载

权限：运维部门/管理者

### bin/
说明：可执行脚本/二进制文件，自动加入 PATH（如 deploy.custom.sh、sendEmail、pve.create.user.sh）

权限：运维部门/管理者

### logs/
说明：运行时日志目录（deploy.sh.log、*-build.log 等）

权限：运维部门/管理者

### docs/
说明：文档/需求记录等

权限：运维部门/管理者

### conf/
说明：运行时/项目配置文件
- namespace/project-name.json：单项目部署配置（`find_project_config` 使用）
- config.cfg、rsyncd.conf、aliyun.functions.json 等
- aliyun.functions.json：FC 函数模板，`cp conf/templates/aliyun.functions.json data/conf/` 后改占位符（NAS/VPC/端口等）。存在即使用；删除则回退内置最小模板

权限：运维部门/管理者/研发部门 可配置

### cache/
说明：运行时缓存（构建 hash 缓存、image_records 镜像记录、docker login 锁文件、base-bake.hcl 等），可安全清理

### .acme.sh/
说明：使用 acme.sh 自动生产/更新 ssl 证书的程序和配置文件，例如 dns api， 软链接到 ~/.acme.sh

官网：https://github.com/acmesh-official/acme.sh

### .aws/
说明：aws Access Key 管理配置文件机密。

权限：运维部门/管理者

### .kube/
说明：k8s集群 config.json 机密配置文件。
权限：运维部门/管理者

### overlay/
说明：需要由运维/管理部门覆盖到各个 Git 项目的配置文件，例如 .env/config 等机密文件。

权限：运维部门/管理者

### .ssh/
说明：gitlab-runner login 所有服务器需要的 ssh 配置文件等 ， ssh private key 等文件。

权限：运维部门/管理者

### helm/
说明：各个业务 Git 项目基于 helm 自动发布部署到 k8s 集群的配置文件。

权限：运维部门/管理者/研发部门 可配置

### glab-cli/ 或 ~/.config/glab-cli/
说明：glab（GitLab CLI）config 文件，通过 GitLab API 获取 gitlab 服务器 项目/用户等信息（替代 python-gitlab）

权限：运维部门/管理者

### gitlab-server/config.toml
说明：服务器开机自启动 gitlab-runner config 文件

权限：运维部门/管理者

### gitlab-server/gitlab-runner.service
说明：服务器开机自启动 gitlab-runner systemctl config 文件 （自定义路径/非默认配置）

权限：运维部门/管理者

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