#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# Project configuration and file management module

# Overlay files into repository
# @param $1 G_DATA Directory containing data files
# @return 0 on success, non-zero on failure
repo_overlay_files() {
    local lang detected_lang arg_disable_overlay="${arg_disable_overlay:-false}"

    ## ========================================================================
    ## 项目语言探测
    ## 自动探测项目的编程语言、版本和Dockerfile信息
    ## 返回固定三段式: "lang:ver:docker_flag"，字段缺失时留空
    ## (例如: "java:17:docker", "node::docker", "unknown::")
    ## ========================================================================
    detected_lang=$(detect_repo_language) # 完整语言标识: lang:ver:docker
    lang=${detected_lang%%:*}        # 仅语言类型: lang

    ## 研发控制权清单：git 提交以下文件即可接管对应环节；tests 类默认跳过，需指定参数或环境变量启用。
    ## 每行格式: 文件 -> 作用；启用方式
    _msg note "研发可 git 提交以下文件接管对应环节:"
    _msg note "  Dockerfile.base -> 构建基础镜像 (提交即生效)"
    _msg note "    Dockerfile.base 作用: 基础镜像，预装依赖 (node: npm install [package.json]，python: pip install -r requirements.txt, php: composer install [composer.json]) ，首次构建慢，后续复用缓存加速"
    _msg note "    package.json/composer.json/requirements.txt 等文件未变化时直接跳过构建基础镜像；变更时需重新构建基础镜像"
    _msg note "  Dockerfile -> 构建业务镜像 (提交即生效)"
    _msg note "    Dockerfile 作用: 业务镜像，复用 base 镜像，FROM base_image, 仅 COPY 代码/其他文件，构建快"
    _msg note "    构建阶段 (auto 或 --build) 直接使用提交的文件; 未提交则自动生成"
    _msg note "  Dockerfile.tests -> 单元/功能/性能测试 (默认跳过)"
    _msg note "    作用: 测试镜像，镜像内定义测试入口 (CMD/ENTRYPOINT)，deploy.sh 只构建并运行"
    _msg note "    业界框架参考: phpunit / npm test / mvn test / pytest / go test / cargo test / rspec / k6 / jmeter 等"
    _msg note "    启用: --test-unit / --test-function / --test-performance 或 PIPELINE_*_TEST=true"

    ## 研发 git 提交的 Dockerfile/Dockerfile.base 才跳过自动覆盖，按仓库自带方式构建；
    ## Dockerfile.base 为可选组件，允许仅提交单个 Dockerfile（如 java 自带多阶段 Dockerfile）；
    ## 上次自动生成的产物（未跟踪，node/python 两段式）不跳过，重新生成刷新（内容恒定，无副作用）。
    if repo_base_is_custom; then
        ## 列出实际跟踪存在的构建文件（git 索引跟踪但工作区缺失时兜底为通用名）
        local custom_files=()
        [[ -f "${G_REPO_DIR}/Dockerfile" ]] && custom_files+=(Dockerfile)
        [[ -f "${G_REPO_DIR}/Dockerfile.base" ]] && custom_files+=(Dockerfile.base)
        [[ ${#custom_files[@]} -eq 0 ]] && custom_files+=(Dockerfile)
        _msg note "检测到仓库自带 ${custom_files[*]} (git 跟踪)，跳过自动覆盖，按仓库自带方式构建"
        _msg warn "仓库自带构建文件，不使用 CI/CD 程序的自动多阶段构建加速模板"
        _msg warn "研发自行处理：多阶段/分层、依赖缓存、国内镜像（apt/npm/基础镜像）加速，否则构建可能超时或卡死"
        return 0
    fi

    ## dry-run: 只展示覆盖计划，不写仓库（Dockerfile/root/.dockerignore 均跳过）
    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] repo_overlay_files (lang=${lang}):"
        _msg note "  rsync overlay/${G_REPO_NAME}/${G_NAMESPACE:-} -> ${G_REPO_DIR}"
        _msg note "  generate Dockerfile / root/ / .dockerignore if missing"
        return 0
    fi

    command -v rsync >/dev/null || _install_packages rsync

    _msg task "Initializing file overlay"

    # Define paths for overlay
    ## Priority 1: ${G_DATA} paths
    local overlay_code_path="${G_DATA}/overlay/${G_REPO_NAME}"
    local overlay_code_path_branch="${G_DATA}/overlay/${G_REPO_NAME}/${G_NAMESPACE}"

    ## 代码覆盖逻辑：
    ## 1. 优先从 ${G_DATA}/overlay/${G_REPO_NAME}/${G_NAMESPACE} 覆盖（对应项目的对应命名空间[git分支]的代码）
    ## 2. 如果命名空间目录不存在，从 ${G_DATA}/overlay/${G_REPO_NAME} 覆盖（对应项目通用代码）
    ## 3. 使用 rsync 进行文件同步，保持文件属性并覆盖目标文件
    if [ -d "$overlay_code_path_branch" ]; then
        _msg note "overlay code: ${overlay_code_path_branch} -> ${G_REPO_DIR}"
        rsync -a "$overlay_code_path_branch/" "${G_REPO_DIR}/"
    elif [ -d "$overlay_code_path" ]; then
        _msg note "overlay code: ${overlay_code_path} -> ${G_REPO_DIR}"
        rsync -a "$overlay_code_path/" "${G_REPO_DIR}/"
    fi

    ## arg_disable_overlay 参数可强制跳过 Dockerfile 和 root/ 覆盖
    ${arg_disable_overlay:-false} && {
        _msg note "overlay disabled by argument"
        return 0
    }

    ## 1. Dockerfile 覆盖
    ## Dockerfile.multi：多阶段编译型（java/go/php/nginx）
    ## Dockerfile.single：单阶段运行时型（python/mysql/redis）
    ## node：特殊处理，Dockerfile.single 作为 base，生成只含 FROM 的 Dockerfile
    local _single="${G_PATH}/conf/Dockerfile.single"
    local _template="${G_PATH}/conf/Dockerfile.multi"
    ## 依赖 base 两段式：主 Dockerfile = FROM base；base 是否重建由 build_image 按依赖指纹决定
    local base_tag
    base_tag="${ENV_DOCKER_REGISTRY%/}/base:${G_REPO_NAME}-${G_REPO_BRANCH}"
    case "$lang" in
    node)
        if detect_node_framework_static; then
            ## 静态前端（vue-cli/vite/react-scripts/umi）：多阶段构建，nginx 承接静态产物
            ## 生成 conf/Dockerfile.web + nginx-spa.conf，不生成 Dockerfile.base
            local node_framework
            node_framework="$(detect_node_framework)"
            _msg note "node framework=${node_framework} (static frontend), overlay multi-stage nginx Dockerfile"
            cp -f "${G_PATH}/conf/Dockerfile.web" "${G_REPO_DIR}/Dockerfile"
            cp -f "${G_PATH}/conf/nginx-spa.conf" "${G_REPO_DIR}/nginx-spa.conf"
        else
            ## 后端 node（SSR/纯后端，nodejs/next/nuxt）：
            if [[ ! -f "${G_REPO_DIR}/Dockerfile.base" ]]; then
                cp -f "${_single}" "${G_REPO_DIR}/Dockerfile.base"
                _msg note "generate Dockerfile.base: ${_single} -> ${G_REPO_DIR}/Dockerfile.base"
            fi
            echo "FROM ${base_tag}" >"${G_REPO_DIR}/Dockerfile"
            _msg note "generate Dockerfile: FROM ${base_tag} -> ${G_REPO_DIR}/Dockerfile"
        fi
        ;;
    php)
        [[ -f "${_template}" ]] && {
            _msg note "generate Dockerfile: ${_template} -> ${G_REPO_DIR}/Dockerfile"
            cp -f "${_template}" "${G_REPO_DIR}/Dockerfile"
        }
        ;;
    python)
        ## 运行时依赖 base（同 node 后端）：requirements.txt 安装依赖到 base，业务镜像 FROM base
        if [[ ! -f "${G_REPO_DIR}/Dockerfile.base" ]]; then
            cp -f "${_single}" "${G_REPO_DIR}/Dockerfile.base"
            _msg note "generate Dockerfile.base: ${_single} -> ${G_REPO_DIR}/Dockerfile.base"
        fi
        echo "FROM ${base_tag}" >"${G_REPO_DIR}/Dockerfile"
        _msg note "generate Dockerfile: FROM ${base_tag} -> ${G_REPO_DIR}/Dockerfile"
        ;;
    java | go | golang | nginx)
        [[ -f "${_template}" ]] && {
            _msg note "generate Dockerfile: ${_template} -> ${G_REPO_DIR}/Dockerfile"
            cp -f "${_template}" "${G_REPO_DIR}/Dockerfile"
        }
        ;;
    *)
        [[ -f "${_single}" ]] && {
            _msg note "generate Dockerfile: ${_single} -> ${G_REPO_DIR}/Dockerfile"
            cp -f "${_single}" "${G_REPO_DIR}/Dockerfile"
        }
        ;;
    esac

    ## 同时覆盖 .dockerignore（如果不存在）
    if [[ ! -f "${G_REPO_DIR}/.dockerignore" ]]; then
        _msg note "overlay .dockerignore: ${G_PATH}/conf/.dockerignore -> ${G_REPO_DIR}/"
        cp -f "${G_PATH}/conf/.dockerignore" "${G_REPO_DIR}/"
    fi

    ## 覆盖可能改变了仓库（新增 Dockerfile/Dockerfile.base），使语言缓存失效，
    ## 让后续 detect_repo_language 重新探测
    unset G_REPO_LANG_CACHE G_REPO_LANG_CACHE_DIR

    ## 2. Dockerfile 所需 root/ 目录结构覆盖
    local conf_root="${G_PATH}/conf/root" repo_root="${G_REPO_DIR}/root"
    local rsync_opts="rsync -r --exclude=*.cnf"
    ## 创建 root/ 目录（如果不存在）
    mkdir -p "${repo_root}"
    ## 优先级1：从 conf/root/ 覆盖基础目录结构（如果不存在 root/opt）
    if [[ ! -d "${repo_root}/opt" ]] && [[ -d "${conf_root}" ]]; then
        _msg note "overlay root/: ${conf_root} -> ${repo_root}"
        ${rsync_opts} "${conf_root}/" "${repo_root}/"
    fi
    ## 优先级2：从 data/overlay/root/ 覆盖自定义目录结构
    if [[ -d "${G_DATA}/overlay/root" ]]; then
        _msg note "overlay root/: ${G_DATA}/overlay/root -> ${repo_root}"
        ${rsync_opts} "${G_DATA}/overlay/root/" "${repo_root}/"
    fi
}

