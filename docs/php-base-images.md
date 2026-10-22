# PHP 基础镜像构建方案（评审稿 v3）

> 目标：8 个 PHP 版本（7.1 / 7.3 / 7.4 / 8.1 / 8.2 / 8.3 / 8.4 / 8.5）全部保留，
> amd64 与 arm64 都推送到 Docker Hub，并且能持续拿到安全更新。
> 本文只讨论方案，不含实现。

## 0. 已定事项（2026-10-22）

1. 7.1 / 7.3 / 7.4：**每版本一个仓库**（`xiagw/php-src-<ver>`），打补丁后源码构建；官方没补丁的自行 backport。
2. 8.1：基底换 `ubuntu:22.04`，用发行版自带的 php8.1（已 backport 本次修复）。
3. 8.2–8.5：维持现状（`ubuntu:24.04` + ondrej PPA）。
4. 新增 `conf/Dockerfile.php`，PHP 单独维护，其它语言继续用 `Dockerfile.single`。
5. 5.6 **不再支持**，从镜像列表移除，`build.sh` 的 5.6/apache 分支随之删除。
6. 7.1/7.3/7.4 允许使用老发行版的 EOL apt 源（`archive.debian.org`）。
7. 补丁验收只跑 `Zend/` + `ext/standard` + 反射相关测试子集，不跑全量 `make test`。

## 1. 现状

- 入口：`lib/kubernetes.sh` 的 `build_base_image php:<ver>` → `conf/Dockerfile.single`（`FROM ubuntu:24.04` + `RUN build.sh php`）。
- `conf/root/opt/build.sh` 的 php 分支：加 `ppa:ondrej/php`，装 `php<ver>` 及 20 个扩展包，改 FPM（`listen=9000`、`pm.max_children=10000`、`rlimit_files=65535`），可选搬运 `swoole.so`；nginx 统一反代（5.6 的 apache+mod_php 分支随 5.6 下线一并删除）。
- 运行期契约（不能丢）：`CMD /opt/run0.sh`、`VOLUME`、`EXPOSE`、`ONBUILD COPY`、`/opt/onbuild.sh`。

## 2. 事实核查（2026-10-22）

### 2.1 版本与支持状态

| 版本 | php.net 状态 | ondrej PPA(noble) | 本次修复来源 |
|---|---|---|---|
| 8.5 | 支持到 2029-12-31 | 8.5.12 | 上游发布 |
| 8.4 | 支持到 2028-12-31 | 8.4.27 | 上游发布 |
| 8.3 | 支持到 2027-12-31 | 8.3.36 | 上游发布 + Ubuntu 同日 backport |
| 8.2 | 支持到 2026-12-31 | 8.2.35 | 上游发布 |
| 8.1 | 2025-12-31 EOL | 8.1.34（冻结） | Ubuntu jammy backport |
| 7.4 | 2022-11-28 EOL | 7.4.33（冻结） | 无公开发布，需自行 backport |
| 7.3 | 2021-12-06 EOL | 7.3.33 | 无补丁（自建 backport） |
| 7.1 | 2019-12-01 EOL | 7.1.33 | 无补丁（自建 backport） |

漏洞：CVE-2026-109618 / CVE-2026-109619（PHP2Shell，CVSS 9.2），官方在 8.2.35 / 8.3.36 / 8.4.27 / 8.5.12 修复。

### 2.2 发行版 backport（Launchpad 实查）

| 发行版 | 包 | 最近安全更新 | 是否含本次修复 |
|---|---|---|---|
| Ubuntu 22.04 jammy | php8.1 | 8.1.2-1ubuntu2.28，2026-10-21 | ✅ `debian/patches/CVE-2026-109618_109619.patch` |
| Ubuntu 24.04 noble | php8.3 | 8.3.6-0ubuntu0.24.04.13，2026-10-21 | ✅ 同日更新 |
| Ubuntu 20.04 focal | php7.4 | 7.4.3-4ubuntu2.29，2025-04-01 | ❌ 已进 ESM，免费源无修复 |

### 2.3 php-src 上游

- 分支仍在：`PHP-7.1` / `PHP-7.3` / `PHP-7.4`，但**全部冻结**（`PHP-7.4` 分支 HEAD 停在 2022-10-31）。
- 本次修复没有进这些 EOL 分支，官方只给发行商/LTS 提供了最小补丁。

### 2.4 可复用的补丁（关键）

Ubuntu jammy 的 php8.1 源码包里可以直接拿到本次补丁：

```
debian/patches/CVE-2026-109618_109619.patch
```

- 1132 行，7 个提交块，90 个 hunk，作者 Arnaud Le Blanc，日期 2026-10-18，标题 `Avoid state corruption via bailout`。
- 触及 11 个文件，集中在 Zend 引擎：`zend_alloc.{c,h}`、`zend_hash.{c,h}`、`zend_vm_def.h`、`zend_execute_API.c`、`zend_API.h`、`zend_types.h`、`zend_strtod.c`、`zend_multiply.h`。
- 结论：**8.1 有现成补丁；7.4 需要以它为基线反向适配；7.1/7.3 的引擎差异更大，适配属于真正的移植工作。**

