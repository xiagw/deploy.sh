# deploy.sh 开发指南

本指南说明如何为 deploy.sh 添加/修改功能。核心代码仅三处，改动应聚焦于此。

## 核心结构

- `deploy.sh`：主入口，负责参数解析、功能标志、模块加载、CI/CD 流程编排
- `lib/*.sh`：功能模块，按加载顺序 `common → config → system → repo → test → analysis → style → build → deployment → kubernetes → notify`
- `conf/`：部署模板与示例（`Dockerfile.*`、`deploy.env`、`templates/`、`conf/root/` 内目标机器脚本）

不在总体评估范围（默认不评审、不主动改）：`bin/`（独立运维脚本）、`cloud/`（云厂商 CLI/Terraform）、`ansible/`、`docs/`、`data/`（运行时数据，已 gitignore）。

## 命名规范

- 全局共享变量前缀：
  - `G_*`：跨函数/跨模块共享的全局变量
  - `ENV_*`：来自 `deploy.env` 的环境配置
  - `arg_*`：命令行参数
  - `CI_*` / `GITHUB_*`：CI 平台外部注入变量
  - 其余一律 `local`，不得裸写全局变量
- 模块前缀按域统一，命令靠前：
  - 部署模块 `deploy_*`（`deploy_to_kubernetes` / `deploy_via_rsync_ssh`）
  - 构建模块 `build_*`
  - 阶段入口 `stage_*`（`stage_build` / `stage_deploy` / `stage_test`），自打印 `_msg stage` 横幅并自守卫
  - 探测 `detect_*`（`detect_repo_language` / `detect_deployment_method`）
  - 可用性校验 `check_*`（`check_docker_available` / `check_k8s_available`）

## 开发约定

- 不保留向后兼容：过时的直接删，不加兼容层、不写 migration、不留 fallback。
- 选能满足当前需求的最简单实现，不做预防性抽象、不多此一举的配置层。
- 系统分层长：先跑通一个最小的端到端版本，再往上加东西；不为了未完成的复杂度拆掉能跑的东西。
- 组件模块化，关注点分离。
- 优先用成熟、有人维护的库，无明确理由不自己重写；先翻项目已有依赖能做什么，再考虑加新包。
- 架构决策往长了做，不接受"先这样以后再换"的临时方案；先看成熟产品怎么解决同一问题，用已验证的模式。

## Shell 脚本硬性要求

- 任何 shell 改动在交版前必须通过：`bash -n <file>` 与 `shellcheck -S warning <file>`（两者零输出/退出码 0）。
- 禁止 `if [ $? -eq 0 ]` 判断命令结果：用 `result=$(cmd); local ret=$?; if [ $ret -eq 0 ]; then`。绝不允许在赋值和 `$?` 判断之间插入其它语句（shellcheck SC2181）。
- 本机 /usr/local/bin 下 `gdate`、`gsed`、`gawk`、`greadlink`、`gtimeout` 等为 GNU 版；需要 GNU 扩展语法（`date -d`、`sed -r`、`readlink -f`）时优先 g 前缀版本。禁止硬编码 `date` / `sed` 并用 GNU 专属参数（macOS BSD 版会报错）。

## 提交规范

- commit message 同时含 title + body。
- 标题必须带 emoji 前缀：`✨` 新功能、`🐛` 修 bug、`♻️` 重构、`📝` 文档、`🚀` 部署/发布。
- 涉及 issue 时 body 写 `Close #xxx`。

## 流程

1. 阅读相关 `lib/*.sh` 模块与 `conf/` 模板，理解现有模式。
2. 按命名规范新增/修改函数，遵循加载顺序。
   - 主脚本各子函数的**上下依赖/调用顺序**见 [architecture.md §3（主流程 main）](./architecture.md)。
   - `config_repo_vars` / `kube_config_init` / `config_build_env` 等位置勿动——后序步骤依赖其设置的变量。
3. 跑 `bash -n` 与 `shellcheck -S warning`。
4. 用 `deploy.sh --dry`（dry-run）验证流程编排与生成的 `docker-bake.hcl` / 注入文件。
5. 提交（bot 身份 + emoji 规范）。
