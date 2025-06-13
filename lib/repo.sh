#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# Project configuration and file management module

# Inject files into repository
# @param $1 G_DATA Directory containing data files
# @return 0 on success, non-zero on failure
repo_inject_file() {
    local lang="$1" arg_disable_inject="${2:-false}"

    command -v rsync >/dev/null || _install_packages "$IS_CHINA" rsync

    _msg step "[inject] Initializing file injection..."

    # Define paths for injection
    ## Priority 1: ${G_DATA} paths
    local inject_code_path="${G_DATA}/inject/${G_REPO_NAME}"
    local inject_code_path_branch="${G_DATA}/inject/${G_REPO_NAME}/${G_NAMESPACE}"

    ## 代码注入逻辑：
    ## 1. 优先从 ${G_DATA}/inject/${G_REPO_NAME}/${G_NAMESPACE} 注入（对应项目的对应命名空间[git分支]的代码）
    ## 2. 如果命名空间目录不存在，从 ${G_DATA}/inject/${G_REPO_NAME} 注入（对应项目通用代码）
    ## 3. 使用 rsync 进行文件同步，保持文件属性并覆盖目标文件
    local inject_src
    if [ -d "$inject_code_path_branch" ]; then
        inject_src="$inject_code_path_branch"
    elif [ -d "$inject_code_path" ]; then
        inject_src="$inject_code_path"
    fi
    echo "Found custom code in $inject_src/, syncing to ${G_REPO_DIR}/"
    rsync -a "$inject_src/" "${G_REPO_DIR}/"

    ${arg_disable_inject:-false} && ENV_INJECT=keep

    ## 根据 ENV_INJECT 变量值（默认为 keep）控制配置文件注入行为：
    ## - keep: 保持现有配置不变
    ## - overwrite: 注入 Dockerfile 和 root 目录结构（优先使用 data/dockerfile/，其次是 conf/dockerfile/）
    ## - remove: 移除 Dockerfile
    ## - create: 创建 docker-compose.yml
    echo "ENV_INJECT: ${ENV_INJECT:-keep}"
    case ${ENV_INJECT:-keep} in
    keep)
        echo "Keeping existing configuration, no files will be overwritten."
        ;;
    overwrite)
        ## 1. Dockerfile 注入
        ## 按优先级查找对应语言的 Dockerfile 模板
        if [[ -f "${G_DATA}/dockerfile/Dockerfile.${lang}" ]]; then
            cp -f "${G_DATA}/dockerfile/Dockerfile.${lang}" "${G_REPO_DIR}/Dockerfile"
        elif [[ -f "${G_PATH}/conf/dockerfile/Dockerfile.${lang}" ]]; then
            cp -f "${G_PATH}/conf/dockerfile/Dockerfile.${lang}" "${G_REPO_DIR}/Dockerfile"
        fi

        if [[ -f "${G_PATH}/conf/dockerfile/Dockerfile.base.${lang}" ]]; then
            case "$lang" in
            node)
                echo "Checking package.json hash..."
                hash_now="$(md5sum "${G_REPO_DIR}/package.json" | cut -d' ' -f1)"
                mkdir -p "${G_DATA}/hash_saved"
                hash_saved="$(cat "${G_DATA}/hash_saved/${G_REPO_NAME}-${G_REPO_BRANCH}-md5" || true)"
                if [[ "$hash_now" = "$hash_saved" ]]; then
                    rm -rf "${G_REPO_DIR}/root" "${G_REPO_DIR}/Dockerfile.base"
                else
                    echo "Copying Dockerfile.base.${lang}..."
                    cp -f "${G_PATH}/conf/dockerfile/Dockerfile.base.${lang}" "${G_REPO_DIR}/Dockerfile.base"
                    echo "${hash_now}" >"${G_DATA}/hash_saved/${G_REPO_NAME}-${G_REPO_BRANCH}-md5"
                fi
                base_tag="${ENV_DOCKER_REGISTRY%/*}/aa:${G_REPO_NAME}-${G_REPO_BRANCH}"
                echo "FROM ${base_tag}" >"${G_REPO_DIR}/Dockerfile"
                ;;
            esac
        fi

        ## 同时注入 .dockerignore（如果不存在）
        [[ -f "${G_REPO_DIR}/Dockerfile" && ! -f "${G_REPO_DIR}/.dockerignore" ]] &&
            cp -f "${G_PATH}/conf/dockerfile/.dockerignore" "${G_REPO_DIR}/"

        ## 2. Dockerfile 所需 root/ 目录结构注入
        local conf_root="${G_PATH}/conf/dockerfile/root" repo_root="${G_REPO_DIR}/root"
        local rsync_opts="rsync -r --exclude=*.cnf"
        ## 创建 root/ 目录（如果不存在）
        mkdir -p "${repo_root}"
        ## 优先级1：从 conf/dockerfile/root/ 注入基础目录结构（如果不存在 root/opt）
        if [[ ! -d "${repo_root}/opt" ]] && [[ -d "${conf_root}" ]]; then
            ${rsync_opts} "${conf_root}/" "${repo_root}/"
        fi
        ## 优先级2：从 data/dockerfile/root/ 注入自定义目录结构
        if [[ -d "${G_DATA}/dockerfile/root" ]]; then
            ${rsync_opts} "${G_DATA}/dockerfile/root/" "${repo_root}/"
        fi
        ;;
    remove)
        echo 'Removing Dockerfile (disable docker build)'
        rm -f "${G_REPO_DIR}/Dockerfile"
        ;;
    create)
        ## TODO
        echo "Generating docker-compose.yml (enable deploy docker-compose)"
        echo '## deploy with docker-compose' >>"${G_REPO_DIR}/docker-compose.yml"
        ;;
    esac
}

