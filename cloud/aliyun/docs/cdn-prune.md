# OSS 源站目录清理评估（三步设计）

用 CDN 离线日志判断 OSS 源站哪些目录长期未被访问，生成「先备份、再删除」的脚本。

拆成**三个可独立运行、按文件解耦**的步骤：

| 步骤 | 命令 | 归属 | 产出 |
|---|---|---|---|
| 1 | `oss dirsize` | `oss.sh` | 目录列表 + 大小清单（倒序） |
| 2 | `cdn access` | `cdn.sh` | 三层访问清单（按 bucket） |
| 3 | `oss prune` | `oss.sh` | 比较两个清单 → 备份/删除脚本 |

```
步骤1  oss dirsize ──► dirs-<bucket>.txt / sizes-<bucket>.tsv
                                    │
步骤2  cdn access  ──► access-<bucket>.txt ─────┤
                                    ▼
步骤3  oss prune   ──► candidates-<日期>-<bucket>.txt
                       backup-<日期>-<bucket>.sh（只备份）
                       rm-<日期>-<bucket>.sh（只删除 --all-versions，备份存在才删）
```

## 硬性约束

- **列目录只用 `ls -d`；绝对禁止 `ls -r`**（会卡死）。
- **取大小**：`--source inventory`（**默认**，读 OSS 存储清单，精确、不实时扫桶，推荐大桶）或
  `--source du`（叶子 `du`+上卷，约 1 遍扫描；上级直属对象少计）。
  **禁止用 `ls`（含非递归）取对象**；`du` 必须带前缀，**不得用 `du -d`**（只数占位对象、无明细）。
- 目录最多 3 层；比较也最多 3 层。
- `--source du` 只统计叶子后上卷，上级目录直属对象不计（少计方向）；要精确用 inventory（默认）。
- 三个步骤互不触发对方的网络操作：步骤 3 只读前两步的缓存文件。

## 缓存路径总览（三步共用同一根目录，避免分散）

```
PRUNE_DIR="${SCRIPT_DATA}/cache/<profile>/<region>/prune"
```

| 路径 | 生产方 | 说明 |
|---|---|---|
| `$PRUNE_DIR/<bucket>.dirs.txt` | 步骤1 | 目录结构（每行 `/目录`） |
| `$PRUNE_DIR/<bucket>.sizes.tsv` | 步骤1 | `路径<TAB>字节`，倒序 |
| `$PRUNE_DIR/<bucket>.struct.date` / `<bucket>.size.date` | 步骤1 | 结构与大小的缓存时间戳 |
| `$PRUNE_DIR/access/<域名>/<日>.txt` | 步骤2 | 每日访问档案 |
| `$PRUNE_DIR/abnormal/<域名>/<日>.txt` | 步骤2 | 每日异常档案 |
| `$PRUNE_DIR/access-<bucket>.txt` / `abnormal-<bucket>.txt` | 步骤2 | 按桶三层并集 |
| `$PRUNE_DIR/candidates-<日期>-<bucket>.txt` | 步骤3 | 候选清单（倒序） |
| `$PRUNE_DIR/backup-<日期>-<bucket>.sh` | 步骤3 | 只做备份（sync）的脚本 |
| `$PRUNE_DIR/rm-<日期>-<bucket>.sh` | 步骤3 | 只做删除（rm --all-versions）的脚本 |

---

## 步骤 1：`oss dirsize`（生成目录列表 + 大小清单）

### 用法

```
bash main.sh -p <profile> [-r <region>] oss dirsize <bucket> \
    [--source inventory|du] [--inventory oss://dest/prefix/] \
    [--min-size 1G] [--exclude <prefix>] [--depth 3] [--refresh]
```

- `--source`：`inventory`（默认）或 `du`。
- `--inventory`：清单目录，形如 `oss://<dest-bucket>/[<prefix>/]<源桶>/<清单ID>/`。
  省略时取环境变量 `OSS_INVENTORY_BASE/<桶>/${OSS_INVENTORY_ID:-report1}/`；
  两者都没有或清单不可用 → **自动回退 `--source du`**。
