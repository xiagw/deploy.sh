#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2154,2034,1090,1091,2086
################################################################################
# Description: Consolidated build functions for various programming languages
# Author: xiagw <fxiaxiaoyu@gmail.com>
# License: GNU/GPL
################################################################################

## 在中国区环境下启用 buildx builder
ensure_buildx_builder() {
    [[ "${G_DEBUG_ON:-false}" == true ]] && return
    [[ -z "${ENV_BUILDX_REMOTE_HOSTS[*]:-}" ]] && return

    local builder_name="deploy-builder"
    if "${IS_CHINA:-false}"; then
        local mirror="docker.m.daocloud.io/"
    fi
    if ! docker buildx inspect "$builder_name" >/dev/null 2>&1; then
        local c=0 append_flag=()
        local buildkit_image="${mirror}${ENV_BUILDX_IMAGE:-moby/buildkit:buildx-stable-1}"
        for dk_host in "${ENV_BUILDX_REMOTE_HOSTS[@]}"; do
            ((++c))
            docker buildx create --name "$builder_name" "${append_flag[@]}" \
                --node "node$c" --driver docker-container --bootstrap \
                --driver-opt image="${buildkit_image}" \
                "$dk_host" ||
                _msg error "创建buildx节点node$c失败: ${dk_host}"
            append_flag=(--append)
        done
    fi
    export G_BUILDER="--builder $builder_name"
}

# 在 k8s 中创建 buildx builder
# docker buildx create --driver kubernetes --name deploy-builder --driver-opt namespace=buildkit,replicas=1 --driver-opt image=docker.m.daocloud.io/moby/buildkit:buildx-stable-1 --bootstrap
ensure_buildx_builder_kubernetes() {
    [[ "${G_DEBUG_ON:-false}" == true ]] && return
    [[ -z "${ENV_BUILDX_KUBERNETES_NAMESPACE:-}" ]] && return
    if "${IS_CHINA:-false}"; then
        local mirror="docker.m.daocloud.io/"
    fi
    local builder_name="deploy-builder-k8s"
    if ! docker buildx inspect "$builder_name" >/dev/null 2>&1; then
        local buildkit_image="${mirror}${ENV_BUILDX_IMAGE:-moby/buildkit:buildx-stable-1}"
        docker buildx create --driver kubernetes --name "$builder_name" \
            --driver-opt namespace="${ENV_BUILDX_KUBERNETES_NAMESPACE:-buildkit}" \
            --driver-opt replicas="${ENV_BUILDX_KUBERNETES_REPLICAS:-1}" \
            --driver-opt image="${buildkit_image}" \
            --bootstrap || _msg error "创建 kubernetes buildx builder 失败"
    fi
    export G_BUILDER="--builder $builder_name"
}

enable_buildx_mode() {
    local mode="${ENV_BUILDX_MODE:-remote}"
    mode="${mode,,}"

    ## dry-run: 只提示会选择哪种 builder，不真正 create/bootstrap
    if ${G_DRY_RUN:-false}; then
        dry_run_note "enable buildx builder (mode=${mode})"
        return 0
    fi

    case "${mode}" in
    auto)
        if [[ -n "${ENV_BUILDX_KUBERNETES_NAMESPACE:-}" ]]; then
            ensure_buildx_builder_kubernetes
        elif [[ -n "${ENV_BUILDX_REMOTE_HOSTS[*]:-}" ]]; then
            ensure_buildx_builder
        else
            _msg warn "ENV_BUILDX_MODE=auto but no buildx host or kubernetes namespace configured"
        fi
        ;;
    kubernetes)
        ensure_buildx_builder_kubernetes
        ;;
    context)
        ## 使用本机 docker context（默认 builder），不创建远端 builder
        _msg note "Using local docker context for buildx (mode=context)"
        unset G_BUILDER
        ;;
    remote | "")
        ensure_buildx_builder
        ;;
    *)
        _msg warn "Unknown ENV_BUILDX_MODE=${mode}, falling back to remote"
        ensure_buildx_builder
        ;;
    esac
}

