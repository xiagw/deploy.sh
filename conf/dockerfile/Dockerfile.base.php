ARG MIRROR=
## 4.8 PHP <=7.2, 5.0/5.1/6.0 PHP 8.0+
ARG SWOOLE_VERSION=6.0
ARG PHP_VERSION=8.4
FROM ${MIRROR}phpswoole/swoole:${SWOOLE_VERSION}-php${PHP_VERSION} as swoole
RUN --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fLo $BUILD_SH $BUILD_URL; \
    bash $BUILD_SH

ARG MIRROR=
ARG OS_VERSION=22.04
FROM ${MIRROR}ubuntu:${OS_VERSION}
LABEL MAINTAINER="xiagw <fxiaxiaoyu@gmail.com>"
ARG IN_CHINA=false
ARG CHANGE_SOURCE=false
ARG PHP_VERSION=8.4
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
