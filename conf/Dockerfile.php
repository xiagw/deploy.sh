# =============================================================================
# PHP 运行时基础镜像（conf/Dockerfile.single 的 PHP 专用版本）
# 由 lib/kubernetes.sh 的 build_base_image 传入 PHP_VERSION。
# 所有版本统一 ubuntu:24.04 + ondrej PPA：该 PPA 已为 7.1/7.3/7.4/8.1 回填 PHP2Shell 补丁。
# 运行期契约与 Dockerfile.single 保持一致：CMD /opt/run0.sh、VOLUME、ONBUILD。
# =============================================================================
ARG MIRROR=

FROM ${MIRROR}ubuntu:24.04

ARG PHP_VERSION=8.4
ARG IS_CHINA=false
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/root/opt/build.sh
ARG TZ=UTC
ARG APP_WORKDIR=/app
ARG APP_PORTS="80 9000"
ARG APP_VOLUME=/app
ARG APP_CMD="/opt/run0.sh"
ARG ONBUILD_CHOWN=0:0
ARG ONBUILD_COPY_SRC=./root/
ARG ONBUILD_COPY_DEST=/

LABEL maintainer="xiagw <fxiaxiaoyu@gmail.com>" \
    org.opencontainers.image.authors="xiagw <fxiaxiaoyu@gmail.com>" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.source="https://github.com/xiagw/deploy.sh" \
    php.version="${PHP_VERSION}"

ENV TZ=${TZ} \
    ONBUILD_CHOWN=${ONBUILD_CHOWN} \
    ONBUILD_COPY_SRC=${ONBUILD_COPY_SRC} \
    ONBUILD_COPY_DEST=${ONBUILD_COPY_DEST}

WORKDIR ${APP_WORKDIR}
EXPOSE ${APP_PORTS}

RUN --mount=type=cache,target=/var/lib/apt/lists,id=apt_lists,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,id=apt_cache,sharing=locked \
    --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fLo $BUILD_SH $BUILD_URL; \
    if command -v bash >/dev/null 2>&1; then bash $BUILD_SH php; else sh $BUILD_SH php; fi

VOLUME ${APP_VOLUME}

CMD ["/bin/bash", "-c", "${APP_CMD:-/opt/run0.sh}"]

ONBUILD COPY --chown=${ONBUILD_CHOWN} ${ONBUILD_COPY_SRC} ${ONBUILD_COPY_DEST}
ONBUILD RUN set -xe; \
    if [ -f /opt/onbuild.sh ]; then \
        if command -v bash >/dev/null 2>&1; then bash /opt/onbuild.sh; else sh /opt/onbuild.sh; fi; \
    fi
