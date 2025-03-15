#### docker build stage 1: Dependencies ####
ARG MVN_IMAGE=maven
ARG MVN_VERSION=3.8-amazoncorretto-8
ARG JDK_IMAGE=amazoncorretto
ARG JDK_VERSION=8

FROM ${MVN_IMAGE}:${MVN_VERSION} AS deps
WORKDIR /src
# 预下载依赖
RUN --mount=type=cache,target=/root/.m2 \
    --mount=type=bind,target=/src,rw \
    bash /src/root/opt/build.sh deps

#### docker build stage 2: Build ####
FROM deps AS builder
ARG IN_CHINA=false
ARG MVN_PROFILE=main
ARG MVN_DEBUG=off
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh
WORKDIR /src
# 构建应用
RUN --mount=type=cache,target=/root/.m2 \
    --mount=type=bind,target=/src,rw \
    if [ -f /src/root/opt/build.sh ]; then bash /src/root/opt/build.sh; \
    elif [ -f build.sh ]; then bash build.sh; \
    else curl -fLo build.sh $BUILD_URL; bash build.sh; fi
    ## 假如此处中断，表明 maven build 失败，请检查代码


#### docker build stage 2 ####
FROM ${JDK_IMAGE}:${JDK_VERSION}
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
RUN --mount=type=cache,target=/var/lib/apt/lists \
    --mount=type=cache,target=/var/cache/yum \
    --mount=type=bind,target=/src,rw \
    if [ -f /src/root/opt/build.sh ]; then bash /src/root/opt/build.sh; \
    elif [ -f build.sh ]; then bash build.sh; \
    else curl -fLo build.sh $BUILD_URL; bash build.sh; fi
COPY --from=builder /jars/ .