### 2.5 官方镜像

`php:<ver>-fpm` 九个版本在 Docker Hub 全部存在，amd64 + arm64 均有（`imagetools inspect` 实测）。
EOL 分支同样冻结，不含本次修复，所以对 7.1–7.4 没有利用价值。

## 3. 源码构建的现实约束

### 3.1 工具链与 OpenSSL

| 版本 | 可编译的发行版 | 原因 |
|---|---|---|
| 7.1 | Debian stretch | 需要 OpenSSL 1.1.0；7.1 系最后几版才支持，stretch 是稳妥选择 |
| 7.3 / 7.4 | Debian buster / bullseye | 同上；7.4 勉强可配 OpenSSL 3，但扩展生态不稳 |
| 8.1+ | bookworm / jammy 及以上 | 原生支持 OpenSSL 3 |

老发行版意味着 apt 源要换 `archive.debian.org`（EOL 不再更新），镜像里会带一批过期系统库。
这是“老 PHP 必须付的代价”，不是方案缺陷。

### 3.2 扩展

现在 apt 一行装完的 20 个扩展，源码构建要逐个处理：一部分用 `--with-*` 编进 PHP，其余用 `pecl install`（redis / msgpack / imagick / swoole）。每个版本一套参数，老版本（7.1/7.3）的 pecl 包还要固定版本号。

### 3.3 构建时间与架构

- amd64：单版本 PHP 编译约 10–20 分钟（`-j$(nproc)`）。
- arm64：GitHub runner 走 QEMU，约 30–60 分钟/版本。
- 3 个源码版本 × 2 架构，首次全量预计 2–4 小时（与现在 28 个镜像的成本同量级，但有 3 个长尾）。

### 3.4 补丁维护

自建补丁意味着：上游不再有人为这些版本做安全审计，后续每个 CVE 都要自己判断、移植、验证。必须在仓库里保留补丁来源、适用版本、验证记录（见 §6）。

## 4. 方案与结论

### 4.1 分版本矩阵

| 版本 | 基底 | 安装方式 | 补丁 | 备注 |
|---|---|---|---|---|
| 8.5 / 8.4 | ubuntu:24.04 | ondrej PPA | 上游 | 现状不变 |
| 8.3 | ubuntu:24.04 | 发行版包或 PPA | 上游 + Ubuntu | 二选一，建议发行版包 |
| 8.2 | ubuntu:24.04 | ondrej PPA | 上游（至 2026-12） | 之后转 backport 或升 8.3 |
| 8.1 | ubuntu:22.04 | 发行版包 | Ubuntu backport | 已验证有补丁 |
| 7.4 | debian:bullseye（builder=runtime） | 源码 | 自建 backport（8.1 补丁适配） | 先在 7.4 验证移植流程 |
| 7.3 | debian:buster | 源码 | 自建 backport | 引擎差异大，工作量大 |
| 7.1 | debian:stretch | 源码 | 自建 backport | 工具链最老，风险最高 |

### 4.2 被否掉的方案

- **B. Debian + sury**：与 PPA 同一维护者、同一批包，EOL 版本同样冻结，换基底无收益。
- **C. 官方镜像做基底**：EOL 镜像不含本次修复，拿不到补丁，只省编译。
- **E. 复制官方二进制到自建 runtime**：同发行版复制等价于 C，跨发行版要带 OpenSSL 1.0/1.1 等旧库，ABI 风险最高且无补丁收益。

## 5. 仓库与构建设计

### 5.1 源码仓库组织

**每版本一个仓库**：

```
xiagw/php-src-7.1   main = php-src PHP-7.1 + 补丁
xiagw/php-src-7.3   main = php-src PHP-7.3 + 补丁
xiagw/php-src-7.4   main = php-src PHP-7.4 + 补丁
```

- 每个仓库只保留一个分支（`main`），补丁文件放 `patches/CVE-*/`，`series` 风格可审计。
- CI 里 `git clone --depth 1 --branch main`，clone 体积与构建时间可控。
- 仓库加 `LABEL org.opencontainers.image.source` 指回对应仓库，便于追溯。

### 5.2 构建方式

builder 与 runtime 同发行版，两阶段：

```dockerfile
FROM debian:bullseye AS builder
# 装 build-essential、libxml2-dev 等，clone 补丁分支，./configure && make
FROM debian:bullseye AS runtime
# 装运行库 + 扩展，COPY --from=builder /usr/local /usr/local
# 叠加 /opt/run0.sh 等契约
```

补丁在构建时打成 tar 或直接 `git apply`（补丁文件随 Dockerfile 目录走，便于审计）。

### 5.3 新文件 `conf/Dockerfile.php`

参数（由 `build_base_image` 传入）：