- `--min-size`：只写 ≥ 该大小的目录（默认 `1G`；`0` 表示全写）。
- `--exclude`：排除前缀，可重复（默认含 `oss-inventory/`）。
- `--refresh`：忽略缓存强制重建。

### 流程（`--source inventory`，默认，推荐大桶）

不实时扫桶，直接读 OSS 已生成的**存储清单**：

1. 在 `oss://<dest-bucket>/<path>/...` 下定位最新的清单时间戳目录，读 `manifest.json` 取 `fileSchema` 与数据文件列表。
2. 逐个 `ossutil cat <data.csv.gz> | gunzip -c`，按 `fileSchema` 里 `Key`/`Size` 列解析，Key 做 URL 解码。
3. 每个对象按 ≤3 层目录前缀累加大小 → `dirs.txt` + `sizes.tsv`（**含直属对象，精确**）。
4. 结果同样受 `--min-size` / `--exclude` 约束；缓存 30 天。

> Inventory 需先按下一节配置好（或用 `oss inventory add` 一键创建）。

### 流程（`--source du`，回退/无清单时）

1. **定位桶区域**：`ossutil stat` 的 `ExtranetEndpoint`，失败回退 profile region。
2. **目录结构（缓存 7 天）**
   - 从根用 `ls -d` 逐层递归 ≤3 层；每层并行 `xargs -P`，单次 `timeout 30`。
   - 只保留 URL 以 `/` 结尾的行（目录），去尾斜杠、去重，输出 `/a`、`/a/b`、`/a/b/c`。
3. **目录大小（缓存 30 天）：只 `du` 叶子目录，再向上求和**
   - 叶子 = 结构里没有子目录的目录（如 `/a/b/c`）；只对叶子 `du` → 约 **1 遍**对象扫描（对比"每个目录都 du"要 ~3 遍）。
   - 把每个叶子的大小累加到它的所有祖先前缀，得到各目录大小。
   - **注意**：上级目录自己的**直属对象不计**（误差方向=少计，只漏删不误删）；会打印告警。
   - 按字节倒序写 `sizes-<bucket>.tsv`；只保留 ≥ `--min-size` 的目录。
   - `du` 无并行参数，靠 `_OSS_DU_JOBS`（默认 8）在目录间并行；**不要用 `du -d`**。
4. **过滤**：剔除 `--exclude` 前缀。

### 产出文件

```
$PRUNE_DIR/<bucket>.dirs.txt      # 每行一个 /目录
$PRUNE_DIR/<bucket>.sizes.tsv     # 路径<TAB>字节，按字节倒序
$PRUNE_DIR/<bucket>.struct.date   # 结构生成日期
$PRUNE_DIR/<bucket>.size.date     # 大小生成日期
```

`sizes-<bucket>.tsv` 示例（倒序）：

```
/image/public/content	322122547200
/video	21474836480
/zk_project	1073741824
```

### 边界

- 缓存过期独立判断：结构 7 天、大小 30 天；只重建过期的那部分。
- 结构/size 缓存与访问无关，任何来源都不得改写它们。
- `--source du` 的误差只在"上级目录直属对象"（少计）；要精确用 `--source inventory`。

---

## 步骤 1 附：配置 OSS 存储清单（Inventory）

> 参考《使用存储空间清单》。清单由 OSS **异步、定期**扫描生成 Gzip CSV，投递到目标 Bucket，
> 之后 `oss dirsize --source inventory` 只下载清单聚合，不再实时扫桶——**大桶（百万/亿级对象）唯一实用方案**。

### 0. 用 `oss inventory` 命令管理清单（推荐）

```bash
# 创建规则（Prefix 不带尾斜杠；--role 默认账号的 aliyunossrole）
bash main.sh -p <profile> oss inventory add <源桶> \
  --dest <目标桶> --prefix oss-inventory --id report1 --freq Weekly

# 查看 / 列举 / 删除
bash main.sh -p <profile> oss inventory get  <源桶> --id report1
bash main.sh -p <profile> oss inventory list <源桶>
bash main.sh -p <profile> oss inventory del  <源桶> --id report1
```

