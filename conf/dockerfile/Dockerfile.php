ARG OS_VER=${OS_VER}
FROM ubuntu:${OS_VER}

ARG CHANGE_SOURCE=false

ARG LARADOCK_PHP_VERSION=${PHP_VERSION}

ARG PHP_SESSION_REDIS=false
ARG PHP_SESSION_REDIS_SERVER=${REDIS_HOST}
ARG PHP_SESSION_REDIS_PORT=${REDIS_PORT}
ARG PHP_SESSION_REDIS_PASS=${REDIS_PASSWORD}
ARG PHP_SESSION_REDIS_DB=1

## for apt to be noninteractive
ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true
ENV TIME_ZOME Asia/Shanghai
ENV OS_VER=${OS_VER}
ENV LARADOCK_PHP_VERSION=${LARADOCK_PHP_VERSION}

EXPOSE 80 443 9000
WORKDIR /var/www/html
CMD ["/opt/run.sh"]

# COPY ./root/opt/build.sh /opt/build.sh
RUN set -xe; \
    if [ "$CHANGE_SOURCE" = true ] || [ "$IN_CHINA" = true ]; then \
    sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list; \
    fi; \
    apt-get update -yqq; \
    apt-get install -yqq --no-install-recommends curl vim ca-certificates; \
    curl -Lo /opt/build.sh https://gitee.com/xiagw/laradock/raw/in-china/php-fpm/root/opt/build.sh; \
    bash /opt/build.sh; \
    apt-get clean all && rm -rf /tmp/*

# ONBUILD COPY ./root/ /
ONBUILD RUN curl -Lo /opt/onbuild.sh https://gitee.com/xiagw/laradock/raw/in-china/php-fpm/root/opt/onbuild.sh; bash /opt/onbuild.sh
