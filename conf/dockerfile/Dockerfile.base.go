# Go 多阶段构建：编译二进制 + Nginx 运行；需在构建时 mount 源码到 /src。
# 示例：docker build -f conf/dockerfile/Dockerfile.base.go --build-arg TAG=1.22 -t mygo:app .
# Build stage
ARG MIRROR=
ARG BUILD_IMAGE=golang
ARG BUILD_TAG=1.26

ARG RUN_IMAGE=nginx
ARG RUN_TAG=stable-alpine

FROM ${MIRROR}${BUILD_IMAGE}:${BUILD_TAG} AS builder

LABEL maintainer="DevOps Team"
LABEL description="Go application build stage"

WORKDIR /src
ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    GOPROXY=https://goproxy.cn,direct

# Download dependencies
RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=type=bind,source=go.sum,target=go.sum \
    --mount=type=bind,source=go.mod,target=go.mod \
    go mod download -x

# Build application
RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=type=bind,target=/src \
    go build -ldflags="-s -w" -o /bin/server .

# Final stage
FROM ${MIRROR}${RUN_IMAGE}:${RUN_TAG} AS final

LABEL maintainer="DevOps Team" \
      description="Production runtime image"

# Install required packages and setup timezone
RUN --mount=type=cache,target=/var/cache/apk \
    set -xe && \
    apk --no-cache --update add \
        ca-certificates \
        tzdata \
        curl && \
    update-ca-certificates && \
    rm -rf /var/cache/apk/*

ARG APP_USER=ops
ARG APP_UID=1000
ARG APP_GID=1000
# Create app user and setup directories
RUN addgroup -g ${APP_GID} ${APP_USER} && \
    adduser -D -u ${APP_UID} -G ${APP_USER} -h /app ${APP_USER}

WORKDIR /app

# Copy binary and config files
COPY --from=build --chown=${APP_USER}:${APP_USER} /bin/server /app/
COPY --chown=${APP_USER}:${APP_USER} config /app/config
COPY --chown=${APP_USER}:${APP_USER} .env /app/

# Setup permissions and startup script
RUN chmod +x /app/server && \
    echo "cd /app && su ${APP_USER} -c /app/server &" > /docker-entrypoint.d/run.sh && \
    chmod +x /docker-entrypoint.d/run.sh

# Configure healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5000/health || exit 1

EXPOSE 5000

USER ${APP_USER}


