# deploy.sh 代码审计报告

> 审计日期：2026-08-12
> 审计范围：`deploy.sh` + `lib/`（**暂不包含 `lib/common.sh` 的问题**，由决策另行处理）
> 审计维度：Bug / 未完成功能与死代码 / 命名规范 / 健壮性与设计
> 状态：P0~P3 **全部已处理**（2026-08-12），P3 见各条目状态。

---

## 0. 审计说明

- 全部结论均经源码核实（含行号），非静态报告转述。
- `lib/common.sh` 的问题按决策**暂缓**，不在本文档范围内（包括：ossutil 安装、`_install_*` 系列、`_` 前缀语义、`_msg log` 追溯性、grep/sed 解析 JSON 等）。
- 严重度分级：🔴 高（真实故障/数据风险）｜🟠 中（功能不完整/不可达）｜🟡 低（规范/健壮性）。

---

## 1. Bug（已确认）

### B-1 🔴 `test_unit` 失败不阻断流水线
- **位置**：`lib/test.sh:23`
- **现象**：`if bash "$test_script"; then ... else _msg error "..."; fi` 之后是裸 `return`，退出码恒为 0。
- **影响**：单测失败只打 `✗` 消息，但函数返回 0，流水线继续走构建/部署。`test_function` 是正确的（失败返回 1），两者行为不一致。
- **状态**：✅ **已修复**（2026-08-12）。失败分支改为 `return 1`，成功分支显式 `return 0`，与 `test_function` 一致。

### B-2 🔴 裸字符串调用 `_msg`，消息被静默丢弃
- **位置**：`lib/system.sh:434 / 439 / 442`
- **现象**：`_msg "create gitlab pipeline, project id is $id"` —— 第一个参数不是任何合法级别，`_msg` 命中 `*) return 0` 直接返回。
- **影响**：证书续签流程里"创建 gitlab pipeline / 搜索 nginx 项目"等提示完全不可见，运维以为没触发。
- **注**：根因在 common.sh 的 `_msg`（未知类型静默返回），但本项是**调用方写错级别**，只需改调用点即可独立修复。
- **建议**：改 `_msg note "..."` / `_msg task "..."`。
- **状态**：✅ **已修复**（2026-08-12）。三处裸 `_msg` 均改为 `_msg note`（system.sh:434/439/442）。

### B-3 🟠 `style_check` 分派与实际语言探测不匹配
- **位置**：`lib/style.sh:184-192`（case 分支）＋ `lib/repo.sh:127-146`（探测产出）
- **现象**：探测只会输出 `java/python/node/php/golang/rust/dotnet/elixir/unknown`，但 case 用的是 `go/c/ios/django/android`。
  - `golang`/`rust`/`dotnet`/`elixir` → 落到 `_msg warn "No style checker available"`
  - `go`/`c`/`ios`/`django`/`android` 分支永不可达
- **影响**：golang 项目的风格检查永远"无检查器"，形同没查。
- **建议**：case 按探测真实产出修正（`go|golang)` 等），并把 `check_go_style` 接到 `golang`。
- **状态**：✅ **已修复**（2026-08-12）。`style.sh:188` case 改为 `go | golang) check_go_style`，`golang`（go.mod 探测产出）现在可走到 `check_go_style`。

### B-4 🟠 `check_php_style` 只检查已提交改动
- **位置**：`lib/style.sh:22`
- **现象**：`git --no-pager diff --name-only HEAD^` 只取已提交的 diff。
- **影响**：未提交/暂存改动不检查；仓库首个 commit（无 `HEAD^`）会报错。
- **建议**：改用 `git diff HEAD`（含工作区+暂存）或 `git diff --cached`，并对无 `HEAD^` 兜底。
- **状态**：✅ **已修复**（2026-08-12）。`style.sh:22` 改用 `git diff --name-only HEAD`，包含工作区+暂存改动，且首个 commit 不再报错。

### B-5 🟡 csproj 版本提取依赖 GNU grep
- **位置**：`lib/repo.sh:221`：`grep -oP '(?<=TargetFramework>net)[^<]+'`
- **影响**：macOS 原生 grep 不支持 `-P`，.NET 项目在 macOS 上版本探测失败。
- **建议**：改用 `grep -oE` 加 sed，或 jq/awk 提取。
- **状态**：✅ **已修复**（2026-08-12）。`repo.sh:221` 改用 `grep -oE 'TargetFramework>net[^<]+' | sed 's/.*>net//' | head -n 1`，去掉 `-P`，macOS 原生 grep 可用。

