ARG MIRROR=
ARG OS_VERSION=22.04
FROM ${MIRROR}ubuntu:${OS_VERSION}

LABEL MAINTAINER="xiagw <fxiaxiaoyu@gmail.com>"

ARG IN_CHINA=false
ARG CHANGE_SOURCE=false

ARG PHP_VERSION=8.3

ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh
ENV PHP_VERSION=${PHP_VERSION}
EXPOSE 80 9000
VOLUME ["/app"]
WORKDIR /app

CMD ["bash", "/opt/run0.sh"]

# RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
# --mount=type=cache,target=/var/cache/apt,sharing=locked \
# --mount=type=bind,target=/src,rw \
RUN --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fL "$BUILD_URL" -o $BUILD_SH; \
    [ -f $BUILD_SH ] && bash $BUILD_SH

ONBUILD COPY ./root/ /
ONBUILD RUN if [ -f /opt/onbuild.sh ]; then bash /opt/onbuild.sh; else :; fi
