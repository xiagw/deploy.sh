# deploy.sh for GitLab CI/CD

# 中文 [README_zh.md](docs/README_zh.md)

deploy.sh is a CI/CD program for GitLab Server.

# How it works
deploy.sh dependend GitLab and GitLab-Runner.

How to detect program language with deploy.sh:
- node: exist ./package.json or include `project_lang=node` in README.md
- php: exist ./composer.json or include `project_lang=php` in README.md
- java: exist ./pom.xml or include `project_lang=java` in README.md
- python: exist ./requirements.txt or include `project_lang=python` in README.md

# Description
Program Lang: shell
Run Platform: Unix/Linux/MacOS...

# Currently supported
* Cloud vendors: AWS, Aliyun, Qcloud, Huaweicloud...
* Code style: phpcs, phpcbf, java code style, jslint, shfmt, hadolint...
* Code quality: sonarqube scan, OWASP, ZAP, vulmap...
* Unit test: phpunit, junit...
* Build: npm build, composer install, maven build, gradle build, docker build, pip install ...
* Deploy method: rsync+ssh, rsync+nfs,rsync + docker image, rsync jar/war, kubectl, helm...
* Function test: Jmeter, pytest...
* Performance test: stress test, jmeter, loadrunner
* Notify deploy result: work-weixin, Telegram, Element(Matrix), dingding...
* Renew cert: [acme.sh](https://github.com/acmesh-official/acme.sh.git) renew cert for https

# Installation
`git clone https://github.com/xiagw/deploy.sh.git $HOME/runner`

## Quick Start
1. Prepare a gitlab-server and gitlab-runner-server
1. [Install gitlab-runner](https://docs.gitlab.com/runner/install/linux-manually.html), register to gitlab-server, and start gitlab-runner
1. cd $HOME
1. git clone https://github.com/xiagw/deploy.sh.git $HOME/runner
1. cd $HOME/runner
1. cp conf/deploy.conf.example conf/deploy.conf      ## change to yours
1. cp conf/deploy.env.example conf/deploy.env        ## change to yours
1. Refer to conf/.gitlab-ci.yaml of this project, setup yours


## Example step
### Step 1: Prepair Gitlab server
There is already a gitlab server (if not, you can refer to [xiagw/docker-gitlab](https://github.com/xiagw/docker-gitlab) to start one with docker-compose)
### Step 2: Prepair Gitlab Runner
There is already a server that has installed gitlab-runner and register to Gitlab server, (executer is shell)
### Step 3: Prepair Application server
The ssh key file had been prepared, and you can log in to the target server without a password from the gitlab-runner server (the id_rsa file can be in $HOME/.ssh/, or in the deploy.sh/conf/.ssh/)
### Step 4: Clone github
Login to the gitlab-runner server and execute
```
git clone https://github.com/xiagw/deploy.sh.git $HOME/runner
```
### Step 5: Update conf/deploy.conf conf/deploy.env
Refer to the conf/deploy.conf.example conf/deploy.env.example, change to yours configure
```
cd $HOME/runner
cp conf/deploy.conf.example conf/deploy.conf      ## change to yours
cp conf/deploy.env.example conf/deploy.env        ## change to yours
```
### Step 6: Create Gitlab project
For example: created `project-A` under the root account on gitlab-server (root/project-A)
### Step 7: Create .gitlab-ci.yml
Create and submit `.gitlab-ci.yml` on Gitlab `project-A`
### Step 8: Enjoy CI/CD

![](docs/readme.png)
# The following need "mermain" support

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
