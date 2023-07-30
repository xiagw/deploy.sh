FROM ubuntu:22.04

WORKDIR /runner

COPY . /runner/

RUN set -xe; \
    # touch Dockerfile composer.json package.json pom.xml requirements.txt; \
    mkdir data; \
    cp -vf conf/example-deploy.env conf/conf/deploy.env; \
    sed -i -e '/=false/s/false/true/g' data/deploy.env; \
    sed -i -e '/ENV_INSTALL_JMETER=/s/true/false/' data/deploy.env; \
    chmod +x deploy.sh; \
    deploy.sh --github-action