# Detect the programming language of the project
# Uses various project files to determine the language
# Sets:
#   lang_type: The detected programming language
detect_repo_language() {
    local lang_files=(
        "pom.xml" "build.gradle" "gradle.build" # Java
        "composer.json"                         # PHP
        "package.json"                          # Node.js
        "requirements.txt" "setup.py" "Pipfile" # Python
        "go.mod"                                # Go
        "Cargo.toml"                            # Rust
        "*.csproj"                              # .NET
        "Gemfile" "*.gemspec"                   # Ruby
        "mix.exs"                               # Elixir
        "README.md" "readme.md" "README.txt" "readme.txt"
    )
    local file lang_type version

    ## 结果缓存: 同一次运行内 detect 被调用 3+ 次（repo_overlay / stage_build / stage_code_style），
    ## 每次全仓 find 开销大；缓存到 G_REPO_LANG_CACHE 避免重复扫描。
    if [[ -n "${G_REPO_LANG_CACHE:-}" && "${G_REPO_LANG_CACHE_DIR:-}" == "$G_REPO_DIR" ]]; then
        echo "${G_REPO_LANG_CACHE}"
        return 0
    fi

    # 首先检查特定的项目文件
    for file in "${lang_files[@]}"; do
        # 处理通配符文件
        if [[ $file == *"*"* ]]; then
            file=$(find "${G_REPO_DIR}" -maxdepth 1 -name "${file##*/}" -print -quit)
            [[ -z "$file" ]] && continue
            ## 归一化为相对文件名，避免后续 "${G_REPO_DIR}/${file}" 双重拼接
            file="${file##*/}"
        else
            [[ -f "${G_REPO_DIR}/${file}" ]] || continue
        fi

        case ${file,,} in
        pom.xml)
            lang_type="java"
            # 尝试提取 Java 版本
            # 1. 首先检查是否存在任何 README 文件(兼容旧规范)
            if [ -z "$version" ]; then
                version=$(find "${G_REPO_DIR}" -maxdepth 1 -type f -iname "readme*" -exec awk -F= 'BEGIN{IGNORECASE=1} /^jdk_version/ {print tolower($2)}' {} + | tr -d ' ' | tail -n 1 || true)
            fi

            # 2. 尝试使用 xmllint（如果可用）
            if [ -z "$version" ] && command -v xmllint >/dev/null 2>&1; then
                version=$(xmllint --xpath "string(//*[local-name()='java.version' or local-name()='maven.compiler.source'])" "${G_REPO_DIR}/${file}" 2>/dev/null || true)
            fi

            # 3. 尝试获取 java.version
            [ -z "$version" ] && version=$(grep -E "<java.version>[^<]+" "${G_REPO_DIR}/${file}" 2>/dev/null | sed -E 's/.*<java.version>([^<]+)<.*/\1/' || true)

            # 4. 尝试获取 maven.compiler.source
            [ -z "$version" ] && version=$(grep -E "<maven.compiler.source>[^<]+" "${G_REPO_DIR}/${file}" 2>/dev/null | sed -E 's/.*<maven.compiler.source>([^<]+)<.*/\1/' || true)

            # 5. 尝试获取 maven.compiler.target
            [ -z "$version" ] && version=$(grep -E "<maven.compiler.target>[^<]+" "${G_REPO_DIR}/${file}" 2>/dev/null | sed -E 's/.*<maven.compiler.target>([^<]+)<.*/\1/' || true)
            ## defautl to 8
            # version="${version:-8}"
            ;;
        build.gradle | gradle.build)
            lang_type="java"
            # 从 build.gradle 提取 Java 版本，支持多种格式
            version=$(grep -E "sourceCompatibility.*=.*|targetCompatibility.*=.*|JavaVersion\.(VERSION_)?[0-9]+.*" "${G_REPO_DIR}/${file}" 2>/dev/null | head -n1 || true)
            if [ -n "$version" ]; then
                # 处理不同的版本格式
                if [[ $version =~ JavaVersion\.(VERSION_)?([0-9]+) ]]; then
                    # 处理 JavaVersion.VERSION_11 或 JavaVersion.11 格式
                    version="${BASH_REMATCH[2]}"
                else
                    # 处理 sourceCompatibility = '1.8' 或 targetCompatibility = 11 格式
                    version=$(echo "$version" | grep -oE "[0-9]+(\.[0-9]+)?" || true)
                fi
                # 统一版本格式，如果是 1.8 这样的格式，转换为 8
                if [[ $version =~ ^1\.([0-9]+)$ ]]; then
                    version="${BASH_REMATCH[1]}"
                fi
            fi
            ;;
        composer.json)
            lang_type="php"
            version=$(jq -r '.require.php // empty' "${G_REPO_DIR}/${file}" 2>/dev/null)
            ;;
        package.json)
            lang_type="node"
            local _node_ver
            _node_ver=$(jq -r '.engines.node // empty' "${G_REPO_DIR}/${file}" 2>/dev/null || true)
            ## engines.node 通常是约束表达式（>=8.9），提取第一个纯数字主版本
            version=$(echo "${_node_ver}" | grep -oE '[0-9]+' | head -1 || true)
            ;;
        requirements.txt | setup.py | Pipfile)
            lang_type="python"
            if [[ ${file} == "setup.py" ]]; then
                version=$(grep -E "python_requires.*=.*" "${G_REPO_DIR}/${file}" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+" || true)
            fi
            ;;
        go.mod)
            lang_type="golang"
            version=$(grep -E "^go [0-9]+\.[0-9]+$" "${G_REPO_DIR}/${file}" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+" || true)
            ;;
        Cargo.toml)
            lang_type="rust"
            ;;
        *.csproj)
            lang_type="dotnet"
            version=$(grep -oE 'TargetFramework>net[^<]+' "${G_REPO_DIR}/${file}" 2>/dev/null | sed 's/.*>net//' | head -n 1 || true)
            ;;
        Gemfile | *.gemspec)
            lang_type="ruby"
            if [[ ${file} == "Gemfile" ]]; then
                version=$(grep -E "^ruby ['\"].*['\"]" "${G_REPO_DIR}/${file}" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" || true)
            fi
            ;;
        mix.exs)
            lang_type="elixir"
            ;;
        *)
            # 从 README 文件中查找项目语言标记
            lang_type=$(awk -F= '/^project_lang/ {print tolower($2)}' "${G_REPO_DIR}/${file}" | tail -n 1)
            lang_type=${lang_type// /}
            ;;
        esac
        [[ -n $lang_type ]] && break
    done

    # 如果没有找到特定的项目文件，尝试通过文件扩展名统计来判断
    if [[ -z $lang_type || $lang_type == "unknown" ]]; then
        # 获取仓库中最常见的源代码文件类型
        local most_common_ext
        most_common_ext=$(find "${G_REPO_DIR}" -type f -name "*.*" | grep -v "/\." | grep -oE "\.[^./]+$" | sort | uniq -c | sort -nr | head -n1 | awk '{print $2}' || true)
        case ${most_common_ext} in
        .java) lang_type="java" ;;
        .py) lang_type="python" ;;
        .js | .ts) lang_type="node" ;;
        .php) lang_type="php" ;;
        .go) lang_type="golang" ;;
        .rs) lang_type="rust" ;;
        .cs) lang_type="dotnet" ;;
        .rb) lang_type="ruby" ;;
        .ex | .exs) lang_type="elixir" ;;
        esac
    fi

    lang_type=${lang_type:-unknown}
    ## 固定三段式输出 lang:ver:docker_flag，字段缺失时留空
    ## 例如 java:17:docker / java:8: / node::docker / unknown::
    local docker_flag=""
    for file in "${G_REPO_DIR}"/Dockerfile "${G_REPO_DIR}"/Dockerfile.*; do
        [[ -f "${file}" ]] && {
            docker_flag="docker"
            break
        }
    done

    echo "${lang_type}:${version}:${docker_flag}"
    ## 写入缓存（下次同 G_REPO_DIR 命中直接返回）
    G_REPO_LANG_CACHE="${lang_type}:${version}:${docker_flag}"
    G_REPO_LANG_CACHE_DIR="$G_REPO_DIR"
}

