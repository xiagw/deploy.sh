# lib/common.sh 代码审查修复记录

日期：2026-08-22
范围：`lib/common.sh`（审查主文件，共 1479 行）；修复涉及 8 个文件（`deploy.sh`、`lib/common.sh`、`lib/system.sh`、`lib/build.sh`、`lib/kubernetes.sh`、`bin/gitlab.sh`、`bin/ddns.sh`、`bin/backup.sh`）

## 结论（重要）

`lib/common.sh` 是**对外共享的基础 API**（被本仓库 deploy.sh / lib / bin 以及外部项目甚至 `curl` 直接引用），因此：

- **保留**：所有不改变函数名、变量名与调用契约的 bug 修复（见下方高/中/低优先级清单）。
- **已全部还原**：此前一轮做的 `G_*` 变量改名（二轮）与全局清理（四轮，`_log` 迁移、删除 `already_check_root`）——变量名与函数契约是外部调用方依赖的公共接口，**不得变更**。还原后 `deploy.sh`、`lib/system.sh`、`lib/build.sh`、`lib/kubernetes.sh`、`bin/gitlab.sh`、`bin/ddns.sh`、`bin/backup.sh` 与 HEAD 无差异，剩余改动只在 `lib/common.sh`。

## 背景

对 `lib/common.sh` 做了一次代码审查。Shellcheck 0.11.0（`-S info` 全级别）与 `bash -n` 均通过，因此下列问题不涉及语法/静态检查，而是**逻辑、健壮性、可移植性与约定**层面的缺陷。本文件按优先级列出问题与修复方案。

## 高优先级

| # | 位置 | 问题 | 修改 |
|---|------|------|------|
| 1 | `_install_acme_github` 内 `cd "$temp_dir" \|\| exit` | `exit` 出现在库函数里，失败会**直接杀死整个调用脚本**（deploy.sh / bin 脚本），而不是只让本函数失败。同时 `./acme.sh` 执行后未校验结果，失败仍会打印成功。 | 改为 `return 1`；`curl \| tar` 失败即报错并 `return 1`；执行安装前检查 `./acme.sh` 存在。 |
| 2 | `_install_aliyun_cli` 的 `if /bin/bash -c "$(curl ...)"` | curl 失败时 `$(...)` 为空，`bash -c ""` 退出码为 0，**误报"安装成功"**。 | 先取回安装脚本并单独检查 curl 退出码，脚本为空或执行失败才走 CDN 回退。 |
| 3 | `get_oom_score` | 注释声称"按 OOM score 取 top 15"，但 `find /proc | sort -nr` 实际按 **PID** 排序。 | 遍历 `/proc/[0-9]*` 收集 `oom_score`，按 score 数值降序取前 15。 |
| 4 | `_get_random_password` | ① `password_rand` 是裸全局变量，从未 `local`/复位，若同一 shell 内被二次调用且新 `bits` 更小，会返回**上一次的旧密码**；② `echo "${password_rand:?...}"` 在变量为空时由 bash 打印自己的报错并**退出 shell**（调用方 `2>/dev/null` 把报错吞掉，得到空密码）。 | `password_rand`/`count` 改为 `local`；失败分支去掉 `:?`，改为打印错误信息并 `return 1`。 |

## 中优先级

| # | 位置 | 问题 | 修改 |
|---|------|------|------|
| 5 | `_notify_wecom` | `wecom_msg` 未经转义直接拼进 JSON，消息含引号/真实换行时**破坏 payload 或注入字段**。 | 转义双引号与真实换行后再拼 JSON；**不转义反斜杠**——否则外部调用方传字面 `\n`（原版靠 JSON 解析成换行）会被双重转义成字面文本。已验证 4 种入参场景（真实换行/字面 `\n`/引号/反斜杠），对原版能正常工作的输入行为一致，且修复了引号场景。 |
| 6 | `_log` 的 `[[ $CURRENT_LOG_LEVEL -ge $level ]]` | 该变量只有 `bin/backup.sh` 设置，其他场景下未定义，`[[ -ge ]]` 对空串做算术判断会**报错且不输出任何日志**。 | 给默认值：`${CURRENT_LOG_LEVEL:-$LOG_LEVEL_INFO}`。 |
| 7 | `_install_kubectl` 的 `sha256sum --check` | `sha256sum` 在 macOS/BSD 不存在（本仓库明确支持 darwin）。 | 探测 `sha256sum`，缺失时回退 `shasum -a 256`，两者都没有则报错。 |
| 8 | `_install_jmeter` 固定 `dlcdn.apache.org` | `dlcdn` 只保留当前版本，一旦发布新版本，钉死的 5.4.1 会 **404**。 | 改用保留全部历史版本的 `archive.apache.org`。 |
| 9 | `_install_wg` 默认分支写死 `install -yqq` | `-yqq` 是 apt 专属参数，该函数却按多发行版设计（`cmd_pkg`）；dnf/pacman/apk 会拒绝。 | 改用统一的 `$cmd_pkg_install`（由 `_set_package_manager` 生成），并补空值守卫。 |

