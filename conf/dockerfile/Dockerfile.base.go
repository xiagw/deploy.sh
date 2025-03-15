# Build stage
ARG BASE_IMAGE=golang
ARG GO_VERSION=1.22
ARG NGINX_VERSION=stable-alpine
ARG APP_USER=appuser
ARG APP_UID=1000
ARG APP_GID=1000

FROM ${BASE_IMAGE}:${GO_VERSION} AS build
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
FROM nginx:${NGINX_VERSION} AS final
LABEL maintainer="DevOps Team"
LABEL description="Production runtime image"

# Install required packages and setup timezone
RUN --mount=type=cache,target=/var/cache/apk \
    set -xe && \
    apk --no-cache --update add \
        ca-certificates \
        tzdata \
        curl && \
    update-ca-certificates && \
    rm -rf /var/cache/apk/*

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