# 根据 lang（固定三段式 lang:ver:docker_flag，字段可为空）生成 docker-bake.hcl
# $1 lang, $2 bake 文件路径, $3 应用镜像 tag, $4 可选 base 镜像 tag（存在 Dockerfile.base 时）
# $5 是否生成 base target（复用时仅注入 BASE_IMAGE 参数，不生成 base target）
generate_bake_file() {
    local lang="${1:?lang required}" bake_file="${2:?bake file required}"
    local repo_tag="${3:?repo tag required}" base_tag="${4:-}" build_base_target="${5:-false}"
    local lang_type ver docker_flag lang_args="" extra_args="" mirror="${ENV_DOCKER_MIRROR:+${ENV_DOCKER_MIRROR%/}/}"
    IFS=: read -r lang_type ver docker_flag <<<"${lang}"
    lang_type="${lang_type:-unknown}"

    ## lang[:ver] → "BUILD_IMAGE BUILD_TAG RUN_IMAGE RUN_TAG"
    ## Dockerfile 全变量化（ARG 默认值是 java），必须四项全量注入
    ## 精确 key 未命中时回退到 lang key（默认版本）
    declare -A LANG_IMAGE_MAP=(
        ["java"]="maven 3.8-amazoncorretto-8 amazoncorretto 8-base"
        ["java:1.7"]="maven 3.6-jdk-7 amazoncorretto 7"
        ["java:7"]="maven 3.6-jdk-7 amazoncorretto 7"
        ["java:11"]="maven 3.9-amazoncorretto-11 amazoncorretto 11-base"
        ["java:17"]="maven 3.9-amazoncorretto-17 amazoncorretto 17-base"
        ["java:21"]="maven 3.9-amazoncorretto-21 amazoncorretto 21-base"
        ["java:25"]="maven 3.9-amazoncorretto-25 amazoncorretto 25-base"
        ["java:26"]="maven 3.9-amazoncorretto-26 amazoncorretto 26-base"
        ["node"]="node 22-slim node 22-slim"
        ["go"]="golang 1.26 alpine latest"
        ["golang"]="golang 1.26 alpine latest"
        ["python"]="python 3.12-slim python 3.12-slim"
        ["php"]="phpswoole/swoole 6.1-php8.4 ubuntu 24.04"
    )

    local map_val="${LANG_IMAGE_MAP[${lang_type}:${ver}]:-${LANG_IMAGE_MAP[${lang_type}]:-}}"
    if [[ -n "${map_val}" ]]; then
        local build_image build_tag run_image run_tag
        read -r build_image build_tag run_image run_tag <<<"${map_val}"
        ## node/python 等 tag 直接跟随版本号；go 仅编译镜像跟随版本
        case "${lang_type}" in
        node) [[ -n "${ver}" ]] && { build_tag="${ver}-slim"; run_tag="${ver}-slim"; } ;;
        python) [[ -n "${ver}" ]] && { build_tag="${ver}-slim"; run_tag="${ver}-slim"; } ;;
        go | golang) [[ -n "${ver}" ]] && build_tag="${ver}" ;;
        esac
        ## node 最低版本限制 18
        if [[ "${lang_type}" == node ]]; then
            local _node_num="${run_tag%%-*}"
            [[ -n "${_node_num}" && "${_node_num}" -lt 18 ]] 2>/dev/null && { build_tag="18-slim"; run_tag="18-slim"; }
        fi
        ## 静态前端（vue-cli/vite/react-scripts/umi）：builder 用 node，final 用 nginx 承接静态产物
        if [[ "${lang_type}" == node ]] && detect_node_framework_static; then
            run_image="nginx"
            run_tag="alpine"
        fi
        lang_args+="
        BUILD_IMAGE = \"${build_image}\"
        BUILD_TAG = \"${build_tag}\"
        RUN_IMAGE = \"${run_image}\"
        RUN_TAG = \"${run_tag}\""
    fi

    ## 语言特有的附加参数
    case "${lang_type}" in
    java)
        lang_args+="
        MVN_PROFILE = \"${G_REPO_BRANCH}\"
        MVN_DEBUG = \"${G_DEBUG_ON:-false}\""

        ;;
    node)
        if detect_node_framework_static; then
            ## 静态前端: 注入构建脚本名（bake 传给 build.sh web <script>，由命名空间映射）
            local web_build_script="build"
            case "${G_NAMESPACE:-}" in
            *uat* | *test*) web_build_script="build:stage" ;;
            *master* | *main* | *prod*) web_build_script="build:prod" ;;
            esac
            lang_args+="
        WEB_BUILD_SCRIPT = \"${web_build_script}\""
        else
            lang_args+="
        ONBUILD_CHOWN = \"1000:1000\"
        ONBUILD_COPY_SRC = \".\"
        ONBUILD_COPY_DEST = \"/app/\""
        fi
        ;;
    python)
        ## 运行时依赖 base（同 node 后端）：业务镜像 ONBUILD 把源码 COPY 到 /app/
        lang_args+="
        ONBUILD_CHOWN = \"1000:1000\"
        ONBUILD_COPY_SRC = \".\"
        ONBUILD_COPY_DEST = \"/app/\""
        ;;
    esac
    ## README 文件中声明的额外安装需求(变量名转为全大写变量值为 true 小写)
    local f
    for f in "${G_REPO_DIR}"/{README,readme}*; do
        [ -f "$f" ] || continue
        if ! grep -qi '^install_.*=.*true' "$f"; then
            continue
        fi
        lang_args+="
        $(grep -ih '^install_.*=.*true' "$f" | tr '[:lower:]' '[:upper:]' | sed 's/TRUE/"true"/g')"
    done

    ## BUILD_SCRIPT_ARG 和 RUN_SCRIPT_ARG 仅在非空时注入（避免覆盖 Dockerfile 默认值）
    [[ -n "${ENV_BUILD_SCRIPT_ARG:-}" ]] && extra_args+="
        BUILD_SCRIPT_ARG = \"${ENV_BUILD_SCRIPT_ARG}\""
    [[ -n "${ENV_RUN_SCRIPT_ARG:-}" ]] && extra_args+="
        RUN_SCRIPT_ARG = \"${ENV_RUN_SCRIPT_ARG}\""
    ## BASE_IMAGE：研发自提交两段式 Dockerfile（FROM ${BASE_IMAGE}）用，注入 base tag
    [[ -n "${base_tag}" ]] && extra_args+="
        BASE_IMAGE = \"${base_tag}\""


    ## 多架构构建平台（逗号分隔，默认 linux/amd64）
    local platforms="${ENV_BUILDX_PLATFORMS:-linux/amd64}" platform_list="" p
    for p in ${platforms//,/ }; do
        platform_list+="\"${p}\", "
    done
    platform_list="${platform_list%, }"

    ## BuildKit 构建缓存（bake cache-from/cache-to，仅 ENV_BUILDX_CACHE=true 时启用）
    ## 优先级: ENV_BUILDX_CACHE_REF（registry ref）> GitHub Actions (type=gha) > 自动推导 registry 缓存 ref
    local cache_block="" cache_from="" cache_to=""
    if [[ "${ENV_BUILDX_CACHE:-false}" == true ]]; then
        if [[ -n "${ENV_BUILDX_CACHE_REF:-}" ]]; then
            cache_from="type=registry,ref=${ENV_BUILDX_CACHE_REF}"
            cache_to="type=registry,ref=${ENV_BUILDX_CACHE_REF},mode=max"
        elif [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
            cache_from="type=gha"
            cache_to="type=gha,mode=max"
        elif [[ -n "${ENV_DOCKER_REGISTRY:-}" ]]; then
            local cache_ref="${ENV_DOCKER_REGISTRY%/}/cache/${G_REPO_NAME}:${G_REPO_BRANCH}"
            cache_from="type=registry,ref=${cache_ref}"
            cache_to="type=registry,ref=${cache_ref},mode=max"
        else
            _msg warn "ENV_BUILDX_CACHE=true but no ENV_BUILDX_CACHE_REF / ENV_DOCKER_REGISTRY / GitHub Actions, cache disabled"
        fi
        if [[ -n "${cache_from}" ]]; then
            cache_block="    cache-from = [\"${cache_from}\"]
    cache-to = [\"${cache_to}\"]
"
        fi
    fi

    cat >"${bake_file}" <<EOF
target "default" {
    context = "${G_REPO_DIR}"
    dockerfile = "Dockerfile"
    platforms = [${platform_list}]
    args = {
        IS_CHINA = "${IS_CHINA}"
        MIRROR = "${mirror}"
        BUILD_OUTPUT_DIR = "/build_output"${lang_args}${extra_args}
    }
    tags = ["${repo_tag}"]
${cache_block}}
EOF
    if [[ -n "${base_tag}" && "${build_base_target}" == true ]]; then
        cat >>"${bake_file}" <<EOF
target "base" {
    inherits = ["default"]
    dockerfile = "Dockerfile.base"
    tags = ["${base_tag}"]
}
EOF
    fi
}

# 自动生成两段式时的说明（每个项目/分支首次构建输出一次，marker 记录）
base_explain() {
    local lang="${1:-}" manifest_name
    manifest_name="$(lang_dep_manifest "${lang}")"
    manifest_name="${manifest_name##*/}"
    [[ -n "${manifest_name}" ]] || return 0
    local marker="${G_DATA}/cache/${G_REPO_NAME}-${G_REPO_BRANCH}-base.explained"
    if ! ${G_DRY_RUN:-false} && [[ -f "${marker}" ]]; then
        return 0
    fi
    ${G_DRY_RUN:-false} || touch "${marker}"
    _msg note "[${lang}] 两段式构建（加速设计）：base 镜像先按 ${manifest_name} 安装依赖，运行时镜像直接 FROM base"
    _msg note "      依赖只安装一次；${manifest_name} 变动才重建 base，未变动直接复用已有（构建更快）"
    _msg note "      base tag: ${ENV_DOCKER_REGISTRY%/}/base:${G_REPO_NAME}-${G_REPO_BRANCH}"
}

build_image() {
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && return 0
    local lang="${1:-}"
    local custom_build_script dockerfile_base_path dockerfile_path buildx_push_option image_uuid target_image_tag base_image_tag bake_file_path docker_mirror ret debug_flag
    local custom_build_ret build_base dep_hash node_base_record deps_base_custom

    ## Ensure buildx builder is available
    enable_buildx_mode

    ## If build.base.sh exists, run it and preserve its exit status
    custom_build_script="${G_REPO_DIR}/build.base.sh"
    if [[ -f "${custom_build_script}" ]]; then
        if ${G_DRY_RUN:-false}; then
            dry_run_note "run custom build script: bash ${custom_build_script#"${G_REPO_DIR}"/}"
        else
            _msg note "Found ${custom_build_script}, running it..."
            [[ "${G_DEBUG_ON:-false}" == true ]] && debug_flag="-x"
            bash "${custom_build_script}" $debug_flag
            custom_build_ret=$?
            return "${custom_build_ret}"
        fi
    fi

    ## 构建并推送镜像到 registry（部署流程需从 registry 拉取）
    docker_login
    buildx_push_option="--push"

    ## 如果存在 Dockerfile.base，则生成 base 镜像的 tag
    ## base 是否重建以依赖声明文件（package.json/requirements.txt）指纹为准（node 后端/python）：
    ## 依赖未变且 registry 已有该 base 时直接复用，不再依赖 Dockerfile.base 文件是否存在
    dockerfile_base_path="${G_REPO_DIR}/Dockerfile.base"
    dockerfile_path="${G_REPO_DIR}/Dockerfile"
    if [[ -f "${dockerfile_base_path}" ]]; then
        base_image_tag="${ENV_DOCKER_REGISTRY%/}/base:${G_REPO_NAME}-${G_REPO_BRANCH}"
        build_base=true
        local lang_type="${lang%%:*}"
        local manifest_name="" node_static=false
        [[ "${lang_type}" == node ]] && detect_node_framework_static && node_static=true
        if lang_uses_deps_base "${lang_type}" && [[ "${node_static}" != true ]]; then
            if repo_base_is_custom; then
                ## 研发自提交 Dockerfile/Dockerfile.base：按其方式走，始终构建 base、不覆写其 Dockerfile
                ## （提醒已在 repo_inject_file 输出）
                deps_base_custom=true
            else
                ## 自动生成的两段式：按依赖声明文件指纹决定是否重建 base
                dep_hash="$(lang_dep_hash "${lang_type}")"
                node_base_record="${G_DATA}/cache/${G_REPO_NAME}-${G_REPO_BRANCH}-base.md5"
                manifest_name="$(lang_dep_manifest "${lang_type}")"
                manifest_name="${manifest_name##*/}"
                base_explain "${lang_type}"
                [[ "${lang_type}" == node ]] && node_lockfile_warn
                if [[ "$(cat "${node_base_record}" 2>/dev/null || echo 0)" == "${dep_hash}" ]]; then
                    if ${G_DRY_RUN:-false} || $G_DOCK manifest inspect "${base_image_tag}" >/dev/null 2>&1; then
                        build_base=false
                        _msg note "[${lang_type}] ${manifest_name} 未变，Dockerfile 直接复用基础镜像（本轮构建较快）"
                    fi
                fi
            fi
        fi
        ## 自动生成时确保主 Dockerfile = FROM base；研发自提交的不动
        if [[ "${deps_base_custom:-false}" != true ]]; then
            if ${G_DRY_RUN:-false}; then
                ${build_base} && dry_run_note "write 'FROM ${base_image_tag}' to ${dockerfile_path#"${G_REPO_DIR}"/} (base image)"
            else
                echo "FROM ${base_image_tag}" >"${dockerfile_path}"
            fi
        fi
    fi

    ## 生成 docker-bake.hcl 文件
    target_image_tag="${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}"
    if ${G_DRY_RUN:-false}; then
        ## dry-run: hcl 写临时文件，不污染仓库
        bake_file_path="$(mktemp)"
    else
        bake_file_path="${G_REPO_DIR}/docker-bake.hcl"
    fi
    generate_bake_file "${lang}" "${bake_file_path}" "${target_image_tag}" "${base_image_tag:-}" "${build_base:-false}"

    ## 自动生成 .dockerignore（仅在项目不存在时创建，避免覆盖用户自定义规则）
    ## 减少远程 buildx 构建时通过 SSH 传输的上下文体积
    local dockerignore_path="${G_REPO_DIR}/.dockerignore"
    if [[ -f "${dockerignore_path}" ]]; then
        : ## 已存在则不动
    elif ${G_DRY_RUN:-false}; then
        dry_run_note "generate ${dockerignore_path#"${G_REPO_DIR}"/} (auto .dockerignore)"
    else
        cat >"${dockerignore_path}" <<'DOCKERIGNORE'
# Auto-generated by deploy.sh — 减少构建上下文体积
.git
.gitignore
.svn
.hg
.idea
.vscode
*.log
*.tmp
node_modules
target
dist
build
.gradle
__pycache__
*.pyc
.env.*
docker-compose*.yml
Dockerfile*
.dockerignore
docker-bake.hcl
README*
LICENSE
CHANGELOG*
DOCKERIGNORE
        _msg note "Auto-generated .dockerignore to reduce build context"
    fi
    ## dry-run: 仅显示构建计划，不实际执行构建
    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] skip docker buildx bake, showing build plan only"
        if $G_DOCK buildx version >/dev/null 2>&1; then
            if [[ -f "${dockerfile_base_path}" ]] && ${build_base:-false}; then
                dry_run_note "$G_DOCK buildx bake ${G_BUILDER:-} --file ${bake_file_path} ${buildx_push_option} ${G_PROGRESS} base"
                $G_DOCK buildx bake ${G_BUILDER:-} --file "${bake_file_path}" --progress=quiet base --print
            fi
            dry_run_note "$G_DOCK buildx bake ${G_BUILDER:-} --file ${bake_file_path} ${buildx_push_option} ${G_PROGRESS}"
            $G_DOCK buildx bake ${G_BUILDER:-} --file "${bake_file_path}" --progress=quiet --print
        else
            _msg note "  docker/buildx not available, showing generated ${bake_file_path##*/}:"
            cat "${bake_file_path}"
        fi
        rm -f "${bake_file_path}"
        return 0
    fi
    ## 存在 Dockerfile.base 且依赖指纹变化（或 registry 无该 base）时才构建 base
    if [[ -f "${dockerfile_base_path}" ]]; then
        if ${build_base:-false}; then
            if [[ "${deps_base_custom:-false}" == true ]]; then
                _msg note "[${lang_type}] 按仓库自带的 Dockerfile.base/Dockerfile 构建基础镜像和运行时镜像"
            else
                _msg note "[${lang_type}] ${manifest_name} 有改动，重建基础镜像 Dockerfile.base（本轮构建较慢）"
            fi
            local base_build_log="${G_DATA:-.}/logs/${G_REPO_NAME}-base-build-${G_REPO_BRANCH}.log"
            _msg note "log file: $base_build_log"
            mkdir -p "$(dirname "$base_build_log")"

            set +e +o pipefail
            $G_DOCK buildx bake ${G_BUILDER:-} --file "${bake_file_path}" ${buildx_push_option} ${G_PROGRESS} base 2>&1 | tee "$base_build_log" >/dev/null
            ret="${PIPESTATUS[0]}"
            set -eo pipefail

            if [ "$ret" -ne 0 ]; then
                echo "============================================================"
                _msg error "Base image build failed (exit code: $ret), showing last 100 lines of build log:"
                echo "============================================================"
                tail -100 "$base_build_log"
                _msg error "Full build log: $base_build_log"
                return 1
            fi
            ## 构建成功：记录依赖指纹，依赖未变时下次直接复用
            if [[ -n "${dep_hash:-}" ]]; then
                mkdir -p "$(dirname "${node_base_record}")"
                echo "${dep_hash}" >"${node_base_record}"
            fi
        fi
    fi

    # Docker build 输出到日志文件，默认不显示构建详情
    # 构建失败时显示最后100行日志便于排查
    local build_log="${G_DATA:-.}/logs/${G_REPO_NAME}-build-${G_REPO_BRANCH}.log"
    _msg note "log file: $build_log"
    mkdir -p "$(dirname "$build_log")"

    set +e +o pipefail
    $G_DOCK buildx bake ${G_BUILDER:-} --file "${bake_file_path}" ${buildx_push_option} ${G_PROGRESS} 2>&1 | tee "$build_log" >/dev/null
    ret=${PIPESTATUS[0]}
    set -eo pipefail

    if [ "$ret" -ne 0 ]; then
        echo "============================================================"
        _msg error "Image build failed (exit code: $ret), showing last 100 lines of build log:"
        echo "============================================================"
        tail -100 "$build_log"
        _msg error "Full build log: $build_log"
        return 1
    fi
    _msg task "Image build completed"

    ## 不包含敏感信息的镜像可以推送到公开仓库 push to ttl.sh
    if [[ "${PIPELINE_TTL_SH:-false}" == "true" || "${ENV_IMAGE_TTL:-false}" == "true" ]]; then
        image_uuid="ttl.sh/$(uuidgen):1h"
        echo "Temporary image tag: $image_uuid"
        if ${G_DRY_RUN:-false}; then
            dry_run_note "$G_DOCK tag ${target_image_tag} ${image_uuid} && $G_DOCK push ${image_uuid}"
        else
            $G_DOCK tag ${target_image_tag} ${image_uuid}
            $G_DOCK push $image_uuid
        fi
        echo "## Then execute the following commands on REMOTE SERVER."
        echo "  $G_DOCK pull $image_uuid"
        echo "  $G_DOCK tag $image_uuid laradock-spring"
    fi

    ## 构建完成后删除本地镜像（已推送到 registry）
    if $G_DOCK image inspect "${target_image_tag}" >/dev/null 2>&1; then
        $G_DOCK rmi "${target_image_tag}" >/dev/null &
        _msg task "Remove image: ${target_image_tag}"
    fi
}

# Main build function that determines which specific builder to run
# Priority: Docker build (if available) > System command build
stage_build() {
    _msg stage "$(_t '构建' 'build')"
    local lang
    ## 语言由构建流程内部探测（detect_repo_language 有缓存，重复调用廉价）
    lang="$(detect_repo_language)"
    local lang_type="${lang%%:*}" # Extract language type without version/docker suffix
    local has_dockerfile=false
    local docker_build_failed=false

    _msg task "Starting build process for ${lang}"

    ## 检查配置文件中的构建方式覆盖
    if [[ -n "${PROJECT_BUILD_METHOD:-}" && "${PROJECT_BUILD_METHOD}" != "auto" ]]; then
        case "${PROJECT_BUILD_METHOD}" in
        docker)
            if check_docker_available; then
                _msg note "Using configured build method: docker"
                build_image "${lang}"
                return $?
            else
                _msg error "Configured build method 'docker' but Docker is not available"
                return 1
            fi
            ;;
        system)
            _msg note "Using configured build method: system command"
            # Skip Docker check, go directly to system build
            has_dockerfile=false
            ;;
        esac
    fi

    # Check if Dockerfile exists
    for file in Dockerfile{,.*}; do
        if [[ -f "${G_REPO_DIR}/${file}" ]]; then
            has_dockerfile=true
            break
        fi
    done

    # Priority 1: Try Docker build if Dockerfile exists and Docker is available
    # prefer_docker=false: 自动模式下直接走系统构建，跳过 Docker（由 Priority 2 承接）
    if [[ "${PROJECT_PREFER_DOCKER:-true}" == true ]] && [[ "$has_dockerfile" == true ]]; then
        if check_docker_available; then
            _msg note "found Dockerfile and dockerd is available → attempting Docker build"
            # Check if lang already has :docker suffix, if not, try Docker build first
            if [[ "$lang" != *:docker ]]; then
                # Try Docker build with fallback
                if build_image "${lang}"; then
                    _msg ok "Docker build completed successfully"
                    return 0
                else
                    _msg warn "Docker build failed, falling back to system command build"
                    docker_build_failed=true
                fi
            else
                # Lang already marked as docker, use Docker build directly
                build_image "${lang}"
                return $?
            fi
        else
            _msg warn "Found Dockerfile but Docker is not available, using system command build"
        fi
    fi

    # Priority 2: Use system command build
    # If Docker build was attempted and failed, or no Dockerfile/Docker available,
    # or prefer_docker=false (skip Docker), use system command build
    if [[ "${PROJECT_PREFER_DOCKER:-true}" != true ]] || [[ "$docker_build_failed" == true ]] || [[ "$has_dockerfile" != true ]] || ! check_docker_available; then
        _msg note "Using system command build for ${lang_type}"
        if ${G_DRY_RUN:-false}; then
            dry_run_note "run ${lang_type} system build (build_${lang_type})"
            return 0
        fi
        case "$lang_type" in
        java) build_java ;;
        node) build_node ;;
        python) build_python ;;
        android) build_android ;;
        ios) build_ios ;;
        ruby) build_ruby ;;
        go | golang) build_go ;;
        c) build_c ;;
        django) build_django ;;
        php) build_php ;;
        shell) build_shell ;;
        *)
            _msg warn "No build function available for language: $lang_type"
            return 1
            ;;
        esac
    fi
}