# Detect the frontend framework/build tool of a Node.js project
# Reads dependencies+devDependencies keys from package.json
# Returns: nuxt | next | vuecli | cra | umi | vite | nodejs
detect_node_framework() {
    local pkg="${G_REPO_DIR}/package.json"
    [[ -f "${pkg}" ]] || { echo "nodejs"; return 0; }
    local out
    out="$(jq -r '
        (.dependencies // {}) + (.devDependencies // {}) |
        if has("nuxt") then "nuxt"
        elif has("next") then "next"
        elif has("@vue/cli-service") then "vuecli"
        elif has("react-scripts") then "cra"
        elif has("umi") or ([keys[] | startswith("@umijs/")] | any) then "umi"
        elif has("vite") then "vite"
        else "nodejs" end
    ' "${pkg}" 2>/dev/null)"
    echo "${out:-nodejs}"
}

# true when framework produces pure static assets served by nginx
# (vuecli/vite/cra/umi), false for SSR/backend (nodejs/next/nuxt)
detect_node_framework_static() {
    case "$(detect_node_framework)" in
    vuecli | cra | umi | vite) return 0 ;;
    *) return 1 ;;
    esac
}

# 运行时依赖语言（node 后端/python）是否走"依赖 base"两段式模式
lang_uses_deps_base() {
    case "${1:-}" in
    node | python) return 0 ;;
    *) return 1 ;;
    esac
}

