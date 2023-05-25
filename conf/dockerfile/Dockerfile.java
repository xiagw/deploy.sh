# FROM maven:3.6-jdk-11 AS builder
FROM maven:3.6-jdk-8 AS builder

ARG IN_CHINA=false
ARG MVN_PROFILE=main
ARG MVN_DEBUG=-q

WORKDIR /src
COPY . .
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -fL https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/build.sh | bash

#############################
# FROM openjdk:11-jdk
# FROM bitnami/tomcat:8.5 as p0
# FROM bitnami/java:1.8-prod as p0
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
RUN curl -fL https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/build.sh | bash

USER 1000
EXPOSE 8080 8081 8082
# volume /data

CMD ["/opt/run.sh"]