# Java Build
build_java() {
    local jars_path="$G_REPO_DIR/build_output"
    ## 统一构建镜像: ENV_BASE_BUILD_IMAGE 可覆盖默认 maven 工具镜像
    local java_image="${ENV_BASE_BUILD_IMAGE:-maven:${ENV_MAVEN_VER:-3.8-jdk-8}}"

    if [[ -f "$G_REPO_DIR/build.gradle" ]]; then
        _msg task "Building with gradle"
        gradle -q
    else
        _msg task "Building with maven"
        local maven_settings=""
        local maven_debug=""

        [[ -f $G_REPO_DIR/settings.xml ]] && maven_settings="--settings settings.xml"
        [[ "${G_DEBUG_ON:-false}" == true ]] && maven_debug='-X'

        ## Create maven cache
        if ! $G_DOCK volume ls | grep -q maven-repo; then
            $G_DOCK volume create --name maven-repo
        fi

        $G_RUN -u 0:0 -v maven-repo:/var/maven/.m2:rw "${java_image}" bash -c "chown -R 1000:1000 /var/maven"
        $G_RUN --user "$(id -u):$(id -g)" \
            -e MAVEN_CONFIG=/var/maven/.m2 \
            -v maven-repo:/var/maven/.m2:rw \
            -v "$G_REPO_DIR":/src:rw -w /src \
            "${java_image}" \
            mvn -T 1C clean $maven_debug \
            --update-snapshots package \
            --define skipTests \
            --define user.home=/var/maven \
            --define maven.compile.fork=true \
            --activate-profiles "${G_REPO_BRANCH}" $maven_settings
    fi

    [ -d "$jars_path" ] || mkdir "$jars_path"

    # Move JAR files
    local jar_files=(
        "${G_REPO_DIR}"/target/*.jar
        "${G_REPO_DIR}"/*/target/*.jar
        "${G_REPO_DIR}"/*/*/target/*.jar
    )
    for jar in "${jar_files[@]}"; do
        [ -f "$jar" ] || continue
        case "$jar" in
        framework*.jar | gdp-module*.jar | sdk*.jar | *commom*.jar) echo 'skip' ;;
        *-dao-*.jar | lop-opensdk*.jar | core-*.jar) echo 'skip' ;;
        *) mv -vf "$jar" "$jars_path"/ ;;
        esac
    done

    # Copy YAML files if needed
    if [[ "${MVN_COPY_YAML:-false}" == true || "${exec_deploy_helm:-false}" = 'true' ]]; then
        local yml_files=(
            "${G_REPO_DIR}"/*/*/*/resources/*"${MVN_PROFILE:-main}".yml
            "${G_REPO_DIR}"/*/*/*/resources/*"${MVN_PROFILE:-main}".yaml
        )
        local c=0
        for yml in "${yml_files[@]}"; do
            [ -f "$yml" ] || continue
            c=$((c + 1))
            cp -vf "$yml" "$jars_path"/"${c}.${yml##*/}"
        done
    fi

    _msg note "[build] java build"
}

