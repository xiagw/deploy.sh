FROM maven:3.6-jdk-8 as BUILDER
ARG MVN_PROFILE=test
ARG MVN_DEBUG=-q
WORKDIR /app
COPY . .
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -xe \
    # && echo "192.168.145.12 mynexus" >>/etc/hosts \
    && [ -d /root/.m2 ] || mkdir -p /root/.m2 \
    && [ -f docs/settings.xml ] && cp -vf docs/settings.xml /root/.m2/ || true \
    && [ -f settings.xml ] && cp -vf settings.xml /root/.m2/ || true
RUN set -xe && mvn -T 1C clean -U package -DskipTests -Dmaven.compile.fork=true
RUN mkdir /jar_file \
    && find . -type f -regextype egrep -iregex '.*SNAPSHOT.*\.jar' -exec cp {} /jar_file/ \; \
    && rm -f /jar_file/framework* /jar_file/gdp-module* /jar_file/sdk*.jar /jar_file/*-common-*.jar /jar_file/*-dao-*.jar

FROM openjdk:8u332 as RUNTIME
## set startup profile
ARG MVN_PROFILE=test
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

RUN set -x; \
    if [ "$INSTALL_FONTS" = true ]; then \
    sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends fontconfig \
    && fc-cache --force \
    && curl -Lo /tmp/fonts.tgz --referer http://www.flyh6.com/ http://cdn.flyh6.com/docker/fonts-2022.tgz \
    && tar -zxf /tmp/fonts.tgz -C /usr/share \
    && rm -f /tmp/fonts.tgz; \
    fi; \
    if [ "$INSTALL_FFMPEG" = true ]; then \
    apt-get update && apt-get install -y --no-install-recommends ffmpeg; \
    fi; \
    ## set ssl
    sed -i 's/SSLv3\,\ TLSv1\,\ TLSv1\.1\,//g' /usr/local/openjdk-8/jre/lib/security/java.security || true; \
    curl -Lo /opt/run.sh https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/run.sh; \
    chmod +x /opt/run.sh; \
    # apt-get autoremove -y \
    apt-get clean all \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY ./jar_file/ .
RUN chown -R 1000:1000 /app \
    && touch "/app/profile.${MVN_PROFILE}" \
    && [ -f run.sh ] && chmod +x run.sh || true

USER 1000
EXPOSE 8080 8081 8082
# volume /data

CMD ["/opt/run.sh"]
