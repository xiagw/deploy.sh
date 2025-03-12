ARG BASE_IMAGE=ubuntu
ARG IMAGE_VERSION=22.04
FROM ${BASE_IMAGE}:${IMAGE_VERSION}

LABEL MAINTAINER="xiagw <fxiaxiaoyu@gmail.com>"

ARG IN_CHINA=false
ARG CHANGE_SOURCE=false

ARG PHP_VERSION=8.3

ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh
ENV PHP_VERSION=${PHP_VERSION}
EXPOSE 80 8080 9000
WORKDIR /app

CMD ["bash", "/opt/run0.sh"]

# RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
# --mount=type=cache,target=/var/cache/apt,sharing=locked \
# --mount=type=bind,target=/src,rw \
RUN --mount=type=bind,target=/src,rw \
    if [ -f /src/root/opt/build.sh ]; then \
        bash /src/root/opt/build.sh; \
    elif [ -f build.sh ]; then \
        bash build.sh; \
    else \
        curl -fLo build.sh "$BUILD_URL" && \
        bash build.sh; \
    fi

ONBUILD COPY ./root/ /
ONBUILD RUN if [ -f /opt/onbuild.sh ]; then bash /opt/onbuild.sh; else :; fi