# Node.js Build
build_node() {
    local path_for_rsync='dist/'
    local file_json
    local file_json_md5
    local yarn_install
    local me_log="${G_DATA}/cache/${G_REPO_NAME}-${G_REPO_BRANCH}-yarn"

    mkdir -p "${G_DATA}/cache"

    file_json="${G_REPO_DIR}/package.json"
    file_json_md5="$G_REPO_GROUP_PATH/$G_NAMESPACE/$(md5sum "$file_json" | awk '{print $1}')"
    yarn_install=false

    if grep -q "$file_json_md5" "${me_log}"; then
        echo "Same checksum for ${file_json}, skip yarn install."
    else
        echo "New checksum for ${file_json}, run yarn install."
        yarn_install=true
    fi

    [ ! -d "${G_REPO_DIR}/node_modules" ] && yarn_install=true

    ## 包管理器: 静态前端按 lockfile 选 npm/yarn；后端沿用 yarn（现状不变）
    local pkg_man="yarn"
    if detect_node_framework_static && [[ -f "${G_REPO_DIR}/package-lock.json" ]]; then
        pkg_man="npm"
    fi

    _msg task "Running ${pkg_man} install"
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && return 0

    # Custom build check
    if [ -f "$G_REPO_DIR/build.custom.sh" ]; then
        $G_RUN -u 1000:1000 -v "${G_REPO_DIR}":/app -w /app "${build_image_from:-${ENV_BASE_BUILD_IMAGE:-node:18-slim}}" bash build.custom.sh
        return
    fi

    # Install dependencies
    if ${yarn_install}; then
        if [[ "${pkg_man}" == npm ]]; then
            $G_RUN -u 1000:1000 -v "${G_REPO_DIR}":/app -w /app "${build_image_from:-${ENV_BASE_BUILD_IMAGE:-node:18-slim}}" bash -c "npm install" &&
                echo "$file_json_md5" >>"${me_log}"
        else
            $G_RUN -u 1000:1000 -v "${G_REPO_DIR}":/app -w /app "${build_image_from:-${ENV_BASE_BUILD_IMAGE:-node:18-slim}}" bash -c "yarn install" &&
                echo "$file_json_md5" >>"${me_log}"
        fi
    else
        _msg task "Skip yarn install..."
    fi

    # Determine build option based on namespace
    local build_opt
    case $G_NAMESPACE in
    *uat* | *test*) build_opt=build:stage ;;
    *master* | *main* | *prod*) build_opt=build:prod ;;
    *) build_opt=build ;;
    esac

    ## 静态前端: 命名空间映射的脚本不存在时回退 build（vite/umi 等项目往往只有 build 脚本）
    if detect_node_framework_static && ! jq -e --arg s "$build_opt" '.scripts | has($s)' "${G_REPO_DIR}/package.json" >/dev/null 2>&1; then
        build_opt=build
    fi

    if [[ "${pkg_man}" == npm ]]; then
        $G_RUN -u 1000:1000 -v "${G_REPO_DIR}":/app -w /app "${build_image_from:-${ENV_BASE_BUILD_IMAGE:-node:18-slim}}" bash -c "npm run ${build_opt}"
    else
        $G_RUN -u 1000:1000 -v "${G_REPO_DIR}":/app -w /app "${build_image_from:-${ENV_BASE_BUILD_IMAGE:-node:18-slim}}" bash -c "yarn run ${build_opt}"
    fi

    [ -d "${G_REPO_DIR}"/build ] && rsync -a --delete "${G_REPO_DIR}"/build/ "${G_REPO_DIR}"/dist/
    _msg note "[build] node (${pkg_man}, script=${build_opt})"
}

