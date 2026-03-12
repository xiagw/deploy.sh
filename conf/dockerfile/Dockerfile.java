# =============================================================================
# Java 应用镜像（多阶段构建）
# 阶段1：Maven 编译；阶段2：仅 JDK 运行 JAR
# 示例：docker build -f conf/dockerfile/Dockerfile.java --build-arg IN_CHINA=true -t myapp:java .
# =============================================================================

#### 阶段 1：Maven 构建 ####
ARG MIRROR=                                    # 基础镜像仓库前缀，如国内镜像
ARG MVN_VERSION=3.8-amazoncorretto-8          # Maven 镜像版本
ARG JDK_VERSION=8                             # 运行阶段 JDK 版本
FROM ${MIRROR}maven:${MVN_VERSION} AS builder
## 构建参数 IN_CHINA 必须在 FROM 后面
ARG IN_CHINA=false                             # 国内环境时设为 true，使用 Maven/NPM 等镜像
ARG MVN_PROFILE=main                           # Maven profile，如 main / prod
ARG MVN_DEBUG=off                              # 设为 on 可保留 Maven 详细日志
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh
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
FROM ${MIRROR}amazoncorretto:${JDK_VERSION}
ARG IN_CHINA=false
ARG MVN_PROFILE=main
ARG TZ=Asia/Shanghai
ARG INSTALL_FONTS=false                        # 是否安装中文字体（报表/导出等）
ARG INSTALL_FFMPEG=false                       # 是否安装 ffmpeg
ARG INSTALL_LIBREOFFICE=false                  # 是否安装 LibreOffice
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh
ENV TZ=$TZ
WORKDIR /app                                   # 应用目录，JAR 与配置放于此
EXPOSE 8080 8081
VOLUME ["/app"]
CMD ["bash", "/opt/run0.sh"]                   # 入口：初始化后由 run1.sh 启动 JAR
RUN --mount=type=cache,target=/var/lib/apt/lists,id=apt_cache,sharing=shared  \
    --mount=type=cache,target=/var/cache/yum,id=yum_cache,sharing=shared  \
    --mount=type=bind,target=/src,rw \
    set -xe; \
    BUILD_SH=/src/root/opt/build.sh; \
    [ -f $BUILD_SH ] || BUILD_SH=build.sh; \
    [ -f $BUILD_SH ] || curl -fLo $BUILD_SH $BUILD_URL; \
    bash $BUILD_SH

# 从构建阶段拷贝已打包的 JAR（build.sh 会输出到 /jars/）
COPY --from=builder /jars/ .