## 低风险

| # | 位置 | 问题 | 修改 |
|---|------|------|------|
| 10 | `_check_root` 用 `sudo -l -U "$USER"` | `-U` 目标用户受 sudoers 策略限制（非 root 且非 `sudo ALL` 可能被拒），`USER` 未设时 `-U ""` 非法；但 `sudo -l` 交互式会提示输密码并缓存凭据，**不能去掉**。 | 改为 `sudo -l`（去掉 `-U`）：有 sudo → 交互提示密码认证、确认权限、缓存凭据，`use_sudo=sudo`；无 sudo / 密码错 → 退出 1。非 tty 下无密码缓存则立即失败，不挂起。 |
| 11 | `_install_flarectl` 硬编码 `sudo install` | 与全文件统一的 `$use_sudo` 不一致；且直接写 `/tmp`。 | 统一为 `${use_sudo:-}`，解包/清理都基于 `$temp_file` 所在目录。 |
| 12 | `_now_ms` 的 `10#$us` | 当 `EPOCHREALTIME` 不含小数部分时 `us` 为空，`10#` 算术**报错**。 | `us=${us:-0}` 兜底。 |
| 13 | `_install_acme_official` 的 `cd acme.sh && ...` | ① `git clone` 失败未检查；② 函数结束不恢复原目录，**污染调用方 CWD**；③ 克隆目录不清理。 | 校验 clone 结果、用 `$PWD` 保存并恢复、结束清理 `acme.sh/`。 |
| 14 | `_compress_pdf_with_gs` 的 `$compressed_bytes/$original_bytes` | 输入文件为 0 字节时**除零**，awk 报错、压缩比为空。 | 加 `original_bytes > 0` 守卫。 |
| 15 | `_get_yes_no` / `get_github_latest_download` | `read_yes_no`、`ret` 为裸全局变量，残留污染全局命名空间。 | 改为 `local`。 |

## 中优先级（二轮）：全局变量 `G_*` 命名规范 —— 已还原，不生效

> 本轮改名已按用户决定**全部还原**（common.sh 为外部共享 API，变量名不可变更）。以下仅保留历史记录。

审查中发现 `lib/common.sh` 大量使用裸全局变量，违反 AGENTS.md「跨函数/跨模块共享的全局变量用 `G_*` 前缀」规范。本轮将全部跨模块全局变量统一改为 `G_*`，共涉及 8 个文件：

| 变量 | 改为 | 涉及文件 |
|------|------|----------|
| `use_sudo` | `G_sudo` | common.sh、system.sh |
| `lsb_dist` | `G_lsb_dist` | common.sh、system.sh |
| `cmd_pkg` | `G_cmd_pkg` | common.sh |
| `cmd_pkg_install` | `G_cmd_pkg_install` | common.sh |
| `apt_update` | `G_apt_update` | common.sh |
| `ip4_current` | `G_ip4_current` | common.sh、ddns.sh |
| `ip6_current` | `G_ip6_current` | common.sh、ddns.sh |
| `already_check_root` | `G_already_check_root` | common.sh |
| `silent_mode` | `G_silent_mode` | common.sh、gitlab.sh、ddns.sh |
| `_msg_lang_val` | `G_msg_lang_val` | common.sh、deploy.sh |
| `IS_CHINA` | `G_IS_CHINA` | common.sh、deploy.sh、build.sh、kubernetes.sh、gitlab.sh |
| `_stage_start_ms` | `G_stage_start_ms` | common.sh、deploy.sh |
| `wan_device` | `G_wan_device` | common.sh、ddns.sh |
| `CURRENT_LOG_LEVEL` | `G_CURRENT_LOG_LEVEL` | common.sh、backup.sh |
| `LOG_FILE` | `G_LOG_FILE` | common.sh、backup.sh |

要点：
- `ENV_IS_CHINA`（deploy.env 配置，`ENV_*` 规范）**保持不变**，仅重命名裸 `IS_CHINA`。
- `build.sh` / `kubernetes.sh` 中 bake 文件里的 Dockerfile build-arg 键名 `IS_CHINA`（配置格式，需与 Dockerfile 的 `ARG IS_CHINA` 对齐）**保持不变**，只改右侧 shell 变量引用。
- `_stage_num` 仅 common 模块内部使用，保留 `_` 前缀。
- `_log` 的 `CURRENT_LOG_LEVEL` / `LOG_FILE` 为 common ↔ backup.sh 跨模块共享，一并改名。
- 只读常量 `LOG_LEVEL_*`、`COLOR_*`（common 模块对外公开 API，不可变）**保持不变**，不套 `G_` 前缀。

## 低风险（三轮）