> - 同 id 已存在时 PUT 报 `409`，先 `del` 再 `add`。
> - 首份报告约 **2~9 分钟**异步生成（不用等一个周期）；要更快验证可用 `--freq Once`。
> - 下面第 1~4 步是等价的**手动方式**（自定义最小权限角色/XML），不需要时可跳过。

### 1. 准备

- 目标 Bucket 必须与源 Bucket **同账号、同 Region**；建议**独立桶**（本桶也可，但要排除报告前缀，见注意事项）。
- 需要 RAM 角色授权 OSS 读源桶、写目标桶。**全程命令行**即可，不必用控制台：
  首次用控制台会引导自动建 `AliyunOSSRole`；纯命令行就按下面第 2 步自己建（生产建议最小权限角色）。

### 2. 纯命令行创建 RAM 角色（替代控制台）

```bash
# 2.1 信任策略：允许 OSS 服务扮演该角色
cat > trust.json <<'JSON'
{"Version":"1","Statement":[{"Effect":"Allow","Action":"sts:AssumeRole",
  "Principal":{"Service":["oss.aliyuncs.com"]}}]}
JSON

# 2.2 创建角色
aliyun --profile <profile> ram create-role \
  --role-name OSSInventoryRole \
  --assume-role-policy-document file://$PWD/trust.json

# 2.3 权限策略：允许写目标桶（清单报告落盘处）
cat > policy.json <<'JSON'
{"Version":"1","Statement":[{"Effect":"Allow","Action":["oss:PutObject"],
  "Resource":["acs:oss:*:*:<dest-bucket>/*"]}]}
JSON
aliyun --profile <profile> ram create-policy \
  --policy-name OSSInventoryPut \
  --policy-document file://$PWD/policy.json

# 若清单任务报源桶权限错误，再给角色补 oss:GetObject/oss:ListObjects（资源写源桶）：
#   "Action":["oss:GetObject","oss:ListObjects"], "Resource":["acs:oss:*:*:<源桶>/*","acs:oss:*:*:<源桶>"]

# 2.4 绑定到角色
aliyun --profile <profile> ram attach-policy-to-role \
  --role-name OSSInventoryRole \
  --policy-name OSSInventoryPut \
  --policy-type Custom

# 2.5 取角色 ARN（填到 inventory.xml 的 RoleArn）
aliyun --profile <profile> ram get-role --role-name OSSInventoryRole \
  | jq -r '.Role.Arn'
```

### 3. 用 ossutil 配置清单规则

写一个 `inventory.xml`（`RoleArn` 用上一步的 ARN，`AccountId`/`Bucket` 填目标桶）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<InventoryConfiguration>
  <Id>report1</Id>
  <IsEnabled>true</IsEnabled>
  <Destination>
    <OSSBucketDestination>
      <Format>CSV</Format>
      <AccountId>100000000000000</AccountId>
      <RoleArn>acs:ram::100000000000000:role/OSSInventoryRole</RoleArn>
      <Bucket>acs:oss:::dest-bucket</Bucket>
      <Prefix>oss-inventory</Prefix>
    </OSSBucketDestination>
  </Destination>
  <Schedule>
    <Frequency>Weekly</Frequency>
  </Schedule>
  <IncludedObjectVersions>Current</IncludedObjectVersions>
  <OptionalFields>
    <Field>Size</Field>
    <Field>LastModifiedDate</Field>
    <Field>StorageClass</Field>
  </OptionalFields>
</InventoryConfiguration>
```

> - `Size` 必选；`StorageClass` 便于将来做 IA→Standard 之类的分析。
> - **`Prefix` 不要带结尾斜杠**：写 `oss-inventory`。若写成 `oss-inventory/`，实际路径会变成
>   `oss-inventory//<源桶>/...`（双斜杠），`--inventory` 就得跟着写双斜杠，很别扭。
> - **PUT 不能覆盖**：同 `inventory-id` 已存在时 `put-bucket-inventory` 报
>   `409 InventoryConfigurationAlreadyExists`，需先 `delete-bucket-inventory` 再 `put`。
> - **首份报告不是"立即"但也不用等一个周期**：实测新建规则后约 **2~9 分钟**异步生成
>   （含 819 万对象的大桶也在此量级；具体受队列影响）。`Frequency=Once` 可用于尽快出一份做验证。