### B-6 🟠 模板残留值校验只在 rsync+ssh 路径
- **位置**：`lib/deployment.sh:328-346`
- **现象**：`192.168.100.102/104`、`example.com` 等示例值拦截只存在于 `deploy_via_rsync_ssh`。
- **影响**：k8s/docker/ftp/sftp/oss 等其它部署方式可带模板残留值直接上线。
- **建议**：把校验提到公共层（如 `find_project_config` 或 `handle_deploy` 入口）。
- **状态**：✅ **已修复**（2026-08-12）。新函数 `check_project_config_template`（config.sh）在 `find_project_config` 末尾统一拦截示例残留，覆盖全部部署方式；`deploy_via_rsync_ssh` 内的重复校验块已删除。`set -Eeo pipefail` 下返回 1 会直接阻断整条流水线。
  - **二次加固**（同日）：模板示例值改为 RFC 5737 文档保留地址 `192.0.2.2/192.0.2.3`（全球不可路由，物理上不可能撞真实服务器）+ 保留域名 `*.example.com`（RFC 2606）；判空改为 `jq -e '.. | strings | select(test("example\\.com|192\\.0\\.2\\.2|192\\.0\\.2\\.3"))'` **递归扫描全量字符串字段**，顺带修复原逻辑查不到 `db_host` 残留的疏漏。正则限定 `example\.com` 避免误伤 `rsync_dest` 含 "example" 单词的路径。

### B-7 🟡 `env_file_set` 存在死循环
- **位置**：`lib/config.sh:246-266`
- **现象**：第一遍 while 循环 `> /dev/null 2>&1` 吞掉输出后又重建，纯冗余（注释也承认"read again to tmp_file"）。
- **建议**：删除第一遍循环。
- **状态**：✅ **已修复**（2026-08-12）。删除第一遍冗余 while 循环，`G_ENV` 存在/不存在两分支统一复用顶部 `mktemp` 的 `tmp_file`。（原第一遍写出的 `tmp_file` 被第二遍 `mktemp` 覆盖泄露，顺带修复。）

### B-8 🔴 `clean_old_tags` 与当前镜像 tag 格式不匹配
- **位置**：`lib/deployment.sh:973+`
- **现象**：当前 tag 为 `t<毫秒>`（`G_IMAGE_TAG="t$(date +%s%3N)"`，无连字符）：
  1. 正则 `.*-([0-9]+)$` 要求 `-` 前缀 → `t<毫秒>` 永不匹配 → 落入"无时间戳"分支 → 非强制时不删。
  2. 即便旧格式含 `-`，tag 是**毫秒**时间戳，而 `cutoff_time=$(date +%s)` 是**秒** → 毫秒值恒 > 当前秒值 → 被判"无效时间戳范围"**全部删除**。
- **影响**：`--clean-tags` 当前格式下要么不生效、要么误删所有 tag。
- **状态**：✅ **已修复**（2026-08-12）。改为捕获末尾 ≥10 位数字段：13 位判定为毫秒并转秒，统一与秒级 `cutoff_time` 比较；非时间戳 tag 仅 `delete_force` 时删。顺带把 `delete_force`/`tag`/`tag_timestamp` 收为 local（原 `delete_force=true` 泄漏到全局）。

---

## 2. 未完成功能 / 死代码

### D-1 🔴 `EXIT_MAIN` 机制是空设计
- **位置**：`lib/build.sh:213`（设置）＋ `deploy.sh:765`（消费者被注释）
- **现象**：自定义构建脚本运行后 `export EXIT_MAIN=true`，但唯一消费点已注释。
- **建议**：确认语义后二选一——恢复消费，或删除设置。
- **状态**：✅ **已移除**（2026-08-12）。**决策**：dry-run 机制已完善，无需 EXIT_MAIN。`build.sh` 的 `export EXIT_MAIN=true`、`deploy.sh` 的注释消费与 `unset` 列表同步删除，无残留引用。

