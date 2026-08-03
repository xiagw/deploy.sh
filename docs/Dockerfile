## xiagw/deploy.sh Dockerfile
ARG MIRROR=
ARG BUILD_IMAGE=ubuntu
ARG BUILD_TAG=24.04
ARG GITHUB_ACTIONS=true

FROM ${MIRROR}${BUILD_IMAGE}:${BUILD_TAG}
ARG GITHUB_ACTIONS

WORKDIR /runner
# EXPOSE 8080
# VOLUME ["/runner/data"]
COPY . /runner/

RUN bash ./deploy.sh -d