下发生效（`--inventory-configuration` 必须用 `file://` 绝对路径）：

```bash
aliyun --profile <profile> ossutil api put-bucket-inventory \
  --bucket <源桶> --inventory-id report1 \
  --inventory-configuration "file://$PWD/inventory.xml" \
  --endpoint http://oss-<region>.aliyuncs.com --region <region>
```

校验 / 查询 / 删除：

```bash
aliyun --profile <profile> ossutil api get-bucket-inventory  --bucket <源桶> --inventory-id report1 --endpoint http://oss-<region>.aliyuncs.com --region <region>
aliyun --profile <profile> ossutil api list-bucket-inventory --bucket <源桶> --endpoint http://oss-<region>.aliyuncs.com --region <region>
aliyun --profile <profile> ossutil api delete-bucket-inventory --bucket <源桶> --inventory-id report1 --endpoint http://oss-<region>.aliyuncs.com --region <region>
```

（`Frequency` 可选 `Daily`/`Weekly`/`Monthly`；文件超百亿建议 `Weekly`。首份清单配置后立即生成，之后按周期在凌晨异步跑。）

### 4. 清单目录结构

```
dest-bucket/oss-inventory/<源桶>/report1/
├── 2026-09-14T16-00Z/          ← 扫描启动时间（UTC）
│   └── manifest.json           ← fileSchema + data 文件列表
└── data/
    └── <uuid>.csv.gz           ← 每行一个对象（含 Key、Size）
```

把 `oss://dest-bucket/oss-inventory/<源桶>/report1/` 传给 `--inventory`：

```bash
bash main.sh -p <profile> oss dirsize <源桶> \
  --source inventory --inventory oss://dest-bucket/oss-inventory/<源桶>/report1/
```

### 5. 缓存与刷新

- `oss dirsize` 按 `<bucket>.size.date` 做 30 天缓存；清单本身更新频率由 `Frequency` 决定。
- 清单更新后想立刻重取：加 `--refresh`。


## 步骤 2：`cdn access`（获取日志，生成三层访问清单）

### 时间口径（关键，勿改错）

- CDN 日志的**时间戳 / 文件名用北京时（UTC+8）**：
  例 `.vrupup.com_2026_09_13_000000_010000.gz` 内容是 `[13/Sep/2026:00:40:47 +0800]`。
- `describe-cdn-domain-logs` 的 `--start-time/--end-time` 用 **UTC**（ISO8601，结尾 `Z`）。
- **业务日 = 北京时日历日**。北京日 `X` 的"全天日志"→ UTC 窗口 **`[X-1 16:00Z, X 16:00Z)`**：
  - 北京 `X 00:00` = UTC `X-1 16:00Z`（起点）
  - 北京 `X+1 00:00` = UTC `X 16:00Z`（终点，开区间）
- 换算：`start = epoch(X 00:00Z) - 8h`，`end = epoch(X 00:00Z) + 16h`。
- 实测：北京 `09-13` → UTC `[2026-09-12T16:00:00Z, 2026-09-13T16:00:00Z)`，返回 **24** 个文件
  `..._2026_09_13_000000_010000.gz`（内容 `00:40 +0800`）… `..._2026_09_13_230000_240000.gz`（内容 `23:54 +0800`）。
- **反例（别再犯）**：误按"UTC 日历日 `[X 00:00Z, X+1 00:00Z)`"取数 = 北京 `[X 08:00, X+1 08:00)`，整体偏移 8 小时。

### 用法

```
bash main.sh -p <profile> [-r <region>] cdn access \
    [--days 30] [--domain <域名>] [--bucket <桶名>] [-s 起] [-e 止]
```

### 流程

1. `cdn describe-user-domains --pager` 得「域名 → bucket」（仅 `Type=oss`；`Content` 必须形如 `<bucket>.oss-*`，否则告警跳过）。
2. **每日归档（原子写）**：主任务取昨日 + 窗口内补档（每次每域名 ≤3 天），写：
   - `access/<域名>/<日>.txt`：从 URL 抽出的 ≤3 层目录前缀（去文件名段、去重）。
   - `abnormal/<域名>/<日>.txt`：4xx/5xx 异常 URI。
   - 全部 `curl` 成功后 `mv` 成正式档案，失败不留残缺档案。
