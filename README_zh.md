# deploy.sh（中文说明）

[![CI](https://github.com/xiagw/deploy.sh/actions/workflows/main.yml/badge.svg?event=push)](https://github.com/xiagw/deploy.sh/actions)

简要说明
- deploy.sh 是一个基于 Bash 的开源 CI/CD 自动化工具，支持传统服务器与容器化 / Kubernetes 环境，可手动执行也可集成到各种 CI 平台（如 GitLab/GitHub/Jenkins 等）。它将构建、代码检查、测试、打包、部署与通知等流程集成在一起，适用于多种部署场景。

目录
- [主要特性](#主要特性)
- [支持平台](#支持平台)
- [依赖与兼容性](#依赖与兼容性)
- [安装](#安装)
- [快速开始](#快速开始)
  - [1）手动运行](#1手动运行)
  - [2）自动化（crontab / loop）](#2自动化crontab--loop)
  - [3）GitLab-Runner 集成](#3gitlab-runner-集成)
  - [4）Jenkins 集成](#4jenkins-集成)
- [项目语言自动检测](#项目语言自动检测)
- [最小配置示例（data/deploy.json & data/deploy.env）](#最小配置示例datadeployjson--datadeployenv)
- [常见问题与故障排查](#常见问题与故障排查)
- [架构图说明](#架构图说明)
- [贡献指南](#贡献指南)
- [捐助方式](#捐助方式)
- [许可证与联系](#许可证与联系)

主要特性
- 代码风格检查：phpcs、phpcbf、Java 代码风格检查、jslint、shfmt、hadolint 等
- 代码质量：SonarQube 扫描、OWASP ZAP、漏洞映射工具等
- 测试：单元测试、功能测试、性能测试（如 JMeter）
- 构建：npm、composer、maven、gradle、docker build、pip 等
- 部署方式：rsync + ssh、rsync、镜像/容器部署、jar/war 部署、ftp、sftp、kubectl、helm 等
- 性能测试：压测、JMeter、LoadRunner 等集成
- 通知：企业微信、钉钉、Telegram、Element(Matrix) 等
- 证书管理：集成 acme.sh 实现自动证书签发与续期
- 云适配：支持 AWS、阿里云、腾讯云、华为云等

支持平台
- GitLab / GitLab-Runner（推荐 shell executor）
- Jenkins（通过脚本调用）
- GitHub Actions / Gitea / Gogs / 以及普通服务器上直接运行

依赖与兼容性（建议）
- Git：建议 >= 2.17
- Bash：建议 >= 4.x（部分系统内置 bash 版本可能影响脚本）
- rsync：推荐 >= 3.x（用于高效文件同步）
- ssh：用于免密登录与远程执行
- kubectl / helm：如使用 k8s/helm 部署，请安装并配置 kubeconfig
- 具体特性兼容性与使用的工具有关，请在生产前测试

安装
在用于运行 deploy.sh 的服务器（例如 CI runner 或运维机）上克隆仓库：
```bash
git clone --depth 1 https://github.com/xiagw/deploy.sh.git $HOME/runner
```

快速开始

1）手动运行
- 如果项目仓库已经存在于服务器上：
```bash
cd /path/to/your_project
$HOME/runner/deploy.sh
```

- 如果项目仓库不存在（deploy.sh 会帮你 clone）：
```bash
$HOME/runner/deploy.sh --git-clone https://github.com/<user>/<repo>.git
```

2）自动化（crontab / loop）
- 使用 crontab 每 5 分钟轮询并执行示例：
```cron
*/5 * * * * for d in /path/to/src/*/; do (cd "$d" && git pull && $HOME/runner/deploy.sh --cron); done
```

- 使用循环脚本持续运行（示例）：
```bash
while true; do
  for d in /path/to/src/*/; do
    (cd "$d" && git pull && $HOME/runner/deploy.sh --loop)
  done
  sleep 300
done
```

3）GitLab-Runner 集成（示例）
- 准备 GitLab Server 与已注册的 GitLab-Runner（shell executor）。
- 在 runner 服务器上：
```bash
cd $HOME/runner
cp conf/example-deploy.json data/deploy.json      # 编辑为你的配置
cp conf/example-deploy.env data/deploy.env        # 编辑为你的配置
```
- 在项目仓库中添加 `.gitlab-ci.yml`，可参考本仓库 `conf/.gitlab-ci.yaml` 示例。

4）Jenkins 集成
- 在 Jenkins Job 中添加构建步骤（Execute shell）：
```bash
bash $HOME/runner/deploy.sh
```
- 根据需要，在 Job 里先拉取代码或设置必要的环境变量。

项目语言自动检测
- node: 存在 package.json，或在 README 中添加 `project_lang=node`
- php: 存在 composer.json，或在 README 中添加 `project_lang=php`
- java: 存在 pom.xml，或在 README 中添加 `project_lang=java`
- python: 存在 requirements.txt，或在 README 中添加 `project_lang=python`
- 其它语言：在 README 中添加 `project_lang=[other]`

最小配置示例（data/deploy.json & data/deploy.env）
- 以下示例为最小可运行配置，生产环境中请根据实际情况补充字段与安全策略。

data/deploy.json（最小示例）
```json
{
  "projects": {
    "example-app": {
      "git": "git@github.com:yourname/example-app.git",
      "deploy_method": "rsync+ssh",
      "target": {
        "host": "app.example.com",
        "user": "deploy",
        "path": "/var/www/example-app",
        "ssh_key": "/home/deploy/.ssh/id_rsa"
      },
      "build": {
        "commands": ["npm install", "npm run build"]
      }
    }
  },
  "default": {
    "timeout": 3600
  }
}
```

data/deploy.env（最小示例）
```env
# 环境变量示例（仅示例）
SSH_PRIVATE_KEY_PATH=/home/deploy/.ssh/id_rsa
DOCKER_REGISTRY=myregistry.example.com
NOTIFY_WECHAT_WEBHOOK=https://qyapi.weixin.qq.com/...
```

常见问题与故障排查
- 无法通过 SSH 登录目标主机：检查私钥权限（chmod 600）并确保公钥已加入目标主机的 `~/.ssh/authorized_keys`。
- git clone / pull 错误：确认 runner 使用的 SSH 密钥或 CI token 是否有仓库访问权限，检查网络与代理设置。
- GitLab-Runner 无法运行脚本：确认 runner 是 shell executor 并处于运行状态：`sudo gitlab-runner status`；Ubuntu 上注意不要在 `$HOME/.bash_logout` 添加会中断 runner 的命令。
- 日志查看：默认输出到控制台。需要持久化请在运行时重定向日志或集成外部日志服务。
- 调试建议：临时在脚本前加入 `set -x`，或在关键步骤加入详尽的日志输出。

架构图说明
- 原 README 包含较长的 mermaid 架构图，建议将完整 mermaid 内容移到 `docs/diagram.md`，在 README 中保留简短说明与链接。如果需要，我可以把 mermaid 内容整理并生成可渲染的 docs 文件或导出 PNG。

贡献
- 欢迎提交 Issue 或 PR。
- 提交前请尽量包含复现步骤、相关日志及测试用例（如适用）。
- 大改动建议先提交 Issue 讨论实现细节。

捐助方式
如果项目对你有帮助，欢迎支持开发（已将图片与更完整的说明移至 docs/payments.md）：
- BTC（native segwit）：bc1qaphg63gygfelzq5ptssv3rq6eayhwclghucf8r
- BTC（segwit）：3LzwrtqD6av77XVN68UXWLKaHEtAPEQiPt
- ETH/ERC20: 0x007779971b2Df368E75F1a660c1308A51f45A02e
- BSC/ERC20: 0x007779971b2Df368E75F1a660c1308A51f45A02e
- TRX/TRC20: TAnZ537r98Jo63aKDTfbWmBeooz29ASd73

许可证与联系
- 本项目采用 MIT 许可证（请以仓库根目录 LICENSE 文件为准）。
- Issues / PRs: https://github.com/xiagw/deploy.sh/issues

最后说明
- 本文档为中文版 README 草稿（英文/双语 README 已保留在 README.md）。
