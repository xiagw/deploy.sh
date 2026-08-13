# AGENTS.md

deploy.sh 部署系统开发约定。

## 命名规范

- 变量前缀（全局共享，文档见 deploy.sh main 注释）:
  - `G_*`：跨函数/跨模块共享的全局变量
  - `ENV_*`：来自 deploy.env 的环境配置
  - `arg_*`：命令行参数
  - `CI_*` / `GITHUB_*`：CI 平台注入变量
  - 其余一律 `local`，不得裸写全局变量
- 模块前缀按域统一，命令靠前:
  - 部署模块用 `deploy_*`（`deploy_to_kubernetes` / `deploy_via_rsync_ssh`）
  - 构建模块用 `build_*`（`build_all` / `build_image`）
  - 入口分派用 `handle_*`（`handle_deploy` / `handle_test` / `handle_notify`）
  - 探测用 `detect_*`（`detect_repo_language` / `detect_deployment_method`）
  - 可用性校验用 `check_*`（`check_docker_available` / `check_k8s_available`）
  - 模块内部私有助手用 `_` 前缀（`_project_hosts` / `_project_oss_dest`）
- 禁止裸字符串调 `_msg`，必须带级别（`_msg note/task/warn/error`）。
