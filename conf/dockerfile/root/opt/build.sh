#!/bin/bash

_is_root() {
    [ "$(id -u)" -eq 0 ]
}

_is_china() {
    ${IN_CHINA:-false} || ${CHANGE_SOURCE:-false}
}

_set_mirror() {
    if [ "$1" = shanghai ]; then
        export TZ=Asia/Shanghai
        ln -snf /usr/share/zoneinfo/"${TZ}" /etc/localtime
        echo "${TZ}" >/etc/timezone
        return
    fi

    url_fly_cdn="http://oss.flyh6.com/d"

    case "$(command -v apt-get || command -v apt || command -v microdnf || command -v dnf || command -v yum || command -v apk)" in
    */apt-get | */apt) cmd_pkg=apt-get && cmd_pkg_opt="$cmd_pkg install -yqq --no-install-recommends" && update_cache=true ;;
    */microdnf) cmd_pkg=microdnf ;;
    */dnf) cmd_pkg=dnf ;;
    */yum) cmd_pkg=yum && cmd_pkg_opt="$cmd_pkg install -y --setopt=tsflags=nodocs" ;;
    */apk) cmd_pkg=apk && cmd_pkg_opt="$cmd_pkg add --no-cache" ;;
    esac

    if _is_china; then
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
            sed -i -e 's/deb.debian.org/mirrors.ustc.edu.cn/g' -e 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
        ## OS Debian
        elif [ -f /etc/apt/sources.list.d/debian.sources ]; then
            sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources
        ## OS alpine, nginx:alpine
        elif [ -f /etc/apk/repositories ]; then
            # sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories
            sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
        fi
    fi

    case "$(command -v mvn || command -v composer || command -v node || command -v python || command -v python3)" in
    */mvn)
        local m2_dir=/root/.m2
        [ -d $m2_dir ] || mkdir -p $m2_dir
        # Generate Maven settings.xml
        cat > "$m2_dir/settings.xml" << 'EOF'
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0
                              https://maven.apache.org/xsd/settings-1.2.0.xsd">

    <localRepository>/var/maven/.m2</localRepository>

    <mirrors>
        <mirror>
            <id>mirror-all</id>
            <mirrorOf>external:*,!custom-group</mirrorOf>
            <name>mirror-all</name>
            <url>http://mirror.flyh6.com/repository/maven2proxy/</url>
        </mirror>
        <mirror>
            <id>mirror-all-2</id>
            <mirrorOf>external:*,!custom-group,!mirror-all</mirrorOf>
            <name>mirror-all-2</name>
            <url>https://repo.huaweicloud.com/repository/maven/</url>
        </mirror>
        <mirror>
            <id>mirror-all-3</id>
            <mirrorOf>external:*,!custom-group,!mirror-all,!mirror-all-2</mirrorOf>
            <name>mirror-all-3</name>
            <url>https://maven.aliyun.com/repository/public</url>
        </mirror>
    </mirrors>

    <profiles>
        <profile>
            <id>default</id>
            <repositories>
                <repository>
                    <id>central</id>
                    <url>https://repo.maven.apache.org/maven2</url>
                    <releases>
                        <enabled>true</enabled>
                    </releases>
                    <snapshots>
                        <enabled>false</enabled>
                    </snapshots>
                </repository>
            </repositories>
        </profile>
    </profiles>

    <activeProfiles>
        <activeProfile>default</activeProfile>
    </activeProfiles>

</settings>
EOF
        ;;
    */composer)
        _is_root || return
        composer config -g repo.packagist composer https://mirrors.aliyun.com/composer/
        mkdir -p /var/www/.composer /.composer
        chown -R 1000:1000 /var/www/.composer /.composer /tmp/cache /tmp/config.json /tmp/auth.json
        ;;
    */node)
        # npm_mirror=https://mirrors.ustc.edu.cn/node/
        # npm_mirror=http://mirrors.cloud.tencent.com/npm/
        # npm_mirror=https://mirrors.huaweicloud.com/repository/npm/
        # http://npm.taobao.org => http://npmmirror.com
        # http://registry.npm.taobao.org => http://registry.npmmirror.com
        npm_mirror=https://registry.npmmirror.com/
        yarn config set registry $npm_mirror
        npm config set registry $npm_mirror
        ;;
    */python | */python3)
        command -v java && return
        command -v mysqld && return
        pip_mirror=https://pypi.tuna.tsinghua.edu.cn/simple
        command -v python3 && python3 -m pip config set global.index-url $pip_mirror
        command -v python && python -m pip config set global.index-url $pip_mirror
        ;;
    esac
}

