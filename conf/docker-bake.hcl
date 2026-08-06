// docker-bake.hcl
// 与 Dockerfile.template（多阶段编译型）/ Dockerfile.single（单阶段运行时型）配套。
// 各语言 target 只负责传不同的 ARG 组合，模板本身通用。
// 用法：
//   docker buildx bake --file docker-bake.hcl --set "java.tags=registry.example.com/myapp:tag" java
//   docker buildx bake --file docker-bake.hcl mysql
// 覆盖变量：--set "<target>.args.<ARG>=value"

variable "IS_CHINA" { default = "false" }
variable "MIRROR" { default = "" }

// 通用构建参数（default target 为 Java 应用多阶段构建，与历史行为一致）
variable "BUILD_IMAGE" { default = "maven" }
variable "BUILD_TAG" { default = "3.9-amazoncorretto-17" }
variable "BUILD_OUTPUT_DIR" { default = "/build_output" }
variable "MVN_DEBUG" { default = "false" }
variable "MVN_PROFILE" { default = "main" }
variable "INSTALL_FONTS" { default = "false" }
variable "INSTALL_FFMPEG" { default = "false" }
variable "INSTALL_LIBREOFFICE" { default = "false" }

variable "RUN_IMAGE" { default = "amazoncorretto" }
variable "RUN_TAG" { default = "17-base" }

variable "IMAGE_REGISTRY" { default = "registry.cn-hangzhou.aliyuncs.com" }
variable "IMAGE_NAME" { default = "flyh6/aa" }
variable "IMAGE_TAG" { default = "latest" }

variable "CONTEXT_PATH" { default = "." }

target "default" {
    context = "${CONTEXT_PATH}"
    dockerfile = "Dockerfile.template"
    # platforms = ["linux/amd64", "linux/arm64"]
    platforms = ["linux/amd64"]
    args = {
        IS_CHINA = "${IS_CHINA}"
        MIRROR = "${MIRROR}"
        BUILD_IMAGE = "${BUILD_IMAGE}"
        BUILD_TAG = "${BUILD_TAG}"
        RUN_IMAGE = "${RUN_IMAGE}"
        RUN_TAG = "${RUN_TAG}"
        BUILD_OUTPUT_DIR = "${BUILD_OUTPUT_DIR}"
        MVN_DEBUG = "${MVN_DEBUG}"
        MVN_PROFILE = "${MVN_PROFILE}"
        INSTALL_FONTS = "${INSTALL_FONTS}"
        INSTALL_FFMPEG = "${INSTALL_FFMPEG}"
        INSTALL_LIBREOFFICE = "${INSTALL_LIBREOFFICE}"
    }
    tags = ["${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"]
    output = ["type=image,push=true"]
    pull = true
}

// ============================================================================
// 多阶段编译型（Dockerfile.template）
// ============================================================================

// Java 应用（maven 编译 + JDK 运行）
target "java-app" {
    inherits = ["default"]
}

// Java 基础镜像（仅 JDK 运行时，无 maven 阶段；对应原 Dockerfile.base.java）
target "java" {
    inherits = ["default"]
    dockerfile = "Dockerfile.single"
    args = {
        RUN_IMAGE = "amazoncorretto"
        RUN_TAG = "17"
        MVN_PROFILE = "base"
    }
}

// Go：golang 编译 → alpine 运行（对应原 Dockerfile.base.go）
target "go" {
    inherits = ["default"]
    args = {
        BUILD_IMAGE = "golang"
        BUILD_TAG = "1.26"
        RUN_IMAGE = "alpine"
        RUN_TAG = "latest"
        APP_PORTS = "5000"
        APP_CMD = "/app/server"
    }
}

// PHP：swoole 编译 → ubuntu 运行（对应原 Dockerfile.base.php）
target "php" {
    inherits = ["default"]
    args = {
        BUILD_IMAGE = "phpswoole/swoole"
        BUILD_TAG = "6.1-php8.4"
        RUN_IMAGE = "ubuntu"
        RUN_TAG = "24.04"
        BUILD_SCRIPT_ARG = "swoole"
        RUN_SCRIPT_ARG = "php"
        PHP_VERSION = "8.4"
        APP_PORTS = "80 9000"
    }
}

// Nginx：编译 GeoIP2 模块 → alpine 运行（对应原 Dockerfile.base.nginx）
target "nginx" {
    inherits = ["default"]
    args = {
        BUILD_IMAGE = "nginx"
        BUILD_TAG = "stable-alpine"
        RUN_IMAGE = "nginx"
        RUN_TAG = "stable-alpine"
        BUILD_SCRIPT_ARG = "geo"
        APP_PORTS = "80 443"
        APP_CMD = "/docker-entrypoint.sh nginx -g 'daemon off;'"
    }
}

// ============================================================================
// 单阶段运行时型（Dockerfile.single）
// ============================================================================

// Node（对应原 Dockerfile.base.node）
target "node" {
    inherits = ["default"]
    dockerfile = "Dockerfile.single"
    args = {
        RUN_IMAGE = "node"
        RUN_TAG = "22-slim"
        ONBUILD_CHOWN = "1000:1000"
        ONBUILD_COPY_SRC = "."
        ONBUILD_COPY_DEST = "/app/"
    }
}

// Python（对应原 Dockerfile.base.python）
target "python" {
    inherits = ["default"]
    dockerfile = "Dockerfile.single"
    args = {
        RUN_IMAGE = "python"
        RUN_TAG = "3.12-slim"
        APP_CMD = "python3"
    }
}

// MySQL（对应原 Dockerfile.base.mysql；APP_CMD 重新进入官方入口以保留初始化）
target "mysql" {
    inherits = ["default"]
    dockerfile = "Dockerfile.single"
    args = {
        RUN_IMAGE = "mysql"
        RUN_TAG = "8.0"
        APP_WORKDIR = "/"
        APP_PORTS = "3306"
        APP_VOLUME = "/var/lib/mysql"
        APP_CMD = "docker-entrypoint.sh mysqld"
        MYSQL_REPLICATION = "single"
    }
}

// Redis（对应原 Dockerfile.base.redis）
target "redis" {
    inherits = ["default"]
    dockerfile = "Dockerfile.single"
    args = {
        RUN_IMAGE = "redis"
        RUN_TAG = "latest"
        APP_WORKDIR = "/data"
        APP_PORTS = "6379"
        APP_VOLUME = "/data"
        APP_CMD = "docker-entrypoint.sh redis-server"
    }
}

group "all" {
    targets = ["java", "node", "go", "python", "php", "nginx", "mysql", "redis"]
}

// Notes:
// - 版本覆盖示例：
//   docker buildx bake -f docker-bake.hcl --set "java.args.RUN_TAG=21" java
//   docker buildx bake -f docker-bake.hcl --set "php.args.PHP_VERSION=8.1" php
// - 应用构建（maven 多阶段）用 default 或 java-app target，需 bind 源码作为 context。
