#!/bin/bash

_is_china() {
    ${IN_CHINA:-false} || ${CHANGE_SOURCE:-false}
}

_set_mirror() {
    case "$1" in
    shanghai)
        export TZ=Asia/Shanghai
        ln -snf /usr/share/zoneinfo/"${TZ}" /etc/localtime
        echo "${TZ}" >/etc/timezone
        return
        ;;
    esac

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
        # shellcheck disable=SC2034
        url_laradock_raw=https://github.com/xiagw/laradock/raw/main
        return
    fi

    if [ "$(id -u)" -eq 0 ]; then
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
        local dotm2=/root/.m2
        [ -d $dotm2 ] || mkdir -p $dotm2
        # Generate Maven settings.xml
        cat >"$dotm2/settings.xml" <<'EOF'
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0
                              https://maven.apache.org/xsd/settings-1.2.0.xsd">

    <mirrors>
        <mirror>
            <id>flyh6</id>
            <mirrorOf>external:*,!custom-group</mirrorOf>
            <name>flyh6</name>
            <url>http://m.flyh6.com/repository/flymaven/</url>
        </mirror>
        <mirror>
            <id>huawei</id>
            <mirrorOf>external:*,!custom-group,!flyh6</mirrorOf>
            <name>huawei</name>
            <url>https://repo.huaweicloud.com/repository/maven/</url>
        </mirror>
        <mirror>
            <id>aliyun</id>
            <mirrorOf>external:*,!custom-group,!flyh6,!huawei</mirrorOf>
            <name>aliyun</name>
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
        [ "$(id -u)" -eq 0 ] || return
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
        if [ ! -f "$i" ]; then
            ## Dockerfile 中 mount bind /src 内sh
            local runsh="/src/root$i"
            if [ -f "$runsh" ]; then
                install -m 0755 "$runsh" "$i"
            else
                curl -fLo "$i" "$url_deploy_raw/conf/dockerfile/root$i"
            fi
        fi
        chmod +x "$i"
    done

    initsh="/src/root/opt/init.sh"
    if [ -f "$initsh" ]; then
        install -m 0755 "$initsh" "/opt/init.sh"
    else
        echo "Not found $initsh, skip copy."
    fi
}

