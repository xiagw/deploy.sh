# deploy.sh

[![CI](https://github.com/xiagw/deploy.sh/actions/workflows/main.yml/badge.svg?event=push)](https://github.com/xiagw/deploy.sh/actions)

部署说明（中文在下方） | 中文版: [README_zh.md](README_zh.md)

简短介绍
- deploy.sh 是一个基于 Bash 的开源 CI/CD 自动化工具，面向传统服务器与容器化 / Kubernetes 环境，支持手动与自动化运行。它集成了构建、代码检查、测试、打包、部署与通知等常见环节，适用于 GitLab/GitHub/Jenkins/Gitea 等平台。

目录
- [主要特性](#主要特性)
- [支持的部署/集成平台](#支持的部署集成平台)
- [依赖与兼容性](#依赖与兼容性)
- [安装](#安装)
- [快速开始](#快速开始)
  - [1) 手动运行](#1-手动运行)
  - [2) 自动化（crontab / loop）](#2-自动化crontab--loop)
  - [3) GitLab-Runner 集成](#3-gitlab-runner-集成)
  - [4) Jenkins 集成](#4-jenkins-集成)
- [如何自动检测项目语言](#如何自动检测项目语言)
- [最小配置示例（deploy.json / deploy.env）](#最小配置示例deployjson--deplo yenv)
- [常见问题与故障排查](#常见问题与故障排查)
- [架构图（说明）](#架构图说明)
- [贡献](#贡献)
- [捐助](#捐助)
- [许可证](#许可证)
- [联系与参考](#联系与参考)

主要特性
- 代码风格检查：phpcs、phpcbf、Java 代码风格、jslint、shfmt、hadolint 等
- 代码质量：SonarQube 扫描、OWASP ZAP、Vulmap（漏洞映射）等
- 测试套件：单元测试、功能测试、性能测试（如 JMeter）
- 构建：npm、composer、maven、gradle、docker build、pip 等
- 部署方式：rsync + ssh、rsync、镜像推送、jar/war 部署、ftp、sftp、kubectl、helm 等
- 性能测试：压测、JMeter、LoadRunner 等
- 通知：企业微信、钉钉、Telegram、Element(Matrix) 等
- 证书管理：集成 [acme.sh](https://github.com/acmesh-official/acme.sh) 自动申请/更新证书
- 云厂商适配：AWS、阿里云、腾讯云、华为云等

支持的部署/集成平台
- GitLab / GitLab-Runner（shell executor）
- Jenkins（通过运行脚本）
- GitHub Actions（通过在 Workflow 中运行 runner）
- Gitea / Gogs / 其它 CI，或直接在服务器上运行

依赖与兼容性（建议）
- Git：>= 2.17
- Bash：>= 4.x（某些系统内置的 bash 版本可能影响脚本）
- rsync：推荐 >= 3.x（用于文件同步）
- ssh：用于免密登录与远程执行
- kubectl / helm：如使用 k8s/helm 部署，需分别安装并配置 kubeconfig
- 只是样例，实际兼容性与所用特性有关，请在具体环境中测试

安装
先将 runner 克隆到部署服务器（例如 GitLab-Runner 服务器或运维机器）：
```bash
git clone --depth 1 https://github.com/xiagw/deploy.sh.git $HOME/runner
```

快速开始

1) 手动运行
- 如果仓库已在服务器上：
```bash
cd /path/to/your_project
$HOME/runner/deploy.sh
```

- 如果仓库尚未克隆（deploy.sh 会自动 clone）：
```bash
$HOME/runner/deploy.sh --git-clone https://github.com/<user>/<repo>.git
```

2) 自动化（crontab / loop）
- 使用 crontab 每 5 分钟轮询一次示例（仅示意）：
```cron
*/5 * * * * for d in /path/to/src/*/; do (cd $d && git pull && $HOME/runner/deploy.sh --cron); done
```

- 使用循环 + sleep：
```bash
while true; do
  for d in /path/to/src/*/; do
    (cd "$d" && git pull && $HOME/runner/deploy.sh --loop)
  done
  sleep 300
done
```

3) GitLab-Runner 集成（示例）
- 准备 GitLab Server 与 GitLab-Runner（shell executor）
- 在 runner 服务器执行：
```bash
cd $HOME/runner
cp conf/example-deploy.json data/deploy.json      # 修改为你的配置
cp conf/example-deploy.env data/deploy.env        # 修改为你的配置
```
- 在你的项目仓库中添加 `.gitlab-ci.yml`，参考本仓库 `conf/.gitlab-ci.yaml` 示例。

4) Jenkins 集成
- 在 Jenkins Job 中的执行步骤添加：
```bash
bash $HOME/runner/deploy.sh
```
- 根据需要在 Job 中先拉取代码或设置环境变量。

如何自动检测项目语言
- node: 存在 package.json，或在 README 中添加 `project_lang=node`
- php: 存在 composer.json，或在 README 中添加 `project_lang=php`
- java: 存在 pom.xml，或在 README 中添加 `project_lang=java`
- python: 存在 requirements.txt，或在 README 中添加 `project_lang=python`
- 其它: 在 README 中添加 `project_lang=[other]`

最小配置示例（deploy.json / deploy.env）
以下示例仅为最小示范，实际配置字段请参照 `conf/example-deploy.json` 与 `conf/example-deploy.env`。

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
# 环境变量示例
SSH_PRIVATE_KEY_PATH=/home/deploy/.ssh/id_rsa
DOCKER_REGISTRY=myregistry.example.com
NOTIFY_WECHAT_WEBHOOK=https://qyapi.weixin.qq.com/...
```

常见问题与故障排查
- 无法 SSH 登录到目标主机：确认私钥权限（600）与公钥已加入目标主机的 authorized_keys。
- git clone / pull 失败：确认 runner 的 SSH key/CI token 是否有仓库访问权限；检查网络/代理。
- GitLab-Runner 无法执行脚本：如果使用 Ubuntu，注意不要在 $HOME/.bash_logout 中执行关闭操作；检查 runner 是否为 shell executor 并运行状态：`sudo gitlab-runner status`
- 日志位置：默认输出到控制台；若需持久化，请在运行脚本时重定向或使用外部日志收集。
- 调试建议：在运行时加 `set -x`（临时），或在脚本中增加调试日志。

架构图说明
- 原 README 中含较长的 mermaid 图。建议将完整图移到 `docs/diagram.md` 或 `docs/diagram.png`，在 README 中保留简短示意并链接到 docs。
- 如果你希望，我可以把原 mermaid 内容整理为 docs/diagram.md 并生成可渲染版本。

贡献
欢迎贡献！
- 请阅读并遵循仓库中的代码风格与测试要求（如有）。
- 提交 PR 前请确保已添加/更新相应文档与测试用例。
- 若需大改动，建议先提交 Issue 讨论设计方案。

捐助
如果你觉得本项目有帮助，可以考虑小额捐赠支持开发（图片与示例地址已放入 docs/payments.md）：
- BTC: bc1qaphg63gygfelzq5ptssv3rq6eayhwclghucf8r
- ETH/ERC20: 0x007779971b2Df368E75F1a660c1308A51f45A02e
- BSC/ERC20: 0x007779971b2Df368E75F1a660c1308A51f45A02e
- TRX/TRC20: TAnZ537r98Jo63aKDTfbWmBeooz29ASd73

许可证
- 本项目采用 MIT 许可证（或请按仓库实际 LICENSE 文件为准）。

联系与参考
- 仓库 Issues: [deploy.sh Issue](https://github.com/xiagw/deploy.sh/issues)
- Pull Requests: [deploy.sh PRs](https://github.com/xiagw/deploy.sh/pulls)
- acme.sh: https://github.com/acmesh-official/acme.sh

---

中文说明（摘要）
deploy.sh 是一个基于 Bash 的轻量 CI/CD 自动化工具，支持 rsync/ssh、镜像构建、k8s/helm 等部署方式，能集成到 GitLab/GitHub/Jenkins 等 CI 平台。上方为英文/通用说明，仓库中亦提供 README_zh.md（完整中文说明）。如果你希望，我可以直接生成完整中文 README（覆盖全部节），我可以将上面内容翻译并润色为完整的中文 README，并在 docs 中补充配置示例与 mermaid 图.
