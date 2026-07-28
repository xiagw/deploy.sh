# =============================================================================
# Java 基础运行镜像（不包含 Maven 构建，仅 JDK + 运行环境）
# 适用于：已有 JAR、或由 CI 构建好再 COPY 进镜像的场景
# 示例：docker build -f conf/dockerfile/Dockerfile.base.java -t myapp:base .
# =============================================================================
ARG MIRROR=
ARG BUILD_IMAGE=amazoncorretto
ARG BUILD_TAG=17
ARG RUN_IMAGE=amazoncorretto
ARG RUN_TAG=17

ARG IN_CHINA=false
ARG MVN_DEBUG=false
ARG MVN_PROFILE=base

# FROM ${MIRROR}${BUILD_IMAGE}:${BUILD_TAG}
FROM ${MIRROR}${RUN_IMAGE}:${RUN_TAG}
ARG IN_CHINA
ARG MVN_DEBUG
ARG MVN_PROFILE

LABEL maintainer="xiagw <fxiaxiaoyu@gmail.com>" \
    org.opencontainers.image.authors="xiagw <fxiaxiaoyu@gmail.com>" \
    org.opencontainers.image.description="Java application base image" \
    org.opencontainers.image.licenses="MIT"

ARG TZ=Asia/Shanghai
ARG INSTALL_FONTS=false
ARG INSTALL_FFMPEG=false
ARG INSTALL_LIBREOFFICE=false
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh

ENV TZ=$TZ
    # JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0" \
    # LC_ALL=C.UTF-8

WORKDIR /app

RUN --mount=type=cache,target=/var/cache/yum,id=var_cache_yum,sharing=shared \
    --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fLo $BUILD_SH $BUILD_URL; \
    bash $BUILD_SH

EXPOSE 8080 8081
VOLUME ["/app"]
# 添加健康检查
# HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
#     CMD curl -f http://localhost:8080/ || exit 1

CMD ["bash", "/opt/run0.sh"]

ONBUILD COPY ./root/ /
ONBUILD RUN if [ -f /opt/onbuild.sh ]; then bash /opt/onbuild.sh; else :; fi