# Detect the programming language of the project
# Uses various project files to determine the language
# Sets:
#   lang_type: The detected programming language
repo_language_detect() {
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

    # 首先检查特定的项目文件
    for file in "${lang_files[@]}"; do
        # 处理通配符文件
        if [[ $file == *"*"* ]]; then
            file=$(find "${G_REPO_DIR}" -maxdepth 1 -name "${file##*/}" -print -quit)
            [[ -z "$file" ]] && continue
        else
            [[ -f "${G_REPO_DIR}/${file}" ]] || continue
        fi

        case ${file,,} in
        pom.xml)
            lang_type="java"
            # 尝试提取 Java 版本
            # 1. 首先检查是否存在任何 README 文件(兼容旧规范)
            if [ -z "$version" ]; then
                version=$(find "${G_REPO_DIR}" -maxdepth 1 -type f -iname "readme*" -exec awk -F= 'BEGIN{IGNORECASE=1} /^jdk_version/ {print tolower($2)}' {} + | tr -d ' ' | tail -n 1)
            fi

            # 2. 尝试使用 xmllint（如果可用）
            if [ -z "$version" ] && command -v xmllint >/dev/null 2>&1; then
                version=$(xmllint --xpath "string(//*[local-name()='java.version' or local-name()='maven.compiler.source'])" "${G_REPO_DIR}/${file}" 2>/dev/null)
            fi

            # 3. 尝试获取 java.version
            [ -z "$version" ] && version=$(grep -E "<java.version>[^<]+" "${G_REPO_DIR}/${file}" 2>/dev/null | sed -E 's/.*<java.version>([^<]+)<.*/\1/')

            # 4. 尝试获取 maven.compiler.source
            [ -z "$version" ] && version=$(grep -E "<maven.compiler.source>[^<]+" "${G_REPO_DIR}/${file}" 2>/dev/null | sed -E 's/.*<maven.compiler.source>([^<]+)<.*/\1/')

            # 5. 尝试获取 maven.compiler.target
            [ -z "$version" ] && version=$(grep -E "<maven.compiler.target>[^<]+" "${G_REPO_DIR}/${file}" 2>/dev/null | sed -E 's/.*<maven.compiler.target>([^<]+)<.*/\1/')
            ## defautl to 8
            # version="${version:-8}"
            ;;
        build.gradle | gradle.build)
            lang_type="java"
            # 从 build.gradle 提取 Java 版本，支持多种格式
            version=$(grep -E "sourceCompatibility.*=.*|targetCompatibility.*=.*|JavaVersion\.(VERSION_)?[0-9]+.*" "${G_REPO_DIR}/${file}" 2>/dev/null | head -n1)
            if [ -n "$version" ]; then
                # 处理不同的版本格式
                if [[ $version =~ JavaVersion\.(VERSION_)?([0-9]+) ]]; then
                    # 处理 JavaVersion.VERSION_11 或 JavaVersion.11 格式
                    version="${BASH_REMATCH[2]}"
                else
                    # 处理 sourceCompatibility = '1.8' 或 targetCompatibility = 11 格式
                    version=$(echo "$version" | grep -oE "[0-9]+(\.[0-9]+)?")
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
            version=$(jq -r '.engines.node // empty' "${G_REPO_DIR}/${file}" 2>/dev/null)
            ;;
        requirements.txt | setup.py | Pipfile)
            lang_type="python"
            if [[ ${file} == "setup.py" ]]; then
                version=$(grep -E "python_requires.*=.*" "${G_REPO_DIR}/${file}" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+")
            fi
            ;;
        go.mod)
            lang_type="golang"
            version=$(grep -E "^go [0-9]+\.[0-9]+$" "${G_REPO_DIR}/${file}" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+")
            ;;
        Cargo.toml)
            lang_type="rust"
            ;;
        *.csproj)
            lang_type="dotnet"
            version=$(grep -oP '(?<=TargetFramework>net)[^<]+' "${G_REPO_DIR}/${file}" 2>/dev/null)
            ;;
        Gemfile | *.gemspec)
            lang_type="ruby"
            if [[ ${file} == "Gemfile" ]]; then
                version=$(grep -E "^ruby ['\"].*['\"]" "${G_REPO_DIR}/${file}" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
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
        most_common_ext=$(find "${G_REPO_DIR}" -type f -name "*.*" | grep -v "/\." | grep -oE "\.[^./]+$" | sort | uniq -c | sort -nr | head -n1 | awk '{print $2}')
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
    # 如果检测到版本信息，将其附加到语言类型后
    lang_type+=":${version}"
    # 如果检测到 Dockerfile，附加 docker 类型
    for file in "${G_REPO_DIR}"/Dockerfile "${G_REPO_DIR}"/Dockerfile.*; do
        [[ -f "${file}" ]] && {
            lang_type+=":docker"
            break
        }
    done

    echo "${lang_type}"
}

