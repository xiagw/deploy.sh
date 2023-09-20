#!/bin/bash

_is_root() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

_set_mirror() {
    if [ "$1" = shanghai ]; then
        export TZ=Asia/Shanghai
        ln -snf /usr/share/zoneinfo/"${TZ}" /etc/localtime
        echo "${TZ}" >/etc/timezone
        return
    fi

    url_fly_cdn="http://cdn.flyh6.com/docker"

    if [ "$IN_CHINA" = true ] || [ "$CHANGE_SOURCE" = true ]; then
        url_deploy_raw=https://gitee.com/xiagw/deploy.sh/raw/main
        url_laradock_raw=https://gitee.com/xiagw/laradock/raw/in-china
    else
        url_deploy_raw=https://github.com/xiagw/deploy.sh/raw/main
        url_laradock_raw=https://github.com/xiagw/laradock/raw/main
        return
    fi
    if _is_root; then
        ## OS ubuntu:22.04 php
        if [ -f /etc/apt/sources.list ]; then
            sed -i -e 's/deb.debian.org/mirrors.ustc.edu.cn/g' \
                -e 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
        ## OS Debian
        elif [ -f /etc/apt/sources.list.d/debian.sources ]; then
            sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources
        ## OS alpine, nginx:alpine
        elif [ -f /etc/apk/repositories ]; then
            # sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories
            sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
        fi
    fi
    case $build_type in
    maven)
        local m2_dir=/root/.m2
        [ -d $m2_dir ] || mkdir -p $m2_dir
        ## 项目内自带 settings.xml docs/settings.xml
        if [ -f settings.xml ]; then
            cp -vf settings.xml $m2_dir/
        elif [ -f docs/settings.xml ]; then
            cp -vf docs/settings.xml $m2_dir/
        elif [ -f /opt/settings.xml ]; then
            mv -vf /opt/settings.xml $m2_dir/
        else
            curl -Lo $m2_dir/settings.xml $url_deploy_raw/conf/dockerfile/root/opt/settings.xml
        fi
        ;;
    composer)
        _is_root || return
        composer config -g repo.packagist composer https://mirrors.aliyun.com/composer/
        mkdir -p /var/www/.composer /.composer
        chown -R 1000:1000 /var/www/.composer /.composer /tmp/cache /tmp/config.json /tmp/auth.json
        ;;
    node)
        # npm_mirror=https://registry.npmmirror.com/
        # npm_mirror=https://mirrors.ustc.edu.cn/node/
        # npm_mirror=http://mirrors.cloud.tencent.com/npm/
        npm_mirror=https://mirrors.huaweicloud.com/repository/npm/
        yarn config set registry $npm_mirror
        npm config set registry $npm_mirror
        ;;
    python)
        pip_mirror=https://pypi.tuna.tsinghua.edu.cn/simple
        pip config set global.index-url $pip_mirror
        ;;
    esac
}

_check_run_sh() {
    if [ -f "$run_sh" ]; then
        echo "Found $run_sh, skip download."
    else
        echo "Not found $run_sh, download..."
        curl -fLo $run_sh "$url_deploy_raw"/conf/dockerfile/root$run_sh
    fi
    chmod +x $run_sh
}

_build_nginx() {
    echo "build nginx:alpine..."
    apk update
    apk upgrade
    apk add --no-cache openssl bash curl shadow
    touch /var/log/messages

    groupmod -g 1000 nginx
    usermod -u 1000 nginx
    # Set upstream conf and remove the default conf
    # echo "upstream php-upstream { server ${PHP_UPSTREAM_CONTAINER}:${PHP_UPSTREAM_PORT}; }" >/etc/nginx/php-upstream.conf
    # rm /etc/nginx/conf.d/default.conf
    if [ -f $run_sh ]; then
        sed -i 's/\r//g' $run_sh
        chmod +x $run_sh
        cp -vf $run_sh /docker-entrypoint.d/
    fi
}

