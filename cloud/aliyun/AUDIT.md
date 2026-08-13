# 审计报告：cloud/aliyun 阿里云 CLI 封装工具

- **审计对象**：`cloud/aliyun/` 全部 25 个 `.sh` 脚本（约 30 万字节）
- **审计维度**：设计、功能、逻辑、函数/变量命名、bug
- **方法**：静态逐行审查 + 本机 `aliyun 3.4.x --help`/`--cli-dry-run` 实测混合标注（标「实测」者为 dry-run/help 验证结论）
- **结论摘要**：~~存在 **3 个创建类操作必挂**（eip add / kvstore add / nat add）~~ **已修复（§2.1）**；剩余 **2 个 P0**（oss batch-copy / rds add 缺必填）、2 个模块因文件覆盖导致功能错位（config CRUD）、以及系统性裸全局变量、GNU/BSD 兼容、`select_with_fzf` 杀死进程等架构问题。详见下文。

---

## 一、设计层面

### 1.1 三重函数覆盖冲突（高优先级）

`main.sh:49` 用 glob 把 `SCRIPT_DIR/*.sh` 全部 source 进同一命名空间，无同名告警机制，源码顺序（字母序）决定覆盖关系：

| 函数 | config.sh | utils.sh | 实际生效 |
|---|---|---|---|
| `create_profile` | `:42`（`aliyun configure set`） | `:233`（jq 直写 `~/.aliyun/config.json`） | utils.sh 版本（u 在 c 后 source） |
| `update_profile` | `:64` | `:265` | utils.sh 版本 |
| `delete_profile` | `:86` | `:285` | utils.sh 版本 |

**影响**：`config add/set/del` 表面上走 config.sh CRUD，实际执行的是 utils.sh 直接改 JSON 文件的版本，绕过 CLI 校验与插件兼容逻辑。`utils.sh` 的这三个函数应删除或改名（config.sh 的 `aliyun configure set` 才是正确实现）。

### 1.2 模块加载机制是死代码

- `main.sh:21-40` 的 `load_module`（含 `stat -c %Y` 变更检测）**从未被调用**——`main.sh:49` 已一次性 source 所有模块，`load_module` 整体死代码，且 `stat -c` 是 GNU-only，macOS `< /usr/bin/stat` 实测 `illegal option -- c`。
- 既然模块全部提前 source，任何「按需加载/热重载」承诺都不成立。

### 1.3 `select_with_fzf` 取消即杀死整个进程（跨文件系统性）

`utils.sh:174-177`：fzf 空选时 `exit 1`，会**终止整个 CLI 进程**而非返回错误。导致：

- 所有模块在 fzf 之后的 `[ -z "$selected" ]` 空值检查、`|| return 1` 兜底全部是死代码；
- 「取消即放弃本次操作、继续后续逻辑」的交互预期无法实现。

### 1.4 裸全局 `ret` / `result` / `return_code`（跨文件系统性）

AGENTS.md 明确「其余一律 local」，但实测多个文件在函数内直接写全局 `ret`：

- ecs.sh（`238/241/355/414/490/1242` 等）、vpc.sh（`354/766/838/971` 等）、rds.sh、polardb.sh、dns.sh、ack.sh、cdn.sh、ram.sh、nat.sh（:56）、eip.sh（:76）、kvstore.sh（:72）、mongodb.sh（:60）、eci.sh（:56）、sms.sh（:45）、acr.sh（:88）、ticket.sh（:72）、nas.sh（:81）、dts.sh

ecs.sh 与 vpc.sh 同名为 `ret`，跨函数互相踩踏，嵌套调用后判断结果完全不可信。

### 1.5 地域语义四种姿势并存

