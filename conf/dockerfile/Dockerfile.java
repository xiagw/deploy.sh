#### docker build stage 1 ####
ARG MIRROR=
ARG MVN_VERSION=3.8-amazoncorretto-8
ARG JDK_VERSION=8

FROM ${MIRROR}maven:${MVN_VERSION} AS builder

ARG IN_CHINA=false
ARG MVN_PROFILE=main
ARG MVN_DEBUG=off
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh
WORKDIR /src
RUN --mount=type=cache,target=/root/.m2,id=maven_cache,sharing=shared \
    --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fL "$BUILD_URL" -o $BUILD_SH; \
    [ -f $BUILD_SH ] && bash $BUILD_SH
    ## 假如此处中断，表明 maven build 失败，请检查代码


#### docker build stage 2 ####
FROM ${MIRROR}amazoncorretto:${JDK_VERSION}

ARG IN_CHINA=false
ARG MVN_PROFILE=main
ARG TZ=Asia/Shanghai
ARG INSTALL_FONTS=false
ARG INSTALL_FFMPEG=false
ARG INSTALL_LIBREOFFICE=false
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh
ENV TZ=$TZ
WORKDIR /app
EXPOSE 8080 8081 8082
CMD ["bash", "/opt/run0.sh"]
RUN --mount=type=cache,target=/var/lib/apt/lists,id=apt_cache,sharing=shared  \
    --mount=type=cache,target=/var/cache/yum,id=yum_cache,sharing=shared  \
    --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fL "$BUILD_URL" -o $BUILD_SH; \
    [ -f $BUILD_SH ] && bash $BUILD_SH

COPY --from=builder /jars/ .