_check_run_sh() {
    for i in /opt/run.sh /opt/run0.sh; do
        if [ -f "$i" ]; then
            echo "Found $i, skip download."
        elif [ -f "/src/root$i" ]; then
            ## Dockerfile 中 mount bind /src 内sh
            install -m 0755 "/src/root$i" "$i"
        else
            echo "Not found $i, download..."
            curl -fLo "$i" "$url_deploy_raw/conf/dockerfile/root$i"
        fi
        chmod +x "$i"
    done

    if [ -f "/src/root/opt/init.sh" ]; then
        install -m 0755 "/src/root/opt/init.sh" "/opt/init.sh"
    else
        echo "Not found /src/root/opt/init.sh, skip copy."
    fi
}

_build_nginx() {
    echo "Building nginx:alpine..."
    $cmd_pkg update && $cmd_pkg upgrade
    $cmd_pkg_opt openssl bash curl shadow

    touch /var/log/messages

    groupmod -g 1000 nginx
    usermod -u 1000 -g 1000 nginx
}

_build_php() {
    echo "Building PHP environment..."
    _set_mirror shanghai

    # Update package cache if needed
    ${update_cache:-false} && $cmd_pkg update -yqq

    # Install essential packages
    $cmd_pkg_opt apt-utils
    $cmd_pkg_opt apt-utils vim curl ca-certificates

    # Configure timezone
    echo "tzdata tzdata/Areas select Asia" >/tmp/preseed.cfg
    echo "tzdata tzdata/Zones/Asia select Shanghai" >>/tmp/preseed.cfg
    debconf-set-selections /tmp/preseed.cfg
    rm -f /etc/timezone /etc/localtime

    # Set environment variables for non-interactive installation
    export DEBIAN_FRONTEND=noninteractive
    export DEBCONF_NONINTERACTIVE_SEEN=true

    # Install and configure locales
    $cmd_pkg_opt tzdata locales
    if ! grep '^en_US.UTF-8' /etc/locale.gen; then
        echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen
    fi
    locale-gen en_US.UTF-8

    # Add PHP repository and install PHP
    echo "Installing PHP ${PHP_VERSION} from ppa:ondrej/php..."
    $cmd_pkg_opt lsb-release gnupg2 ca-certificates apt-transport-https software-properties-common
    LC_ALL=C.UTF-8 LANG=C.UTF-8 add-apt-repository -y ppa:ondrej/php

    # Install PHP-specific packages based on version
    case "$PHP_VERSION" in
    8.3) $cmd_pkg_opt php"${PHP_VERSION}"-common ;;
    8.*) : ;;
    *) $cmd_pkg_opt php"${PHP_VERSION}"-mcrypt ;;
    esac

    # Upgrade and install PHP packages
    $cmd_pkg upgrade -yqq
    $cmd_pkg_opt libpq-dev php"${PHP_VERSION}" php"${PHP_VERSION}"-{bcmath,bz2,curl,fpm,gd,gmp,imagick,intl,mbstring,mongodb,msgpack,mysql,redis,soap,sqlite3,xml,xmlrpc,zip}

    # Install and configure web server
    case "$PHP_VERSION" in
    5.6)
        $cmd_pkg_opt apache2 libapache2-mod-fcgid libapache2-mod-php"${PHP_VERSION}"
        sed -i '1i ServerTokens Prod\nServerSignature Off\nServerName www.example.com' /etc/apache2/sites-available/000-default.conf
        ;;
    *)
        $cmd_pkg_opt nginx
        ;;
    esac

    # apt update && apt install -y libpq-dev # php"${PHP_VERSION}"-dev
    # pecl channel-update pecl.php.net
    # pecl install -D 'enable-sockets="no" enable-openssl="no" enable-http2="no" enable-mysqlnd="no" enable-swoole-json="no" enable-swoole-curl="no" enable-cares="no"' swoole-4.8.13
    # pecl install -D 'enable-sockets="no" enable-openssl="no" enable-http2="no" enable-mysqlnd="no" enable-swoole-json="no" enable-swoole-curl="no" enable-cares="no"' swoole-5.1.6
    # echo "extension=swoole.so" > /etc/php/"${PHP_VERSION}"/mods-available/swoole.ini
    # phpenmod swoole

    # Configure PHP-FPM
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

    # Configure PHP
    sed -i \
        -e "/memory_limit/s/128M/1024M/" \
        -e "/post_max_size/s/8M/1024M/" \
        -e "/upload_max_filesize/s/2M/1024M/" \
        -e "/max_file_uploads/s/20/1024/" \
        -e '/disable_functions/s/$/phpinfo,/' \
        -e '/max_execution_time/s/30/60/' \
        /etc/php/"${PHP_VERSION}"/fpm/php.ini

    _check_run_sh
}

