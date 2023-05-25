#!/bin/bash

_set_timezone() {
    if [ "$IN_CHINA" = false ] || [ "${CHANGE_SOURCE}" = false ]; then
        return
    fi
    ln -snf /usr/share/zoneinfo/${TZ:-Asia/Shanghai} /etc/localtime
    echo ${TZ:-Asia/Shanghai} >/etc/timezone
}

_set_mirror() {
    url_fly_cdn="http://cdn.flyh6.com/docker"

    if [ "${IN_CHINA:-true}" = true ]; then
        url_deploy_raw=https://gitee.com/xiagw/deploy.sh/raw/main
    else
        url_deploy_raw=https://github.com/xiagw/deploy.sh/raw/main
    fi

    if [ "$IN_CHINA" = false ] || [ "${CHANGE_SOURCE}" = false ]; then
        return
    fi
    ## maven
    if command -v mvn; then
        m2_dir=/root/.m2
        [ -d $m2_dir ] || mkdir -p $m2_dir
        if [ -f settings.xml ]; then
            cp -vf settings.xml $m2_dir/
        elif [ -f docs/settings.xml ]; then
            cp -vf docs/settings.xml $m2_dir/
        else
            url_settings=$url_deploy_raw/conf/dockerfile/settings.xml
            curl -Lo $m2_dir/settings.xml $url_settings
        fi
    fi
    ## OS ubuntu:20.04 php
    if [ -f /etc/apt/sources.list ]; then
        sed -i -e 's/deb.debian.org/mirrors.ustc.edu.cn/g' \
            -e 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
    fi
    ## alpine, nginx:alpine
    if [ -f /etc/apk/repositories ]; then
        sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories
    fi
    ## node, npm, yarn
    if command -v yarn || command -v npm; then
        yarn config set registry https://registry.npm.taobao.org
        npm config set registry https://registry.npm.taobao.org
    fi
}

_build_nginx() {
    echo "build nginx ..."
    apk update
    apk upgrade
    apk add --no-cache openssl bash curl
    touch /var/log/messages
    apk --no-cache add shadow

    groupmod -g 1000 nginx
    usermod -u 1000 nginx
    # Set upstream conf and remove the default conf
    # echo "upstream php-upstream { server ${PHP_UPSTREAM_CONTAINER}:${PHP_UPSTREAM_PORT}; }" >/etc/nginx/php-upstream.conf
    # rm /etc/nginx/conf.d/default.conf
    sed -i 's/\r//g' /docker-entrypoint.d/run.sh
    chmod +x /docker-entrypoint.d/run.sh
}

