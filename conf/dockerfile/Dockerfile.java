FROM maven:3.6-jdk-8 AS builder
ARG MVN_PROFILE=main
ARG MVN_DEBUG=-q
ARG IN_CHINA=false
ARG SETTINGS=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/settings.xml
WORKDIR /src
COPY . .
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -xe; \
    [ -d /root/.m2 ] || mkdir -p /root/.m2; \
    if [ "${IN_CHINA}" = true ]; then \
    curl -Lo /root/.m2/settings.xml $SETTINGS; \
    fi; \
    [ -f docs/settings.xml ] && cp -vf docs/settings.xml /root/.m2/ || true \
    && [ -f settings.xml ] && cp -vf settings.xml /root/.m2/ || true
RUN mvn -q -T 1C clean -U package -DskipTests -Dmaven.compile.fork=true
WORKDIR /jar_file
RUN find /src -type f -regextype egrep -iregex '.*SNAPSHOT.*\.jar' -exec cp {} ./ \; \
    && rm -f ./framework* ./gdp-module* sdk*.jar ./*-commom-*.jar ./*-dao-*.jar ./lop-opensdk*.jar ./core-*.jar

#############################
# FROM openjdk:11-jdk
# FROM bitnami/tomcat:8.5 as p0
# FROM bitnami/java:1.8-prod as p0
FROM openjdk:8u332
ARG IN_CHINA=false
## set startup profile
ARG MVN_PROFILE=main
## Set Timezone
ARG TZ=Asia/Shanghai
ENV TZ=$TZ
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
## set java opts
ARG JAVA_OPTS='java -Xms256m -Xmx384m'
ENV JAVA_OPTS="$JAVA_OPTS"
## install fonts
ARG INSTALL_FONTS=false
## install ffmpeg
ARG INSTALL_FFMPEG=false
ARG RUNSH=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/run.sh
ARG FONTS=http://cdn.flyh6.com/docker/fonts-2022.tgz

RUN set -x; \
    if [ "$IN_CHINA" = true ]; then \
    sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list; \
    fi; \
    apt-get update -q \
    && apt-get install -y -q --no-install-recommends less; \
    if [ "$INSTALL_FONTS" = true ]; then \
    apt-get update -q \
    && apt-get install -y -q --no-install-recommends fontconfig \
    && fc-cache --force \
    && curl -Lo /tmp/fonts.tgz --referer http://www.flyh6.com/ $FONTS \
    && tar -zxf /tmp/fonts.tgz -C /usr/share \
    && rm -f /tmp/fonts.tgz; \
    fi; \
    if [ "$INSTALL_FFMPEG" = true ]; then \
    apt-get update -q \
    && apt-get install -y --no-install-recommends ffmpeg; \
    fi; \
    ## set ssl
    sed -i 's/SSLv3\,\ TLSv1\,\ TLSv1\.1\,//g' /usr/local/openjdk-8/jre/lib/security/java.security || true; \
    useradd -u 1000 spring \
    && curl -Lo /opt/run.sh $RUNSH \
    && chmod +x /opt/run.sh \
    # apt-get autoremove -y \
    && apt-get clean all \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /jar_file/ .
# COPY ./jar_file/ .
RUN chown -R 1000:1000 /app \
    && touch "/app/profile.${MVN_PROFILE}"

USER 1000
EXPOSE 8080 8081 8082
# volume /data

CMD ["/opt/run.sh"]