| # | 位置 | 问题 | 修改 |
|---|------|------|------|
| 16 | 文件头第 3 行 | 声称"兼容 sh/bash/zsh"，实际使用 bash 专属语法，声明与实现不符。 | 改为"仅兼容 bash/zsh（`[[ ]]`、`(( ))`、`${var:0:N}` 等），不兼容 POSIX sh"。 |
| 17 | `_msg` stage 横幅补位 | `pad=$((58 - ${#left}))` 按**字符数**补位，CJK/emoji 为双宽字符导致时长右对齐不齐。 | 新增 `_display_width()`（多字节字符按 2 列计），按显示宽度补位。实测 CJK 与 ASCII 标题对齐一致。 |
| 18 | `_install_kubectl` | ① 硬编码 `linux/amd64`，macOS/arm64 会 404；② `curl -fsSLO` 与校验在**当前目录**产生 `kubectl`/`kubectl.sha256` 污染；③ 校验依赖 `sha256sum --check` 的"文件名在当前目录"假设。 | 下载到 `mktemp -d` 临时目录；增加 darwin/linux × amd64/arm64 探测；校验改为直接比较 sha256 十六进制。 |
| 19 | `_install_ossutil` | 在当前目录下载 `ossu.zip` 并解压，污染 CWD（靠末尾 `rm -f` 兜底）。 | 全部在 `mktemp -d` 内完成；下载/解压失败即报错；二进制名不再假设为 `ossutil`，用 `find -name 'ossutil*'` 定位。 |
| 20 | `_install_aws` | ① 硬编码 `linux-x86_64`，macOS 无法安装；② 解压与 eksctl 直接写 `/tmp`；③ 无 dry-run 守卫。 | 增加 darwin（`.pkg`）/linux（zip）分支，不支持的 OS 明确报错；全程用 `mktemp -d`；补 `--dry` 守卫；sudo 统一为 `${use_sudo:-sudo}`。 |
| 21 | `_install_terraform` | 只写死 `apt-get`（Hashicorp apt 源），非 Debian 系会以晦涩的 apt 报错失败。 | 函数入口校验 `apt-get` 存在，缺失时明确报错并 `return 1`。 |
| 22 | `_install_flarectl` / `_install_jmeter` | sudo 默认值不统一（`${use_sudo:-}` vs `${use_sudo:-sudo}` vs 硬编码 `sudo`）。 | 统一为 `${use_sudo:-sudo}`（写入 `/usr/local/bin` 的按需安装函数，非 root 时回退 sudo）。 |

说明：
- 全部安装类函数已移除对系统 `/tmp` 的直接写入与当前目录污染；剩余 `/tmp` 引用仅为 `_log` 的日志默认路径（`${LOG_FILE:-/tmp/tmp.log}`，实际由 backup.sh 显式设置）与 `_set_mirror` composer 的 chown 目标。

## 四轮：清除不必要的全局变量 —— 已还原，不生效

> 本轮对 `_log` 的迁移与 `already_check_root` 的删除已按用户决定**全部还原**：`_log` + `LOG_LEVEL_*` + `COLOR_*` 常量回到 `lib/common.sh`，`already_check_root` 逻辑恢复。以下仅保留历史记录。

审查结论：16 个全局中，13 个为 AGENTS 规范定义的合理全局（10 个跨模块、3 个模块内跨函数），3 个不必要，本轮清除：

| # | 全局 | 判定 | 处理 |
|---|------|------|------|
| 23 | `G_CURRENT_LOG_LEVEL` | 仅为旧版 `_log` 服务；`_log` 的调用方只有 `bin/backup.sh`（immich 有自己独立的 `_log`，build.sh 用 `_msg note`）。 | 把 `_log` + `LOG_LEVEL_*` + `COLOR_*` 常量整体移入 `bin/backup.sh`；common.sh 内部调用者（`_check_commands`、`_check_disk_space`）改用标准 `_msg`。 |
| 24 | `G_LOG_FILE` | 同上，只为 `_log` 服务。 | 随 `_log` 一并移入 backup.sh，作为脚本内部变量（去掉 `G_` 前缀）。 |
| 25 | `G_already_check_root` | 纯 memoization，防止 `_check_root` 被重复执行。删除后重复调用只是多跑一次 `sudo -l`（凭据已缓存时不会重复提示密码），无副作用。 | 直接删除标志及其读写。 |

结果：`lib/common.sh` 全局变量 16 → 13 个，同时删除 `_log`、`LOG_LEVEL_*`、`COLOR_*` 约 60 行旧日志代码。

## 未修改（延后）项

- 全局变量 `G_*` 命名规范：**不执行**（见「结论」——common.sh 为外部共享 API，变量名不可变更）。
- sh/bash/zsh 兼容性声明、stage 横幅 CJK 对齐等：已处理（见低风险三轮 #16/#17）。

## 验证方式

还原后剩余改动仅在 `lib/common.sh`（其余 7 个文件与 HEAD 无差异）：

```bash
bash -n lib/common.sh
shellcheck -S warning lib/common.sh   # 零输出、退出码 0
```

全项目回归：全部 161 个 `.sh` 文件 `bash -n` 通过；`lib/common.sh` 通过 `shellcheck -S info` 全级别。
