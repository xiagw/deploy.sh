## xiagw/deploy.sh Dockerfile
ARG MIRROR=
ARG IMAGE_NAME=ubuntu
ARG TAG=22.04

FROM ${MIRROR}${IMAGE_NAME}:${TAG}

WORKDIR /runner
# EXPOSE 8080
# VOLUME ["/runner/data"]
COPY . /runner/

RUN set -xe; \
    # touch Dockerfile composer.json package.json pom.xml requirements.txt; \
    [ -d data ] || mkdir data; \
    cp -vf conf/templates/deploy.env data/deploy.env; \
    DEBUG_ON=true GITHUB_ACTIONS=true bash -x ./deploy.sh -d