_build_nginx() {
    echo "Building nginx:alpine..."
    $cmd_pkg update && $cmd_pkg upgrade
    # 安装基础包
    # 如果只需要运行时依赖
    if [ "${1:-build}" = runtime ]; then
        $cmd_pkg_opt pcre geoip openssl bash curl shadow
        touch /var/log/messages
        # 设置用户权限
        groupmod -g 1000 nginx
        usermod -u 1000 -g 1000 nginx
        return 0
    fi

    # 安装编译依赖
    $cmd_pkg_opt \
        gcc \
        libc-dev \
        make \
        openssl \
        openssl-dev \
        pcre-dev \
        zlib-dev \
        linux-headers \
        wget \
        gnupg \
        libxslt-dev \
        gd-dev \
        geoip-dev \
        nginx

    # 创建构建目录
    mkdir -p /build
    cd /build || exit 1

    # 获取当前nginx版本号
    NGINX_VERSION=$(nginx -v 2>&1 | sed 's/.*\///;s/ .*//')
    if [ -z "$NGINX_VERSION" ]; then
        NGINX_VERSION="1.26.3" # 设置默认稳定版本
    fi

    # 下载并解压nginx源码
    if ! wget -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"; then
        echo "Failed to download nginx source" >&2
        return 1
    fi

    tar -xzf "nginx-${NGINX_VERSION}.tar.gz"
    rm "nginx-${NGINX_VERSION}.tar.gz"

    # 编译安装nginx
    cd "nginx-${NGINX_VERSION}" || exit 1
    CONFIGURE_SCRIPT="configure_nginx.sh"
    echo "./configure \\" >"$CONFIGURE_SCRIPT"
    nginx -V 2>&1 | grep 'configure arguments:' | sed 's/configure arguments: //' | sed 's/$/ --with-http_geoip_module/' >>"$CONFIGURE_SCRIPT"
    sh "$CONFIGURE_SCRIPT"
    rm -f "$CONFIGURE_SCRIPT"

    make
    make install

    # 验证GeoIP模块安装
    if /usr/sbin/nginx -V 2>&1 | grep -q 'with-http_geoip_module'; then
        echo "GeoIP module successfully installed."
    fi
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

    _is_china && sed -i -e "s/ppa.launchpadcontent.net/launchpad.proxy.ustclug.org/" /etc/apt/sources.list.d/ondrej-ubuntu-php-jammy.list

    $cmd_pkg update -yqq

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

_build_node() {
    echo "Building node environment..."

    # Update and install packages
    $cmd_pkg update -yqq
    $cmd_pkg_opt less vim curl ca-certificates

    # Create necessary directories
    mkdir -p /.cache /app
    chown -R node:node /.cache /app

    # Update npm and install cnpm if in China
    node_ver=$(node --version | sed -E 's/^[^0-9]*([0-9]+).*/\1/')
    if [ "$node_ver" -le 18 ]; then
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
        if command -v runuser >/dev/null 2>&1; then
            runuser -u node -- sh -c "cd /app && $(_is_china && echo 'cnpm' || echo 'npm') install"
        else
            su node -c "cd /app && $(_is_china && echo 'cnpm' || echo 'npm') install"
        fi
    else
        echo "Error: /app/package.json not found" >&2
        return 1
    fi
}

_build_maven() {
    # Set up Maven options with standard parameters
    mvn_opts="mvn -T 1C --batch-mode --update-snapshots -DskipTests -Dmaven.compile.fork=true clean package"
    [ "$MVN_DEBUG" = off ] && mvn_opts+=" --quiet"
    [ -f /root/.m2/settings.xml ] && mvn_opts+=" --settings=/root/.m2/settings.xml"

    # Run Maven build
    $mvn_opts -DskipTests -Dmaven.compile.fork=true clean package

    # Copy artifacts to /jars directory
    mkdir -p /jars
    find . -type f -path "*/target/*.jar" -not -iname '*-sources.jar' \
        -not -iname '*-javadoc.jar' -not -iname '*-tests.jar' \
        -not -iname '*-original.jar' -exec cp -v {} /jars/ \;

    # Copy config files if needed
    [ -f /src/.jvm.options ] && cp -v /src/.jvm.options /jars/

    local i=0
    while IFS= read -r file; do
        ((++i))
        # Get only the first directory level using awk, handling all path cases
        first_dir=$(echo "$file" | awk -F/ '{for(i=1;i<=NF;i++) if($i!="." && $i!="") {print $i; exit}}')
        # Copy file with first directory as prefix
        cp -v "$file" "/jars/${first_dir}_$(basename "$file")"
    done < <(
        find . -type f -path "*/src/*/resources/*" \( -iname "*${MVN_PROFILE:-main}*.yml" -o -iname "*${MVN_PROFILE:-main}*.yaml" \)
    )
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
    [ -f /src/.jvm.options ] && cp -avf /src/.jvm.options /app/
    command -v su || command -v runuser || $cmd_pkg install -y util-linux
    command -v useradd || $cmd_pkg install -y shadow-utils

    # Create spring user if it doesn't exist
    id spring || useradd -u 1000 -s /bin/bash -m spring

    # Create profile file if no yml/yaml files exist
    if ! find /app -maxdepth 2 -type f \( -iname "*.yml" -o -iname "*.yaml" \) | grep -q .; then
        if [ "${MVN_PROFILE}" != base ]; then
            touch "/app/profile.${MVN_PROFILE:-main}"
        fi
    fi

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
    curl -fL "https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-$JMETER_VERSION.tgz" | tar -C /opt/ -xz
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

    my_ver=$(mysqld --version | awk '{print $3}' | cut -d. -f1)
    if [ "$my_ver" -lt 8 ]; then
        my_cnf=/etc/my.cnf
    else
        my_cnf=/etc/mysql/conf.d/my.cnf
    fi

    # Generate base configuration
    cat >$my_cnf <<'EOF'
[mysqld]
host_cache_size=0
initialize-insecure=0
explicit_defaults_for_timestamp
tls_version=TLSv1.2,TLSv1.3
character-set-server=utf8mb4
# lower_case_table_names = 1
myisam_recover_options = FORCE,BACKUP
max_allowed_packet = 128M
max_connect_errors = 1000000
sync_binlog = 1
log_bin = log-bin
log_bin_index = log-bin
skip-name-resolve
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
EOF

    # Add version-specific configurations
    if [ "$my_ver" -lt 8 ]; then
        # MySQL 5.7 specific configurations
        cat >>$my_cnf <<'EOF'
sql-mode="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER"
default-authentication-plugin=mysql_native_password
character-set-client-handshake = FALSE
binlog_format = ROW
EOF
    else
        # MySQL 8.0 specific configurations
        cat >>$my_cnf <<'EOF'
sql-mode="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO"
EOF
    fi

    case "$MYSQL_REPLICATION" in
    single | master2slave)
        cat >>$my_cnf <<'EOF'
server_id = 1
auto_increment_offset = 1
auto_increment_increment = 1
EOF
        ;;
    master1)
        cat >>$my_cnf <<'EOF'
