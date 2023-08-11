#!/bin/bash

_set_mirror() {
    if [ "$1" = shanghai ]; then
        ln -snf /usr/share/zoneinfo/"${TZ:-Asia/Shanghai}" /etc/localtime
        echo "${TZ:-Asia/Shanghai}" >/etc/timezone
        return
    fi
    url_fly_cdn="http://cdn.flyh6.com/docker"

    if [ "$IN_CHINA" = true ] || [ "$CHANGE_SOURCE" = true ]; then
        url_deploy_raw=https://gitee.com/xiagw/deploy.sh/raw/main
        url_laradock_raw=https://gitee.com/xiagw/laradock/raw/in-china
    else
        url_deploy_raw=https://github.com/xiagw/deploy.sh/raw/main
        url_laradock_raw=https://github.com/xiagw/laradock/raw/main
    fi

    if [ "$IN_CHINA" = false ] && [ "${CHANGE_SOURCE}" = false ]; then
        return
    fi

    ## OS ubuntu:22.04 php
    if [ -f /etc/apt/sources.list ]; then
        sed -i -e 's/deb.debian.org/mirrors.ustc.edu.cn/g' \
            -e 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
    ## OS alpine, nginx:alpine
    elif [ -f /etc/apk/repositories ]; then
        # sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories
        sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
    fi
    ## maven
    if command -v mvn; then
        m2_dir=/root/.m2
        [ -d $m2_dir ] || mkdir -p $m2_dir
        ## 项目内自带 settings.xml docs/settings.xml
        if [ -f settings.xml ]; then
            cp -vf settings.xml $m2_dir/
        elif [ -f docs/settings.xml ]; then
            cp -vf docs/settings.xml $m2_dir/
        else
            curl -Lo $m2_dir/settings.xml $url_deploy_raw/conf/dockerfile/root/opt/settings.xml
        fi
    fi
    ## PHP composer
    if command -v composer; then
        composer config -g repo.packagist composer https://mirrors.aliyun.com/composer/
        mkdir -p /var/www/.composer /.composer
        chown -R 1000:1000 /var/www/.composer /.composer /tmp/cache /tmp/config.json /tmp/auth.json
    fi
    ## node, npm, yarn
    # npm_mirror=https://registry.npm.taobao.org/
    npm_mirror=https://registry.npmmirror.com/
    if command -v npm; then
        addgroup -g 1000 -S php
        adduser -u 1000 -D -S -G php php
        yarn config set registry $npm_mirror
        npm config set registry $npm_mirror
        su - node -c "yarn config set registry $npm_mirror; npm config set registry $npm_mirror"
    fi
    ## python pip
    if command -v pip; then
        pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
    fi
}

_build_nginx() {
    echo "build nginx alpine ..."
    apk update
    apk upgrade
    apk add --no-cache openssl bash curl shadow
    touch /var/log/messages

    groupmod -g 1000 nginx
    usermod -u 1000 nginx
    # Set upstream conf and remove the default conf
    # echo "upstream php-upstream { server ${PHP_UPSTREAM_CONTAINER}:${PHP_UPSTREAM_PORT}; }" >/etc/nginx/php-upstream.conf
    # rm /etc/nginx/conf.d/default.conf
    if [ -f /docker-entrypoint.d/run.sh ]; then
        sed -i 's/\r//g' /docker-entrypoint.d/run.sh
        chmod +x /docker-entrypoint.d/run.sh
    fi
}

