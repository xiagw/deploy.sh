# PHP 基础镜像（Ubuntu + PHP-FPM + Swoole 等），run0/run1 启动服务。
# 示例：docker build -f conf/dockerfile/Dockerfile.base.php --build-arg PHP_VERSION=8.5 -t myphp:base .
ARG MIRROR=
## PHP <= 7.2
# ARG SWOOLE_VERSION=4.8
## 5.0/5.1/6.1 PHP >= 8.0
ARG SWOOLE_VERSION=6.1
ARG PHP_VERSION=8.5
ARG PHP_VERSION_2=8.4
ARG OS_VERSION=24.04
FROM ${MIRROR}phpswoole/swoole:${SWOOLE_VERSION}-php${PHP_VERSION_2} AS swoole
RUN --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fLo $BUILD_SH $BUILD_URL; \
    bash $BUILD_SH swoole

FROM ${MIRROR}ubuntu:${OS_VERSION}
LABEL MAINTAINER="xiagw <fxiaxiaoyu@gmail.com>"
ARG IN_CHINA=false
ARG CHANGE_SOURCE=false
ARG PHP_VERSION=8.5
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh
ENV PHP_VERSION=${PHP_VERSION}
EXPOSE 80 9000
VOLUME ["/app"]
WORKDIR /app
CMD ["bash", "/opt/run0.sh"]
COPY --from=swoole /swoole.so /
# RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
# --mount=type=cache,target=/var/cache/apt,sharing=locked \
# --mount=type=bind,target=/src,rw \
RUN --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fLo $BUILD_SH $BUILD_URL; \
    bash $BUILD_SH

ONBUILD COPY ./root/ /
ONBUILD RUN if [ -f /opt/onbuild.sh ]; then bash /opt/onbuild.sh; else :; fi