_build_php() {
    echo "build php ..."
    _set_mirror shanghai
    apt-get update -yqq
    # apt-get install -yqq libjemalloc2
    $apt_opt apt-utils
    # $apt_opt libterm-readkey-perl
    $apt_opt vim curl ca-certificates
    # apt-get install -y language-pack-en-base

    ## preesed tzdata, update package index, upgrade packages and install needed software
    (
        echo "tzdata tzdata/Areas select Asia"
        echo "tzdata tzdata/Zones/Asia select Shanghai"
    ) >/tmp/preseed.cfg
    debconf-set-selections /tmp/preseed.cfg
    rm -f /etc/timezone /etc/localtime

    export DEBIAN_FRONTEND=noninteractive
    export DEBCONF_NONINTERACTIVE_SEEN=true

    $apt_opt tzdata
    $apt_opt locales

    if ! grep '^en_US.UTF-8' /etc/locale.gen; then
        echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen
    fi
    locale-gen en_US.UTF-8

    case "$PHP_VERSION" in
    8.1)
        echo "install PHP from repo of OS..."
        ;;
    *)
        echo "install PHP from ppa:ondrej/php..."
        apt-get install -yqq lsb-release gnupg2 ca-certificates apt-transport-https software-properties-common
        LC_ALL=C.UTF-8 LANG=C.UTF-8 add-apt-repository -y ppa:ondrej/php
        case "$PHP_VERSION" in
        8.*) : ;;
        *) $apt_opt php"${PHP_VERSION}"-mcrypt ;;
        esac
        ;;
    esac

    apt-get upgrade -yqq
    $apt_opt \
        php"${PHP_VERSION}" \
        php"${PHP_VERSION}"-redis \
        php"${PHP_VERSION}"-mongodb \
        php"${PHP_VERSION}"-imagick \
        php"${PHP_VERSION}"-fpm \
        php"${PHP_VERSION}"-gd \
        php"${PHP_VERSION}"-mysql \
        php"${PHP_VERSION}"-xml \
        php"${PHP_VERSION}"-xmlrpc \
        php"${PHP_VERSION}"-bcmath \
        php"${PHP_VERSION}"-gmp \
        php"${PHP_VERSION}"-zip \
        php"${PHP_VERSION}"-soap \
        php"${PHP_VERSION}"-curl \
        php"${PHP_VERSION}"-bz2 \
        php"${PHP_VERSION}"-mbstring \
        php"${PHP_VERSION}"-msgpack \
        php"${PHP_VERSION}"-sqlite3

    # php"${PHP_VERSION}"-process \
    # php"${PHP_VERSION}"-pecl-mcrypt  replace by  php"${PHP_VERSION}"-libsodium

    if [ "$PHP_VERSION" = 5.6 ]; then
        $apt_opt apache2 libapache2-mod-fcgid libapache2-mod-php"${PHP_VERSION}"
        sed -i -e '1 i ServerTokens Prod' -e '1 i ServerSignature Off' -e '1 i ServerName www.example.com' /etc/apache2/sites-available/000-default.conf
    else
        $apt_opt nginx
    fi
    # $apt_opt lsyncd openssh-client

    sed -i \
        -e '/fpm.sock/s/^/;/' \
        -e '/fpm.sock/a listen = 9000' \
        -e '/rlimit_files/a rlimit_files = 65535' \
        -e '/pm.max_children/s/5/10000/' \
        -e '/pm.start_servers/s/2/10/' \
        -e '/pm.min_spare_servers/s/1/10/' \
        -e '/pm.max_spare_servers/s/3/20/' \
        -e '/^;slowlog.*log\//s//slowlog = \/var\/log\/php/' \
        -e '/^;request_slowlog_timeout.*/s//request_slowlog_timeout = 2/' \
        /etc/php/"${PHP_VERSION}"/fpm/pool.d/www.conf
    sed -i \
        -e "/memory_limit/s/128M/1024M/" \
        -e "/post_max_size/s/8M/1024M/" \
        -e "/upload_max_filesize/s/2M/1024M/" \
        -e "/max_file_uploads/s/20/1024/" \
        -e '/disable_functions/s/$/phpinfo,/' \
        -e '/max_execution_time/s/30/60/' \
        /etc/php/"${PHP_VERSION}"/fpm/php.ini
}

_onbuild_php() {
    if command -v php && [ -n "$PHP_VERSION" ]; then
        echo "command php exists, php ver is $PHP_VERSION"
    else
        return
    fi

    if [ "$PHP_SESSION_REDIS" = true ]; then
        sed -i -e "/session.save_handler/s/files/redis/" \
            -e "/session.save_handler/a session.save_path = \"tcp://${PHP_SESSION_REDIS_SERVER}:${PHP_SESSION_REDIS_PORT}?auth=${PHP_SESSION_REDIS_PASS}&database=${PHP_SESSION_REDIS_DB}\"" \
            /etc/php/"${PHP_VERSION}"/fpm/php.ini
    fi

    ## setup nginx for ThinkPHP
    rm -f /etc/nginx/sites-enabled/default
    curl -fLo /etc/nginx/sites-enabled/default "$url_laradock_raw"/php-fpm/root/opt/nginx.conf

    _check_run_sh
}

_build_node() {
    echo "build node ..."
    if _is_root; then
        [ -d /.cache ] || mkdir /.cache
        [ -d /app ] || mkdir /app
        chown -R node:node /.cache /app
        # npm install -g rnpm@1.9.0
    else
        # npm install
        yarn install
    fi
    [ -d root ] && rm -rf root || true
}

