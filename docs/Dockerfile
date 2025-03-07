## arch: x86_64
ARG IMAGE_NAME=ubuntu:22.04
## arch: arm64
# ARG IMAGE_NAME=arm64v8/ubuntu

FROM ${IMAGE_NAME}

WORKDIR /runner

COPY . /runner/

RUN set -xe; \
    # touch Dockerfile composer.json package.json pom.xml requirements.txt; \
    [ -d data ] || mkdir data; \
    cp -vf conf/example-deploy.env data/deploy.env; \
    sed -i -e '/=false/s/false/true/g' data/deploy.env; \
    sed -i -e '/ENV_INSTALL_JMETER=/s/true/false/' \
    -e '/ENV_INSTALL_DOCKER=/s/true/false/' \
    -e '/ENV_INSTALL_PODMAN=/s/false/true/' \
    -e '/ENV_IN_CHINA=/s/true/false/' data/deploy.env; \
    chmod +x deploy.sh; \
    ./deploy.sh --github-action