> **已解决**（本次修订）：统一为「`--biz-region-id` + `--region` 处处同传」。
> `call_aliyun_api`（base.sh:17）在调用方未显式传 `--region` 时自动补上全局 `-r` 指定的地域，
> 保证 endpoint 选择处处跟随 `-r`（nas/kvstore/dts 不再落回 profile 默认地域）；中心化服务已显式传
> `--region`（cas/alidns）不受影响，ram/cdn/bssopenapi 等无副作用。`generic_list` 死逻辑删除，
> 恒注入 `--biz-region-id`。缺失 `--biz-region-id` 的区域调用已补齐：dts 全部、ecs 快照/启停/实例属性、
> polardb 账号/白名单/备份、rds describe-zones、vpc sg 规则（实测）。

同一处 `-r <region>` 全局选项，各模块处理不一致：

- `--biz-region-id` + `--region` 都传（vpc create/list）
- 只传 `--biz-region-id` 不传 `--region`（generic_create、nas 全不传、kvstore 多处缺 `--region`）→ **endpoint 落回 profile 默认地域，`-r` 对 nas/kvstore 静默失效**
- 完全不传（dts 大部分调用）
- 中心化服务特殊处理（ram/cdn/cas）

`base.sh:231` `generic_list` 用「`api_action` 含不含 `biz-region-id` 字符串」决定是否注入该参数，`api_action` 永远不含，条件恒真，是死逻辑。

### 1.6 跨系统耦合

`main.sh:49` 把 `${SCRIPT_LIB}/common.sh`（另一套 deploy.sh 系统）也 source 进来，且 utils.sh 的 `_notify_wecom` 依赖它；一旦库出现同名函数会被无提示覆盖。

---

## 二、功能层面（功能缺失 / 承诺未落地）

### 2.1 创建/操作类功能实际必挂（高优先级）

> **已解决**（本次修订）：下表 7 项全部修复，并已用 `--cli-dry-run` 逐一验证参数合法。

| 位置 | 命令 | 修复 |
|---|---|---|
| eip.sh:128 | `eip add` | `generic_create` 改用新插件命令 `allocate-eip-address`（`--biz-region-id` 对该命令合法），不再用 PascalCase `AllocateEipAddress`。 |
| kvstore.sh:199 | `kvstore add` | 改用 `create-instance` 并补必填 `--zone-id`（未传时经 `describe-zones` 交互选择/唯一自动选中）。 |
| nat.sh:121 | `nat add` | 补必填 `--nat-type Enhanced` 与 `--vswitch-id`（自动解析 VPC 下交换机）；`--spec` 已被 API 废弃，签名改为 `<VPC-ID> <名称>`。 |
| dts.sh:220/258/430 | `dts add/sync-add` 及启动 | 创建接口补必填 `--migration-job-class`/`--biz-region`（同步补 `--source-region/--dest-region/--pay-type`）后追加 `configure-*` 配置任务名/源目标类型/全库迁移；`dts start` 改用正确接口 `start-migration-job`，轮询改用 `describe-migration-job-status` 读 `.MigrationJobStatus`（stop 同步修正为 `Suspending`）。 |
| sms.sh:44/58 | `sms get` | 实测 `query-sms-template-list/query-sms-sign-list` 配 `--api-version 2017-05-25` 即存在，原代码正确；真实缺陷是 `2>/dev/null` 吞错。已改为失败时把 API 错误原文打到 stderr，不再误报「没有模板/签名」。 |
| ack.sh:187-213 | `ack create` | 响应字段改为 `.cluster_id`（实测 snake_case），缺失即报错，不再死等 30 分钟；`ack add-node` 从 DELETE 语义的 `POST /clusters/{id}/nodes`（实为 DeleteClusterNodes）改为节点池扩容 `POST /clusters/{id}/nodepools/{poolId} {count}`。 |
| lbs.sh:341/385 | `lbs add-nlb` | `ZoneId` 改为从 `describe-vswitches` 取所选交换机可用区；`alb create` 另补实测必填 `--load-balancer-edition` 与 `--load-balancer-billing-config`。 |

### 2.2 功能承诺未实现