# 依赖声明 manifest 路径（用 JSON/声明文件，不用 lockfile）
lang_dep_manifest() {
    case "${1:-}" in
    node)   echo "${G_REPO_DIR}/package.json" ;;
    php)    echo "${G_REPO_DIR}/composer.json" ;;
    python) if [[ -f "${G_REPO_DIR}/requirements.txt" ]]; then echo "${G_REPO_DIR}/requirements.txt"; else echo "${G_REPO_DIR}/Pipfile"; fi ;;
    *)      echo "" ;;
    esac
}

# 依赖指纹：以声明 manifest 为准（声明变化即重建 base）
lang_dep_hash() {
    local m
    m="$(lang_dep_manifest "${1:-}")"
    [[ -n "${m}" && -f "${m}" ]] && md5sum "${m}" 2>/dev/null | cut -d' ' -f1
}

# 检查 lockfile 与声明 manifest 是否同步；不同步时仅告警（决策仍以声明文件为准）
node_lockfile_warn() {
    local pkg="${G_REPO_DIR}/package.json" lock="${G_REPO_DIR}/package-lock.json"
    [[ -f "${pkg}" ]] || return 0
    [[ -f "${lock}" ]] || return 0
    ## yarn.lock / pnpm-lock.yaml 为文本格式，无法可靠比对，跳过
    if ! jq -e '.packages[""] // empty' "${lock}" >/dev/null 2>&1; then
        return 0
    fi
    local pkg_keys lock_keys
    pkg_keys="$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' "${pkg}" | LC_ALL=C sort -u)"
    lock_keys="$(jq -r '.packages[""] | (.dependencies // {}) + (.devDependencies // {}) | keys[]' "${lock}" | LC_ALL=C sort -u)"
    [[ "${pkg_keys}" == "${lock_keys}" ]] || \
        _msg warn "[node] package-lock.json 与 package.json 依赖不一致，建议重新生成 lockfile"
}