### D-2 🟠 `PROJECT_PREFER_DOCKER` / `PROJECT_PREFER_K8S` 是摆设
- **位置**：`lib/config.sh:134-150`（导出）——全库 0 消费
- **现象**：项目配置的 `build.prefer_docker` / `deploy.prefer_k8s` 解析导出后没人用，只有 `method` 生效。
- **建议**：接入 `build_all` / `determine_deployment_method`，或从模板与解析中移除。
- **状态**：✅ **已实现**（2026-08-12，按用户决策）。恢复 config.sh 对应 key 解析+export 与模板键 `prefer_docker`/`prefer_k8s`（默认 `true`），并真正接进自动检测：
  - `build_all`（build.sh）Priority 1 加 `prefer_docker` 门槛，`false` 时直接走 Priority 2 系统构建（Priority 2 条件同步加 `prefer_docker != true`，避免空跑）。
  - `determine_deployment_method`（deployment.sh）Step 1（Helm+k8s）/ Step 2（Dockerfile+k8s）加 `prefer_k8s` 门槛，`false` 时跳过 k8s 落到 docker-compose → rsync。
  - 语义：method 非 auto 仍是强制最高优先，两开关只影响自动级联。已用分支矩阵验证 true/false 四条路径。

### D-3 🟠 `kube_create_storage_class` 无调用
- **位置**：`lib/kubernetes.sh:177`；`deployment.sh:140` 的 `kube_check_pv_pvc` 被注释
- **建议**：补 CLI 入口（如 `--create-storage-class`）。
- **状态**：✅ **已修复**（2026-08-12）。新增 `--create-storage-class` CLI 入口（deploy.sh parse + 主流程独立功能），在 `kube_config_init` 之后执行并 `return`，需要 `ENV_NAS_URL`。

### D-4 🟠 死函数清单（主流程不可达）
| 函数 | 文件 | 说明 |
|---|---|---|
| `repo_language_detect_and_build` | lib/build.sh:809 | buildpack 路径未接入主流程 |
| `generate_lang_dockerfile` / `generate_base_dockerfile` | lib/build.sh:757/784 | 互相引用，整体死 |
| `update_nginx_geoip_db` | lib/system.sh:120 | GeoIP 更新无 CLI 入口 |

- **建议**：按 AGENTS"不保留向后兼容、过时直接删"——补入口。
- **状态**：✅ **已修复**（2026-08-12，按"补入口"而非删除）。新增三个独立 CLI 入口：`--gen-dockerfile`（按检测语言写 `Dockerfile.<lang>`，跑在 `$G_REPO_DIR`）、`--build-buildpacks`（用 Cloud Native Buildpacks 打包，`pack build ENV_DOCKER_REGISTRY/G_IMAGE_NAME:G_IMAGE_TAG`，需 pack CLI）、`--update-geoip`（同步 Nginx GeoIP，需 `ENV_NGINX_IPS`）。均在主流程对应依赖就绪后执行并 `return`。

### D-5 🟡 文档过期
- **位置**：`docs/refactoring.md`
- **现象**：引用不存在的 `lib/docker.sh`、`is_demo_mode`、`is_china`、`kube_setup`、`deploy_notify`（实际为 `handle_notify`）。
- **建议**：刷新 refactoring.md 或标注已过期。
- **状态**：✅ **已修复**（2026-08-12）。refactoring.md 全面刷新：Docker 操作并入 `lib/build.sh`（buildx/bake/`docker_login`/`detect_repo_language_and_build`），补充 config.sh/style.sh 模块；函数清单改为现状（`detect_repo_language`、`kube_setup_terraform`、`handle_deploy`、`_msg`/`_t`、`_install_*` 等）；`G[...]` 关联数组规范改为 `G_*` 平铺变量约定并指向 AGENTS.md；同步修正 architecture.md、plan-task-dispatch.md 中改名的函数引用。

---

## 3. 命名规范问题

### N-1 🟡 `get_lang` 存值却像函数名
- **位置**：`deploy.sh:705` `get_lang=$(repo_language_detect)`
- **建议**：`detected_lang` 或 `G_LANG`。
- **状态**：✅ **已修复**（2026-08-12）。`deploy.sh:705` 改为 `local detected_lang`（main 内 local，非全局），`repo.sh:17` 同步为 local `detected_lang`。

