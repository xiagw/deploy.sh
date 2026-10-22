# PHP 基础镜像构建方案（v4）

> 目标：8 个 PHP 版本（7.1 / 7.3 / 7.4 / 8.1 / 8.2 / 8.3 / 8.4 / 8.5）全部保留，
> amd64 与 arm64 都推送到 Docker Hub，并且能持续拿到安全更新。

## 0. 结论（2026-10-22 修订）

**不需要 fork、不需要源码构建、不需要自建补丁。**

ondrej PPA（`ppa:ondrej/php`）在 2026-10-21 14:45 UTC 同时重建了 7.1 / 7.3 / 7.4 / 8.1 的源码包，
并回填了官方给 LTS 厂商的最小补丁 `Avoid-state-corruption-via-bailout.patch`
（即 CVE-2026-109618 / CVE-2026-109619 的修复）。8.2–8.5 本身就是官方发布版。

方案因此简化为一条路径：**全部版本 `ubuntu:24.04` + ondrej PPA**。

## 1. 证据

### 1.1 PPA 源码包内的补丁（`debian/patches/series` 实查）

| 版本 | PPA revision | 包发布时间 | 补丁文件 | 补丁行数 |
|---|---|---|---|---|
| 7.1 | `7.1.33-80+ubuntu24.04.1+deb.sury.org+1` | 2026-10-21 14:45Z | `0186-Avoid-state-corruption-via-bailout.patch` | 698 |
| 7.3 | `7.3.33-35+ubuntu24.04.1+deb.sury.org+1` | 2026-10-21 14:45Z | `0139-Avoid-state-corruption-via-bailout.patch` | 912 |
| 7.4 | `7.4.33-31+ubuntu24.04.1+deb.sury.org+1` | 2026-10-21 14:45Z | `0164-Avoid-state-corruption-via-bailout.patch` | — |
| 8.1 | `8.1.34-9+ubuntu24.04.1+deb.sury.org+1` | 2026-10-21 14:45Z | `0083-Avoid-state-corruption-via-bailout.patch` | — |

补丁作者 Arnaud Le Blanc，与 Ubuntu jammy 源码包里的 `CVE-2026-109618_109619.patch`
标题一致，属于同一份最小 backport。

### 1.2 官方发布版（上游直接可用）

| 版本 | 版本号 | 说明 |
|---|---|---|
| 8.5 | 8.5.12 | 2026-10-21 安全发布 |
| 8.4 | 8.4.27 | 同上 |
| 8.3 | 8.3.36 | 同上 |
| 8.2 | 8.2.35 | 同上（上游安全支持到 2026-12-31） |

### 1.3 其他事实

- 5.6 已移除：PPA 只有 5.6.40 冻结版，没有补丁（PHP 官方也没给 5.6 提供 backport），保留即永久带洞。
- Ubuntu jammy 的 `php8.1` 同日也 backport 了补丁（`8.1.2-1ubuntu2.28`），可作为备选基底，但不再需要。
- php-src 的 EOL 分支（`PHP-7.1/7.3/7.4`）仍冻结（`PHP-7.4` HEAD 停在 2022-10-31），没有可 cherry-pick 的上游提交。
- `php:<ver>-fpm` 官方镜像九个版本在 Docker Hub 都有 amd64+arm64，但 EOL 版本冻结且不含本次修复，没有利用价值。

## 2. 最终方案

| 版本 | 基底 | 安装源 | 补丁来源 |
|---|---|---|---|
| 8.5 / 8.4 / 8.3 / 8.2 | ubuntu:24.04 | ondrej PPA | 上游发布版 |
| 8.1 | ubuntu:24.04 | ondrej PPA | PPA backport（8.1.34-9） |
| 7.4 | ubuntu:24.04 | ondrej PPA | PPA backport（7.4.33-31） |
| 7.3 | ubuntu:24.04 | ondrej PPA | PPA backport（7.3.33-35） |
| 7.1 | ubuntu:24.04 | ondrej PPA | PPA backport（7.1.33-80） |

实现：

- `conf/Dockerfile.php`：PHP 专用 Dockerfile，只接收 `PHP_VERSION`，运行期契约（CMD/VOLUME/EXPOSE/ONBUILD）与 `Dockerfile.single` 一致。
- `lib/kubernetes.sh` 的 `build_base_image` php 分支：`dk_file=conf/Dockerfile.php`，传 `PHP_VERSION` + `APP_PORTS`。
- `conf/root/opt/build.sh`：php 分支保持原样（PPA + 扩展 + FPM 配置）。
- `conf/base-images.txt`：8 个 PHP 版本，无 5.6。