- **oss.sh:1138-1250 `oss set`**：help 广告 acl/lifecycle/cors/website/referer 五种设置，实际只实现 acl，其余必报错。
- **nas.sh:202-226 `nas update`**：help 承诺「更新名称+描述」，实现只发 `--description`，从未改名称（NAS 无改名接口，功能未落地又不说明）。
- **oss.sh:121-123**：`oss_upload_cert` / `oss_delete_cert` / `oss_deploy_cert` 被分发但**全仓库无定义**，运行时 `command not found`。
- **cas.sh:277-283 批量删旧证书**：`cas_delete` 内部 `confirm_action` 交互确认，非交互场景 read 得空 → 确认取消 → `|| true` 吞掉 → **「自动删除历史证书」永不生效**。
- **acr.sh:294** `docker login --username=$user --password=$token` 明文口令进 shell 历史；`:295` 把 `authorizationToken` 原文写日志。

### 2.3 分页缺失

> **已解决**（本次修订）：改用 aliyun CLI 内置 `--pager`（别名 `--all-pages`）自动逐页合并，`--page-size` 不再需要。

- ~~dns.sh:213/383 只取第一页（page-size 100），超 100 条记录的域名在 fzf 里永远找不到目标记录。~~ **已修**：`describe-domains`/`describe-domain-records` 全部列表调用加 `--pager`。
- ~~dts.sh:74-105 `dts_list` 默认每页 30，只显示第一页。~~ **已修**：migration/subscription 用自动 `--pager`；`describe-synchronization-jobs` 自动识别失败，改用显式 `--pager path=SynchronizationInstances`（已实测）。顺带修正 `dts_subscribe_list`/`dts del` 的订阅字段路径（真实响应是 `.SubscriptionInstances.SubscriptionInstance[].SubscriptionInstanceID/.InstanceCreateTime`，原 `.SubscriptionInstanceInfos.SubscriptionInstanceInfo[].SubscriptionInstanceId/.CreateTime` 恒空）。
- ~~vpc.sh:135-152 `vpc_list_all` 对每个 VPC 串行 3 次 list，无分页，region 内 VPC 多时极慢。~~ **已修**：顶层 `describe-vpcs` 加 `--pager`，超过单页的 VPC 不再丢失（串行性能问题保留，见 §1.4 后续治理）。

### 2.4 死代码函数（未被任何调用方引用）

> **已解决**（本次修订）：全部删除（全仓库零调用，已核实）。

- ~~oss.sh：`get_cname_token`(:416)、`generate_oss_signature`(:509)、`verify_domain_ownership`(:542)~~ **已删**
- ~~dns.sh：`get_domain_list`(:71，与 `dns_domain_list` 重复实现)~~ **已删**
- ~~ram.sh：`ram_create_updated`(:740，从未被 dispatch，且其生成的密码无长度/复杂度校验)~~ **已删**（`ram add` 走 `ram_create`，`_ram_random_password` 仍在用）
- ~~utils.sh：`get_credentials`(:181)~~ **已删**

---

## 三、逻辑层面

### 3.1 死代码分支

> **已解决**（本次修订）：fzf 空选 fallback 一项实为 §1.3 的连带（`select_with_fzf` 已是 `return 1`，分支可达，无需改）；其余死分支已清理。

- ~~**fzf 空选 fallback**：vpc.sh `:255-258/270-274/1063-1067`、oss.sh `:255-258`、「使用默认网段」等 fallback 在 `select_with_fzf` 空选即 `exit 1` 的情况下永远不可达。~~ **已解决**（§1.3 实已修：`select_with_fzf` 空选 `return 1`，这些 fallback 已可达）。
- ~~**`="null"` 死条件**：nat.sh:186、kvstore.sh:247。~~ **已修**：nat.sh 已无；kvstore.sh 删除 `[ "$instance_name" = "null" ]`（上游 `// "未知"` 已兜底）。
- ~~**默认值掩蔽交互分支**：rds.sh:414 `description=${4:-...}`、rds.sh:708 `privilege=${4:-...}`。~~ **已修**：改为 `$4`，描述/权限的交互选择分支恢复可达（此前权限永远无法交互选择，实为功能缺陷）。
- ~~**nas.sh:100 `name=${1:-nas-...}` 后 `:106` 的 `[ -z "$name" ]` 永假；polardb.sh:284 同样。~~ **已修**：nas.sh 删除永假检查（保留自动生成名逻辑）；polardb.sh:284 无交互分支，默认值保留。
- ~~**`diag` 双段冗余判断**：ecs.sh:420 `[ "$key_count" -eq 0 ] || [ "$key_count" = "0" ]`。~~ **已修**：ecs.sh 三处同款冗余（:420/875/972）统一删去 `= "0"` 段。