# Python Build
build_python() {
    _msg task "Running python build"
    if [ -f "$G_REPO_DIR/requirements.txt" ]; then
        pip install -r requirements.txt
    fi
    _msg note "[build] python build"
}

# Android Build
build_android() {
    _msg task "Running android build"
    if [ -f "$G_REPO_DIR/gradlew" ]; then
        chmod +x "$G_REPO_DIR/gradlew"
        "$G_REPO_DIR/gradlew" clean assembleRelease
    else
        _msg warn "No gradlew found in project"
    fi
    _msg note "[build] android build"
}

# iOS Build
build_ios() {
    _msg task "Running iOS build"
    if [ -f "$G_REPO_DIR/Podfile" ]; then
        pod install
        ## 展开 *.xcworkspace 通配符（此前将字面量传给 xcodebuild 必然失败）
        local workspace
        workspace=$(find "$G_REPO_DIR" -maxdepth 1 -name "*.xcworkspace" -print -quit)
        if [ -n "$workspace" ]; then
            xcodebuild -workspace "$workspace" -scheme "Release" build
        else
            _msg warn "No .xcworkspace found in $G_REPO_DIR, skipping xcodebuild"
        fi
    fi
    _msg note "[build] iOS build"
}

# Ruby Build
build_ruby() {
    _msg task "Running ruby build"
    if [ -f "$G_REPO_DIR/Gemfile" ]; then
        bundle install
    fi
    _msg note "[build] ruby build"
}

