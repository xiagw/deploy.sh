# 消息输出系统重设计（docs/demo）

## 1. 现状问题归因

以你这次 `--dry` 真实输出为证，乱来自 4 处：

| # | 现象 | 根因 |
|---|------|------|
| 1 | `2026-08-11 20:57:25 - set proxy environment variables - [0h0m0s]` 这种长前缀满屏 | `time` 类型带完整日期，却被用了 55 处当"操作进行中"标记，而非真正锚点 |
| 2 | `[14] vulmap scan`、`[15] END.` 中间冒出的步数 | 全局 `STEP` 计数器泄漏进 `time` 行，序号无意义 |
| 3 | `PP_SONAR: false`、`Found existing Dockerfile, skipping injection.`、docker/helm 输出混在一起 | 裸 `echo` 与提示消息无统一缩进/前缀，看不出层级 |
| 4 | `stage 3/6: build` vs `tasks execution completed` vs BEGIN/END 三种视觉风格 | 时间戳策略不统一（有的带日期、有的带 HH:MM:SS、有的啥都不带） |

`_msg` 实际用法统计（全库）：

```
error 101  green 73  time 55  step 52  warn 30  purple 22
info 19  stepend 12  warning 14  yellow 7  stage 6  success 13  ...
```

核心矛盾：**`time`（带完整日期）做的是 `step`（操作标记）的活**；BEGIN/END 真正的锚点语义被稀释了。

## 2. 设计目标

1. 每条消息一眼能看出"我是什么"：流程锚点 / 阶段 / 动作 / 说明 / 状态。
2. 全库只有**一种时间戳策略**，不再混两套。
3. 层级通过缩进表达：stage 之下的动作有缩进，pipeline 级不缩进。
4. 命令原始输出与提示消息可区分。
5. 平时不刷屏；需要完整时间时看 `G_LOG`（`log` 类型已有完整时间戳）。

## 3. 新类型与格式规范

`_msg` 收敛为 9 种类型，`STEP` 全局计数器删除。

| 类型 | 用途 | 格式 | 颜色 |
|------|------|------|------|
| `anchor` | BEGIN / END / 流程里程碑，唯一带时间戳的位置 | `[HH:MM:SS] ▸ BEGIN`<br>`[HH:MM:SS] ✓ completed in 0h0m1s` | 白加粗 |
| `stage` | 阶段横幅，**序号自动计算**，右侧带**阶段差值** | 上下 `━` 分隔线 + `▶ STAGE n/N · 标题  +diff` | cyan |
| `task` | 执行动作（原 `step` + 原 53 处 `time`） | `  · msg`（剥除 `[tag]`） | 默认 |
| `note` | 说明 / 面包屑 / 结果判断（原 `info`、`stepend`、PP_*） | `  ⋯ msg` | 灰 |
| `ok` | 成功状态 | `✓ msg` | 绿色 |
| `warn` | 警告 | `! msg` | 黄色 |
| `error` | 失败 | `✗ msg` | 红色 |
| `log` | 日志文件（不动） | 原样 | - |
| `question` | 交互提问（不动) | 原样 | - |

规则：
- 时间戳只在 `anchor` 出现；stage 横幅只有 `+diff`（距上一个 stage 的耗时差）和 `[total]` 累计值，没有日期。
- `task`/`note` 统一 2 空格缩进 + `·`/`⋯` 前缀；不缩进的行只有 anchor / 横幅 / 状态行。
- 命令原始输出（docker buildx bake JSON、docker/helm 命令回显）**原样透传不修饰**，前面用一条 `task` 或 `note` 说明它是什么。
- 剥离 `[tag]` 逻辑保留在 `task` 打印时（调用点保留 tag 作 grep 锚点）。

### 3.5 阶段序号自动计算（已定）

`main` 不再手写 `stage 1/6`。机制：

1. 全局 `STAGE_NUM` / `STAGE_TOTAL` / `STAGE_PREV_SEC` 由 `_msg stage` 内部维护。
2. `main` 在任务执行前调用一次 `count_enabled_stages()`：按固定的阶段规格数组（quality/style、test_unit、build_all、deploy、test_func、security）统计**本次真正启用的阶段数**，写入 `STAGE_TOTAL`。
3. 各阶段执行处只写 `_msg stage "标题"`，`_msg stage` 自动 `((++STAGE_NUM))` 并打印 `STAGE n/N`。
4. diff 计算：`SECONDS - STAGE_PREV_SEC`，打印后重置 `STAGE_PREV_SEC=SECONDS`。