# 仓库中的 Dockerfile.base/Dockerfile 是否为研发提交（git 跟踪中）
# 自动覆盖的产物不跟踪，返回 1；非 git 仓库视为自动覆盖，返回 1
repo_base_is_custom() {
    git -C "${G_REPO_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    git -C "${G_REPO_DIR}" ls-files --error-unmatch Dockerfile >/dev/null 2>&1 ||
        git -C "${G_REPO_DIR}" ls-files --error-unmatch Dockerfile.base >/dev/null 2>&1
}

# Detect repository languages using Docker and GitHub Linguist
# Uses crazymax/linguist Docker image, fallback: "ghcr.io/crazy-max/linguist:latest"
# @return String containing detected languages and their percentages
detect_repo_language_docker() {
    local target_dir="${1:-.}" format="${2:-}" docker_image="crazymax/linguist:latest"

    # Run linguist in Docker container
    case "$format" in
    json)
        docker run --rm -t -v "${target_dir}:/repo" -w /repo "$docker_image" --json
        ;;
    breakdown)
        docker run --rm -t -v "${target_dir}:/repo" -w /repo "$docker_image" --breakdown
        ;;
    *)
        docker run --rm -t -v "${target_dir}:/repo" -w /repo "$docker_image"
        ;;
    esac
}