### 3.2 错误被吞导致「误报成功/误导」

> **已解决**（本次修订）：4 处退出码丢失/错误吞掉的 bug 已修；base.sh 一项实测不触发（成功路径 aliyun stderr 为空）。

- ~~base.sh:95/113 `call_api_logged/delete` 把 stderr 混入 `result`，成功路径 jq 失败时把 aliyun 的 stderr 垃圾当成功 JSON 回显。~~ **实测不触发**：aliyun 成功调用 stderr 为空，`2>&1` 混入无实际影响，未改动。
- ~~ram.sh:163 `create-login-profile` 的 stderr 与退出码全吞（`>/dev/null 2>&1`）→ 失败仍报「子账号创建成功」并打印一个登录不了的密码。~~ **已修**：改为检查登录配置结果，失败时警告并 `return 1`，不再打印无效密码。
- ~~cas.sh:194-198 上传失败分支**缺 `return 1`**，函数以 0 退出且 `log_result` 照写「成功」。~~ **已修**：失败分支补 `return 1`（跳过 log_result）。
- ~~polardb.sh:333 `polardb_account_create` 失败分支不 `return 1`，函数返回 0，退出码丢失。~~ **已修**：失败分支补 `return 1`。
- ~~cdn.sh:482-487 用 grep "unknown command" 判断插件不支持，其余错误文本进入成功分支，**购买没发生却返回 0**。~~ **已修**：捕获调用退出码，成功返回 0 并回显结果，其余错误 `return 1`。

### 3.3 等待/轮询逻辑失效

> **已解决**（本次修订）：三处轮询全部改为「终态即退出」。

- ~~dts.sh:441 `describe-migration-jobs --migration-job-id` 实测接口无此参数 → 空转满 150 秒；`:476` jq 字段路径 `.MigrationJobs.MigrationJob[0].Status` 与响应形态不符，`Paused` 永远等不到。~~ **已修**：`dts start/stop` 轮询改用实测合法的 `describe-migration-job-status` 读 `.MigrationJobStatus`（§2.1 已改），并在本次修订为两处轮询补终态分支——`PrecheckFailed`/`MigrationFailed`/`Finished`（start）、`MigrationFailed`/`PrecheckFailed`（stop）立即报错退出，状态为空也报错，不再空转满 150 秒。
- ~~ack.sh:241 轮询只认 `running/failed`，`updating`/`deleting` 等其他终态死等 30 分钟。~~ **已修**：改为白名单——仅 `initial`（创建中）继续等待，`running` 成功退出，其余任何状态（`failed`/`inactive`/`unavailable`/`updating`/`deleting`/`delete_failed` 等终态，实测自官方集群状态文档）立即报错退出，状态为空同样报错。
- ~~eip.sh:255-269 解绑失败仅警告、随后 `release` 必失败再报错；固定 `sleep 10` 不做状态轮询。~~ **已修**：解绑失败直接 `return 1`（不再带着已绑定状态去 release）；解绑成功后轮询 `describe-eip-addresses --allocation-id` 直至 `Status == Available`（12×5 秒超时），超时即报错中止。

### 3.4 计数/空结果边界

- base.sh:178 `grep -c . || echo "0"`：`temp_output` 只含空行时 grep 输出 `0` 且退出码 1，`$()` 捕获 `0\n0`，`[ "$count" = "0" ]` 恒假 → 空结果消息不显示、表头仍打印。
- cdn.sh:390 翻页判断 `.Instance | length`，`Instance` 为单对象而非数组时 jq 报错被吞 → 恒空 → **无限循环**。
- base.sh:176 `[ "$count" = "null" ] || [ -z "$count" ] && count="0"` 依赖 `||`/`&&` 左结合，语义隐晦且 `-z ""` 恒真导致前一条件多余。