效果：spec 模式只跑 1 个阶段也显示 `STAGE 1/1`，auto 显示 `1/6…6/6`，流程代码不出现任何数字字面量。

### 3.6 补充规范（新增）

**A. 消息措辞**
- 单条消息**不混中英文**；沿用现有语言习惯（运维提示已中文的保持中文），新写统一用英文动词短语。
- task 用动名词（`detecting language`、`building docker image`），note 用陈述句（`Dockerfile found, skipped`），stage 标题用名词（`unit test`、`security scan`）。
- 句尾不带句号；`!`/`✗` 等符号之后空一格再跟消息。

**B. 排版**
- stage 横幅前后各留 1 个空行；task/note 之间不空行。
- task 与右侧 note 列尝试对齐：`printf '%-34s'`，超过宽度的自动缩短省略（`…`）不换行破坏列。
- 嵌套说明（dry-run 预览命令行、配置文件片段）在 `note` 下再缩进 2 空格，用 `⋯` 同级前缀区分层级。
- 长原始输出（buildkit、helm、terraform）上下不加装饰行，避免把大块输出夹碎；只需在输出前给一条 `task`。

**C. 状态语义**
- task = 动作**开始**；动作结束只给 ok / warn / error 状态行（如 `✓ scan completed`），不追加 `note "completed"` 冗余行。
- 可跳过项（PP_* / dry-run）统一 `note` 前缀 `⋯ disabled ...` / `⋯ [dry-run] ...`，保证可 grep。
- 一次任务失败：error 行 + 非零退出，`anchor` 的 END 显示 `✗` 和失败码（若整体失败）。

**D. 数值与单位**
- 时间统一秒级：stage diff 显示 `+1s`（≥60s 才显示 `+1m02s`、≥1h 显示 `+1h02m03s`），END 累计显示 `0h0m1s`。
- diff 指**距上一个 stage 开始**的时间差（即上一个阶段耗时）；第一阶段的 diff 相对 BEGIN。

**E. 命名**
- `_msg` 类型名即输出语义名（anchor/stage/task/note/ok/warn/error/log/question），不再出现 `time`/`step`/`stepend` 这类语义重叠的类型。

## 4. 决策点

**已定**：阶段序号自动计算（3.5）、stage 时间差值（D4）。需要确认的：

> ### 决策 D4 时间差值格式（已定）
> - stage 横幅右侧显示 `+diff`（距上一阶段开始的耗时）；END 锚点显示累计 `0h0m1s`。
> - 秒级格式规则见 3.6-D。

### 决策 D1 时间戳策略
- **A（推荐）**：只有 `anchor` 带 `HH:MM:SS`（无日期）。最干净；完整信息在 G_LOG。
- B：`anchor` 带日期 + `stage` 横幅带 `HH:MM:SS`，task/note 不带。
- C：全部带 `HH:MM:SS`（接近现状的修整版）。

### 决策 D2 符号与颜色
- **A（推荐）**：`✓ ! ✗ · ⋯ ▶` 这组 UTF-8 符号 + 当前配色。
- B：不用符号，只靠颜色 + 两种前缀 `  - ` / `  # `（ASCII 安全，老终端/C 盘兼容）。
- C：符号进可选的 `style-symbols` 开关，默认关。

### 决策 D3 PP_* 开关行与 dry-run 预览
现在 `PP_SONAR: false` 是裸 echo，dry-run 的命令预览走 `_msg purple`。
- **A（推荐）**：PP_* → `_msg note "  ⋯ disabled (PP_SONAR=false)"`；dry-run 预览统一 → `_msg note`，前缀 `⋯ [dry-run] ...`，可 grep 过滤。
- B：PP_* 只有在 `-d/--debug` 才打，平时静默。
- C：维持现状类型，只套新缩进。

## 5. Demo（改造后，对应你这次 `--dry` 同一次运行）