_build_maven() {
    # --settings=settings.xml --activate-profiles=main
    # mvn -T 1C install -pl $moduleName -am --offline
    mvn --threads 1C --update-snapshots -DskipTests $MVN_DEBUG -Dmaven.compile.fork=true clean package

    mkdir /jars
    while read -r jar; do
        [ -f "$jar" ] || continue
        echo "$jar" | grep -E 'framework.*|gdp-module.*|sdk.*\.jar|.*-commom-.*\.jar|.*-dao-.*\.jar|lop-opensdk.*\.jar|core-.*\.jar' ||
            cp -vf "$jar" /jars/
    done < <(find ./target/*.jar ./*/target/*.jar ./*/*/target/*.jar 2>/dev/null)
    if [[ "${MVN_COPY_YAML:-false}" == true ]]; then
        c=0
        while read -r yml; do
            [ -f "$yml" ] || continue
            c=$((c + 1))
            cp -vf "$yml" /jars/"${c}.${yml##*/}"
        done < <(find ./*/*/*/resources/*"${MVN_PROFILE:-main}".yml ./*/*/*/resources/*"${MVN_PROFILE:-main}".yaml 2>/dev/null)
    fi
}

_build_jdk_runtime_amzn() {
    ## set ssl
    sec_file=/usr/lib/jvm/java-17-amazon-corretto/conf/security/java.security
    if [[ -f $sec_file ]]; then
        sed -i 's/SSLv3\,\ TLSv1\,\ TLSv1\.1\,//g' $sec_file
    fi

    _check_run_sh

    chown -R 1000:1000 /app
    for file in /app/*.{yml,yaml}; do
        if [ -f "$file" ]; then
            break
        else
            touch "/app/profile.${MVN_PROFILE:-main}"
        fi
    done
    # yum clean all
    rm -rf /var/cache/yum
}

_build_jdk_runtime() {
    apt-get update -yqq
    $apt_opt less apt-utils
    ## disable --no-install-recommends
    apt-get install -yqq libjemalloc2
    if [ "$INSTALL_FFMPEG" = true ]; then
        $apt_opt ffmpeg
    fi
    if [ "$INSTALL_FONTS" = true ]; then
        $apt_opt fontconfig
        fc-cache --force
        curl --referer http://cdn.flyh6.com/ -Lo - "$url_fly_cdn"/fonts-2022.tgz |
            tar -C /usr/share -zxf -
    fi
    ## set ssl
    sec_file=/usr/local/openjdk-8/jre/lib/security/java.security
    if [[ -f $sec_file ]]; then
        sed -i 's/SSLv3\,\ TLSv1\,\ TLSv1\.1\,//g' $sec_file
    fi

    _check_run_sh

    chown -R 1000:1000 /app
    for file in /app/*.{yml,yaml}; do
        if [ -f "$file" ]; then
            break
        else
            touch "/app/profile.${MVN_PROFILE:-main}"
        fi
    done
}

_build_python() {
    echo TODO...
    return 1
}

_build_mysql() {
    echo "build mysql ..."
    chown -R mysql:root /var/lib/mysql/
    chmod o-rw /var/run/mysqld

    my_cnf=/etc/mysql/conf.d/my.cnf
    if mysqld --version | grep '8\..\.'; then
        cp -f "$me_path"/my.8.cnf $my_cnf
    else
        cp -f "$me_path"/my.cnf $my_cnf
    fi
    chmod 0444 $my_cnf
    if [ "$MYSQL_SLAVE" = 'true' ]; then
        sed -i -e "/server_id/s/1/${MYSQL_SLAVE_ID:-2}/" -e "/auto_increment_offset/s/1/2/" $my_cnf
    fi
    if [ -f /etc/my.cnf ]; then
        sed -i '/skip-host-cache/d' /etc/my.cnf
    fi

    printf "[client]\npassword=%s\n" "${MYSQL_ROOT_PASSWORD}" >"$HOME"/.my.cnf
    printf "export LANG=C.UTF-8\alias l='ls -al'" >"$HOME"/.bashrc

    chmod +x /opt/*.sh
}

_build_redis() {
    echo "build redis ..."
    [ -n "${REDIS_PASSWORD}" ] && sed -i -e "s/.*requirepass foobared/requirepass ${REDIS_PASSWORD}/" /etc/redis.conf
    mkdir /run/redis
    chown redis:redis /run/redis
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
    if [ -w "$me_path" ]; then
        me_log="$me_path/${me_name}.log"
    else
        me_log="/tmp/${me_name}.log"
    fi

    run_sh=/opt/run.sh
    echo "build log file: $me_log"

    apt_opt="apt-get install -yqq --no-install-recommends"

    if command -v nginx; then
        build_type=nginx
    elif command -v composer; then
        build_type=composer
    elif command -v php && [ -n "$PHP_VERSION" ]; then
        build_type=php
    elif command -v mvn; then
        build_type=maven
    elif command -v java; then
        build_type=java
    elif command -v node; then
        build_type=node
    elif command -v python && command -v pip; then
        build_type=python
    elif command -v mysql; then
        build_type=mysql
    fi

    _set_mirror

    case "$1" in
    --onbuild)
        _onbuild_php
        return 0
        ;;
    esac

    case $build_type in
    nginx) _build_nginx ;;
    php) _build_php ;;
    composer) _build_composer ;;
    maven) _build_maven ;;
    java)
        if command -v apt-get; then
            _build_jdk_runtime
        else
            _build_jdk_runtime_amzn
        fi
        ;;
    node) _build_node ;;
    python) _build_python ;;
    mysql) _build_mysql ;;
    esac

    ## clean
    if _is_root; then
        if command -v apt-get; then
            apt-get autoremove -y
            apt-get clean all
            rm -rf /var/lib/apt/lists/*
        fi
        rm -rf /tmp/* /opt/*.{cnf,xml,log}
    else
        :
    fi
}

main "$@"