3. **聚合三层清单**：按 bucket 把其所有域名、最近 `--days` 天的访问目录取并集，写 `access-<bucket>.txt`（≤3 层），异常同理写 `abnormal-<bucket>.txt`。
4. 打印每个域名的覆盖天数、昨日访问目录数、异常数。

### 产出文件

```
$PRUNE_DIR/access/<域名>/<日>.txt   # 每日档案
$PRUNE_DIR/abnormal/<域名>/<日>.txt
$PRUNE_DIR/access-<bucket>.txt      # 三层访问并集
$PRUNE_DIR/abnormal-<bucket>.txt
```

### 边界

- 只负责"日志 → 目录清单"，不做任何 OSS 列目录或 `du`。
- 业务日按**本地（北京时 UTC+8）**：CDN 日志的时间戳/文件名都是北京时，而 API 参数用 UTC。
  所以本地昨天 `X` 的窗口 = `[X-1 16:00Z, X 16:00Z)`（= 北京 `[X 00:00, X+1 00:00)`）。
- 该命令可每日跑；窗口内档案靠补档逐步补齐。

---

## 步骤 3：`oss prune`（比较两个清单，生成备份/删除脚本）

### 用法

```
bash main.sh -p <profile> [-r <region>] oss prune <bucket> \
    [--days 30] [--min-size 1G] [--exclude <prefix>] [--dry-run]
```

### 流程

1. **读缓存**：
   - `$PRUNE_DIR/<bucket>.dirs.txt` + `$PRUNE_DIR/<bucket>.sizes.tsv`（步骤 1）。
   - `$PRUNE_DIR/access-<bucket>.txt`（步骤 2）。
   - 任一缺失/过期 → 明确提示先跑对应步骤，本轮不比较、不生成脚本。
2. **比较**：
   - `blocked = 访问目录 + 其所有祖先链`。
   - `候选 = dirs − blocked`，**只保留最浅的候选**（祖先入选则其后代不再单列，避免重复删除）。
   - 过滤：`size ≥ --min-size`；剔除 `--exclude` 前缀。
   - 按大小倒序。
3. **产出**：
   - `candidates-<日期>-<bucket>.txt`（完整候选，倒序）。
   - 非 `--dry-run` 生成**两个**脚本：`backup-<日期>-<bucket>.sh`（只备份）+ `rm-<日期>-<bucket>.sh`（只删除）。

### 备份 / 删除脚本（拆成两个文件）

`ossutil sync` 的退出码不可靠，不能用 `sync && rm` 保证"备份失败就不删"，所以**拆成两个脚本、分两次人工执行**：

**`backup-<日期>-<bucket>.sh`（只备份，不删除）**
```bash
#!/usr/bin/env bash
set -e

PROFILE="<profile>"
ENDPOINT="http://oss-<region>.aliyuncs.com"
REGION="<region>"
BACKUP_ROOT="<SCRIPT_DATA>/prune-backup/<日期>/<bucket>"

echo "备份 oss://<bucket>/a/b/"
mkdir -p "${BACKUP_ROOT}/a/b"
aliyun --profile "${PROFILE}" ossutil sync --endpoint "${ENDPOINT}" --region "${REGION}" \
  "oss://<bucket>/a/b/" "${BACKUP_ROOT}/a/b/"
```

**`rm-<日期>-<bucket>.sh`（只删除，`--all-versions`）**
```bash
#!/usr/bin/env bash
set -e

PROFILE="<profile>"
ENDPOINT="http://oss-<region>.aliyuncs.com"
REGION="<region>"
BACKUP_ROOT="<SCRIPT_DATA>/prune-backup/<日期>/<bucket>"

echo "删除 oss://<bucket>/a/b/"
n=$(find "${BACKUP_ROOT}/a/b" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "${n:-0}" -gt 0 ]; then
    aliyun --profile "${PROFILE}" ossutil rm -r -f --all-versions \
      --endpoint "${ENDPOINT}" --region "${REGION}" "oss://<bucket>/a/b/"
else
    echo "  跳过：备份无文件（${BACKUP_ROOT}/a/b，计数 ${n:-0}）" >&2
fi
```