_onbuild_php() {
    # Check if PHP is installed and PHP_VERSION is set
    if ! command -v php >/dev/null || [ -z "$PHP_VERSION" ]; then
        return
    fi

    php -v

    # Configure Redis session handling if enabled
    if [ "$PHP_SESSION_REDIS" = true ]; then
        sed -i \
            -e "/session.save_handler/s/files/redis/" \
            -e "/session.save_handler/a session.save_path = \"tcp://${PHP_SESSION_REDIS_SERVER}:${PHP_SESSION_REDIS_PORT}?auth=${PHP_SESSION_REDIS_PASS}&database=${PHP_SESSION_REDIS_DB}\"" \
            /etc/php/"${PHP_VERSION}"/fpm/php.ini
    fi

    # Setup nginx for ThinkPHP
    curl -fLo /etc/nginx/sites-enabled/default "${url_laradock_raw}/php-fpm/root/opt/nginx.conf"

    _check_run_sh
}

_build_node() {
    echo "Building node environment..."

    # Update and install packages
    $cmd_pkg update -yqq
    $cmd_pkg_opt less vim curl ca-certificates

    # Create necessary directories
    mkdir -p /.cache /app
    chown -R node:node /.cache /app

    # Update npm and install cnpm if in China
    if node -v | grep -E 'v1[0-9]\.'; then
      npm install -g npm@10.8
    else
      npm install -g npm
    fi
    _is_china && npm install -g cnpm

    _check_run_sh

    # Copy package.json if it exists in /src
    [ -f /src/package.json ] && cp -avf /src/package.json /app/

    # Install dependencies if package.json exists
    if [ -f /app/package.json ]; then
        su node -c "cd /app && $(_is_china && echo 'cnpm' || echo 'npm') install"
    else
        echo "Error: /app/package.json not found" >&2
        return 1
    fi
}

_build_maven() {
    # Set up Maven options
    mvn_opt="mvn --threads 1C --update-snapshots --define skipTests --define maven.compile.fork=true --define user.home=/var/maven"
    [ "$MVN_DEBUG" = off ] && mvn_opt+=" --quiet"
    [ -f /root/.m2/settings.xml ] && mvn_opt+=" --settings=/root/.m2/settings.xml"

    # Run Maven clean and package
    $mvn_opt clean package

    # Set up jars directory
    jars_dir=/jars
    mkdir -p $jars_dir

    # Copy relevant JAR files
    find ./target/*.jar ./*/target/*.jar ./*/*/target/*.jar 2>/dev/null | while read -r jar; do
        [ -f "$jar" ] || continue
        case "$jar" in
        framework* | gdp-module* | sdk*.jar | *-commom-*.jar | *-dao-*.jar | lop-opensdk*.jar | core-*.jar) continue ;;
        *) cp -vf "$jar" $jars_dir/ ;;
        esac
    done

    # Copy Java options file if it exists
    [ -f /src/.java_opts ] && cp -avf /src/.java_opts $jars_dir/

    # Copy YAML files if MVN_COPY_YAML is true
    if [[ "${MVN_COPY_YAML:-false}" == true ]]; then
        c=0
        find ./*/*/*/*"${MVN_PROFILE:-main}".{yml,yaml} 2>/dev/null | while read -r yml; do
            [ -f "$yml" ] || continue
            ((++c))
            cp -vf "$yml" $jars_dir/"${c}.${yml##*/}"
        done
    fi
}

