ARG BASE_IMAGE=amazoncorretto
ARG JDK_VERSION=8

FROM ${BASE_IMAGE}:${JDK_VERSION}

LABEL maintainer="xiagw <fxiaxiaoyu@gmail.com>" \
    org.opencontainers.image.authors="xiagw <fxiaxiaoyu@gmail.com>" \
    org.opencontainers.image.description="Java application base image" \
    org.opencontainers.image.licenses="MIT"

ARG IN_CHINA=false
ARG MVN_PROFILE=main
ARG TZ=Asia/Shanghai
ARG INSTALL_FONTS=false
ARG INSTALL_FFMPEG=false
ARG INSTALL_LIBREOFFICE=false
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh

ENV TZ=$TZ
    # JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0" \
    # LC_ALL=C.UTF-8

WORKDIR /app

RUN --mount=type=cache,target=/var/cache/yum,sharing=locked \
    --mount=type=bind,target=/src,rw \
    set -ex; \
    # 执行构建脚本
    if [ -f /src/root/opt/build.sh ]; then \
        bash /src/root/opt/build.sh; \
    elif [ -f build.sh ]; then \
        bash build.sh; \
    else \
        curl -fLo build.sh "$BUILD_URL" && \
        bash build.sh; \
    fi

EXPOSE 8080 8081 8082

# 添加健康检查
# HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
#     CMD curl -f http://localhost:8080/ || exit 1

CMD ["bash", "/opt/run0.sh"]

ONBUILD COPY ./root/ /
ONBUILD RUN if [ -f /opt/onbuild.sh ]; then bash /opt/onbuild.sh; else :; fi
