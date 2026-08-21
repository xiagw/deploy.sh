# deploy.sh 执行计划与依赖分层（RUN 单数组）

> 描述 deploy.sh 的执行流程设计：必备步骤链、可选函数的真实依赖、以及
> 「RUN 单数组，位置即依赖顺序」的组装方式。本文档同时是 RUN 数组的依赖注释。
>
> 适用范围：`deploy.sh` + `lib/*.sh`（conf/、docs/ 等不适用）。

---

## 1. 演进背景

调度机制的三代设计：

| 版本 | 结构 | 问题 |
|---|---|---|
| v1 | `arg_flags` 关联数组（0/1 开关）+ 各函数内部自守卫 | 标志与执行双份数据；独立功能单独运行时误触发自动模式（`-r` 跑全流程） |
| v2 | `RUN_REPO`/`RUN_TASKS`/`RUN_STAGES`/`RUN_DEPLOY` 四个数组 + main 三个循环点 | 可选函数按数组整体放置，独立功能被单循环点连坐，无法按真实依赖提前 |
| v3（当前） | `RUN` 单数组，**位置即依赖顺序**；`parse_command_args` 解析后直接组装；main 退化为一个 for 循环 | — |

v3 要点：

- 数组位置 = 执行顺序 = 依赖顺序，由 `parse_command_args` 一次组装完成（无独立 `_run_build_plan` 函数）。
- 必备步骤（config_deploy_init 等）也作为数组条目，保证顺序是唯一事实来源。
- main 的正文退化为 `for fn in "${RUN[@]}"; do "$fn"; done`。
- `RUN_DEPLOY` 保留为 `stage_deploy` 的选型查询表（非循环数组）。

---

## 2. 必备步骤链（顺序固定）

以下步骤无条件进入 RUN，且相对顺序不可打乱（find_project_config 除外，见下）：

```
config_deploy_init  →  G_DATA/G_ENV、source deploy.env 加载 ENV_*、扩展 PATH
system_check        →  安装 git/curl/rsync 等基础工具、检测发行版
config_deploy_vars  →  G_REPO_* / G_NAMESPACE / G_IMAGE_TAG / G_IMAGE_NAME
                        （读 G_REPO_DIR 的 git 分支与 commit）
find_project_config →  G_CONF + PROJECT_BUILD_METHOD / PROJECT_DEPLOY_METHOD
                        （读 G_REPO_GROUP_PATH，生成/加载 data/conf/.../project.json）
                        ※ 条件步骤: 仅当计划含 stage_build / stage_deploy（含自动模式）时进入
system_proxy        →  按 ENV_HTTP_PROXY/ENV_SOCK_PROXY 设置代理环境变量（中国区）
kube_config_init    →  KUBECTL_OPT / HELM_OPT（读 G_NAMESPACE，找 kubeconfig）
system_clean_disk   →  磁盘空间不足时清理
system_install_tools→  按项目安装所需工具
config_deploy_setup →  SSH 密钥、$HOME 符号链接（.ssh/.acme.sh/.aws/.kube/.aliyun）、python-gitlab
config_build_env    →  G_DOCK / G_RUN / IS_CHINA（安装 docker/podman）
repo_inject_file    →  注入 conf/root、生成 Dockerfile.base/Dockerfile 到 G_REPO_DIR
```

链内强顺序约束（依据）：

- `config_deploy_vars` 必须在仓库准备（setup_git_branch）之后：`get_git_branch` 优先读 CI 变量，
  本地场景回退到 `git rev-parse`（repo.sh:447），分支切换必须先于该读取。
- `find_project_config`（若进入）必须在 `config_deploy_vars` 之后：读 `G_REPO_GROUP_PATH`。
  仅在计划含 stage_build（读 PROJECT_BUILD_METHOD，build.sh:382）或 stage_deploy
  （读 G_CONF hosts / PROJECT_DEPLOY_METHOD，deployment.sh:702/791）时进入；独立功能
  （-x/--clean-tags/-r 等）与测试跳过，避免无关配置阻断或产生模板残留告警。
- `kube_config_init` 必须在 `config_deploy_vars` 之后：读 `G_NAMESPACE`。
- `config_build_env` 计算 `IS_CHINA`，此前必须保持 unset：
  `_install_packages → _set_mirror`（common.sh:962）读 `IS_CHINA` 决定是否改写 apt 源。

---

## 3. 依赖分层图