| 变量 | 用途 |
|---|---|
| `PHP_VERSION` | 版本号，决定扩展与 FPM 路径 |
| `PHP_BASE_IMAGE` | 基底镜像，如 `ubuntu:22.04` / `debian:bullseye` |
| `PHP_INSTALL` | `apt` 或 `source` |
| `PHP_SRC_REPO` / `PHP_SRC_REF` | 仅 source 模式使用，默认 `xiagw/php-src-<ver>` + `main` |
| `PHP_PATCH_DIR` | 额外补丁目录（可选） |

运行期契约（CMD/VOLUME/EXPOSE/ONBUILD）从 `Dockerfile.single` 原样迁移，保证子项目无感。

版本 → 基底/安装方式的映射放在 `build_base_image` 的 php 分支（或独立 `conf/php-base-matrix.txt`），Dockerfile 里不写死版本号。

## 6. 补丁治理（必须做，否则无法审计）

每个自建补丁记录：

1. 来源：Ubuntu/Debian 源码包路径或 commit SHA。
2. 适用版本与文件清单。
3. 验证方式：`make test` 的关键子集 + 本次漏洞 PoC（如有）回归。
4. 已知差异：哪些 hunk 是手工改写、为什么。
5. 元数据写进镜像 `LABEL`：`org.opencontainers.image.revision`、`php.patch.set`。

## 7. 分阶段落地

| 阶段 | 内容 | 验证 |
|---|---|---|
| P1 | `conf/Dockerfile.php` + 8.1（jammy）+ 8.2–8.5 走原路径 | 8 个 tag 仍可构建，8.1 带补丁 |
| P2 | 7.4 源码构建 + 8.1 补丁反向适配 | `php -v` 到 7.4.33 且补丁生效；`make test` 关键子集 |
| P3 | 7.3 → 7.1 依次适配 | 每版单独验收，失败则回退到冻结镜像 |
| P4 | arm64 全量构建 + 双架构 push | `imagetools inspect` 确认 manifest list |

P2 是分水岭：7.4 能完成，说明“自建补丁 + 源码构建”路径成立；做不动就停在这里，≤7.3 继续冻结。

### 7.1 逐版本顺序（一次只推进一个）

原则：**每个版本单独构建、单独验收、单独推送；上一版通过才动下一版。**
失败不影响已发布的 tag（bake 在 push 前失败不会产生半成品 manifest）。

| # | 版本 | 代码改动 | 验收要点 |
|---|---|---|---|
| 1 | 8.5 | 新 `Dockerfile.php`，`ubuntu:24.04` + PPA | `php -v` = 8.5.12；`php -m` 对照现有扩展；FPM 9000；ONBUILD 冒烟 |
| 2 | 8.4 | 无（只换 `PHP_VERSION`） | 同上，版本 = 8.4.27 |
| 3 | 8.3 | 无 | 同上，版本 = 8.3.36 |
| 4 | 8.2 | 无 | 同上，版本 = 8.2.35 |
| 5 | 8.1 | `PHP_BASE_IMAGE=ubuntu:22.04`、`PHP_PPA=false` | `apt-cache policy php8.1` 显示 8.1.2-1ubuntu2.28；其余同 8.x |
| 6 | 7.4 | 新建 `xiagw/php-src-7.4`，补丁适配 | `php -v` = 7.4.33；测试子集；PoC 回归 |
| 7 | 7.3 | 新建 `xiagw/php-src-7.3` | 同上 |
| 8 | 7.1 | 新建 `xiagw/php-src-7.1` | 同上 |

每步固定动作：

1. 本地构建（amd64）→ 跑验收清单；不通过就停，回到 7.1 之前的状态。
2. 本地通过后 `gh workflow run base-images.yml -f images=php:<ver>`，等 CI 双架构推送完成。
3. `docker buildx imagetools inspect xiagw/php:<ver>-base` 确认 amd64 + arm64 manifest。
4. 记录结果（版本号、补丁 commit、验收输出）到本文档附录，再推进下一个。

时间预算：8.x 每版本地 5–10 分钟 + CI 10–25 分钟；7.x 源码版本地 10–20 分钟（amd64）、CI 30–60 分钟（arm64 QEMU）。

## 8. 需要确认

1. 仓库命名确认：`xiagw/php-src-7.1` / `-7.3` / `-7.4`，还是 `xiagw/php-7.4`？
2. 是否给每个源码仓库配一条 CI（打补丁 + 子集测试 + 出 tar 包），还是只在部署仓库里构建时验证？
3. 8.1 的补丁基线已经拿到（Ubuntu 源码包），7.4 适配完成后是否要先灰度一个业务验证再推全部版本？

## 9. 验证清单

- `docker run --rm <image> php -v` + `php -m` 对照现有扩展列表。
- `docker buildx imagetools inspect` 确认 amd64 + arm64。
- FPM 监听 9000、`pm.max_children` 生效。
- nginx + FPM 模式跑通（已有 5.6 的 apache 模式随版本下线删除）。
- ONBUILD：子项目 `COPY . /app/` 后 `/opt/onbuild.sh` 执行。
- 漏洞回归：用公开 PoC 或最小复现脚本确认 CVE-2026-109618/109619 不再触发。
- `trivy image` 对比新老镜像的 PHP 相关告警。