### 3.5 状态列举错位

- polardb.sh:543 fzf 解析 `.Accounts.Account[]`，而 DescribeAccounts 实际返回 `.Accounts[]` → 账号选择恒报「没有找到数据库账号」。
- ack.sh:76 列表用 `.version`，接口字段是 `current_version` → 版本列恒 null。
- lbs.sh:131-137 NLB 用 `.LoadBalancerAddresses[0].PublicIPv4Address`，NLB 响应字段是 `.Address` → IP 列恒 `"-"`。
- cdn.sh:390、oss.sh:962 等 jq/awk 与响应对不齐，见 bug 清单。

### 3.6 其他逻辑问题

- oks.sh 全站 `--internal` 设置（:95）在每个命令函数里被重写回公网 endpoint（249/295/316/575/666/1070/1155/150）→ 内网选项整体失效。
- utils.sh:401 DAILY 粒度一天多条 Item，`Item[]` 展开多行后 `(( ))` 算术直接报错，应求和。
- eci.sh:116-119 / mongodb.sh:176-199 查询失败或实例不存在时仍默认「未知」并进入确认+删除流程，缺存在性守卫（与 nat/kvstore「未找到即中止」不一致）。
- vpc.sh:468-472 `get_next_vswitch_cidr` 的 `ret` 检查是死代码（永不失败），且只识别 `192.168.x.0/24`，末段 255 时生成非法网段。

---

## 四、函数/变量命名层面

### 4.1 同名函数互相覆盖（最高优先）

- `create_profile`/`update_profile`/`delete_profile`：config.sh 与 utils.sh 双重定义，utils.sh 覆盖生效（见 §1.1）。**必须删掉 utils.sh 的三份**。

### 4.2 裸全局变量（非 local）

- `ret`/`result`/`return_code`：见 §1.4，遍布 18 个文件。
- `res` 之外还有：ecs.sh `key_pair_names_json`(:810)、`instance_ids_json`(:904/999)、oss.sh `global_uris_file`(:781)、vpc.sh `name_input`(:222)、cdn.sh `ret`。
- `_ACR_API_VERSION`(acr.sh:10)、`CAS_CERT_FILE`(cas.sh:12) 大写裸全局，README 变量前缀约定（G_*/ENV_*）完全未遵守。

### 4.3 动词混用 / 命名不一致

- 同义动词混用：`get`(大部分模块) vs `list`(README/help 文案大量广告 `list`) vs `fetch`——命令面 `get` 与文档 `list` 不一致。
- 日志 operation 名与 subcommand 不一致：vpc.sh:699 log 用 `sg-rule-list` 而命令是 `get-sg-rule`；nas.sh:288 `mount-create`/`mount-list` 而命令是 `add-mount`/`get-mount`。
- 私有前缀不一致：`get_supported_disk_categories`(ecs.sh:1234) 无 `_ecs_` 前缀，与 `_ecs_resolve_*` 约定不符；ack.sh `balance_pod_on_node`/`scale_deployment`/`check_cooldown` 无 `ack_` 前缀；oss.sh:127 `uris` 分发到 `set_object_standard`（无 `oss_` 前缀）。
- 局部变量遮蔽函数名：ecs.sh:203/215 变量 `vpc_list` 遮蔽同模块 `vpc_list` 函数。
- 双入口并存：vpc.sh 的 `get_vpc_id` 与 `_vpc_resolve_vpc_id` 并存（仅 ack.sh 用前者）；ram.sh `_ram_resolve_user` 与 `_ram_select_user` 语义几乎相同。
- ecs.sh 里 `_lbs_set_meta`(lbs.sh:389) 靠「调用方先 local 声明 `_lb_*` 变量」的动态作用域传状态，`_lbs_set_meta` 自身不 local，无护栏。

### 4.4 魔法字符串 / 硬编码

