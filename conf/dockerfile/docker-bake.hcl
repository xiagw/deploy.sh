// docker-bake.hcl
// Generic docker buildx bake template that pairs with conf/dockerfile/Dockerfile.template
// Usage: docker buildx bake --file docker-bake.hcl --set "IMAGE_NAME=myapp" --set "IMAGE_TAG=latest" default

//  /usr/local/bin/docker build
// --add-host=git.flyh5.cn:192.168.44.11
// --quiet
// --build-arg IN_CHINA=true
// --build-arg MIRROR=registry.cn-hangzhou.aliyuncs.com/flyh5/
// --build-arg BUILD_TAG=3.9-amazoncorretto-17
// --build-arg RUN_TAG=17-base
// --build-arg MVN_PROFILE=main
// --tag registry.cn-hangzhou.aliyuncs.com/flyh6/oe:1785066590202
// --push

variable "IN_CHINA" { default = "false" }
variable "MIRROR" { default = "" }

// Build/runtime image variables (left empty to require caller to set appropriate images)
variable "BUILD_IMAGE" { default = "maven" }
variable "BUILD_TAG" { default = "3.9-amazoncorretto-17" }
variable "BUILD_OUTPUT_DIR" { default = "/build_output" }
variable "BUILD_MVN_PROFILE" { default = "main" }
variable "BUILD_INSTALL_FONTS" { default = "false" }
variable "BUILD_INSTALL_FFMPEG" { default = "false" }
variable "BUILD_INSTALL_LIBREOFFICE" { default = "false" }

variable "RUN_IMAGE" { default = "amazoncorretto" }
variable "RUN_TAG" { default = "17-base" }

variable "IMAGE_REGISTRY" { default = "registry.cn-hangzhou.aliyuncs.com" }
variable "IMAGE_NAME" { default = "flyh6/aa" }
variable "IMAGE_TAG" { default = "1785066590202" }

variable "PLATFORMS" { default = "linux/amd64" }

variable "CONTEXT_PATH" { default = "." }
variable "DOCKER_FILE" { default = "Dockerfile.template" }

target "default" {
    context = "${CONTEXT_PATH}"
    dockerfile = "${DOCKER_FILE}"
    platforms = ["${PLATFORMS}"]
    # platforms = ["linux/amd64", "linux/arm64"]
    platforms = ["linux/amd64"]
    args = {
        IN_CHINA = "${IN_CHINA}"
        MIRROR = "${MIRROR}"
        BUILD_IMAGE = "${BUILD_IMAGE}"
        BUILD_TAG = "${BUILD_TAG}"
        RUN_IMAGE = "${RUN_IMAGE}"
        RUN_TAG = "${RUN_TAG}"
        BUILD_OUTPUT_DIR = "${BUILD_OUTPUT_DIR}"
        BUILD_MVN_PROFILE = "${BUILD_MVN_PROFILE}"
        BUILD_INSTALL_FONTS = "${BUILD_INSTALL_FONTS}"
        BUILD_INSTALL_FFMPEG = "${BUILD_INSTALL_FFMPEG}"
        BUILD_INSTALL_LIBREOFFICE = "${BUILD_INSTALL_LIBREOFFICE}"
    }
    tags = ["${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"]
}

// Common specialized targets. Callers may override vars via --set or env vars.
target "java" {
    inherits = ["default"]
    args = {
        MVN_PROFILE = main
    }
}

target "node" {
    inherits = ["default"]
}

target "go" {
    inherits = ["default"]
}

target "python" {
    inherits = ["default"]
}

target "php" {
    inherits = ["default"]
}

group "all" {
    targets = ["java","node","go","python","php"]
}

// Notes:
// - Use `--set` to override variables inline, e.g.:
//   docker buildx bake --file docker-bake.hcl --set "IMAGE_REGISTRY=registry.example.com" --set "IMAGE_NAME=myapp" --set "IMAGE_TAG=20260726" java
// - If you omit BUILD_IMAGE (single-stage runtime-only), set RUN_IMAGE/RUN_TAG and leave BUILD_IMAGE empty.
// - This template intentionally avoids hardcoded build-arg values; choose per-target values via --set or by editing a copied bake file.
