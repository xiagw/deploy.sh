# AGENTS.md

This file provides guidance to the AI agent when working with code in this repository.

Bash wrapper around the Alibaba Cloud CLI (plugin mode, aliyun >= 3.4). Entry: `bash main.sh [-p <profile>] [-r <region>] <service> <operation> [args...]`. UI text is Chinese.

## Aliyun CLI 3.4+ parameter rules (critical)

- All API calls go through `call_aliyun_api` (base.sh), which appends `--profile` and auto-plugin-install flags. Never call `aliyun` directly in service modules.
- Plugin CLI renamed params that clash with reserved/global flags: use `--biz-region-id` (not `--region-id`/`--RegionId`) and `--biz-key-pair-name` (not `--key-pair-name`). Other commands may have similar `--biz-*` renames — verify with `aliyun <product> <command> --help` before adding/changing any call.
- Use new plugin-style kebab-case commands, not legacy PascalCase API names: `ram get-account-alias` (not `ram GetAccountAlias`), `sts get-caller-identity`, `ecs describe-key-pairs`. Exception: ACK uses REST style (`cs GET /clusters`); CR personal edition uses REST style (`cr GET /namespace --version 2016-06-07 --force`); `dds` (MongoDB) and `eci` use PascalCase API mode (no plugin).
- Central services ignore the user region: `cas` calls must use `--region cn-hangzhou`; `alidns` calls must use `--region public` (cn-hangzhou also fails). `ram`/`cdn` need no region.
- `--region` (global flag) selects the endpoint; `--biz-region-id` is the API's RegionId business param. Regional services often need both.

## Conventions

- Subcommands are verb-first: `get`, `add`, `set`, `del`, plus suffixed forms like `add-key`, `get-perm`, `del-vsw`. Do not introduce noun-first names (`key-add`).
- All yes/no confirmations must accept y/Y/yes case-insensitively: reuse `confirm_action` (base.sh) instead of inline `read`.
- Commands with optional args fall back to fzf interactive selection (`select_with_fzf`); auto-select when only one candidate.
- Variables `profile` and `region` are set in `main.sh` and used implicitly (not passed) by service functions.
- Logs go to `<repo-root>/data/logs/aliyun/<profile>/<region>/`, cached data to `data/cache/<profile>/<region>/<service>/` (utils.sh). Do not revert to the old `data/<profile>/<region>/logs/` layout.
- New service module: copy an existing simple module (e.g. `nat.sh`), implement `handle_<service>_commands`, add a case in `main.sh`.

## Testing

- No test suite. Verify with `bash -n <file>` then live calls, e.g. `bash main.sh -p flyh5 -r cn-hangzhou ecs get-key`. Append `</dev/null` and a timeout for non-interactive runs; `get-all` and `dns get` can exceed 2 minutes.
- `aliyun --cli-dry-run ...` prints the request without calling the API — use it to validate param names.

## Gotchas

- RAM permissions have two scopes: account-level (`ram list-policies-for-user`) and resource-group-level (`resourcemanager ListPolicyAttachments --PrincipalType IMSUser --PrincipalName "<user>@<alias>.onaliyun.com"`). The console shows both; querying only the first looks "empty".
- macOS: `main.sh` needs `greadlink` (Homebrew coreutils); `stat -c` in `load_module` is GNU-style.
- macOS 兼容：脚本内禁用裸 `stat -c`/`date -d`（GNU 语法），须探测 `gstat`/`gdate` 回退；`${TMPDIR:-/tmp}` 要去尾斜杠再拼文件（macOS TMPDIR 带 `/` 会拼出 `//`）。ack.sh 的 `run_once` 中已有 `runtime_dir` 的现成模式可参考。


## ACK 扩缩容 / OpenKruise WorkloadSpread（ack.sh 机制，勿凭直觉改）

- **PHP 部署**（deployment 名含 `php`，如 fly-php71/81/83）绑定了 OpenKruise **WorkloadSpread 双 subset**：
  - `fixed-resource-pool`：真实节点，`maxReplicas` 由 helm chart **静态写死（当前 = 4）**，不随节点数/cordon 状态动态变化；works 精确到「扩到 4 台后多出的 pod 注入 elastic」
  - `elastic-resource-pool`：virtual-kubelet（ECI，按量计费），无上限
  - 分配不感知节点 cordon/可用性：只认静态 maxReplicas，即使真实节点更多也固定扩到 4 后进 virtual —— **勿按可用节点数"修正"**
  - `maxReplicas` 支持 IntOrString（整数/百分比/不设），百分比按 **workload replicas** 计算（非节点数）
- **缩容顺序**：WorkloadSpread 用 `deletion-cost(-100)` 保证 **elastic subset 的 pod 优先删除** —— 主缩容回基线时，超出 fixed 容量的 elastic pod 被顺带清空，正常回到基线后不应再有 virtual pod
- **闲时回收**（把 virtual pod 迁回真实节点降费）：只有 fixed 有空位（`WorkloadSpread status.missingReplicas > 0 或 -1`）时 `rollout restart` 才有意义——重建时 webhook 按 missingReplicas 顺序注入 fixed subset，旧 elastic pod 被替换；`missingReplicas = 0`（fixed 满）时 restart 无效（新 pod 仍落 elastic），此时唯一手段是缩容
- **回收使用 `rollout restart`，不要用 `kubectl delete pod`**：Deployment RollingUpdate（集群实测 maxSurge=25%/maxUnavailable=25%）先创建新 pod 等就绪再删旧，单副本也**无断流**（用户实测 + K8s 文档核准）；delete 是先删后建、无滚动保护，会断流。曾误用 delete + 曾加 patch(maxUnavailable)（与 chart 实际值相同，幂等无用）——均已回退/移除
- **副本语义（用户生产模型）**：扩容上限 `--max` 缺省 = 真实节点数（每节点 1 副本朴素预期，资源有限时打满再加无意义）；**缩容终点 = 基线 `--min`（扩容前副本数，通常 1 单 pod、PHP 特殊 2），不被节点数拦截** —— 禁止把 node_fixed 用于缩容门槛（曾误用导致「副本 3/节点 5 时缩不回 1」的死锁）
- 曾踩坑实录（改动时对照，忌重犯）：① 误认为 restart 单副本也断流 → 实为先建后删无断流；② 误用 node_fixed 挡缩容 → 死锁；③ 误加 missing=0 跳过回收 → virtual 永不清理；④ 曾把函数拆成 scale-php 特例封装 → 已合并为 scale-pod 按部署名自动识别 PHP（step=2/min=2/max=0/PHP 阈值因子），scale-php 命令已删除