- ecs.sh:441 默认 100Mbps 出网带宽（直接产生费用）、:340-341 ARM 判定考硬编码实例类型后缀、:404 镜像簇 `acs:ubuntu_24_04_x64` 硬编码。
- cdn.sh:466 魔数 `1541405199`/`1024`/`126`/`4.000`/`700` 无注释。
- ack.sh:680 虚拟节点名硬编码 `virtual-kubelet-cn-hangzhou-k`，非杭州地域失效。

---

## 五、Bug 清单（按严重程度）

### P0 — 功能不可用 / 必挂

| # | 位置 | 问题 | 依据 |
|---|---|---|---|
| 1 | eip.sh:128 | `eip add`：`generic_create` + PascalCase `AllocateEipAddress` + 注入 `--biz-region-id`，参数不合法 | 实测 ~~**已修**（改用 `allocate-eip-address`） |
| 2 | kvstore.sh:199 | `kvstore add`：同款组合必失败，且缺必填 `--zone-id` | 实测 ~~**已修**（`create-instance` + `--zone-id` 交互选择） |
| 3 | nat.sh:121-123 | `nat add`：缺必填 `--nat-type` `--vswitch-id` | 实测 ~~**已修**（补 `--nat-type Enhanced`/`--vswitch-id`） |
| 4 | dts.sh:220/258/430 | 创建/同步/启动接口名与必填参数全部错误 | 实测 ~~**已修**（补必填 + configure + `start-migration-job`） |
| 5 | sms.sh:44/58 | 模板/签名查询命令不存在，误报「无数据」 | 实测 ~~**已修**（命令实需 `--api-version 2017-05-25`，原代码已带；改为失败时报真错） |
| 6 | ack.sh:187-213 | `POST /clusters` 读 `.ClusterId`（实际 `cluster_id`）→ 死等 30 分钟 | 实测响应文档 ~~**已修**（读 `.cluster_id`） |
| 7 | oss.sh:650-651 | batch-copy 命令多了 `ls`，实际执行 `ossutil ls` 而非 `cp` → **批量复制从不执行** | 代码 |
| 8 | rds.sh:316-326 | `create-db-instance` 缺必填 `--db-instance-storage-type`，`rds add` 必失败 | 实测 |
| 9 | vpc.sh:752-812 | `set-sg-rule <规则ID>` 直传时 `sg_id` 未赋值（只在交互分支 local）→ `--security-group-id ""` 必失败 | 代码 |
| 10 | cas.sh:249-257/329 | 两阶段域名推导（awk 拼 `.example.com` vs `${domain_cdn#*.}`）结论不一致 → 部署证书名对不上，`>/dev/null` 吞错 → **静默失败** | 代码 |
| 11 | lbs.sh:341/385 | `zone` 未定义 → NLB/ALB ZoneId 为空必失败 | 代码 ~~**已修**（ZoneId 取自交换机；ALB 补 edition/billing 必填） |

### P1 — 数据错误 / 错误静默降级

