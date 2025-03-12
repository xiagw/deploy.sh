ARG GO_VERSION=1.22
# FROM registry.cn-hangzhou.aliyuncs.com/flyh5/flyh5:golang-${GO_VERSION} AS build
FROM golang:${GO_VERSION} AS build
ARG IN_CHINA=false
WORKDIR /src
ENV CGO_ENABLED 0
ENV GOPROXY https://goproxy.cn,direct
RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=type=bind,source=go.sum,target=go.sum \
    --mount=type=bind,source=go.mod,target=go.mod \
    go mod download -x
RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=type=bind,target=/src \
    CGO_ENABLED=0 go build -o /bin/server .

# FROM alpine:latest AS final
# FROM registry.cn-hangzhou.aliyuncs.com/flyh5/flyh5:nginx-alpine AS final
FROM nginx:stable-alpine AS final
RUN --mount=type=cache,target=/var/cache/apk \
    set -xe; \
    apk --update add ca-certificates tzdata; \
    update-ca-certificates
# ENTRYPOINT [ "/bin/server" ]
# CMD [ "/bin/server" ]
EXPOSE 5000
WORKDIR /app
COPY --from=build /bin/server /app/
RUN --mount=type=bind,target=/src \
    set -xe; \
    chmod +x /app/server; \
    cp -af /src/config /app/; \
    cp -af /src/.env /app/; \
    # cp -af /src/web/* /usr/share/nginx/html/; \
    chown -R "1000:1000" /app; \
    adduser --disabled-password --gecos "" --home "/app" --no-create-home --uid 1000 appuser; \
    echo "cd /app && su appuser -c /app/server &" >/docker-entrypoint.d/run.sh; \
    chmod +x /docker-entrypoint.d/run.sh


