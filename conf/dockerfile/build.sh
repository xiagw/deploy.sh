#!/bin/bash

_set_timezone() {
    ln -snf /usr/share/zoneinfo/${TZ:-Asia/Shanghai} /etc/localtime
    echo ${TZ:-Asia/Shanghai} >/etc/timezone
}

_set_mirror() {
    if [ "$IN_CHINA" = false ] || [ "${CHANGE_SOURCE}" = false ]; then
        return
    fi

    if command -v mvn; then
        m2_dir=/root/.m2
        [ -d $m2_dir ] || mkdir -p $m2_dir
        if [ -f settings.xml ]; then
            cp -vf settings.xml $m2_dir/
        elif [ -f docs/settings.xml ]; then
            cp -vf docs/settings.xml $m2_dir/
        else
            url_settings=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/settings.xml
            curl -Lo $m2_dir/settings.xml $url_settings
        fi
    fi

    if [[ -f /etc/apt/sources.list ]]; then
        sed -i -e 's/deb.debian.org/mirrors.ustc.edu.cn/g' \
            -e 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
    fi

    if [ -f /etc/apk/repositories ]; then
        sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories
    fi
}

_build_mvn() {
    _set_mirror

    # --settings=settings.xml --activate-profiles=main
    mvn --threads 2C --update-snapshots -DskipTests -Dmaven.compile.fork=true clean package

    mkdir /jars
    find . -type f -regextype egrep -iregex '.*SNAPSHOT.*\.jar' |
        grep -Ev 'framework.*|gdp-module.*|sdk.*\.jar|.*-commom-.*\.jar|.*-dao-.*\.jar|lop-opensdk.*\.jar|core-.*\.jar' |
        xargs -t -I {} cp -vf {} /jars/
}

_build_runtime_jdk() {
    _set_timezone

    _set_mirror

    apt-get update -q
    apt-get install -y -q --no-install-recommends less

    if [ "$INSTALL_FFMPEG" = true ]; then
        apt-get install -y --no-install-recommends ffmpeg
    fi

    if [ "$INSTALL_FONTS" = true ]; then
        url_fonts=http://cdn.flyh6.com/docker/fonts-2022.tgz
        apt-get install -y -q --no-install-recommends fontconfig
        fc-cache --force
        curl --referer http://www.flyh6.com/ -Lo - $url_fonts |
            tar -C /usr/share -zxf -
    fi

    ## set ssl
    if [[ -f /usr/local/openjdk-8/jre/lib/security/java.security ]]; then
        sed -i 's/SSLv3\,\ TLSv1\,\ TLSv1\.1\,//g' /usr/local/openjdk-8/jre/lib/security/java.security
    fi

    url_run=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/run.sh
    curl -Lo /opt/run.sh $url_run
    chmod +x /opt/run.sh

    useradd -u 1000 spring

    chown -R 1000:1000 /app
    touch "/app/profile.${MVN_PROFILE}"

    # apt-get autoremove -y
    apt-get clean all
    rm -rf /var/lib/apt/lists/*
}

_build_other() {
    echo "build..."
}

main() {
    set -xe
    # set -eo pipefail
    # shopt -s nullglob
    if command -v mvn; then
        _build_mvn
    elif command -v java; then
        _build_runtime_jdk
    else
        _build_other
    fi
}

main "$@"
