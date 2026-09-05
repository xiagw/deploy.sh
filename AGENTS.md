# AGENTS.md

deploy.sh 部署系统开发约定。

## 核心范围

本仓库是「单入口 + 模块库」结构的 CI/CD 部署系统。**核心代码仅三处**，总体评估、修改、测试都聚焦于此：

- `deploy.sh`：主入口，负责参数解析、功能标志、模块加载、CI/CD 流程编排
- `lib/*.sh`：功能模块，按 deploy.sh 的加载顺序即 `common → config → system → repo → test → analysis → style → build → deployment → kubernetes → notify`
- `conf/`：部署模板与示例（Dockerfile.*、deploy.env、templates/、conf/root/ 内的目标机器脚本），供 deploy.sh 及各模块引用

以下目录是独立工具、模板或运行数据，**不做总体评估，默认不评审、不主动修改**：

- `bin/`：独立运维脚本（backup/ddns/gitea/gitlab/mysql/openwrt/ops/pve/wireguard/weixin/zentao），不经过 deploy.sh 流程
- `cloud/`：各云厂商 CLI 封装与 Terraform（aliyun/aws/huawei/tencent/terraform），独立体系
- `ansible/`：Ansible playbook 与 roles
- `docs/`：文档与临时示例脚本（docs/eda、docs/pxe、docs/utils）
- `data/`：运行时数据（deploy.env 实际值、日志、项目配置），已 gitignore，不入评审

## 命名规范

- 变量前缀（全局共享，文档见 deploy.sh main 注释）:
  - `G_*`：跨函数/跨模块共享的全局变量
  - `ENV_*`：来自 deploy.env 的环境配置
  - `arg_*`：命令行参数
  - `CI_*` / `GITHUB_*`：CI 平台外部注入变量
  - 其余一律 `local`，不得裸写全局变量
- 模块前缀按域统一，命令靠前:
  - 部署模块用 `deploy_*`（`deploy_to_kubernetes` / `deploy_via_rsync_ssh`）
  - 构建模块用 `build_*`（`build_image` 等内部构建函数）
  - 阶段入口用 `stage_*`（`stage_build` / `stage_deploy` / `stage_unit_test`），自打印 `_msg stage` 横幅并自守卫
  - 探测用 `detect_*`（`detect_repo_language` / `detect_deployment_method`）
  - 可用性校验用 `check_*`（`check_docker_available` / `check_k8s_available`）