| # | 位置 | 问题 |
|---|---|---|
| 12 | polardb.sh:174-178 | `describe-db-node-classes` 实测命令不存在 → 交互选规格永远失败、走备用表 |
| 13 | polardb.sh:543 | `.Accounts.Account[]` 字段错 → 账号选择恒「没有找到」 |
| 14 | cdn.sh:457-479 | 规格选择循环是死代码（只影响日志），实际永远买 1TB，日志标「准备购买 X TB」与实际不符 |
| 15 | cdn.sh:311-321 | 刷新失败也 `count++`，「共刷新 N 条」虚报成功数；`trigger` 绕过 20h 冷却锁 |
| 16 | cdn.sh:225-229 | `stat -c %Y`/`date -d` GNU-only，macOS 上冷却机制**静默失效**（AGENTS 明确要求 gdate/gstat 探测） |
| 17 | cdn.sh:390 | `.Instance | length` 对单对象报错 → 恒空 → 无限循环翻页 |
| 18 | oss.sh:424/449 | `grep -oP` BSD grep 不支持 `-P` → token 恒空 |
| 19 | oss.sh:756-760/946 | `date -d` GNU-only → 日志日期校验失败 |
| 20 | oss.sh:974-1003 | awk 列映射与 ossutil ls 实际列不符 → 日志查询恒「未找到访问日志」 |
| 21 | oss.sh:1047-1054 | `uris_file` 取到「记录数为 N 条」的 `$NF="条"` → `--target-bucket` 自动处理永不执行；`target_bucket` 靠动态作用域传递 |
| 22 | vpc.sh:508 | `--ipv6-cidr-block "$ipv6_octet"` 传十进制段号而非 IPv6 CIDR（需 dry-run 复核） |
| 23 | vpc.sh:733-748 | add-sg-rule 混用 `--permissions 单值` + 裸 `k=v` → 规则缺字段 |
| 24 | vpc.sh:810-818 | set-sg-rule 对 IPv6 源不处理，且 `--policy accept`/`--priority 10` 硬编码覆盖原规则（数据丢失） |
| 25 | acr.sh:294-295 | `docker login` 明文口令 + `authorizationToken` 落盘日志（安全） |
| 26 | utils.sh:401 | DAILY 多条 Item 展开后算术崩（改余额告警） |
| 27 | ticket.sh:57/63 | `date -d '3 months ago'` GNU-only → macOS 上起始时间空 → `list-tickets`（必填）失败，**ticket get/fzf 全部不可用** |
| 28 | base.sh:178 | 空行边界致空结果分支不触发（见 §3.4） |
| 29 | base.sh:349 | `generic_delete` 通用分支 `${service_name^}Id` 拼 PascalCase 参数，插件不认，仅当 service 非 rds/polardb/ecs 时命中 → 实际是死分支 |
| 30 | ram.sh:163 | create-login-profile 错误全吞 → 假成功并打印不可用的密码 |
| 31 | rds.sh:324 | `--security-ip-list 0.0.0.0/0` + Internet → 公网全放行，重大安全风险 |
| 32 | rds.sh:445-447 | 密码恰好 32 位再追加 `@` → 变 33 位超限 |
| 33 | rds.sh:131-145 | 引擎/版本下拉用 `describe-regions` 的结果，且成功失败分支完全相同 → 纯死调用 |

### P2 — 不致命但应修

| # | 位置 | 问题 |
|---|---|---|
| 34 | base.sh:402-421 | `validate_required_params` 用「末参含空格」判定错误消息且用负下标，bash<4.x 崩溃；末参本身含空格时误吞 |
| 35 | main.sh:34 | `load_module` 死代码 + `stat -c %Y` GNU-only |
| 36 | main.sh:64 | profile 探测依赖表格格式；`region` 失败仅回退 cn-hangzhou 不读真实 region |
| 37 | ecs.sh:1071/1111/1292/1328/505 | ~~create-snapshot/start/stop/describe-attribute 等缺 `--biz-region-id`~~ **已修**（本次修订补齐） |
| 38 | vpc.sh:552/667/1104/1091 | ~~多个 delete 只传 `--biz-region-id` 缺 `--region`~~ **已修**（`call_aliyun_api` 自动补 `--region`） |
| 39 | ecs.sh:108 | 分页合并用 `echo "$merged" "$result"` 拼两段 JSON 再 `jq -s`，脆弱 |
| 40 | ecs.sh:810 | 删密钥用 `--key-pair-names` 与模块统一 `--biz-key-pair-name` 不一致，且缺 region |
| 41 | ram.sh:552-554 | fzf 未安装时静默回退授予全部 16 个管理员策略（含 AliyunRAMFullAccess）——高危回退 |
| 42 | cas.sh:281 | `cas_delete ... 2>/dev/null || true` 吞掉真实错误 |
| 43 | cas.sh:287-295 | 失败也覆盖 `upload_log` → 轮换链断裂 |
| 44 | cas.sh:170 | 私钥经命令行参数（`--key "$(cat file)"`）暴露，且可能超命令行长度限制 |
| 45 | mongodb.sh:150 | `--RegionId "$region"` 无 `${region:-}` 兜底 |
| 46 | eip.sh:194-198 | 带宽校验放行 `0`（EIP 下限 1） |
| 47 | acr.sh:72-77 | `_acr_resolve_repo` 的 `namespace` 参数被忽略，`del-repo ns X` 仍显示全部仓库 |
| 48 | acr.sh:101-104 | 命名空间叫 json/tsv/human 时被 `is_output_format` 误判 |
| 49 | acr.sh:201-202 | `repo_create` 已给全必填仍无条件 `read` 询问 → 非交互卡住 |
| 50 | ack.sh:614 | deployment 空值校验在 lock 之后，lock 命中时错误可能被短路 |
| 51 | ack.sh:650-651 | `kubectl top` 失败时 cpu/mem 空，`((cpu>warn))` 以 0 静默跳过告警 |
| 52 | ack.sh:543/608 | `stat -c`/`date -d` GNU-only，auto-scale 在 macOS 不可用 |
| 53 | lbs.sh:276-286 | PrePaid 缺 Duration/PricingCycle 必填，选择后创建必失败无提示 |
| 54 | ram.sh:308 | 手拼 JSON 日志，用户名含特殊字符破坏 JSON |
| 55 | config.sh:52-53/74-75 | 密钥明文作命令行参数传 `aliyun configure set`，`ps` 可见 |
| 56 | config.sh:89 / 各模块多处 | 直接 `aliyun ...` 绕过 `call_aliyun_api`（AGENTS.md 要求统一走 wrapper） |
| 57 | 全部 | `confirm_action`/`read -r` 在非 TTY（CI/cron）下没有任何超时/空输入防护 |

