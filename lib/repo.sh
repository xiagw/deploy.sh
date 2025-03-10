#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# Project configuration and file management module

# Inject files into repository
# @param $1 G_DATA Directory containing data files
# @return 0 on success, non-zero on failure
repo_inject_file() {
    local lang_type="$1" action="${2:-false}" env_inject="${3:-false}"
    $action && return 0

    command -v rsync >/dev/null || _install_packages "$IS_CHINA" rsync

    _msg step "[inject] from ${G_DATA}/inject/"

    # Define paths for injection
    local inject_code_path="${G_DATA}/inject/${G_REPO_NAME}"
    local inject_code_path_branch="${G_DATA}/inject/${G_REPO_NAME}/${G_NAMESPACE}"
    ## 项目git代码库内如果已存在 Dockerfile
    local project_dockerfile="${G_REPO_DIR}/Dockerfile"
    ## git库内没有 Dockerfile 时尝试从 1. data/ 2. conf/ 自动注入 Dockerfile
    local inject_dockerfile_1="${G_DATA}/dockerfile/Dockerfile.${lang_type}"
    local inject_dockerfile_2="${G_PATH}/conf/dockerfile/Dockerfile.${lang_type}"
    ## git库内 注入 root/ 目录
    local inject_root_path="${G_PATH}/conf/dockerfile/root"
    ## Java 项目打包镜像时注入的 settings.xml 文件
    local inject_setting="${G_DATA}/dockerfile/settings.xml"
    ## 打包镜像时注入的 .dockerignore 文件
    local inject_dockerignore="${G_PATH}/conf/dockerfile/.dockerignore"
    ## 打包镜像时注入的 /opt/init.sh 文件 容器启动时初始化配置文件 init.sh 可以注入 /etc/hosts 等配置
    local inject_init="${G_DATA}/dockerfile/init.sh"
    ## 替换git库部分代码文件
    if [ -d "$inject_code_path_branch" ]; then
        _msg warning "Found custom code in $inject_code_path_branch, syncing to ${G_REPO_DIR}/"
        rsync -av "$inject_code_path_branch/" "${G_REPO_DIR}/"
    elif [ -d "$inject_code_path" ]; then
        _msg warning "Found custom code in $inject_code_path, syncing to ${G_REPO_DIR}/"
        rsync -av "$inject_code_path/" "${G_REPO_DIR}/"
    fi
    ## frontend (VUE) .env file / 替换前端代码内配置文件
    if [[ "$lang_type" == node ]]; then
        env_files="$(find "${G_REPO_DIR}" -maxdepth 2 -name "${G_NAMESPACE}-*")"
        for file in $env_files; do
            [[ -f "$file" ]] || continue
            echo "Located environment file: $file"
            if [[ "$file" =~ 'config' ]]; then
                cp -avf "$file" "${file/${G_NAMESPACE}./}" # vue2.x
            else
                cp -avf "$file" "${file/${G_NAMESPACE}/}" # vue3.x
            fi
        done
    fi
    ## 检查并注入 .dockerignore 文件
    if [[ -f "${project_dockerfile}" && ! -f "${G_REPO_DIR}/.dockerignore" ]]; then
        cp -avf "${inject_dockerignore}" "${G_REPO_DIR}/"
    fi

    ## data/deploy.env:ENV_INJECT, default is keep， 使用 data/ 目录下的全局模板文件替换项目文件，例如 dockerfile init.sh等
    ${env_inject:-false} && ENV_INJECT=keep

    echo "ENV_INJECT: ${ENV_INJECT:-keep}"
    case ${ENV_INJECT:-keep} in
    keep)
        echo "Keeping existing configuration, no files will be overwritten."
        ;;
    overwrite)
        ## 代码库内已存在 Dockerfile 不覆盖
        if [[ -f "${project_dockerfile}" ]]; then
            echo "Dockerfile already exists in project directory, skipping copy operation."
        else
            if [[ -f "${inject_dockerfile_1}" ]]; then
                cp -avf "${inject_dockerfile_1}" "${project_dockerfile}"
            elif [[ -f "${inject_dockerfile_2}" ]]; then
                cp -avf "${inject_dockerfile_2}" "${project_dockerfile}"
            fi
        fi
        ## build image files 打包镜像时需要注入的文件
        if [ -d "${G_REPO_DIR}/root/opt" ]; then
            echo "Directory root/opt already exists in project path, skipping copy operation"
        else
            cp -af "${inject_root_path}" "$G_REPO_DIR/"
        fi
        if [[ -f "${inject_init}" && -d "$G_REPO_DIR/root/opt/" ]]; then
            cp -avf "${inject_init}" "$G_REPO_DIR/root/opt/"
        fi

        case "${lang_type}" in
        java)
            # Copy Java settings.xml if it exists 优先查找 data/ 目录
            [[ -f "${inject_setting}" ]] && cp -avf "${inject_setting}" "${G_REPO_DIR}/"

            # Read JDK version from README files
            jdk_version=$(grep -iE 'jdk_version=([0-9.]+)' "${G_REPO_DIR}"/{README,readme}* 2>/dev/null | sed -E 's/.*=([0-9.]+).*/\1/' | tail -n1)

            # Set Maven and JDK versions based on JDK version
            case "${jdk_version:-}" in
            1.7 | 7) MVN_VERSION="3.6-jdk-7" && JDK_VERSION="7" ;;
            1.8 | 8) MVN_VERSION="3.8-amazoncorretto-8" && JDK_VERSION="8" ;;
            11) MVN_VERSION="3.9-amazoncorretto-11" && JDK_VERSION="11" ;;
            17) MVN_VERSION="3.9-amazoncorretto-17" && JDK_VERSION="17" ;;
            21) MVN_VERSION="3.9-amazoncorretto-21" && JDK_VERSION="21" ;;
            *) MVN_VERSION="3.8-amazoncorretto-8" && JDK_VERSION="8" ;; # Default
            esac

            # Adjust versions if using Docker mirror
            if [ -n "${ENV_DOCKER_MIRROR}" ]; then
                MVN_VERSION="maven-${MVN_VERSION}"
                [[ "${JDK_VERSION}" == "7" ]] && JDK_VERSION="openjdk-7" || JDK_VERSION="amazoncorretto-${JDK_VERSION}"
            fi

            # Add build arguments
            G_ARGS+=" --build-arg MVN_VERSION=${MVN_VERSION} --build-arg JDK_VERSION=${JDK_VERSION}"
            # Check for additional installations
            for install in FFMPEG FONTS LIBREOFFICE; do
                if grep -qi "INSTALL_${install}=true" "${G_REPO_DIR}"/{README,readme}* 2>/dev/null; then
                    G_ARGS+=" --build-arg INSTALL_${install}=true"
                fi
            done
            export G_ARGS
            ;;
        esac
        ;;
    remove)
        echo 'Removing Dockerfile (disable docker build)'
        rm -f "${project_dockerfile}"
        ;;
    create)
        ## TODO
        echo "Generating docker-compose.yml (enable deploy docker-compose)"
        echo '## deploy with docker-compose' >>"${G_REPO_DIR}/docker-compose.yml"
        ;;
    esac
}