```
config_deploy_init ─────────────────────────────────────────────┐
   │                                                           │
   ├── system_check                                             │
   │     ├── clean_old_tags          仅 ENV_*+skopeo【真独立，最早】│
   │     ├── kube_setup_terraform    仅 G_DATA/terraform【真独立，最早】│
   │     └── setup_git_repo/svn/branch 【必须早于 config_deploy_vars】│
   │                                                           ▼
   ├── config_deploy_vars ────────────────────────────────── G_REPO_* / G_NAMESPACE / G_IMAGE_*
   │     ├── generate_lang_dockerfile           依赖 G_REPO_DIR
   │     ├── detect_repo_language_and_build     依赖 G_REPO_DIR + G_IMAGE_*（须在注入前）
   │     └── find_project_config ──► system_proxy
   │           ├── copy_docker_image            中国区需代理
   │           └── kube_config_init ──► KUBECTL_OPT/HELM_OPT
   │                 ├── kube_create_storage_class   依赖 KUBECTL_OPT + G_NAMESPACE
   │                 ├── kube_create_pv_pvc          依赖 KUBECTL_OPT + G_NAMESPACE
   │                 ├── system_clean_disk / system_install_tools
   │                 └── config_deploy_setup ──► $HOME/.acme.sh 符号链接
   │                       ├── system_cert_renew     依赖 acme 账号文件（软依赖）
   │                       └── config_build_env ──► IS_CHINA
   │                             ├── build_base_image_select  依赖 IS_CHINA + ENV_DOCKER_*
   │                             └── repo_inject_file ──► G_REPO_DIR 注入
   │                                   └── stage_*（8 个阶段）──► handle_notify
```

---

## 4. 可选函数依赖表

| 函数 | 触发条件 | 真实依赖（代码证据） | 最早位置 |
|---|---|---|---|
| `setup_git_repo` | `-g` 或 `GITEA_ACTIONS=true` | config_deploy_init（ENV_GITEA_SERVER/PATH），自装 git | 链首；且须在 config_deploy_vars 前 |
| `setup_svn_repo` | `-s` | config_deploy_init，自装 svn | 链首 |
| `setup_git_branch` | `-b` 且无 `-g` | git + G_REPO_DIR | 链首；须在 config_deploy_vars 前 |
| `clean_old_tags` | `--clean-tags` | 仅 ENV_CLEAN_TAGS_* + skopeo（不自装） | config_deploy_init 后即可 |
| `kube_setup_terraform` | `-K` | 仅 G_DATA/terraform，自装 terraform（common.sh:836） | config_deploy_init 后即可 |
| `copy_docker_image` | `-c` | ENV_DOCKER_MIRROR + skopeo + system_proxy（中国区代理） | system_proxy 后 |
| `system_cert_renew` | `-r` | $HOME/.acme.sh 账号文件 + config_deploy_setup（软依赖，仅当 G_DATA/.acme.sh 存在才建链接，config.sh:254） | config_deploy_setup 后 |
| `generate_lang_dockerfile` | `--gen-dockerfile` | G_REPO_DIR + detect_repo_language | config_deploy_vars 后 |
| `detect_repo_language_and_build` | `--build-buildpacks` | G_REPO_DIR + G_IMAGE_NAME/TAG + pack | config_deploy_vars 后；须在 repo_inject_file 前（构建语义） |
| `kube_create_storage_class` | `--create-storage-class` | KUBECTL_OPT（kube_config_init）+ G_NAMESPACE + ENV_NAS_URL | kube_config_init 后 |
| `kube_create_pv_pvc` | `-P` | KUBECTL_OPT + G_NAMESPACE | kube_config_init 后 |
| `build_base_image_select` | `-x` | ENV_DOCKER_* + G_PATH/conf + **IS_CHINA**（kubernetes.sh:398 读 `IS_CHINA:-true`） | config_build_env 后 |

> 注：`build_base_image_select` 不依赖 `find_project_config`，但依赖 `config_build_env` 设置的
> `IS_CHINA`（提前会令 `${IS_CHINA:-true}` 默认命中中国镜像源，见第 7 节），故只能放到
> config_build_env 之后，无法更早。

---

## 5. RUN 单数组方案

### 5.1 组装位置

`parse_command_args` 负责「解析 + 组装」两件事，无独立 `_run_build_plan` 函数：

```
parse_command_args "$@"     # while 解析参数 → 设 arg_* 布尔/参数 + RUN_DEPLOY
                            # 循环后直接组装 RUN（位置即依赖顺序）
```

- 解析只设 `arg_*` 标量（约 13 个布尔）与参数，不再填分派数组。
- 组装只读这些 `arg_*` 与 `RUN_DEPLOY`，逐条按依赖顺序追加函数名。
- `RUN_DEPLOY` 由解析阶段 `RUN_DEPLOY+=(deploy_k8s)` 填充，仅作 stage_deploy 选型查询表。

### 5.2 自动模式