### N-2 🟡 跨模块共享全局变量无前缀
- `deploy_result`（deployment.sh）、`test_result`（test.sh）、`sub_path_name` / `run_with_crontab` / `image_retain` / `deploy_method`（deploy.sh）游离于 `G_*` 约定外。
- `sub_path_name` 本质是参数，应为 `arg_sub_path`。
- **状态**：✅ **已修复**（2026-08-12）。`deploy_result`→`G_DEPLOY_RESULT`、`test_result`→`G_TEST_RESULT`（handle_test 去掉 `local` 真正落全局，notify 可读到）、`sub_path_name`→`arg_sub_path`、`run_with_crontab`→`arg_cron`、`image_retain`→`arg_image_retain`；`deploy_method` 经 R-3 已为 main 内 `local`（非全局，无需前缀），`record_deployed_image` 的形参改名为 local `deploy_ok` 避免遮蔽 `G_DEPLOY_RESULT`。main() unset 清单同步纳入新全局量。

### N-3 🟡 探测类函数动词不统一
- `detect`：`determine_deployment_method` / `repo_language_detect`
- `check`：`check_docker_available` / `check_crontab_execution` / `system_check`
- **建议**：统一为 `detect_*`（探测）与 `check_*`（可用性校验）。
- **状态**：✅ **已修复**（2026-08-12）。`determine_deployment_method`→`detect_deployment_method`，`repo_language_detect`→`detect_repo_language`（含 `_docker`/`_and_build` 后缀变体），调用点 deploy.sh/repo.sh/build.sh/style.sh 同步；`check_*`/`system_check` 语义本就正确，保留。

### N-4 🟡 模块前缀不统一
- 动词在前：`handle_deploy` / `handle_test` / `handle_notify`
- 域在前：`deploy_to_kubernetes` / `deploy_via_rsync_ssh` / `build_all`
- **建议**：按模块统一 `deploy_*`、`build_*`、`handle_*` 前缀规则，写进 AGENTS.md。
- **状态**：✅ **已处理**（2026-08-12）。新增项目根 `AGENTS.md`，写入命名规范（`G_*`/`ENV_*`/`arg_*`/`CI_*` 前缀、`deploy_*`/`build_*`/`handle_*`/`detect_*`/`check_*`/`_` 私有助手规则）；函数名本身语义已由前缀表达（域在前=部署/构建动词，handle_*=分派入口），维持现状不批量改名。

### N-5 🟡 大小写混用
- `DRY_RUN` / `MSG_LANG`（大写下划线，非 `ENV_*`）与 `arg_flags` / `deploy_method`（小写）并存。
- **建议**：统一命名法，文档化。
- **状态**：✅ **已修复**（2026-08-12）。`DRY_RUN`→`G_DRY_RUN`（12 文件 ~55 处）、`MSG_LANG`→`G_MSG_LANG`，按 `G_*` 全局约定统一；`arg_flags` 属 `arg_*` 参数命名空间、`deploy_method` 为 local，均合规，命名法写入 AGENTS.md。

---

## 4. 健壮性 / 设计建议

### R-1 🟡 `||`/`&&` 优先级隐晦
- **位置**：`deploy.sh:688` `[[ $deploy_sum -gt 0 ]] || $all_zero && ((++STAGE_TOTAL))`
- **现象**：`||` 与 `&&` 同级左结合，实际是 `([[ .. ]] || $all_zero) && ((..))`；`$all_zero` 直接当命令执行。结果正确但极易被误改。
- **建议**：改显式 `if`。
- **状态**：✅ **已修复**（2026-08-12，随 R-3 重写顺带消除）。现 `deploy.sh:768` 为 `[[ $deploy_sum -gt 0 ]] && ((++STAGE_TOTAL))`，无 `|| $all_zero` 死条件（grep 已确认全库无残留）。

### R-2 🟠 构建默认行为两套
- auto 模式 `image_retain` 为空 → 默认 **push**（推 registry）；`-B` 无参默认 `remove`。
- **建议**：统一默认（如 `remove`），push 需显式 `-B push` 或 `ENV_*`。
- **状态**：✅ **已修复**（2026-08-12）。统一为 **默认 `remove`**（`build_image` 的 `--push`/`--load` 分支改为仅 `retention_mode=push` 时 `--push`，空值不再默认推送）；`-B` 无参 `remove`；支持 `ENV_IMAGE_RETAIN`（push|keep|remove）全局覆盖。唯一例外：auto 模式（`all_zero`，构建后跟部署）由 main 显式传 `push`——部署方法均从 registry 拉镜像，不推会断链。