- `rm` 脚本对每条候选**统计备份目录里的文件个数**，为 0（或目录不存在）则**跳过**，避免未备份就删。
  （只判断目录存在不可靠：`sync` 失败时也可能留下空目录。）
- 使用流程：跑 `backup-*.sh` → 人工核对备份 → 跑 `rm-*.sh`。

### 产出文件

```
$PRUNE_DIR/candidates-<日期>-<bucket>.txt
$PRUNE_DIR/backup-<日期>-<bucket>.sh
$PRUNE_DIR/rm-<日期>-<bucket>.sh
```

### 边界

- 只读步骤 1、2 的缓存，不发起 CDN / OSS 列举请求。
- 定时由外部 cron 决定（建议每月一次）；不再内置 30 天计时器。

---

## 数据契约（三步骤只靠文件解耦）

以下文件均在 `$PRUNE_DIR/` 下：

| 文件 | 生产方 | 消费方 | 格式 | TTL |
|---|---|---|---|---|
| `<bucket>.dirs.txt` | `oss dirsize` | `oss prune` | 每行 `/目录` | 7 天 |
| `<bucket>.sizes.tsv` | `oss dirsize` | `oss prune` | `路径<TAB>字节`（倒序） | 30 天 |
| `access-<bucket>.txt` | `cdn access` | `oss prune` | 每行 `/目录`（≤3 层并集） | 每次运行覆盖 |
| `abnormal-<bucket>.txt` | `cdn access` | 人工/报表 | `状态码<TAB>uri` | 每次运行覆盖 |

## 建议 cron

**业务日按本地（北京时 UTC+8）**：CDN 日志的时间戳/文件名都是北京时，API 参数用 UTC。
本地昨天 `X` 的窗口 = `[X-1 16:00Z, X 16:00Z)`（= 北京 `[X 00:00, X+1 00:00)`）。该窗口在
北京 `X+1 00:00`（= UTC `X 16:00Z`）关闭；留投递延迟，**上午 10 点**跑。

cron 环境 PATH 极简，且本机 `jq` 由 mise 管理、`bash` 需 5.x，所以要显式设 PATH 并用绝对路径 bash；
不加 `cd`（脚本按自身路径解析项目根）。

> 算例（现在=北京 09-14）：
> - 本地昨天 = 09-13。
> - 抓取窗口 = UTC `[09-12 16:00Z, 09-13 16:00Z)` = 北京 `[09-13 00:00, 09-14 00:00)`。
> - 该窗口在北京 09-14 00:00（UTC 09-13 16:00Z）关闭 → 10:00 跑时已过 10 小时（含投递延迟余地）。
> - 实测 `.vrupup.com` 该窗口返回 24 个文件，文件名 `..._2026_09_13_000000_010000.gz` ~ `..._230000_240000.gz`（北京全日）。

```cron
# cron 赋值行不展开变量：PATH 写绝对路径（把 <home> 换成家目录）
PATH=/usr/local/bin:/usr/bin:/bin:<home>/.local/share/mise/shims

# 每天 10:00：取本地(北京)昨天日志、生成三层访问清单
0 10 * * * /usr/local/bin/bash /path/to/deploy.sh/cloud/aliyun/main.sh -p <profile> cdn access >> /tmp/aliyun-cdn-access.log 2>&1

# 每周日 08:00：读清单生成目录 + 大小清单
#   注意：dirsize 有 30 天缓存，定时刷新必须加 --refresh（否则每周跑也会复用缓存不更新）
0 8 * * 0 /usr/local/bin/bash /path/to/deploy.sh/cloud/aliyun/main.sh -p <profile> oss dirsize <源桶> --inventory oss://<目标桶>/<清单前缀>/<源桶>/report1/ --refresh >> /tmp/aliyun-oss-dirsize.log 2>&1

# 每月 1 日 04:30：比较并生成备份/删除脚本（人工复核后执行脚本）
30 4 1 * * /usr/local/bin/bash /path/to/deploy.sh/cloud/aliyun/main.sh -p <profile> oss prune <源桶> >> /tmp/aliyun-oss-prune.log 2>&1
```

