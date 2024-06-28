## arch: x86_64
ARG IMAGE_NAME=ubuntu:22.04
## arch: arm64
# ARG IMAGE_NAME=arm64v8/ubuntu

FROM gcr.io/kaniko-project/executor:debug as builder

FROM ${IMAGE_NAME}
WORKDIR /runner
COPY ./ /runner/
COPY --from=builder /kaniko/ /runner/bin/
RUN --mount=type=cache,target=/var/lib/apt/lists \
    --mount=type=cache,target=/var/cache/apt \
    set -xe; \
    [ -d data ] || mkdir data; \
    cp -avf conf/deploy.env data/deploy.env; \
    chmod +x deploy.sh; \
    ./deploy.sh --github-action
