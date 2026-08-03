## xiagw/deploy.sh Dockerfile
ARG MIRROR=
ARG BUILD_IMAGE=ubuntu
ARG BUILD_TAG=24.04

FROM ${MIRROR}${BUILD_IMAGE}:${BUILD_TAG}
ARG GITHUB_ACTIONS=true

WORKDIR /runner
# EXPOSE 8080
# VOLUME ["/runner/data"]
COPY . /runner/

RUN bash ./deploy.sh -d