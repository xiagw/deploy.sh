## arch: x86_64
ARG IMAGE_NAME=ubuntu

## arch: arm64
# ARG IMAGE_NAME=arm64v8/ubuntu

FROM ${IMAGE_NAME}:22.04

ARG IN_CHINA=false
ARG CHANGE_SOURCE=false
ARG PHP_VERSION=8.1
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh

## for apt to be noninteractive
ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true
ENV TIME_ZOME Asia/Shanghai
ENV PHP_VERSION=${PHP_VERSION}

EXPOSE 80 443 9000
WORKDIR /var/www/html
WORKDIR /app
CMD ["bash", "/opt/run.sh"]

# SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY ./root/ /
RUN set -xe; \
    if [ -f /opt/build.sh ]; then \
    echo "found /opt/build.sh"; \
    else \
    if [ "$CHANGE_SOURCE" = true ] || [ "$IN_CHINA" = true ]; then \
    sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list; \
    fi; \
    apt-get update -yqq; \
    apt-get install -yqq --no-install-recommends curl ca-certificates vim; \
    apt-get clean all && rm -rf /tmp/*; \
    curl -fLo /opt/build.sh $BUILD_URL; \
    fi; \
    bash /opt/build.sh

ONBUILD COPY ./root/ /
ONBUILD RUN if [ -f /opt/onbuild.sh ]; then bash /opt/onbuild.sh; else :; fi