######## M2M replication (master to master, source to source)
server_id = 1
## 主键奇数列
auto_increment_offset = 1
## 递增步长 2
auto_increment_increment = 2
EOF
        ;;
    master2)
        cat >>$my_cnf <<'EOF'
######## M2M replication (master to master, source to source)
server_id = 2
## 主键偶数列
auto_increment_offset = 2
## 递增步长 2
auto_increment_increment = 2
EOF
        ;;
    esac

    chmod 0644 $my_cnf

    if [ -f /etc/my.cnf ]; then
        sed -i '/skip-host-cache/d' /etc/my.cnf
    fi

    cat >>/root/.bashrc <<'EOF'
export LANG=C.UTF-8
echo "[client]" >/root/.my.cnf
echo "password=${MYSQL_ROOT_PASSWORD}" >>/root/.my.cnf
chmod 600 /root/.my.cnf
EOF

    ## mysql backup script
    if [ -f /src/root/opt/mbk.sh ]; then
        install -m 0755 /src/root/opt/mbk.sh /opt/mbk.sh
    else
        mysql_bak="$url_deploy_raw/conf/dockerfile/root/opt/mbk.sh"
        curl -fLo /opt/mbk.sh "$mysql_bak"
    fi
    chmod +x /opt/mbk.sh
    if [ -f /usr/local/bin/docker-entrypoint.sh ]; then
        sed -i '/if .* _is_sourced.* then/i (exec /opt/mbk.sh) &' /usr/local/bin/docker-entrypoint.sh
    elif [ -f /entrypoint.sh ]; then
        sed -i '/echo ".Entrypoint. MySQL Docker Image/i (exec /opt/mbk.sh) &' /entrypoint.sh
    else
        echo "not found entrypoint file"
    fi
}

_build_redis() {
    echo "build redis ..."
    if [ -f /etc/redis.conf ] && [ -n "${REDIS_PASSWORD}" ]; then
        sed -i -e "s/.*requirepass foobared/requirepass ${REDIS_PASSWORD}/" /etc/redis.conf
    fi

    cat >>/root/.bashrc <<'EOF'
export REDISPASS_AUTH=${REDIS_PASSWORD}
EOF
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

    # 单独处理 PHP_VERSION
    if [ -n "$PHP_VERSION" ]; then
        _build_php
        return
    fi

    case "$(
        command -v nginx ||
            command -v composer ||
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
    */nginx) _build_nginx "$@" ;;
    */composer) _build_composer ;;
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

    ## clean
    if [ "$(id -u)" -eq 0 ]; then
        rm -rf /tmp/* /opt/*.{cnf,xml,log}
    fi

    for script in /opt/*.sh; do
        [ -f "$script" ] || continue
        chmod +x "$script"
    done
}

main "$@"