组装开始时预计算 `auto_mode`：对全部 `arg_*` 触发条件与 `RUN_DEPLOY` 做一次判定，
用户未请求任何功能（如仅 `-w` 等修饰参数、或完全无参数）时 `auto_mode=true`。
组装结束若 `auto_mode` 为 true，追加全部 8 个阶段；`find_project_config` 的进入条件
也依赖它（auto 模式含 stage_build/stage_deploy，需要项目配置）。

- Gitea Actions 的 `setup_git_repo` 属环境驱动，**不计入**用户请求，不会抑制自动模式。
- 独立功能（`-r`/`-K`/`--clean-tags` 等）单独执行时不触发自动模式。

### 5.3 main 流程

```
main:
    set -Eeo pipefail; SECONDS=0
    run_project_ci
    unset 残留变量
    declare -a RUN=() RUN_DEPLOY=()
    parse_command_args "$@"          # 解析 + 组装 RUN
    for module in ...; do source ... done    # 加载 lib 模块
    _msg anchor 开始
    for fn in "${RUN[@]}"; do "$fn"; done    # 唯一执行循环（RUN 最后一项为 handle_notify）
    _msg anchor 完成
    return "${G_DEPLOY_RESULT:-0}"
```

---

## 6. RUN 数组顺序总表（代码即文档）

```
config_deploy_init
system_check
clean_old_tags                # arg_clean_tags（真独立，最早）
kube_setup_terraform          # arg_create_k8s（真独立，最早）
setup_git_repo                # arg_git_clone_url 或 GITEA_ACTIONS（后者不计入 requested）
setup_svn_repo                # arg_svn_checkout_url
setup_git_branch              # arg_git_clone_branch 且无 arg_git_clone_url
config_deploy_vars
generate_lang_dockerfile      # arg_gen_dockerfile
detect_repo_language_and_build# arg_build_buildpacks（须在 repo_inject_file 前）
find_project_config           # 条件: arg_build 或 RUN_DEPLOY 非空 或 auto_mode
system_proxy
copy_docker_image             # arg_src（中国区需代理）
kube_config_init
kube_create_storage_class     # arg_create_storage_class（依赖 KUBECTL_OPT）
kube_create_pv_pvc            # arg_sub_path（依赖 KUBECTL_OPT）
system_clean_disk
system_install_tools
config_deploy_setup
system_cert_renew             # arg_renew_cert（依赖 $HOME/.acme.sh 链接）
config_build_env
build_base_image_select       # arg_build_base（依赖 IS_CHINA）
repo_inject_file
stage_code_quality            # arg_code_quality
stage_code_style              # arg_code_style
stage_unit_test               # arg_test_unit
stage_build                   # arg_build
stage_deploy                  # RUN_DEPLOY 非空；自动模式下走 detect_deployment_method
stage_functional_test         # arg_test_func
stage_security_zap            # arg_security_zap
stage_security_vulmap         # arg_security_vulmap
handle_notify                 # 恒执行（末尾）
```

自动模式（auto_mode=true）时 `stage_code_quality .. stage_security_vulmap` 全部加入。

---

## 7. 关键约束说明

1. **仓库准备必须早于 config_deploy_vars**：`get_git_branch`/`get_git_commit_sha` 在本地
   回退读 `G_REPO_DIR` 的 git（repo.sh:447/463），`setup_git_branch` 先切换分支。
2. **kube_create_\* 必须晚于 kube_config_init**：直接用 `$KUBECTL_OPT`（kubernetes.sh:197/255）。
3. **build_base_image_select 必须晚于 config_build_env**：读 `IS_CHINA`（kubernetes.sh:398），
   而 IS_CHINA 仅由 config_build_env 计算（deploy.sh:321），且其前须保持 unset（_set_mirror 依赖）。
4. **generate_lang_dockerfile / buildpacks 必须早于 repo_inject_file**：先按源码生成 Dockerfile /
   构建镜像，再注入环境配置，避免注入内容被构建进镜像。
5. **copy_docker_image 必须晚于 system_proxy**：中国区 skopeo 拉取需代理。
6. **system_cert_renew 必须晚于 config_deploy_setup**：账号文件位于 `$HOME/.acme.sh`，
   config_deploy_setup 仅在 `G_DATA/.acme.sh` 存在时建链接（config.sh:254），软依赖。
7. **find_project_config 为条件步骤**：仅计划含 stage_build / stage_deploy（含自动模式）时进入；
   独立功能与测试跳过，避免无关配置阻断或产生模板残留告警。
   `stage_build` 读 `PROJECT_BUILD_METHOD`（build.sh:382），`stage_deploy` 读
   `G_CONF` hosts / `PROJECT_DEPLOY_METHOD`（deployment.sh:702/791），故这两条路径必须加载。
