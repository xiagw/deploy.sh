# =============================================================================
# Java 应用镜像（多阶段构建）
# 示例：docker build -f conf/dockerfile/Dockerfile.java --build-arg IN_CHINA=true -t myapp:java .
# =============================================================================

#### 阶段 1：Maven 构建 ####
# 国内环境时设为镜像地址 official/base/custom image
ARG MIRROR=
ARG BUILD_IMAGE=maven
ARG BUILD_TAG=3.9-amazoncorretto-17

ARG RUN_IMAGE=amazoncorretto
ARG RUN_TAG=17

# 国内环境时设为 true，使用 Maven/NPM 等镜像
ARG IN_CHINA=false
# Maven profile，如 develop / main
ARG MVN_PROFILE=main
# 设为 true 可显示 Maven 详细日志
ARG MVN_DEBUG=false
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh
ARG BUILD_OUTPUT_DIR=/build_output
# 是否安装中文字体（报表/导出等）
ARG INSTALL_FONTS=false
# 是否安装 ffmpeg
ARG INSTALL_FFMPEG=false
# 是否安装 LibreOffice
ARG INSTALL_LIBREOFFICE=false

#### 阶段 1：Maven 编译 ####
FROM ${MIRROR}${BUILD_IMAGE}:${BUILD_TAG} AS builder
ARG IN_CHINA
ARG MVN_PROFILE
ARG MVN_DEBUG
ARG BUILD_URL
ARG BUILD_OUTPUT_DIR

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


#### 阶段 2：仅 JDK 运行 ####
FROM ${MIRROR}${RUN_IMAGE}:${RUN_TAG} AS final
ARG IN_CHINA
ARG MVN_PROFILE
ARG MVN_DEBUG
ARG BUILD_URL
ARG BUILD_OUTPUT_DIR
ARG INSTALL_FONTS
ARG INSTALL_FFMPEG
ARG INSTALL_LIBREOFFICE

ARG TZ=Asia/Shanghai

ENV TZ=$TZ
# 应用目录，JAR 与配置放于此
WORKDIR /app
EXPOSE 8080 8081
VOLUME ["/app"]
# 入口：初始化后由 run1.sh 启动 JAR
CMD ["bash", "/opt/run0.sh"]
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