# Export the function
# export -f repo_language_detect

# Detect repository languages using Docker and GitHub Linguist
# Uses crazymax/linguist Docker image, fallback: "ghcr.io/crazy-max/linguist:latest"
# @return String containing detected languages and their percentages
repo_language_detect_docker() {
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

# Export the function
# export -f repo_language_detect_docker

# Version Control System Module
# Handles operations for different version control systems:
# - Git repository management
# - SVN repository management

# GITHUB_WORKSPACE=/home/ops/.cache/act/1298bce48350a805/hostexecutor
# Git related functions
setup_git_repo() {
    local is_gitea="${1:-false}" git_repo_url="$2" git_repo_branch="${3:-main}" git_repo_group git_repo_name git_repo_dir
    command -v git >/dev/null || _install_packages "$IS_CHINA" git

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
        _msg step "[repo] Updating existing repo: "
        echo "  $git_repo_dir, branch: ${git_repo_branch}"
        git clean -fxd
        git fetch --quiet
        git checkout --quiet "${git_repo_branch}"
        git pull --quiet
    else
        _msg step "[repo] Cloning git repo:"
        echo "  $git_repo_url, branch: ${git_repo_branch}"
        git clone --quiet --depth 1 -b "${git_repo_branch}" "$git_repo_url" "$git_repo_dir" || {
            _msg error "Failed to clone git repo: $git_repo_url"
            return 1
        }
        cd "$git_repo_dir" || return 1
    fi
}

get_git_branch() {
    command -v git >/dev/null || _install_packages "$IS_CHINA" git
    local branch="${CI_COMMIT_REF_NAME:-}"

    # Try to determine branch name from different sources
    [ -z "$branch" ] && branch=${GITHUB_REF_NAME:-}
    [ -z "$branch" ] && git rev-parse --git-dir >/dev/null 2>&1 && branch=$(git rev-parse --abbrev-ref HEAD)

    # Default to main if branch is HEAD or not set
    branch=${branch:-main}
    [[ "$branch" == HEAD ]] && branch=main

    echo "$branch"
}

get_git_commit_sha() {
    command -v git >/dev/null || _install_packages "$IS_CHINA" git
    local sha=""

    # Try to get commit SHA from different sources
    sha=${CI_COMMIT_SHORT_SHA:-}
    [ -z "$sha" ] && [ -n "${GITHUB_SHA:-}" ] && sha=${GITHUB_SHA:0:8}
    [ -z "$sha" ] && git rev-parse --git-dir >/dev/null 2>&1 && sha=$(git rev-parse HEAD | head -c8)

    # If all sources failed, generate a random 8-digit hex
    [ -z "$sha" ] && sha=$(LC_ALL=C head -c20 /dev/urandom | od -An -tx1 | LC_ALL=C tr -d ' \n' | head -c8)

    echo "$sha"
}

get_git_last_commit_message() {
    command -v git >/dev/null || _install_packages "$IS_CHINA" git
    if git rev-parse --git-dir >/dev/null 2>&1; then
        git --no-pager log --no-merges --oneline -1
    else
        echo "not-git"
    fi
}

# SVN related functions
setup_svn_repo() {
    [ -z "$1" ] && return
    local svn_repo_url="${1:-}" svn_repo_name svn_repo_dir="${G_PATH}/builds/${svn_repo_name}"
    svn_repo_name=$(basename "$svn_repo_url")

    command -v svn >/dev/null || _install_packages "$IS_CHINA" subversion
    if [ -d "$svn_repo_dir/.svn" ]; then
        _msg step "[repo] Updating existing repo: $svn_repo_dir"
        (cd "$svn_repo_dir" && svn update) || {
            _msg error "Failed to update svn repo: $svn_repo_url"
            return 1
        }
    else
        _msg step "[repo] Checking out new repo: $svn_repo_url"
        svn checkout "$svn_repo_url" "$svn_repo_dir" || {
            _msg error "Failed to checkout svn repo: $svn_repo_url"
            return 1
        }
    fi
}
