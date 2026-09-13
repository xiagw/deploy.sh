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
                       rm-<日期>-<bucket>.sh（sync 备份 + rm，人工复核后执行）
```

## 硬性约束

- **列目录只用 `ls -d`；绝对禁止 `ls -r`**（会卡死）。
- **取大小只用 `du`；禁止用 `ls`（含非递归）去取对象**。`du` 必须带前缀，**不得用 `du -d`**（只数占位对象、无明细）。
- 目录最多 3 层；比较也最多 3 层。
- 直属对象由 `du <目录>` 递归统计天然包含，无需单独处理。
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
| `$PRUNE_DIR/rm-<日期>-<bucket>.sh` | 步骤3 | 备份+删除脚本 |

---

## 步骤 1：`oss dirsize`（生成目录列表 + 大小清单）

### 用法

```
bash main.sh -p <profile> [-r <region>] oss dirsize <bucket> \
    [--min-size 1G] [--exclude <prefix>] [--depth 3] [--refresh]
```

- `--min-size`：只写 ≥ 该大小的目录（默认 `1G`；`0` 表示全写）。
- `--exclude`：排除前缀，可重复（默认含 `oss-inventory/`）。
- `--refresh`：忽略缓存强制重建。

### 流程

1. **定位桶区域**：`ossutil ls`（账号桶列表 → Region 列），失败回退 profile region。
2. **目录结构（缓存 7 天）**
   - 从根用 `ls -d` 逐层递归 ≤3 层；每层并行 `xargs -P`，单次 `timeout 30`。
   - 只保留 URL 以 `/` 结尾的行（目录），去尾斜杠、去重。
   - 输出 `/a`、`/a/b`、`/a/b/c`（前导斜杠）。
3. **目录大小（缓存 30 天，全用 `du`）**
   - 对结构里的**每一个目录**并行 `du <prefix>`，解析 `total du size:<N>`。
   - `du` 递归统计该目录下所有对象，**天然包含直属对象**，无需叶子+上卷、也无需告警。
   - 结果按字节倒序写 `sizes-<bucket>.tsv`；只保留 ≥ `--min-size` 的目录。
   - **不要用 `du -d`**（只数占位对象）；`du` 必须带前缀。
4. **过滤**：剔除 `--exclude` 前缀。
5. 写缓存文件（见下）。

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

---

## 步骤 2：`cdn access`（获取日志，生成三层访问清单）

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
- 日志日期按上海时区（UTC+8）口径换算 API 的 UTC 窗口。
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
   - 非 `--dry-run` 生成 `rm-<日期>-<bucket>.sh`。

### 删除脚本格式

每个候选两条命令，`set -e` 保证备份失败即中止、不会删；脚本**只生成、不执行**：

```bash
#!/usr/bin/env bash
set -e

PROFILE="<profile>"
ENDPOINT="http://oss-<region>.aliyuncs.com"
REGION="<region>"
BACKUP_ROOT="<SCRIPT_DATA>/prune-backup/<日期>/<bucket>"

echo "备份并删除 oss://<bucket>/a/b/"
mkdir -p "${BACKUP_ROOT}/a/b"
aliyun --profile "${PROFILE}" ossutil sync --endpoint "${ENDPOINT}" --region "${REGION}" \
  "oss://<bucket>/a/b/" "${BACKUP_ROOT}/a/b/"
aliyun --profile "${PROFILE}" ossutil rm -r -f --endpoint "${ENDPOINT}" --region "${REGION}" \
  "oss://<bucket>/a/b/"
```

### 产出文件

```
$PRUNE_DIR/candidates-<日期>-<bucket>.txt
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

cron 环境 PATH 极简，且本机 `jq` 由 mise 管理、`bash` 需 5.x，所以必须显式设置
`PATH` 并用绝对路径的 bash；不加 `cd`（脚本按自身路径解析项目根）。

```cron
PATH=/usr/local/bin:/Users/xia/.local/share/mise/shims:/usr/bin:/bin

# 每天 02:30：取日志、生成三层访问清单
30 2 * * * /usr/local/bin/bash /Users/xia/Cursor/deploy.sh/cloud/aliyun/main.sh -p flyh6 cdn access >> /Users/xia/Cursor/deploy.sh/data/logs/aliyun/cron/cdn-access.log 2>&1

# 每周日 03:00：重建目录结构 + 大小清单（慢，可等）
0 3 * * 0 /usr/local/bin/bash /Users/xia/Cursor/deploy.sh/cloud/aliyun/main.sh -p flyh6 oss dirsize pilihuo >> /Users/xia/Cursor/deploy.sh/data/logs/aliyun/cron/oss-dirsize.log 2>&1

# 每月 1 日 04:00：比较并生成备份/删除脚本（人工复核后执行脚本）
0 4 1 * * /usr/local/bin/bash /Users/xia/Cursor/deploy.sh/cloud/aliyun/main.sh -p flyh6 oss prune pilihuo >> /Users/xia/Cursor/deploy.sh/data/logs/aliyun/cron/oss-prune.log 2>&1
```

要点：

1. **先建日志目录**（cron 不会自动建，缺目录会让重定向失败）：
   `mkdir -p /Users/xia/Cursor/deploy.sh/data/logs/aliyun/cron`
2. **`PATH` 必须包含**：`/usr/local/bin`（bash/aliyun/gdate/greadlink/gstat）与
   `/Users/xia/.local/share/mise/shims`（`jq`）。否则 cron 里报 `jq: command not found`。
3. **bash 用绝对路径** `/usr/local/bin/bash`（脚本用了 bash 4+ 语法，系统自带 3.2 会报错）。
4. **日志分两类**：
   - cron 包装日志（进度、警告、`ls -d`/`du` 输出）→ `>> .../data/logs/aliyun/cron/*.log 2>&1`。
   - API 调用日志已由框架写入 `data/logs/aliyun/<profile>/<region>/<service>.log`，无需再定向。
5. **日志增长**：`>>` 会持续追加；只想留最近一次改 `>`，想留历史就配 logrotate 或定期清理。
6. **避免周期重叠**：`oss dirsize` 可能跑数分钟，不要用过高频的周期；必要时加锁文件互斥。

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