要点：

1. **按天的任务上午 10:00**：本地昨天窗口在北京 00:00 关窗，10 点已过 10 小时（留足投递延迟）。
2. **日志写 `/tmp`**：`/tmp` 通常已存在，无需建目录；注意系统会定期清理 `/tmp`（macOS periodic / Linux tmpfiles），日志是易失的，需要留存请自行转存。
3. **`PATH` 顶部定义一次即可**：需含 `/usr/local/bin`（bash/aliyun/gdate/greadlink/gstat）与
   mise shims（`jq`）。注意 **cron 的赋值行不展开变量**，故 PATH 要写绝对路径（`<home>` 换成家目录）。
   不想让 PATH 带家目录可一次性 `ln -s "$HOME/.local/share/mise/shims/jq" /usr/local/bin/jq`，
   PATH 只写 `/usr/local/bin:/usr/bin:/bin`。
4. **bash 用绝对路径** `/usr/local/bin/bash`（脚本用了 bash 4+ 语法，系统自带 3.2 会报错）。
5. **清单用 `--inventory` 参数显式传入**（见上面 cron）；也可用环境变量
   `OSS_INVENTORY_BASE` + `OSS_INVENTORY_ID`（默认 `report1`）。两者都没有或清单不可用会自动回退 `--source du`。
6. **日志分两类**：
   - cron 包装日志（进度、警告、`ls -d`/`du` 输出）→ `>> /tmp/aliyun-*.log 2>&1`（易失）。
   - API 调用日志已由框架写入 `data/logs/aliyun/<profile>/<region>/<service>.log`，无需再定向。
7. **日志增长**：`>>` 会持续追加；只想留最近一次改 `>`，想留历史就配 logrotate 或定期清理。
8. **避免周期重叠**：`oss dirsize` 可能跑数分钟，不要用过高频的周期；必要时加锁文件互斥。
9. **定时刷新要加 `--refresh`**：`oss dirsize` 默认 30 天缓存（供按需调用省去重复下载）；
   每周/每月定时任务若不加 `--refresh`，会命中缓存而不更新。清单多久更新一次由 `Frequency` 决定。

## 待办（未实现，待决定）

- **旧档案清理**：`cdn access` 目前**不清理**超出聚合窗口的每日档案
  （`access/<域名>/<日>.txt`、`abnormal/<域名>/<日>.txt` 只增不减）。
  后续可加：每次运行删除早于 `today - days` 的 `.txt` 及残留 `.tmp`（保留最近 `days` 天，与聚合窗口一致）。

## 迁移（旧实现清理）

- `cdn.sh` 中旧 `cdn prune` 及其专属辅助函数（`_cdn_bucket_region`、`_cdn_bucket_dir_tree`）随本次拆分**删除**。
- 保留并复用：时区换算函数、`_cdn_fetch_log_rows`、`_cdn_fetch_parse_domain_day`（供 `cdn access`）。
- 旧内置 30 天计时器（`last_compare`）删除，比较周期交由 cron。

## 注意事项

- 报告桶用本桶 + 固定前缀（如 `oss-inventory/`）时，步骤 1 与步骤 3 都要排除该前缀。
- OSS 缓存缺失时，步骤 3 必须**跳过比较、不生成脚本**，防止误删。
- `ls` 解析：只保留行内 URL 以 `/` 结尾者（目录）；文件（无尾斜杠）一律丢弃。
- 访问集含 404/扫描器路径属正常，只会多 block、不会误删。
- **内网 endpoint**：加全局 `-in/--internal`（`oss ... -in`）。生效范围：`oss dirsize` 的
  `stat`/`ls -d`/`du` 与 `oss prune` 生成脚本里的 `ENDPOINT` 都切到
  `http://oss-<region>-internal.aliyuncs.com`。**仅同地域 ECS/VPC 内可达**，默认走公网。