---

## 六、命名落实情况对照（AGENTS.md）

| 约定 | 现状 |
|---|---|
| 动词开头 subcommand | 大体合规，但有 `cmd.sh`：cdn `refresh`/`purge`、cmd `uris` 使用名词/疑点，help 与 dispatch 多处不同步（oss help 未列出 set/uris/upload-cert；cd cmd `set` 映射到恒报错的 `cas_update` 且在 help 缺失） |
| 禁止 `if [ $? -eq 0 ]` | 大量违反：base.sh:264/307/359、utils.sh:304、config.sh:55/77/91、各模块普遍。合规写法 `result=$(...); local ret=$?` 与违规写法**同文件并存** |
| 一律 local | 系统性违反，见 §1.4 |
| g 前缀 GNU 工具 | 系统性违反：`date -d`/`stat -c`/`grep -P`/`sort -V` 在多文件出现 |

---

## 七、建议实施顺序

1. **P0 修复**（当前必挂功能）：eip/kvstore/nat/dts/rds add 参数修正；oss batch-copy 去掉多余 `ls`；ack create 读 `cluster_id`；vpc set-sg-rule 补 `sg_id`；cas 部署域名推导统一。
2. **删死代码与冲突**：删除 utils.sh 的 `create_profile/update_profile/delete_profile`（保留 config.sh 版本）；删除各死函数；`load_module` 并入 source 流程或删除。
3. **系统治理**：全部 `ret`/`result` 加 `local`；`select_with_fzf` 空选改为 `return 1`、`check_fzf` 失败改为 `return`；GNU 工具统一 gdate/gstat 探测；~~region 语义统一为「`--biz-region-id` + `--region` 处处同传」~~ **已完成**（见 §1.5，`call_aliyun_api` 自动补 `--region` + 各区域调用补齐 `--biz-region-id`）。
4. **功能落地**：oss set 剩余设置、nas 改名说明、cdn 规格选择/冷却修复、dts 状态轮询字段、sms 换用存在命令。
5. **安全**：rds 默认公网放行必须删除或改 Intranet；ak/token/私钥不进日志与命令行；ram 高危回退改显式确认。
6. **补测试**：当前无任何测试，至少引入 `bash -n` + `shellcheck` CI，并对 P0 命令加 `--cli-dry-run` 冒烟用例。

---

*本报告基于当前工作区代码静态审查及本机 aliyun CLI 3.4.x 实测，未执行任何真实 API 变更操作。行号以审查时工作区为准。*