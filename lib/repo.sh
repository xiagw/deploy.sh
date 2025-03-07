#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# Project configuration and file management module

# Inject files into repository
# @param $1 G_DATA Directory containing data files
# @return 0 on success, non-zero on failure
repo_inject_file() {
    local lang_type="$1" action="${2:-false}" env_inject="${3:-false}"
    $action && return 0

    command -v rsync >/dev/null || _install_packages "$(is_china)" rsync

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
        _msg warning "found $inject_code_path_branch, sync to ${G_REPO_DIR}/"
        rsync -av "$inject_code_path_branch/" "${G_REPO_DIR}/"
    elif [ -d "$inject_code_path" ]; then
        _msg warning "found $inject_code_path, sync to ${G_REPO_DIR}/"
        rsync -av "$inject_code_path/" "${G_REPO_DIR}/"
    fi
    ## frontend (VUE) .env file / 替换前端代码内配置文件
    if [[ "$lang_type" == node ]]; then
        env_files="$(find "${G_REPO_DIR}" -maxdepth 2 -name "${G_NAMESPACE}-*")"
        for file in $env_files; do
            [[ -f "$file" ]] || continue
            echo "Found $file"
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
        echo '<skip>'
        ;;
    overwrite)
        ## 代码库内已存在 Dockerfile 不覆盖
        if [[ -f "${project_dockerfile}" ]]; then
            echo "found Dockerfile in project path, skip copy."
        else
            if [[ -f "${inject_dockerfile_1}" ]]; then
                cp -avf "${inject_dockerfile_1}" "${project_dockerfile}"
            elif [[ -f "${inject_dockerfile_2}" ]]; then
                cp -avf "${inject_dockerfile_2}" "${project_dockerfile}"
            fi
        fi
        ## build image files 打包镜像时需要注入的文件
        if [ -d "${G_REPO_DIR}/root/opt" ]; then
            echo "found exist path root/opt in project path, skip copy"
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
            BUILD_ARG+=" --build-arg MVN_VERSION=${MVN_VERSION} --build-arg JDK_VERSION=${JDK_VERSION}"
            # Check for additional installations
            for install in FFMPEG FONTS LIBREOFFICE; do
                if grep -qi "INSTALL_${install}=true" "${G_REPO_DIR}"/{README,readme}* 2>/dev/null; then
                    BUILD_ARG+=" --build-arg INSTALL_${install}=true"
                fi
            done
            export BUILD_ARG
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
    local lang_files=("pom.xml" "composer.json" "package.json" "requirements.txt" "README.md" "readme.md" "README.txt" "readme.txt")
    local file lang_type

    for file in "${lang_files[@]}"; do
        [[ -f "${G_REPO_DIR}/${file}" ]] || continue
        case ${file,,} in
        pom.xml | build.gradle)
            lang_type="java"
            ;;
        composer.json) lang_type="php" ;;
        package.json) lang_type="node" ;;
        requirements.txt) lang_type="python" ;;
        *)
            lang_type=$(awk -F= '/^project_lang/ {print tolower($2)}' "${G_REPO_DIR}/${file}" | tail -n 1)
            lang_type=${lang_type// /}
            ;;
        esac
        [[ -n $lang_type ]] && break
    done

    lang_type=${lang_type:-unknown}
    echo "${lang_type}"
}

# Export the function
# export -f repo_language_detect

# Version Control System Module
# Handles operations for different version control systems:
# - Git repository management
# - SVN repository management

# Git related functions
setup_git_repo() {
    command -v git >/dev/null || _install_packages "$(is_china)" git
    local git_repo_url git_repo_branch git_repo_group git_repo_name git_repo_dir
    git_repo_url="${1:-}"
    git_repo_branch="${2:-main}"

    # Extract the full group path and repo name from different URL formats
    if [[ $git_repo_url =~ ^git@ ]]; then
        # Handle SSH format: git@host:group/name.git
        git_repo_full_path="${git_repo_url#*:}"
    else
        # Handle URL format: (https|ssh)://host/group/name.git
        git_repo_full_path="${git_repo_url#*://*/}"
    fi

    git_repo_name="$(basename "$git_repo_full_path" .git)"
    git_repo_group="$(dirname "$git_repo_full_path")"
    git_repo_dir="${G_PATH}/builds/${git_repo_group}/${git_repo_name}"
    mkdir -p "$git_repo_dir"

    if cd "$git_repo_dir" && git rev-parse --git-dir >/dev/null 2>&1; then
        _msg step "Updating existing repo: $git_repo_dir, branch: ${git_repo_branch}"
        git clean -fxd
        git fetch --quiet
        git checkout --quiet "${git_repo_branch}"
        git pull --quiet
    else
        _msg step "Cloning git repo: $git_repo_url, branch: ${git_repo_branch}"
        git clone --quiet --depth 1 -b "${git_repo_branch}" "$git_repo_url" "$git_repo_dir" || {
            _msg error "Failed to clone git repo: $git_repo_url"
            return 1
        }
        cd "$git_repo_dir" || return 1
    fi
}

get_git_branch() {
    command -v git >/dev/null || _install_packages "$(is_china)" git
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
    command -v git >/dev/null || _install_packages "$(is_china)" git
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
    command -v git >/dev/null || _install_packages "$(is_china)" git
    if git rev-parse --git-dir >/dev/null 2>&1; then
        git --no-pager log --no-merges --oneline -1
    else
        echo "not-git"
    fi
}

# SVN related functions
setup_svn_repo() {
    command -v svn >/dev/null || _install_packages "$(is_china)" subversion
    local svn_repo_url="${1:-}" svn_repo_name svn_repo_dir="${G_PATH}/builds/${svn_repo_name}"
    svn_repo_name=$(basename "$svn_repo_url")

    if [ -d "$svn_repo_dir/.svn" ]; then
        _msg step "Updating existing repo: $svn_repo_dir"
        (cd "$svn_repo_dir" && svn update) || {
            _msg error "Failed to update svn repo: $svn_repo_url"
            return 1
        }
    else
        _msg step "Checking out new repo: $svn_repo_url"
        svn checkout "$svn_repo_url" "$svn_repo_dir" || {
            _msg error "Failed to checkout svn repo: $svn_repo_url"
            return 1
        }
    fi
}
