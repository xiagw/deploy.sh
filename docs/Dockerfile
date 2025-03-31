## xiagw/deploy.sh Dockerfile
ARG MIRROR=
ARG IMAGE_NAME=ubuntu
ARG TAG=22.04

FROM ${MIRROR}${IMAGE_NAME}:{TAG}

WORKDIR /runner
# EXPOSE 8080
# VOLUME ["/runner/data"]
COPY . /runner/

RUN set -xe; \
    # touch Dockerfile composer.json package.json pom.xml requirements.txt; \
    [ -d data ] || mkdir data; \
    cp -vf conf/example-deploy.env data/deploy.env; \
    sed -i -e '/^ENV_INSTALL.*=false/s/false/true/g' data/deploy.env; \
    sed -i -e '/ENV_INSTALL_JMETER=/s/true/false/' -e '/ENV_INSTALL_DOCKER=/s/true/false/' data/deploy.env; \
    chmod +x deploy.sh; \
    bash -x ./deploy.sh -d --github-action