### R-3 🟠 `deploy_method` 双写 + 静默 last-wins
- parse 时写 `arg_flags["deploy_*"]` 和 `deploy_method`；`-k -y` 同传时后一个覆盖，无任何提示。
- **建议**：按 docs/plan-task-dispatch.md 阶段 2——从 `arg_flags` 派生并 `warn` 多方法场景。
- **状态**：✅ **已修复**（2026-08-12，落地 plan-task-dispatch 阶段 2）。parse 只写 `arg_flags`，`deploy_method` 在阶段 4 从单一 `deploy_display` 顺序表派生：0 个不部署、1 个即该方法、多个 `_msg warn` 明示"仅执行首个，多目标请走 GitLab 多 job"后取顺序表首个（原静默 last-wins → 显式 + 顺序确定）。auto 模式保持空、走 `determine_deployment_method` 探测链路。同时删除 `deploy_sum` 的关联数组乱序迭代（改顺序表统计）与 `STAGE_TOTAL`/阶段 4 的 `|| $all_zero` 死条件。

### R-4 🟡 FTP/SFTP 凭据进命令行
- `sshpass -p ...`、`ftp -inv`（deployment.sh）→ 进程列表可见密码。
- **建议**：用 `SSHPASS` 环境变量/`expect` 或密钥；FTP 密码至少不入 argv。
- **状态**：✅ **已修复**（2026-08-12）。SFTP（`_sftp_upload_one`）改 `export SSHPASS="${ENV_SFTP_PASSWORD}"` + `sshpass -e`，密码不再进 argv；无密码分支 `unset SSHPASS` 防残留。FTP 走 heredoc stdin（密码本就与 argv 无关），保持现状。

### R-5 🟡 OSS 目标解析逻辑重复
- `deploy_via_rsync_ssh` 与 `handle_deploy` 的 OSS 分支各自解析 `oss:// rsync_dest`。
- **建议**：抽一个 `_project_oss_dest` 共用。
- **状态**：✅ **已修复**（2026-08-12）。新增 `_project_oss_dest`（deployment.sh）：按当前命名空间取 `oss://` 开头的 `rsync_dest`，空则回退 `ENV_OSS_DEST`；`handle_deploy` 的 OSS 分支改用它，删掉内联 jq 解析。`deploy_via_rsync_ssh` 按每台主机逐个上传，语义不同，保留逐行 `rsync_dest` 判断。

### R-6 🟡 硬编码阈值
- helm/probe timeout 120s、clean 180 天、disk 80%、`--history-max 3` 等无 ENV 覆盖。
- **建议**：常用阈值进 `ENV_*`（可选）。
- **状态**：✅ **已实现**（2026-08-12）。新增可覆盖环境变量（默认值保持原行为）：`ENV_HELM_TIMEOUT`（默认 `120s`，helm `--timeout` 与 rollout status）、`ENV_HELM_HISTORY_MAX`（默认 `3`）、`ENV_CLEAN_TAGS_DAYS`（默认 `180`，`clean_old_tags` 截止天数）、`ENV_DISK_THRESHOLD`（默认 `80`，`system_clean_disk`）。

---

## 5. 建议修复优先级（后续决策用）

| 优先级 | 项 | 理由 |
|---|---|---|
| P0 | B-1、B-2、B-8 | 真实故障：单测假通过、提示不可见、清理误删 |
| P1 | B-3、B-4、B-6、D-1、D-2 | 功能不完整/不可达 |
| P2 | D-3、D-4、R-2、R-3 | 死代码/默认行为（**2026-08-12 全部已修**） |
| P3 | 其余（B-5、B-7、D-5、N-*、R-*） | 规范与健壮性（**2026-08-12 全部已处理**） |

## 6. 验证约束

- 任何修改必须过 `bash -n <file>` 与 `shellcheck -S warning <file>`（零输出、exit 0）。
- 禁止 `if [ $? -eq 0 ]` 判断命令结果（用 `result=$(cmd); local ret=$?` 模式）。
- 修改后更新本文档对应项的状态。
