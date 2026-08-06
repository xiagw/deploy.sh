
## 全局变量
ARG IS_CHINA=false
ARG MIRROR=
ARG BUILD_IMAGE=maven
ARG BUILD_TAG=3.9-amazoncorretto-17
ARG RUN_IMAGE=amazoncorretto
ARG RUN_TAG=17

ARG IMAGE_TYPE=java
ARG APP_PORT=8080
ARG APP_WORKDIR=/app
ARG APP_USER=1000
ARG APP_UID=1000
ARG APP_GID=1000

ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/root/opt/build.sh
ARG BUILD_OUTPUT_DIR=/build_output

# Maven profile，如 develop / main
ARG MVN_PROFILE=main
# 是否安装中文字体（报表/导出等）
ARG INSTALL_FONTS=false
# 是否安装 ffmpeg
ARG INSTALL_FFMPEG=false
# 是否安装 LibreOffice
ARG INSTALL_LIBREOFFICE=false

################################################################################
#### 阶段 1：Maven 编译 ####
FROM ${MIRROR}${BUILD_IMAGE}:${BUILD_TAG} AS builder
## FROM之前的全局变量必须重新定义
ARG IS_CHINA
ARG APP_WORKDIR
ARG APP_PORT
ARG APP_USER
ARG APP_UID
ARG APP_GID
ARG MVN_PROFILE
ARG BUILD_OUTPUT_DIR
ARG BUILD_URL

WORKDIR /src
# 使用缓存加速 Maven 依赖；需在构建时 mount 源码到 /src
RUN --mount=type=cache,target=/root/.m2,id=maven_cache,sharing=shared \
    --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fLo $BUILD_SH $BUILD_URL; \
    bash $BUILD_SH
    ## 假如此处中断，表明 maven build 失败，请检查代码


################################################################################
#### 阶段 2：仅 JDK 运行 ####
FROM ${MIRROR}${RUN_IMAGE}:${RUN_TAG} AS final
ARG IS_CHINA
ARG APP_WORKDIR
ARG APP_PORT
ARG APP_USER
ARG APP_UID
ARG APP_GID
ARG MVN_PROFILE
ARG BUILD_OUTPUT_DIR
ARG BUILD_URL
ARG INSTALL_FONTS
ARG INSTALL_FFMPEG
ARG INSTALL_LIBREOFFICE

ARG TZ=Asia/Shanghai

ENV TZ=$TZ
WORKDIR ${APP_WORKDIR}
EXPOSE 8080 8081
VOLUME ["${APP_WORKDIR}"]
# 入口：初始化后由 run1.sh 启动 JAR
CMD ["bash", "-c", "/opt/run0.sh"]
RUN --mount=type=cache,target=/var/lib/apt/lists,id=apt_cache,sharing=shared  \
    --mount=type=cache,target=/var/cache/yum,id=yum_cache,sharing=shared  \
    --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fLo $BUILD_SH $BUILD_URL; \
    bash $BUILD_SH

# 从构建阶段拷贝已打包的 JAR（build.sh 会输出到 /build_output/）
COPY --from=builder $BUILD_OUTPUT_DIR/ .