_build_php() {
    echo "build php ..."
    # usermod -u 1000 www-data
    # groupmod -g 1000 www-data

    apt-get update -yqq
    $apt_opt apt-utils libjemalloc2

    ## preesed tzdata, update package index, upgrade packages and install needed software
    truncate -s0 /tmp/preseed.cfg
    echo "tzdata tzdata/Areas select Asia" >>/tmp/preseed.cfg
    echo "tzdata tzdata/Zones/Asia select Shanghai" >>/tmp/preseed.cfg
    debconf-set-selections /tmp/preseed.cfg
    rm -f /etc/timezone /etc/localtime

    $apt_opt tzdata
    $apt_opt locales

    if ! grep -q '^en_US.UTF-8' /etc/locale.gen; then
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
        add-apt-repository ppa:ondrej/php
        case "$PHP_VERSION" in
        8.*)
            :
            ;;
        *)
            $apt_opt php"${PHP_VERSION}"-mcrypt
            ;;
        esac
        ;;
    esac

    apt-get upgrade -yqq
    $apt_opt \
        vim curl ca-certificates \
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
    curl -fLo /etc/nginx/sites-enabled/default \
        "$url_laradock_raw"/php-fpm/root/opt/nginx.conf

    ## startup run.sh
    if [ -f "$run_sh" ]; then
        echo "Found $run_sh"
    else
        echo "Download $run_sh ..."
        curl -fLo $run_sh "$url_deploy_raw"/conf/dockerfile/root$run_sh
    fi
    chmod +x /opt/run.sh
}

_build_mysql() {
    echo "build mysql ..."
    chown -R mysql:root /var/lib/mysql/
    chmod o-rw /var/run/mysqld

    my_cnf=/etc/mysql/conf.d/my.cnf
    if mysqld --version | grep '5\.7'; then
        cp -f "$me_path"/my.5.7.cnf $my_cnf
    elif mysqld --version | grep '8\.0'; then
        cp -f "$me_path"/my.8.0.cnf $my_cnf
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
}

_build_node() {
    echo "build node ..."

    mkdir /.cache
    chown -R node:node /.cache /apps
    npm install -g rnpm@1.9.0
}

_build_maven() {
    # --settings=settings.xml --activate-profiles=main
    # mvn -T 1C install -pl $moduleName -am --offline
    mvn --threads 1C --update-snapshots -DskipTests $MVN_DEBUG -Dmaven.compile.fork=true clean package

    mkdir /jars
    jar_files=(
        ./target/*.jar
        ./*/target/*.jar
        ./*/*/target/*.jar
    )
    for jar in "${jar_files[@]}"; do
        [ -f "$jar" ] || continue
        echo "$jar" | grep -E 'framework.*|gdp-module.*|sdk.*\.jar|.*-commom-.*\.jar|.*-dao-.*\.jar|lop-opensdk.*\.jar|core-.*\.jar' ||
            cp -vf "$jar" /jars/
    done
    if [[ "${MVN_COPY_YAML:-false}" == true ]]; then
        yml_files=(
            ./*/*/*/resources/*"${MVN_PROFILE:-main}".yml
        )
        c=0
        for yml in "${yml_files[@]}"; do
            [ -f "$yml" ] || continue
            c=$((c + 1))
            cp -vf "$yml" /jars/"${c}.${yml##*/}"
        done
    fi
}

_build_jdk_runtime() {
    apt-get update -yqq
    $apt_opt less apt-utils
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
    ## startup run.sh
    if [ -f "$run_sh" ]; then
        echo "Found $run_sh"
    else
        echo "Download $run_sh ..."
        curl -fLo $run_sh "$url_deploy_raw"/conf/dockerfile/root$run_sh
    fi
    chmod +x /opt/run.sh

    useradd -u 1000 spring
    chown -R 1000:1000 /app
    for file in /app/*.{yml,yaml}; do
        if [ -f "$file" ]; then
            break
        else
            touch "/app/profile.${MVN_PROFILE:-main}"
        fi
    done
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

    run_sh=/opt/run.sh
    echo "build log file: $me_log"

    apt_opt="apt-get install -yqq --no-install-recommends"

    _set_mirror

    case "$1" in
    --onbuild)
        _onbuild_php
        return 0
        ;;
    esac

    if command -v nginx; then
        _build_nginx
    elif [ -n "$PHP_VERSION" ]; then
        _set_mirror shanghai
        _build_php
    elif command -v mvn && [ -n "$MVN_PROFILE" ]; then
        _build_maven
    elif command -v java && [ -n "$MVN_PROFILE" ]; then
        _build_jdk_runtime
    elif command -v node; then
        _build_node
    fi

    # apt-get autoremove -y
    if command -v apt-get; then
        apt-get clean all
        rm -rf \
            /var/lib/apt/lists/* \
            /opt/settings.xml \
            /opt/*.log
    fi
    rm -rf /tmp/*
}

main "$@"