_build_jdk_runtime() {
    if ${INSTALL_JEMALLOC:-false}; then
        if ${update_cache:-false}; then
            $cmd_pkg update -yqq
            # $cmd_pkg less apt-utils
            $cmd_pkg install -yqq libjemalloc2
        else
            $cmd_pkg install -y memkind
        fi
    fi
    if ${INSTALL_FFMPEG:-false}; then
        ${update_cache:-false} && $cmd_pkg update -yqq
        if command -v apt-get; then
            $cmd_pkg_opt ffmpeg
        elif command -v yum; then
            yum install -y tar xz
            mkdir /ffmpeg-release-amd64-static
            curl -L https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz | tar -xJ --strip-components=1 -C /ffmpeg-release-amd64-static
            ln -sf /ffmpeg-release-amd64-static/ffmpeg /usr/local/bin/ffmpeg
        fi
    fi
    if ${INSTALL_LIBREOFFICE:-false}; then
        ${update_cache:-false} && $cmd_pkg update -yqq
        $cmd_pkg_opt libreoffice
    fi
    if ${INSTALL_REDIS:-false}; then
        ${update_cache:-false} && $cmd_pkg update -yqq
        $cmd_pkg_opt redis-server
    fi
    if ${INSTALL_FONTS:-false}; then
        ${update_cache:-false} && $cmd_pkg update -yqq
        $cmd_pkg_opt fontconfig
        curl --referer "$url_fly_cdn" -Lo /tmp/fonts.zip "$url_fly_cdn"/fonts.zip
        cd /usr/share/fonts && unzip -o /tmp/fonts.zip
        fc-cache -fv
    fi

    # Set SSL configuration
    for file in /usr/lib/jvm/java-17-amazon-corretto/conf/security/java.security \
        /usr/lib/jvm/java-1.8.0-amazon-corretto/jre/lib/security/java.security \
        /usr/local/openjdk-8/jre/lib/security/java.security; do
        [[ -f $file ]] && sed -i 's/SSLv3\,\ TLSv1\,\ TLSv1\.1\,//g' "$file"
    done

    _check_run_sh

    # Set up app directory and permissions
    mkdir -p /app
    chown -R 1000:1000 /app
    [ -f /src/.java_opts ] && cp -avf /src/.java_opts /app/
    command -v su || $cmd_pkg install -y util-linux
    command -v useradd || $cmd_pkg install -y shadow-utils

    # Create spring user if it doesn't exist
    id spring || useradd -u 1000 -s /bin/bash -m spring

    # Create profile file if no yml/yaml files exist
    for file in /app/*.{yml,yaml}; do
        if [ -f "$file" ]; then
            break
        else
            touch "/app/profile.${MVN_PROFILE:-main}"
        fi
    done

    # Clean up if yum is available
    if command -v yum; then
        yum clean all
        rm -rf /var/lib/yum/yumdb /var/lib/yum/history
    fi
}

_build_jmeter() {
    if [ "$CHANGE_SOURCE" = true ] || [ "$IN_CHINA" = true ]; then
        sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
    fi
    apt-get update
    apt-get install -yqq --no-install-recommends curl ca-certificates vim iputils-ping unzip
    curl -fL "https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-$JMETER_VERSION.tgz" | tar -C /opt/ -xz
    rm -rf /tmp/*
}

_build_python() {
    echo TODO...
    return
}

_build_mysql() {
    echo "build mysql ..."
    chown -R mysql:root /var/lib/mysql/
    chmod o-rw /var/run/mysqld

    my_cnf=/etc/mysql/conf.d/my.cnf
    # Generate MySQL configuration based on version
    cat > $my_cnf << 'EOF'
# The MySQL  Client configuration file.
#
# For explanations see
# http://dev.mysql.com/doc/mysql/en/server-system-variables.html

[mysqld]
host_cache_size=0
initialize-insecure=FALSE
explicit_defaults_for_timestamp
tls_version=TLSv1.2,TLSv1.3
EOF

    # Get MySQL version and compare
    mysql_version=$(mysqld --version | awk '{print $3}' | cut -d. -f1)
    if [ "$mysql_version" -gt 8 ]; then
        cat >> $my_cnf << 'EOF'
sql-mode="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO"
character-set-server=utf8mb4
# default-authentication-plugin=mysql_native_password
EOF
    else
        cat >> $my_cnf << 'EOF'
sql-mode="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER"
character-set-server=utf8mb4
default-authentication-plugin=mysql_native_password
EOF
    fi

    cat >> $my_cnf << 'EOF'

character-set-client-handshake = FALSE
# lower_case_table_names = 1
myisam_recover_options = FORCE,BACKUP
max_allowed_packet = 128M
max_connect_errors = 1000000
sync_binlog = 1
log_bin = log-bin
log_bin_index = log-bin
EOF

    if mysqld --version | grep '8\..\.'; then
        echo '# binlog_format = ROW' >> $my_cnf
    else
        echo 'binlog_format = ROW' >> $my_cnf
    fi

    cat >> $my_cnf << 'EOF'
skip-name-resolve

######## M2M replication (master)
server_id = 1
## 主键奇数列
auto_increment_offset = 1
## 递增步长 2
# auto_increment_increment = 2
auto_increment_increment = 1

######## M2M replication (slave)
# server_id = 2
## 主键偶数列
# auto_increment_offset = 2
## 递增步长 2
# auto_increment_increment = 2

read_only = 0
# binlog_do_db = default
binlog_ignore_db = mysql
binlog_ignore_db = test
binlog_ignore_db = information_schema
replicate_ignore_db = mysql
replicate_ignore_db = test
replicate_ignore_db = information_schema
replicate_ignore_db = easyschedule
replicate_wild_ignore_table = easyschedule.%
# log_replica_updates

#############################################
# query_cache_type = 0
# query_cache_size = 0
# innodb_log_files_in_group = 2
# innodb_log_file_size = 2560M
# tmp_table_size = 32M
# max_heap_table_size = 64M
max_connections = 2048
# thread_cache_size = 50
open_files_limit = 65535
# table_definition_cache = 2048
# table_open_cache = 2048
# innodb_flush_method = O_DIRECT
# innodb_redo_log_capacity = 2560M
# innodb_flush_log_at_trx_commit = 1
# innodb_file_per_table = 1
# innodb_buffer_pool_size = 1G
# log_queries_not_using_indexes = 0
slow_query_log = 1
long_query_time = 1
# innodb_stats_on_metadata = 0

[mysql]
default-character-set=utf8mb4

[client]
default-character-set=utf8mb4
EOF

    chmod 0444 $my_cnf
    if [ "$MYSQL_SLAVE" = 'true' ]; then
        sed -i -e "/server_id/s/1/${MYSQL_SLAVE_ID:-2}/" -e "/auto_increment_offset/s/1/2/" $my_cnf
    fi
    if [ -f /etc/my.cnf ]; then
        sed -i '/skip-host-cache/d' /etc/my.cnf
    fi

    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        printf "[client]\npassword=%s\n" "${MYSQL_ROOT_PASSWORD}" >"$HOME"/.my.cnf
        printf "export LANG=C.UTF-8\alias l='ls -al'" >"$HOME"/.bashrc
    fi
    if ls -A /opt/*.sh; then
        chmod +x /opt/*.sh
    fi
}

_build_redis() {
    echo "build redis ..."
    if [ -f /etc/redis.conf ] && [ -n "${REDIS_PASSWORD}" ]; then
        sed -i -e "s/.*requirepass foobared/requirepass ${REDIS_PASSWORD}/" /etc/redis.conf
    fi
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

    echo "build log file: $me_log"

    _set_mirror

    case "$1" in
    --onbuild | onbuild)
        _onbuild_php
        return 0
        ;;
    esac

    case "$(
        command -v nginx ||
            command -v composer ||
            ([ -n "$PHP_VERSION" ] && echo /usr/bin/php) ||
            command -v mvn ||
            command -v jmeter ||
            command -v java ||
            command -v node ||
            command -v mysql ||
            command -v python ||
            command -v redis ||
            command -v catalina.sh ||
            command -v memcached ||
            command -v rabbitmq
    )" in
    */nginx) _build_nginx ;;
    */composer) _build_composer ;;
    */php) _build_php ;;
    */mvn) _build_maven ;;
    */jmeter) _build_jmeter ;;
    */java) _build_jdk_runtime ;;
    */node) _build_node ;;
    */mysql) _build_mysql ;;
    */python) command -v mysqld >/dev/null || _build_python ;;
    */redis) _build_redis ;;
    */catalina.sh) _build_tomcat ;;
    */memcached) _build_memcached ;;
    */rabbitmq) _build_rabbitmq ;;
    *) echo "No specific build environment detected." ;;
    esac

    ## copy run.sh run0.sh

    ## clean
    if _is_root; then
        rm -rf /tmp/* /opt/*.{cnf,xml,log}
    else
        :
    fi
}

main "$@"
