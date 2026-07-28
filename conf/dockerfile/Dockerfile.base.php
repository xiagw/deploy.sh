# PHP 基础镜像（Ubuntu + PHP-FPM + Swoole 等），run0/run1 启动服务。
ARG MIRROR=
ARG IN_CHINA=true
ARG BUILD_IMAGE=phpswoole/swoole
ARG BUILD_TAG=8.4
ARG RUN_IMAGE=ubuntu
ARG RUN_TAG=8.5
ARG APP_PORT=8080
ARG APP_WORKDIR=/app
ARG APP_USER=1000
ARG APP_UID=1000
ARG APP_GID=1000
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh
ARG BUILD_OUTPUT_DIR=/build_output

## PHP <= 7.2
# ARG SWOOLE_VERSION=4.8
## 5.0/5.1/6.1 PHP >= 8.0
ARG SWOOLE_VERSION=6.1
ARG OS_VERSION=24.04

FROM ${MIRROR}${BUILD_IMAGE}:${SWOOLE_VERSION}-php${BUILD_TAG} AS builder
RUN --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fLo $BUILD_SH $BUILD_URL; \
    bash $BUILD_SH swoole


FROM ${MIRROR}${RUN_IMAGE}:${OS_VERSION}

LABEL MAINTAINER="xiagw <fxiaxiaoyu@gmail.com>"

ARG IN_CHINA
ARG RUN_TAG
ARG BUILD_URL

ENV PHP_VERSION=${RUN_TAG}

EXPOSE 80 9000
VOLUME ["/app"]
WORKDIR /app
CMD ["bash", "/opt/run0.sh"]
COPY --from=builder /build_output/ /
# RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
# --mount=type=cache,target=/var/cache/apt,sharing=locked \
# --mount=type=bind,target=/src,rw \
RUN --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fLo $BUILD_SH $BUILD_URL; \
    bash $BUILD_SH php

ONBUILD COPY ./root/ /
ONBUILD RUN if [ -f /opt/onbuild.sh ]; then bash /opt/onbuild.sh; else :; fi