# Export the function
# export -f repo_inject_file

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
            if compgen -G "${G_REPO_DIR}/${file}" >/dev/null; then
                file=$(ls "${G_REPO_DIR}/${file}" | head -n 1)
            else
                continue
            fi
        else
            [[ -f "${G_REPO_DIR}/${file}" ]] || continue
        fi

        case ${file,,} in
        pom.xml)
            lang_type="java"
            # 尝试提取 Java 版本
            if command -v xmllint >/dev/null 2>&1; then
                version=$(xmllint --xpath "string(//*[local-name()='java.version' or local-name()='maven.compiler.source'])" "${G_REPO_DIR}/${file}" 2>/dev/null)
            fi
            ;;
        build.gradle | gradle.build)
            lang_type="java"
            # 可以从 build.gradle 提取 Java 版本
            version=$(grep -E "sourceCompatibility.*=.*" "${G_REPO_DIR}/${file}" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+")
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
    lang_type="${lang_type}:${version}:"
    # 如果检测到 Dockerfile，附加 docker 类型
    for file in "${G_REPO_DIR}"/Dockerfile "${G_REPO_DIR}"/Dockerfile.*; do
        [[ -f "${file}" ]] && {
            lang_type="${lang_type}docker"
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

# Git related functions
setup_git_repo() {
    local is_gitea="${1:-false}" git_repo_url="$2" git_repo_branch="${3:-main}" git_repo_group git_repo_name git_repo_dir
    command -v git >/dev/null || _install_packages "$IS_CHINA" git

    # Handle Gitea parameter
    if ${is_gitea}; then
        unset DOCKER_HOST
        # Determine Gitea server
        if [[ -z "${ENV_GITEA_SERVER:-}" ]]; then
            if [[ -z "${GITHUB_SERVER_URL:-}" ]]; then
                _msg error "Either ENV_GITEA_SERVER or GITHUB_SERVER_URL must be set for Gitea setup"
                return 1
            fi
            ENV_GITEA_SERVER="${GITHUB_SERVER_URL#*://}"
        fi

        # Validate Gitea server
        if [[ "${ENV_GITEA_SERVER}" =~ gitea.example.com ]]; then
            _msg error "ENV_GITEA_SERVER cannot contain 'example' as it is a default value placeholder"
            return 1
        fi

        # Check required environment variables
        if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
            _msg error "GITHUB_REPOSITORY environment variable is required for Gitea setup"
            return 1
        fi

        # Set git repository URL and branch
        git_repo_url="ssh://git@${ENV_GITEA_SERVER}/${GITHUB_REPOSITORY}.git"
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
    mkdir -p "$git_repo_dir"

    if [ -d "${git_repo_dir}/.git" ] && cd "$git_repo_dir" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ "$(git rev-parse --git-dir)" = ".git" ]; then
        _msg step "[repo] Updating existing repo: $git_repo_dir, branch: ${git_repo_branch}"
        git clean -fxd
        git fetch --quiet
        git checkout --quiet "${git_repo_branch}"
        git pull --quiet
    else
        _msg step "[repo] Cloning git repo: $git_repo_url, branch: ${git_repo_branch}"
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