# Go Build
build_go() {
    _msg task "Running go build"
    go build -v ./...
    _msg note "[build] go build"
}

# C/C++ Build
build_c() {
    _msg task "Running C/C++ build"
    if [ -f "$G_REPO_DIR/CMakeLists.txt" ]; then
        mkdir -p build && cd build || exit
        cmake ..
        make
        cd .. || exit
    elif [ -f "$G_REPO_DIR/Makefile" ]; then
        make
    fi
    _msg note "[build] C/C++ build"
}

# Docker Build
build_docker() {
    _msg task "Running docker build"
    if [ -f "$G_REPO_DIR/Dockerfile" ]; then
        docker build -t "${G_REPO_NAME}:latest" .
    fi
    _msg note "[build] docker build"
}

# Django Build
build_django() {
    _msg task "Running django build"
    if [ -f "$G_REPO_DIR/manage.py" ]; then
        python manage.py collectstatic --noinput
        python manage.py migrate
    fi
    _msg note "[build] django build"
}

# PHP Build
build_php() {
    _msg task "Running php build"
    if [ -f "$G_REPO_DIR/composer.json" ]; then
        composer install --no-dev
    fi
    _msg note "[build] php build"
}

# Shell Build
# 用 shc 将仓库内 *.sh 编译为 native 可执行文件（混淆源码，防明文误读/复制篡改）。
# shc 产物是 glibc/arch 绑定的 native 二进制，跨机器分发受限，但满足部署场景防护。
build_shell() {
    _msg task "Running shell build with shc"
    if ${G_DRY_RUN:-false}; then
        dry_run_note "run shc on shell scripts under ${G_REPO_DIR}"
        return 0
    fi

    command -v shc >/dev/null || {
        _msg warn "shc not installed, installing..."
        _install_packages shc
    }
    command -v shc >/dev/null || {
        _msg error "shc is unavailable, shell build aborted"
        return 1
    }

    local script exit_code=0 first_line shc_src shell_path work_file
    while IFS= read -r script; do
        _msg note "[build] shc encrypting ${script}"
        ## shc 只识别第一行直接是 shell 路径的 shebang，
        ## `#!/usr/bin/env bash` 会让 shc 报 "Unknown shell (env)"。
        ## 对 env shebang 用临时副本改写为绝对路径再编译，不污染源文件。
        shc_src="$script"
        first_line=$(head -n1 "$script")
        if [[ "$first_line" == "#!"*"/usr/bin/env "* ]]; then
            shell_path=$(command -v "${first_line##* }" 2>/dev/null) || {
                _msg warn "[build] cannot resolve interpreter '${first_line##* }' for ${script}, skipping"
                continue
            }
            work_file=$(mktemp)
            printf '#!%s\n' "$shell_path" >"$work_file"
            tail -n +2 "$script" >>"$work_file"
            shc_src="$work_file"
        fi
        shc -rf "$shc_src" -o "${script}.shc" || {
            _msg error "[build] shc failed for ${script}"
            exit_code=1
        }
        [[ -n "${work_file:-}" ]] && rm -f "$work_file"
        work_file=""
    done < <(find "${G_REPO_DIR}" -maxdepth 1 -type f -name '*.sh')

    if [ "$exit_code" -eq 0 ]; then
        _msg ok "[build] shell build completed"
    else
        _msg error "[build] some shell scripts failed to build"
    fi
    return "$exit_code"
}

