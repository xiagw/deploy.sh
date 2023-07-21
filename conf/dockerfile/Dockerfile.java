##### stage 1 ########################
# FROM maven:3.6-jdk-11 AS builder
FROM maven:3.6-jdk-8 AS builder

ARG IN_CHINA=false
ARG MVN_PROFILE=main
ARG MVN_DEBUG=-q

WORKDIR /src
COPY . .
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -fL https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh | bash

# https://blog.frankel.ch/faster-maven-builds/2/
# RUN --mount=type=cache,target=/root/.m2 curl -fL https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/build.sh | bash

##### stage 2 ########################
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
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -fL https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh | bash

USER 1000
EXPOSE 8080 8081 8082
# volume /data

CMD ["bash", "/opt/run.sh"]