```
[20:57:25] ▸ BEGIN  deploy.sh  ·  repo=j2091  ·  mode=auto

  · configure proxy environment
  · initialize file injection                      ⋯ Dockerfile found, skipped
  · detect language → java:1.8:docker

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ▶ STAGE 1/6 · code quality & style             +1s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  · sonarqube code analysis                        ⋯ disabled (PP_SONAR=false)
  · code style check                               ⋯ disabled (PP_CODE_STYLE=false)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ▶ STAGE 2/6 · unit test                         +0s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  · unit test execution                            ⋯ disabled (PP_UNIT_TEST=false)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ▶ STAGE 3/6 · build                             +1s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  · docker build · java:1.8:docker
  ⋯ Dockerfile + dockerd available → buildx bake
  ⋯ [dry-run] build plan only

/usr/local/bin/docker buildx bake  --progress=plain
{
  "group": { ... },
  "target": { ... }
}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ▶ STAGE 4/6 · deployment                        +1s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  · detecting deployment method
  ⋯ Helm charts + k8s available → deploy_k8s
  · helm upgrade j2091 · namespace=develop         ⋯ [dry-run]
  ⋯ reusable: helm upgrade j2091 ... --set image.repository=flyh6/jm,image.tag=t1786453045658

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ▶ STAGE 5/6 · functional test                   +0s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  · functional test execution                      ⋯ disabled (PP_FUNCTION_TEST=false)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ▶ STAGE 6/6 · security scan                     +1s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  · ZAP scan                                       ⋯ disabled (PP_SCAN_ZAP=false)
  · vulmap scan                                    ⋯ disabled (PP_SCAN_VULMAP=false)
  · deployment result notification                 ⋯ disabled (PP_NOTIFY=false)

[20:57:26] ✓ deploy.sh completed in 0h0m1s · all tasks done
```

对照现状：同为一次 dry-run，改动后满屏的 `2026-08-11 20:57:25 - ... - [0h0m0s]`、`[14] vulmap scan`、裸 `PP_*: false` 全部消失；阶段数字由计数器自动给出，每个 stage 自带 `+diff` 耗时差。

## 6. 调用点迁移清单（机械替换）

| 现在 | 数量 | 改为 |
|------|------|------|
| `_msg time "BEGIN"/"END."` | 2 | `_msg anchor` |
| `_msg time "[tag] ..."`（Running/完成/跳过等） | 53 | `_msg task` |
| `_msg step "[tag] msg"` | 52 | `_msg task` |
| `_msg stepend "[build] ..."` | 12 | `_msg note` |
| `_msg info` | 19 | `_msg note` |
| 裸 `echo "PP_*: ..."` | 4 | `_msg note`（D3 定） |
| `_msg purple` 的 dry-run 预览 | ~10 | `_msg note`（D3 定） |
| `_msg green/red/yellow` 状态 | 大量 | 加 `✓/!/✗` 前缀（类型不变） |
| deploy.sh 各阶段 `_msg stage "stage N/6: ..."` | 6 | 改为 `_msg stage "标题"`（序号自动），并在任务执行前声明阶段规格数组 + 调 `count_enabled_stages()` |

涉及文件：`deploy.sh`、`lib/{common,build,analysis,deployment,config,system,test,repo,notify,kubernetes}.sh`；`common.sh` 的 `_msg` 重写类型表。`deploy.sh` 新增 `count_enabled_stages()`（按阶段规格统计本次启用数，支持 spec/auto 两种模式）。

## 7. 改动范围与工作量

- `lib/common.sh`：`_msg` 类型表重写（anchor/stage/task/note/ok/warn/error），删 STEP，`stage` 内维护 `STAGE_NUM/STAGE_TOTAL/STAGE_PREV_SEC`，约 1.5 小时。
- `deploy.sh`：新增 `count_enabled_stages()` + 阶段规格数组，6 处阶段头改为 `_msg stage "标题"`，约 0.5 小时。
- 迁移 100+ 调用点：机械替换 + 全库 grep 校验，约 2-3 小时。
- 回归：`bash -n` + `shellcheck -S warning` 全部文件 + 一次真实 `--dry` 走查。单 job（`-u`）验证 `STAGE 1/1`。

## 8. 不做的事

- 不改 `_msg log` 的日志行格式（G_LOG 锚点保留）。
- 不引入日志级别过滤（info/debug 只有 PP_* 一行受 D3 影响）。
- 不改交互 `_msg question`。