# Docker operations module for deploy.sh
# Handles Docker login, context management, image building and pushing

docker_login() {
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && return 0
    local lock_login_registry="$G_DATA/cache/.docker.login.${ENV_DOCKER_LOGIN_TYPE:-aliyun}.lock"
    local time_last

    if ${G_DRY_RUN:-false}; then
        dry_run_note "docker login ${ENV_DOCKER_REGISTRY%%/*} (${ENV_DOCKER_LOGIN_TYPE:-aliyun})"
        return 0
    fi
    mkdir -p "${G_DATA}/cache"

    case "${ENV_DOCKER_LOGIN_TYPE:-aliyun}" in
    aws)
        time_last="$(stat -t -c %Y "$lock_login_registry" 2>/dev/null || echo 0)"
        ## Compare the last login time, login again after 12 hours / 比较上一次登陆时间，超过12小时则再次登录
        if [[ "$(date +%s -d '12 hours ago')" -lt "${time_last:-0}" ]]; then
            return 0
        fi
        _msg task "AWS ECR login [${ENV_DOCKER_LOGIN_TYPE:-aliyun}]..."
        if aws ecr get-login-password --profile="${ENV_AWS_PROFILE}" --region "${ENV_REGION_ID:?undefine}" |
            $G_DOCK login --username AWS --password-stdin "${ENV_DOCKER_REGISTRY%%/*}" >/dev/null; then
            touch "$lock_login_registry"
        else
            _msg error "AWS ECR login failed"
            return 1
        fi
        ;;
    *)

        if [[ -f "$lock_login_registry" ]]; then
            return 0
        fi
        if printf '%s\n' "${ENV_DOCKER_PASSWORD}" |
            $G_DOCK login --username="${ENV_DOCKER_USERNAME}" --password-stdin "${ENV_DOCKER_REGISTRY%%/*}"; then
            touch "$lock_login_registry"
        else
            _msg error "Docker login failed"
            return 1
        fi
        ;;
    esac
}