## 3. 曾被否掉的方案

| 方案 | 结论 |
|---|---|
| fork php-src 每版本一仓 + 自建补丁 | **不再需要**：PPA 已提供同源补丁；自建补丁只会增加维护面和验证成本 |
| 多阶段源码构建 | 同上；且 7.1/7.3 需老发行版 + EOL apt 源，arm64 走 QEMU 30–60 分钟/版本 |
| Debian + sury | 与 PPA 同一维护者、同一批包，无收益 |
| 官方镜像做基底 / 复制官方二进制 | EOL 镜像不含本次修复，拿不到补丁；跨发行版复制还有 ABI 风险 |
| 5.6 保留 | 无补丁，已移除 |

保留的备选：若将来 PPA 停止维护某个 EOL 版本，再启用源码方案（7.1 → `debian:stretch`，7.3/7.4 → `debian:buster`/`bullseye`），
届时才需要 fork 仓库与自建补丁。

## 4. 逐版本落地计划

原则：**一次只推进一个版本，验收通过再推下一个。** 失败不影响已发布 tag（bake 在 push 前失败不会产生半成品 manifest）。

| # | 版本 | 预期版本号 | 验收要点 |
|---|---|---|---|
| 1 | 8.5 | 8.5.12 | ✅ 已完成（2026-10-22，见 §5） |
| 2 | 8.4 | 8.4.27 | ✅ 已完成 |
| 3 | 8.3 | 8.3.36 | ✅ 已完成 |
| 4 | 8.2 | 8.2.35 | `php -v`、扩展、FPM、双架构 |
| 5 | 8.1 | 8.1.34（包 revision `-9`） | 同上；`dpkg-query -W php8.1-cli` 确认 revision |
| 6 | 7.4 | 7.4.33（包 revision `-31`） | 同上 |
| 7 | 7.3 | 7.3.33（包 revision `-35`） | 同上 |
| 8 | 7.1 | 7.1.33（包 revision `-80`） | 同上 |

每步固定动作：

1. `gh workflow run base-images.yml -f images=php:<ver>`（或 API 触发）。
2. 等 build job 完成，确认 `prepare` / `ensure-repos` / `build` 三绿。
3. Docker Hub 上确认 `xiagw/php:<ver>-base` 的 amd64 + arm64 manifest。
4. 拉镜像执行：`php -v`、`php -m` 对照扩展表、`grep listen /etc/php/<ver>/fpm/pool.d/www.conf`、`dpkg-query -W php<ver>-cli`。
5. 记录结果到 §5，推进下一个。

时间预算：单版本 CI 约 12–18 分钟（双架构，arm64 走 QEMU）。

## 5. 验收记录

| 版本 | 完成时间 | PHP 版本 | manifest | 备注 |
|---|---|---|---|---|
| 8.5 | 2026-10-22 02:31Z | 8.5.12 | amd64 `82c04a02` / arm64 `cf5cdc09` | 扩展、FPM、ONBUILD 全部通过 |
| 8.4 | 2026-10-22 02:48Z | 8.4.27 | amd64 `2fb01fb6` / arm64 `3772d18a` | 同上 |
| 8.3 | 2026-10-22 03:05Z | 8.3.36 | amd64 `3cd4198b` / arm64 `a88fa7bf` | 同上 |
| 8.2 | — | — | — | 进行中 |
| 8.1 | — | — | — | 待开始 |
| 7.4 | — | — | — | 待开始 |
| 7.3 | — | — | — | 待开始 |
| 7.1 | — | — | — | 待开始 |

## 6. 验证清单（每版本复用）

- `php -v` 版本号符合预期。
- `php -m` 包含：bcmath bz2 gd gmp imagick intl mbstring msgpack mysqli pdo_mysql pdo_pgsql pgsql redis soap sqlite3 xsl zip opcache。
- FPM：`listen = 9000`、`pm.max_children = 10000`、`rlimit_files = 65535`。
- `/opt/run0.sh`、`/opt/run1.sh` 存在且可执行；`docker inspect` 有两条 ONBUILD。
- `dpkg-query -W php<ver>-cli` 的 revision 与 §1.1 一致（确认装的是回填补丁后的包）。
- `docker buildx imagetools inspect xiagw/php:<ver>-base` 显示 amd64 + arm64。
