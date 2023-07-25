##############################
#    docker build stage 1    #
##############################
# FROM maven:3.6-jdk-11 AS builder
FROM maven:3.6-jdk-8 AS builder

ARG IN_CHINA=false
ARG MVN_PROFILE=main
ARG MVN_DEBUG=-q
ARG MVN_COPY_YAML=false

WORKDIR /src
COPY . .
COPY ./root/ /
# SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -xe; \
    if [ -f /opt/build.sh ]; then \
    echo "found /opt/build.sh"; \
    else \
    curl -fLo /opt/build.sh https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh; \
    fi
RUN bash /opt/build.sh
# https://blog.frankel.ch/faster-maven-builds/2/
# RUN --mount=type=cache,target=/root/.m2 curl -fL https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/build.sh | bash



##############################
#    docker build stage 2    #
##############################
FROM openjdk:8u332

ARG IN_CHINA=false
## set startup profile
ARG MVN_PROFILE=main
ARG TZ=Asia/Shanghai
ARG INSTALL_FONTS=false
ARG INSTALL_FFMPEG=false

ENV TZ=$TZ

WORKDIR /app
COPY --from=builder /jars/ .
COPY ./root/ /
RUN set -xe; \
    if [ -f /opt/build.sh ]; then \
    echo "found /opt/build.sh"; \
    else \
    curl -fLo /opt/build.sh https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh; \
    fi; \
    bash /opt/build.sh

USER 1000
EXPOSE 8080 8081 8082
# volume /data

CMD ["bash", "/opt/run.sh"]