# Common layers for all images
generate_base_dockerfile() {
    # Base images for different languages
    declare -A BASE_IMAGES=(
        ["java"]="eclipse-temurin:17-jre-alpine"
        ["python"]="python:3.11-slim"
        ["node"]="node:18-alpine"
        ["go"]="golang:1.20-alpine"
    )
    cat <<EOF
FROM ${BASE_IMAGES[$1]}

# Common security updates
RUN set -ex && \
    apk update --no-cache && \
    apk upgrade --no-cache

# Add non-root user
RUN adduser -D -u 1000 appuser
USER appuser

# Common environment variables
ENV TZ=Asia/Shanghai
ENV LANG=en_US.UTF-8
EOF
}

# Language specific layers
generate_lang_dockerfile() {
    ## RUN 单数组成员（--gen-dockerfile 触发，parse 组装），无守卫直接执行
    local lang dockerfile
    lang="$(detect_repo_language | cut -d: -f1)"
    dockerfile="Dockerfile.${lang}"

    generate_base_dockerfile "$lang" >"$dockerfile"

    case "$lang" in
    java)
        cat <<EOF >>"$dockerfile"
COPY target/*.jar app.jar
CMD ["java", "-jar", "app.jar"]
EOF
        ;;
    python)
        cat <<EOF >>"$dockerfile"
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "app.py"]
EOF
        ;;
        # 其他语言的特定配置...
    esac
    exit $?
}

detect_repo_language_and_build() {
    ## RUN 单数组成员（--build-buildpacks 触发，parse 组装），无守卫直接执行
    local target_dir="${G_REPO_DIR:-.}"
    local lang_type builder

    # 首先检测语言
    lang_type=$(detect_repo_language)

    # 根据语言选择合适的builder
    case "${lang_type%%:*}" in
    java)
        builder="gcr.io/buildpacks/builder:java"
        ;;
    python)
        builder="gcr.io/buildpacks/builder:python"
        ;;
    node)
        builder="gcr.io/buildpacks/builder:nodejs"
        ;;
    go)
        builder="gcr.io/buildpacks/builder:go"
        ;;
    php)
        builder="paketobuildpacks/builder:base"

        # 创建 project.toml 配置文件来指定 PHP 版本和扩展
        cat >"${target_dir}/project.toml" <<EOF
[[build.env]]
name = "BP_PHP_VERSION"
value = "${PHP_VERSION:-8.3}"  # 默认使用 PHP 8.3，可以通过环境变量覆盖

[[build.env]]
name = "BP_PHP_SERVER"
value = "nginx"  # 使用 nginx 作为 web 服务器

[[build.env]]
name = "BP_PHP_WEB_DIR"
value = "public"  # web 根目录，可以根据项目修改

# PHP 扩展配置
[[build.env]]
name = "BP_PHP_ENABLE_EXTENSIONS"
value = "${PHP_EXTENSIONS:-bcmath,gd,intl,pdo_mysql,redis,zip,soap}"  # 默认扩展列表，可以通过环境变量覆盖

# PECL 扩展配置
[[build.env]]
name = "BP_PHP_ENABLE_PECL_EXTENSIONS"
value = "${PHP_PECL_EXTENSIONS:-}"  # 可以通过环境变量指定 PECL 扩展

# PHP-FPM 配置
[[build.env]]
name = "BP_PHP_FPM_CONFIGURATION"
value = """
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
"""

# PHP INI 配置
[[build.env]]
name = "BP_PHP_INI_CONFIGURATION"
value = """
memory_limit = 512M
max_execution_time = 60
upload_max_filesize = 64M
post_max_size = 64M
"""
EOF

        # 如果存在自定义的 PHP 配置目录，复制配置文件
        if [ -d "${target_dir}/.php/conf.d" ]; then
            mkdir -p "${target_dir}/.php.ini.d"
            cp "${target_dir}/.php/conf.d/"*.ini "${target_dir}/.php.ini.d/" 2>/dev/null || true
        fi
        ;;
    *)
        builder="gcr.io/buildpacks/builder:base"
        ;;
    esac

    # 使用buildpack构建镜像
    pack build "${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}" \
        --builder "$builder" \
        --env BP_INCLUDE_FILES="project.toml" \
        --path "$target_dir"
    exit $?
}
