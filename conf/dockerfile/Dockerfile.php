FROM ubuntu:22.04

ARG CHANGE_SOURCE=false
ARG IN_CHINA=false
ARG LARADOCK_PHP_VERSION=8.1

## for apt to be noninteractive
ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true
ENV TIME_ZOME Asia/Shanghai
ENV LARADOCK_PHP_VERSION=${LARADOCK_PHP_VERSION}

EXPOSE 80 443 9000
WORKDIR /var/www/html
CMD ["bash", "/opt/run.sh"]

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# COPY ./root/opt/build.sh /opt/build.sh
RUN set -xe; \
    if [ "$CHANGE_SOURCE" = true ] || [ "$IN_CHINA" = true ]; then \
    sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list; \
    fi; \
    apt-get update -yqq; \
    apt-get install -yqq --no-install-recommends curl ca-certificates vim; \
    apt-get clean all && rm -rf /tmp/*; \
    curl -fL https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh | bash

ONBUILD COPY ./root/ /
ONBUILD RUN curl -fL https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh | bash -s --onbuild
