# 计划：任务调度与部署分发优化（deploy.sh 658 行之后）

## 背景与意图

`deploy.sh` 是 GitLab pipeline 各 job 共用的脚本，三种使用方式：

1. **auto（默认）**：不带参数，全系列任务按固定顺序执行。
2. **spec（分 job）**：GitLab 每个 job 带单一参数（如 `-u` / `-k` / `-R`），只跑该 job 的任务。
3. **debug（单 job 调试）**：`-d` 加单参数，如 `-d -u`，只跑指定任务并开启 `set -x`。

当前机制：`arg_flags` 关联数组记录各任务开关，`all_zero` 判定 auto/spec，任务按阶段顺序逐个守卫执行。

## 现状事实（代码行为，非评价）

- `parse_command_args` 中 deploy 参数**双写**：`arg_flags["deploy_xxx"]=1` 和 `deploy_method=deploy_xxx`（deploy.sh:230-235）。
- auto 模式下所有 `arg_flags` 置 1，但 `deploy_method` 保持为空（deploy.sh:290-294）。
- 阶段 5 判定：统计 `deploy_*` 开关之和 > 0 **或** `all_zero`，然后 `handle_deploy "${deploy_method:-}" ...`（deploy.sh:707-715）。
- `handle_deploy` 收到空方法时调用 `detect_deployment_method`（按 helm → Dockerfile → compose → hosts → 默认 rsync 的优先级链）探测单一方法（lib/deployment.sh:451-559, 563-602）。
- 因此**任何情况下实际只执行一个 deploy 方法**；`deploy_method` 只在 spec 模式被显式参数设置。

## 问题清单

### P1-1 关联数组迭代顺序随机
`for key in "${!arg_flags[@]}"`（deploy.sh:664）对关联数组顺序无保证，spec 模式列出的任务每次运行顺序可能不同，job 日志间不可对比。→ 需要固定顺序。

### P1-2 deploy 判定冗余
`deploy_sum -gt 0 || $all_zero`（deploy.sh:713）中，auto 模式已把所有 `deploy_*` 置 1，`deploy_sum` 必 >0，`|| $all_zero` 是死条件。可删，不影响行为。

### P1-3 静默 last-wins
`-k -y` 同传时 `deploy_method` 被后一个参数覆盖（deploy.sh:230-235），`deploy_sum` 又 >0，最终只部署后一个方法且**无任何提示**。分 job 工具中最容易踩的坑。

### P1-4 单一来源
同一意图（"用哪种方法部署"）存了两份：`arg_flags["deploy_*"]` 与 `deploy_method`。容易不一致。

### P2-5 输出条理
- spec 列表显示内部 key（`deploy_k8s`），不如 CLI 参数（`-k`）直观。
- 列表用裸 `echo`，不走 `_msg`，无统一时间/级别前缀。
- 各阶段无进度输出，长 job 只有 BEGIN 和 END。

## 决策点：是否支持同一次运行多目标部署？

用户问题：一次同时部署到单机 / k8s / rsync，有可能吗？

- 需求真实存在（灰度、CDN+源站、多环境并行），但成熟产品建模为**每环境/每目标一个 job** 或 **方法+目标矩阵**，不是"一次强行全跑"。
- 每个 deploy_* 有独占前置条件（k8s 可用、compose 文件、hosts 配置、ftp 变量），同一仓库天然只满足少数方法。
- 部分成功/失败的状态聚合与回滚语义复杂，`set -e` 下难以表达。

**决定：本次不做多方法同跑**。多目标走 GitLab 多 job（同一仓库 `deploy-k8s` job 跑 `-k`，`deploy-rsync` job 跑 `-y`）。单次运行保持单一方法，仅把静默 last-wins 改为显式行为。

不为此提前铺"目标列表"抽象（规则 2：最简单实现；规则 7：不为假设的复杂度做架构）。

## 实施方案

### 阶段 1：输出条理化（低风险、独立可先做）

**文件**: `deploy.sh`

1. 任务列表用固定顺序数组（与阶段注释一致：code_quality → code_style → test_unit → build_all → deploy_* → test_func → security_zap → security_vulmap），替代裸 assoc 迭代。
2. key → 显示文本映射（`deploy_k8s` → `-k/--deploy-k8s` 等），列表改走 `_msg`。
3. 阶段 1-7 各加一行 `_msg step "stage N: <name>"`，与 job 日志开头的 `[detect]` 风格一致（lib/deployment.sh:458 已有 `_msg step` 先例）。

**验证**: spec 模式任务列表顺序稳定；job 日志能看出阶段进度。

### 阶段 2：deploy 判定收编（核心改动）

**文件**: `deploy.sh`

1. 删除 `|| $all_zero` 死条件。
2. `deploy_method` 从 `arg_flags` **在阶段 5 派生**，替代 parse 时双写：
   - 遍历 `deploy_*` 开关，收集启用的键。
   - 0 个 → 不走部署（现状不变）。
   - 1 个 → 该键即方法。
   - 多个 → `_msg warn` 明确"检测到多个部署方式，仅执行 X；多目标部署请走 GitLab 多 job"，然后执行第一个（或在严格模式报错，见下）。
3. 排除 auto 模式：auto 时所有 deploy 开关为 1，仍走原 `detect_deployment_method` 探测链路，不误触发多重判定。

**状态**: ✅ **已完成**（2026-08-12）。`deploy_method` 改为从 `deploy_display` 顺序表在阶段 4 派生（R-3）；多方法 warn + 取顺序首个；`deploy_sum` 改顺序表统计，`STAGE_TOTAL` 与阶段 4 的 `|| $all_zero` 死条件已删。

**验证**: `-k` / `-k -y` / `--dry` / 无参数自动四种场景，deploy 方法与提示符合预期。

### 阶段 3（决策后可选）：多参数同传策略二选一

- **A. warn + 执行最后一个**：贴近现状、零破坏，仅在日志明示。
- **B. error 退出**：更严格，防手滑；多目标需求明确走多 job。
- 倾向 **A**（规则 3：不动能跑的东西；B 只在确有误用反馈时上）。

### 明确不做

- 不改 `handle_deploy` 签名为目标数组。
- 不新增"多方法并行/聚合退出码"。
- 不碰 EXIT_MAIN 提前收尾逻辑——经复核它是 dry-run/优雅停止语义，`set -e` 已覆盖真实失败，非本次问题。

## 验证方式

- 全部改动文件过 `bash -n <file>` 与 `shellcheck -S warning <file>`（零输出、exit 0）。
- 手动场景回归：
  1. 无参数（auto 全系列）
  2. `-u` 单跑（spec，仅测试）
  3. `-d -u` debug 单跑
  4. `-k -y` 同传（显式提示 + 单一执行）
  5. `--dry` 预览
  6. 多跑几次确认列表顺序稳定
- 对比 git diff，确保阶段注释与列表顺序一致。

## 工作量估算

- 阶段 1: 约 1 小时
- 阶段 2: 约 1-2 小时
- 阶段 3: 约 0.5 小时