# Version Control System Module
# Handles operations for different version control systems:
# - Git repository management
# - SVN repository management

# GITHUB_WORKSPACE=/home/ops/.cache/act/1298bce48350a805/hostexecutor
# Git related functions
setup_git_repo() {
    ## RUN 单数组成员（-g/--git-clone 或 GITEA_ACTIONS 触发，parse 组装）
    ## 守卫: Gitea Actions 下无论是否传参都执行；-g 时 git_repo_url 由 parse 必填校验
    local is_gitea="${GITEA_ACTIONS:-false}" git_repo_url="${arg_git_clone_url:-}" git_repo_branch="${arg_git_clone_branch:-main}"
    $is_gitea || [ -n "$git_repo_url" ] || return 0
    local git_repo_group git_repo_name git_repo_dir
    local gitea_server git_repo_full_path
    command -v git >/dev/null || _install_packages git

    # Handle Gitea parameter
    if ${is_gitea}; then
        unset DOCKER_HOST
        # Determine Gitea server, if not default port 22,
        if [[ -n "${ENV_GITEA_SERVER}" ]]; then
            gitea_server="${ENV_GITEA_SERVER}"
        else
            if [[ -z "${GITHUB_SERVER_URL}" ]]; then
                _msg error "Either ENV_GITEA_SERVER or GITHUB_SERVER_URL must be set for Gitea setup"
                return 1
            fi
            gitea_server="${GITHUB_SERVER_URL#*://}"
        fi

        # Validate Gitea server
        if [[ "${gitea_server}" =~ .example.com ]]; then
            _msg error "gitea_server cannot contain 'example' as it is a default value placeholder"
            return 1
        fi

        # Check required environment variables
        if [[ -z "${GITHUB_REPOSITORY}" ]]; then
            _msg error "GITHUB_REPOSITORY environment variable is required for Gitea setup"
            return 1
        fi

        # Set git repository URL and branch
        git_repo_url="ssh://git@${gitea_server}/${GITHUB_REPOSITORY}.git"
        if [[ -n "${GITHUB_REF_NAME:-}" ]]; then
            git_repo_branch="${GITHUB_REF_NAME}"
        fi
    fi
    # Check if we have a valid repository URL
    if [[ -z "$git_repo_url" ]]; then
        _msg error "Git repository URL is required"
        return 1
    fi
    # Extract the full group path and repo name from different URL formats
    if [[ $git_repo_url =~ ^git@ ]]; then
        # Handle SSH format: git@host:port/group/name.git or git@host:group/name.git
        if [[ $git_repo_url =~ ^git@[^:]+:[0-9]+/ ]]; then
            # Has port number
            git_repo_full_path=$(echo "$git_repo_url" | sed -E 's|^git@[^:]+:[0-9]+/(.+)|\1|')
        else
            # No port number
            git_repo_full_path="${git_repo_url#*:}"
        fi
    else
        # Handle URL format: (https|ssh)://host/group/name.git
        git_repo_full_path="${git_repo_url#*://*/}"
    fi

    git_repo_name="$(basename "$git_repo_full_path" .git)"
    git_repo_group="$(dirname "$git_repo_full_path")"
    git_repo_dir="${G_PATH}/builds/${git_repo_group}/${git_repo_name}"
    [ -d "${git_repo_dir}" ] || mkdir -p "$git_repo_dir"

    if [ -d "${git_repo_dir}/.git" ] && cd "$git_repo_dir" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ "$(git rev-parse --git-dir)" = ".git" ]; then
        _msg task "Updating existing repo: "
        echo "  $git_repo_dir, branch: ${git_repo_branch}"
        git clean -fxd
        git fetch --quiet
        git checkout --quiet "${git_repo_branch}"
        git pull --quiet
    else
        _msg task "Cloning git repo:"
        echo "  $git_repo_url, branch: ${git_repo_branch}"
        git clone --quiet --depth 1 -b "${git_repo_branch}" "$git_repo_url" "$git_repo_dir" || {
            _msg error "Failed to clone git repo: $git_repo_url"
            return 1
        }
        cd "$git_repo_dir" || return 1
    fi
}

