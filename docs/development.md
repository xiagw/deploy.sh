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
  - 阶段入口 `stage_*`（`stage_build` / `stage_deploy` / `stage_unit_test`），自打印 `_msg stage` 横幅并自守卫
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
- **`set -Eeo pipefail` 下的错误处理陷阱**：`var=$(curl|grep|jq ...)` 这类赋值，命令失败时 errexit 会先杀脚本，后面的 `if [ -z "$var" ]` 错误分支与回退永不执行（死码）。触发面：grep 无匹配、jq 解析失败、API 限流/不可达、空仓库。修复约定：
  1. 命令替换必须兜底：`var=$(cmd ...) || true`，或放进 `if !`。
  2. `&&` 列表末尾加 `|| true`，避免 errexit 豁免仅在 `||` 前失效。
  3. `_msg` 无错误时一律 `>&2`（检测链 stdout 只能有业务返回值）。
  4. 布尔门控用 `[[ ... == true ]]`，不把字符串当命令。
  5. 失败即 fail-fast：`|| { _msg error; return 1; }`，不吞码、不后台化。

## 提交规范

- commit message 同时含 title + body。
- 标题必须带 emoji 前缀：`✨` 新功能、`🐛` 修 bug、`♻️` 重构、`📝` 文档、`🚀` 部署/发布。
- 涉及 issue 时 body 写 `Close #xxx`。

## 基础镜像的 CI

`.github/workflows/base-images.yml` 负责构建 `conf/Dockerfile.single` 的 29 个基础镜像并推送到 Docker Hub。

**为什么不在 push 时自动构建**：`conf/Dockerfile.single` 是所有镜像共享的模板，改一行就可能让全部镜像失效，从 diff 无法判断影响面；全量是 29 个 job × 2 架构（arm64 走 QEMU），2–4 小时。所以不挂 `push` 触发，改为显式调用。

**为什么不用 commit message 关键字**：GitHub 的 `on:` 读不到 commit message（GitLab 的 `rules:if` 可以），只能在 job 内解析，workflow 照样启动并留下一条空 run；关键字还是隐式契约，漏写不会有任何提示。

**触发方式**（两个入口，镜像名单统一读 `conf/base-images.txt`）：

```bash
# 交互式：fzf 多选后触发 GitHub Actions
./deploy.sh -X

# 直传镜像，跳过 fzf（脚本/测试用；-x 本地构建同理）
./deploy.sh -X mysql:8.0 redis:7-alpine

# 脚本化：直接调 gh
gh workflow run base-images.yml -f images=mysql:8.0
gh workflow run base-images.yml -f images=php:8.4,redis:7-alpine -f platforms=linux/amd64
gh workflow run base-images.yml -f images=all
gh run watch
```

`-x`/`-X` 的直传参数会先对照 `conf/base-images.txt` 校验，写错直接报错退出；`--dry` 只打印将要执行的 `gh workflow run`，不会真的触发。

- `images` 必填，空值直接报错；只有 `all` 表示全量。
- 默认平台 `linux/amd64,linux/arm64`，只出单架构时传 `platforms=linux/amd64`。
- 名单会对照 `conf/base-images.txt` 校验，写错立即失败；该文件同时是 `deploy.sh -x`（本地构建）的 fzf 列表来源。
- 推送 tag 规则：`<DOCKERHUB_USERNAME>/<image>:<version>-base`，如 `xiagw/php:8.4-base`。
- 依赖仓库 secret：`DOCKERHUB_USERNAME`、`DOCKERHUB_TOKEN`（PAT，不要用账号密码）。`ensure-repos` job 会自动创建缺失的仓库，因此 PAT 需要 **Repo Read, Write, Delete**（含 manage repositories）；只给 Read & Write 时建仓库会 403。
- 缺仓库时 push 报 `denied: requested access to the resource is denied`，先看 `ensure-repos` 的日志。
- 构建参数由 `build_base_image` 生成，CI 与本地不维护第二份映射；平台通过 `G_BAKE_PLATFORMS` 传入。

## 流程

1. 阅读相关 `lib/*.sh` 模块与 `conf/` 模板，理解现有模式。
2. 按命名规范新增/修改函数，遵循加载顺序。
   - 主脚本各子函数的**上下依赖/调用顺序**见 [architecture.md §3（主流程 main）](./architecture.md)。
   - `config_repo_vars` / `kube_config_init` / `config_build_env` 等位置勿动——后序步骤依赖其设置的变量。
3. 跑 `bash -n` 与 `shellcheck -S warning`。
4. 用 `deploy.sh --dry`（dry-run）验证流程编排与生成的 `docker-bake.hcl` / 覆盖文件。
5. 提交（bot 身份 + emoji 规范）。
