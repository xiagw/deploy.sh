deploy.sh for GitLab CI/CD：

- 支持 阿里云，
- 支持 腾讯云，
- 支持 AWS，
- 支持 直接拷代码文件，
- 支持 docker build image，
- 支持 PHP，Java，Vue，Dockerfile 代码格式化检查，
- 支持 调用acme.sh更新ssl证书
- 支持 调用单元测试
- 支持 调用Sonarqube Scan
- 支持 调用功能自动化测试
- 支持 调用性能压测
- 支持 docker 挂载 nfs，直接部署文件模式
- 支持 Node， npm/yarn，直接部署文件模式
- 支持 Node， docker image 直接部署image模式
- 支持 Java， maven/gradle打包，直接部署jar包文件模式
- 支持 Java， docker image 直接部署image模式
- 支持 PHP， 直接部署文件模式
- 支持 PHP， composer，直接部署文件模式
- 支持 PHP， docker image 直接部署image模式
- 支持 k8s 部署
- 支持 helm 部署
- 支持 普通文件模式部署
- 支持 结果的消息提醒，企业微信，Telegram，Element(Matrix)

# Quick Start
1. 安装操作系统 ubuntu/centos...
1. 安装 gitlab-runner 并且 register it 并且启动 gitlab-runner...
1. cd $HOME
1. git clone https://github.com/xiagw/deploy.sh.git
1. 设置 .gitlab-ci.yaml 于目标git仓库

# 以下显示图片需要 mermain 支持

```mermaid
graph TB;

Dev -- pull/push --> Java;
Dev -- pull/push --> PHP;
Dev -- pull/push --> VUE;
Dev -- pull/push --> Python;
Dev -- pull/push --> other[Languages];
Java -- pull/push --> git;
PHP -- pull/push --> git;
VUE -- pull/push --> git;
Python -- pull/push --> git;
other -- pull/push --> git;
Ops -- shell --> git;
git --> CI[deploy.sh];
Ops -- shell --> CI;
UI -- sketch --> PD;
PD -- issues --> git[GitLab Server];
QA -- issues--> git;
QA -- test--> testm[Manuel tests];
QA -- test--> testauto[Auto tests];
CI -- rsync --> Servers;
CI -- kubectl/helm --> K8s;
CI -- docker --> Build;
CI -- sql --> db1[Database manage];
CI -- cert manage --> cert[Cert manage];
CI -- notify --> notify[Notify manage];
db1 -- sql --> flyway;
cert -- shell --> acme[acme.sh];
acme -- dns api --> dns1[dns api CF];
acme -- dns api --> dns2[dns api ali];
CI -- code --> rev[Code check];
CI -- test --> test[Test center];
test -- test --> testu[Unit tests];
testu -- test --> testf[Function tests];
testf -- test --> testl[Load tests];
rev --> format[Code formater];
format --> sonar[Sonarqube scan];
Build -- push --> Repo[Docker Registry];
Servers -- pub --> Cloud-x[Pub Cloud];
Cloud-x --> mx[VM];
Servers -- pri --> own[Pri Cloud];
own --> my[SVRS]
K8s -- pri --> ENV_D[ENV develop];
K8s -- pri --> ENV_T[ENV testing];
K8s -- pri --> ENV_M[ENV master];
ENV_D -- pri --> app_d[app 1,2,3...];
app_d -- pri --> cache_d[redis cluster];
cache_d -- pri --> db_d[mysql cluster];
ENV_T -- pri --> app_t[app 1,2,3...];
app_t -- pri --> cache_t[redis cluster];
cache_t -- pri --> db_t[mysql cluster];
ENV_M -- pri --> app_m[app 1,2,3...];
app_m -- pri --> cache_m[redis cluster];
cache_m -- pri --> db_m[mysql cluster];
```