# Switch an existing workspace repo to a target branch
# Local changes are discarded by default (git clean -fxd), same as setup_git_repo.
# - branch exists (local/remote): fetch + checkout + pull
# - branch missing: create from the default branch (origin/HEAD, fallback main)
# @param $1 branch name
# @param $2 workspace dir
setup_git_branch() {
    ## RUN 单数组成员（-b/--git-branch 触发，parse 组装）
    ## 守卫: 仅 -w/-b（非克隆场景）时切换分支；-g 克隆时分支由 setup_git_repo 处理，此处跳过
    local git_repo_branch="${arg_git_clone_branch:-}" git_repo_dir="${arg_workspace:-${CI_PROJECT_DIR:-$PWD}}"
    [ -n "$git_repo_branch" ] && [ -z "${arg_git_clone_url:-}" ] || return 0
    local default_branch
    command -v git >/dev/null || _install_packages git

    if ! git -C "$git_repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
        _msg error "[repo] not a git repo: $git_repo_dir"
        return 1
    fi

    _msg task "Switch workspace repo to branch: $git_repo_branch"
    _msg note "[repo] discarding local changes in $git_repo_dir"
    git -C "$git_repo_dir" reset --hard HEAD
    git -C "$git_repo_dir" clean -fxd
    git -C "$git_repo_dir" fetch --quiet

    if git -C "$git_repo_dir" rev-parse --quiet --verify "refs/heads/${git_repo_branch}" >/dev/null ||
        git -C "$git_repo_dir" rev-parse --quiet --verify "refs/remotes/origin/${git_repo_branch}" >/dev/null; then
        git -C "$git_repo_dir" checkout --quiet "$git_repo_branch"
        git -C "$git_repo_dir" pull --quiet
    else
        default_branch=$(git -C "$git_repo_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)
        default_branch=${default_branch#refs/remotes/origin/}
        [ -z "$default_branch" ] && default_branch=main
        _msg note "[repo] branch $git_repo_branch not found, creating from $default_branch"
        git -C "$git_repo_dir" checkout --quiet -b "$git_repo_branch" "origin/${default_branch}"
        git -C "$git_repo_dir" push --quiet -u origin "$git_repo_branch" || {
            _msg warn "[repo] failed to push new branch $git_repo_branch upstream"
        }
    fi
    _msg ok "[repo] $git_repo_dir @ $git_repo_branch"
}

get_git_branch() {
    command -v git >/dev/null || _install_packages git
    local branch="${CI_COMMIT_REF_NAME:-}"

    # Try to determine branch name from different sources
    [ -z "$branch" ] && branch=${GITHUB_REF_NAME:-}
    [ -z "$branch" ] && git rev-parse --git-dir >/dev/null 2>&1 && branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    # Default to main if branch is HEAD or not set
    branch=${branch:-main}
    [[ "$branch" == HEAD ]] && branch=main

    echo "$branch"
}

get_git_commit_sha() {
    command -v git >/dev/null || _install_packages git
    local sha=""

    # Try to get commit SHA from different sources
    sha=${CI_COMMIT_SHORT_SHA:-}
    [ -z "$sha" ] && [ -n "${GITHUB_SHA:-}" ] && sha=${GITHUB_SHA:0:8}
    [ -z "$sha" ] && git rev-parse --git-dir >/dev/null 2>&1 && sha=$(git rev-parse HEAD 2>/dev/null | head -c8)

    # If all sources failed, generate a random 8-digit hex
    [ -z "$sha" ] && sha=$(LC_ALL=C head -c20 /dev/urandom | od -An -tx1 | LC_ALL=C tr -d ' \n' | head -c8)

    echo "$sha"
}

get_git_last_commit_message() {
    command -v git >/dev/null || _install_packages git
    if git rev-parse --git-dir >/dev/null 2>&1; then
        git --no-pager log --no-merges --oneline -1
    else
        echo "not-git"
    fi
}

# SVN related functions
setup_svn_repo() {
    ## RUN 单数组成员（-s/--svn-checkout 触发，parse 组装）
    ## 守卫: svn_repo_url 由 parse 必填校验，此处防御
    local svn_repo_url="${arg_svn_checkout_url:-}"
    [ -n "$svn_repo_url" ] || return 0
    local svn_repo_name svn_repo_dir
    svn_repo_name=$(basename "$svn_repo_url")
    svn_repo_dir="${G_PATH}/builds/${svn_repo_name}"

    command -v svn >/dev/null || _install_packages subversion
    if [ -d "$svn_repo_dir/.svn" ]; then
        _msg task "Updating existing repo: $svn_repo_dir"
        (cd "$svn_repo_dir" && svn update) || {
            _msg error "Failed to update svn repo: $svn_repo_url"
            return 1
        }
    else
        _msg task "Checking out new repo: $svn_repo_url"
        svn checkout "$svn_repo_url" "$svn_repo_dir" || {
            _msg error "Failed to checkout svn repo: $svn_repo_url"
            return 1
        }
    fi
}