_build_php() {
    echo "build php ..."

    usermod -u 1000 www-data
    groupmod -g 1000 www-data

    apt-get update -yqq
    $apt_opt apt-utils
    ## preesed tzdata, update package index, upgrade packages and install needed software
    truncate -s0 /tmp/preseed.cfg
    echo "tzdata tzdata/Areas select Asia" >>/tmp/preseed.cfg
    echo "tzdata tzdata/Zones/Asia select Shanghai" >>/tmp/preseed.cfg
    debconf-set-selections /tmp/preseed.cfg
    rm -f /etc/timezone /etc/localtime

    $apt_opt tzdata
    $apt_opt locales

    grep -q '^en_US.UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen
    locale-gen en_US.UTF-8

    case "$LARADOCK_PHP_VERSION" in
    8.*)
        echo "Use default repo of OS."
        ;;
    *)
        echo "Use ppa:ondrej/php"
        $apt_opt software-properties-common
        add-apt-repository ppa:ondrej/php
        $apt_opt php"${LARADOCK_PHP_VERSION}"-mcrypt
        ;;
    esac

    apt-get upgrade -yqq
    $apt_opt \
        php"${LARADOCK_PHP_VERSION}" \
        php"${LARADOCK_PHP_VERSION}"-redis \
        php"${LARADOCK_PHP_VERSION}"-mongodb \
        php"${LARADOCK_PHP_VERSION}"-imagick \
        php"${LARADOCK_PHP_VERSION}"-fpm \
        php"${LARADOCK_PHP_VERSION}"-gd \
        php"${LARADOCK_PHP_VERSION}"-mysql \
        php"${LARADOCK_PHP_VERSION}"-xml \
        php"${LARADOCK_PHP_VERSION}"-xmlrpc \
        php"${LARADOCK_PHP_VERSION}"-bcmath \
        php"${LARADOCK_PHP_VERSION}"-gmp \
        php"${LARADOCK_PHP_VERSION}"-zip \
        php"${LARADOCK_PHP_VERSION}"-soap \
        php"${LARADOCK_PHP_VERSION}"-curl \
        php"${LARADOCK_PHP_VERSION}"-bz2 \
        php"${LARADOCK_PHP_VERSION}"-mbstring \
        php"${LARADOCK_PHP_VERSION}"-msgpack \
        php"${LARADOCK_PHP_VERSION}"-sqlite3
    # php"${LARADOCK_PHP_VERSION}"-process \
    # php"${LARADOCK_PHP_VERSION}"-pecl-mcrypt  replace by  php"${LARADOCK_PHP_VERSION}"-libsodium

    $apt_opt libjemalloc2

    if [ "$INSTALL_APACHE" = true ]; then
        $apt_opt apache2 libapache2-mod-fcgid \
            libapache2-mod-php"${LARADOCK_PHP_VERSION}"
        sed -i -e '1 i ServerTokens Prod' -e '1 i ServerSignature Off' \
            -e '1 i ServerName www.example.com' \
            /etc/apache2/sites-available/000-default.conf
    else
        $apt_opt nginx
    fi
    apt-get clean all && rm -rf /tmp/*
}

_build_mysql() {
    echo "build mysql ..."
    chown -R mysql:root /var/lib/mysql/
    chmod o-rw /var/run/mysqld

    my_cnf=/etc/mysql/conf.d/my.cnf
    if mysqld --version | grep '5\.7'; then
        cp -f $me_path/my.5.7.cnf $my_cnf
    elif mysqld --version | grep '8\.0'; then
        cp -f $me_path/my.8.0.cnf $my_cnf
    else
        cp -f $me_path/my.cnf $my_cnf
    fi
    chmod 0444 $my_cnf
    if [ "$MYSQL_SLAVE" = 'true' ]; then
        sed -i -e "/server_id/s/1/${MYSQL_SLAVE_ID:-2}/" -e "/auto_increment_offset/s/1/2/" $my_cnf
    fi
    sed -i '/skip-host-cache/d' /etc/my.cnf

    printf "[client]\npassword=%s\n" "${MYSQL_ROOT_PASSWORD}" >/root/.my.cnf
    printf "export LANG=C.UTF-8" >/root/.bashrc

    chmod +x /opt/*.sh
}

_build_redis() {
    echo "build redis ..."
}
_build_node() {
    echo "build node ..."

    mkdir /.cache
    chown -R node:node /.cache
    npm install -g rnpm@1.9.0
    npm install -g apidoc

    # su - node -c
    # if [ "$IN_CHINA" = true ]; then
    #     yarn config set registry https://registry.npm.taobao.org
    #     npm config set registry https://registry.npm.taobao.org
    # fi
}

_build_mvn() {
    # --settings=settings.xml --activate-profiles=main
    # mvn -T 1C install -pl $moduleName -am --offline
    mvn --threads 1C --update-snapshots -DskipTests -Dmaven.compile.fork=true clean package

    mkdir /jars
    find . -type f -regextype egrep -iregex '.*SNAPSHOT.*\.jar' |
        grep -Ev 'framework.*|gdp-module.*|sdk.*\.jar|.*-commom-.*\.jar|.*-dao-.*\.jar|lop-opensdk.*\.jar|core-.*\.jar' |
        xargs -t -I {} cp -vf {} /jars/
}

_build_runtime_jdk() {
    apt-get update -q
    $apt_opt less
    if [ "$INSTALL_FFMPEG" = true ]; then
        $apt_opt ffmpeg
    fi
    if [ "$INSTALL_FONTS" = true ]; then
        $apt_opt fontconfig
        fc-cache --force
        curl --referer http://www.flyh6.com/ -Lo - $url_fly_cdn/fonts-2022.tgz |
            tar -C /usr/share -zxf -
    fi
    ## set ssl
    if [[ -f /usr/local/openjdk-8/jre/lib/security/java.security ]]; then
        sed -i 's/SSLv3\,\ TLSv1\,\ TLSv1\.1\,//g' /usr/local/openjdk-8/jre/lib/security/java.security
    fi
    ## startup run.sh
    curl -Lo /opt/run.sh $url_deploy_raw/conf/dockerfile/root/run.sh
    chmod +x /opt/run.sh

    useradd -u 1000 spring
    chown -R 1000:1000 /app
    touch "/app/profile.${MVN_PROFILE}"

    $apt_opt libjemalloc2

    # apt-get autoremove -y
    apt-get clean all
    rm -rf /var/lib/apt/lists/*
}

_build_tomcat() {
    # FROM bitnami/tomcat:8.5 as tomcat
    sed -i -e '/Connector port="8080"/ a maxConnections="800" acceptCount="500" maxThreads="400"' /opt/bitnami/tomcat/conf/server.xml
    # && sed -i -e '/UMASK/s/0027/0022/' /opt/bitnami/tomcat/bin/catalina.sh
    sed -i -e '/localhost_access_log/ a rotatable="false"' /opt/bitnami/tomcat/conf/server.xml
    sed -i -e '/AsyncFileHandler.prefix = catalina./ a 1catalina.org.apache.juli.AsyncFileHandler.suffix = out\n1catalina.org.apache.juli.AsyncFileHandler.rotatable = False' /opt/bitnami/tomcat/conf/logging.properties
    ln -sf /dev/stdout /opt/bitnami/tomcat/logs/app-all.log
    # && ln -sf /dev/stdout /opt/bitnami/tomcat/logs/app-debug.log
    # && ln -sf /dev/stdout /opt/bitnami/tomcat/logs/app-info.log
    # && ln -sf /dev/stdout /opt/bitnami/tomcat/logs/app-error.log
    ln -sf /dev/stdout /opt/bitnami/tomcat/logs/catalina.out
    ln -sf /dev/stdout /opt/bitnami/tomcat/logs/localhost_access_log.txt
    # && useradd -m -s /bin/bash -u 1001 tomcat
    # && chown -R 1001 /opt/bitnami/tomcat
    rm -rf /opt/bitnami/tomcat/webapps_default/*
}

main() {
    set -xe
    # set -eo pipefail
    # shopt -s nullglob

    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="$me_path/${me_name}.log"

    apt_opt="apt-get install -yqq --no-install-recommends"

    _set_mirror

    if command -v nginx && [ -n "$INSTALL_NGINX" ]; then
        _build_nginx
    elif [ -n "$LARADOCK_PHP_VERSION" ]; then
        _set_timezone
        _build_php
    elif command -v mvn && [ -n "$MVN_PROFILE" ]; then
        _build_mvn
    elif command -v java && [ -n "$MVN_PROFILE" ]; then
        _build_runtime_jdk
    fi
}

main "$@"
