#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2154

find_project_config() {
    # 查找项目专用配置 data/conf/<namespace>/<project>.json；不存在且模板存在时自动从模板创建
    # 写入: G_CONF（配置路径）
    local project_path="${G_REPO_GROUP_PATH:-}"
    local namespace project_name
    local project_conf

    ## 如果未提供项目路径，报错退出
    if [[ -z "${project_path}" ]]; then
        _msg error "Project path is required but not provided"
        return 1
    fi

    ## 解析项目路径，提取命名空间和项目名
    namespace="${project_path%%/*}"
    project_name="${project_path##*/}"

    ## 创建项目配置目录
    mkdir -p "${G_DATA}/conf/${namespace}"

    ## 项目专用配置文件
    ## 路径格式: data/conf/namespace/project-name.json
    project_conf="${G_DATA}/conf/${namespace}/${project_name}.json"
    local template_file="${G_PATH}/conf/templates/project-config.json"
    if [[ -f "${project_conf}" ]]; then
        G_CONF="${project_conf}"
        _msg note "load project config: ${G_CONF}"
        ## 读取构建和部署配置覆盖（如果存在）
        _load_project_build_deploy_config "${project_conf}"
    elif [[ -f "${template_file}" ]]; then
        ## 项目专用配置文件不存在，从模板创建默认配置
        command -v jq >/dev/null 2>&1 || _install_packages jq || {
            _msg error "jq is required to create project config: ${project_conf}"
            return 1
        }
        ## 从模板创建配置文件，并替换项目路径
        if ! jq --arg project_path "${project_path}" '.project = $project_path' \
            "${template_file}" >"${project_conf}"; then
            _msg error "Failed to create project config from template: ${template_file}"
            rm -f "${project_conf}"
            return 1
        fi

        G_CONF="${project_conf}"
        _msg note "Created default project config: ${G_CONF}"
        _msg warn "Note: This is a template configuration. Modify it if you need rsync/ftp deployment."
        ## 读取构建和部署配置覆盖（如果存在）
        _load_project_build_deploy_config "${project_conf}"
    else
        _msg error "Project config not found: ${project_conf}"
        _msg error "Template file not found: ${template_file}"
        _msg error "Please create the project configuration file manually."
        return 1
    fi

    ## 拦截模板残留值：任何部署方式都不允许带示例 IP/域名上线
    check_project_config_template "$G_CONF" || return 1
}

check_project_config_template() {
    # 校验项目配置是否残留模板示例值：递归扫全部字符串字段，命中 RFC5737 192.0.2.x / RFC2606 *.example.com
    # 残留返回 1；deploy.method=auto 时降级为 warn（探测链路不读 hosts），显式指定部署方式时残留即阻断
    local config_file="${1:-}"
    [[ -z "$config_file" || ! -f "$config_file" ]] && return 0

    if jq -e '.. | strings | select(test("example\\.com|192\\.0\\.2\\.2|192\\.0\\.2\\.3"))' "$config_file" >/dev/null 2>&1; then
        ## auto 模式由 detect_deployment_method 探测链路决定部署方式，不读 hosts[].* 字段，
        ## 配置残留模板值不影响实际探测，仅警告提示，不阻断流程。
        if [[ "${PROJECT_DEPLOY_METHOD:-auto}" == "auto" ]]; then
            return 0
        fi
        _msg error "================================================================"
        _msg error "ERROR: Configuration file contains example/template values!"
        _msg error "================================================================"
        _msg error "The configuration file appears to be unmodified template:"
        _msg error "  Configuration file: $config_file"
        _msg error ""
        _msg error "Please edit the configuration file and update:"
        _msg error "  - hosts[].host: Replace example IPs (192.0.2.2/192.0.2.3) with real server IPs"
        _msg error "  - hosts[].user: Replace example usernames with real SSH usernames"
        _msg error "  - hosts[].rsync_dest: Replace example paths with real deployment paths"
        _msg error "  - hosts[].db_host: Replace example database hosts with real ones"
        _msg error ""
        _msg error "Deployment cannot proceed with template configuration."
        _msg error "After editing, run the deployment command again."
        return 1
    fi
    return 0
}

config_deploy_init() {
    # 初始化部署环境配置（deploy.env，不存在则从模板复制）
    # 写入: G_ENV / G_DATA / G_PATH；在项目路径确定前调用（G_CONF 由 config_repo_vars 之后设置）
    ## 初始化环境变量配置文件
    mkdir -p "${G_DATA}/conf"
    [[ -f "${G_ENV}" ]] || cp -v "${G_PATH}/conf/templates/deploy.env" "${G_ENV}"

    ## 从 deploy.env 加载所有 ENV_* 环境变量
    # shellcheck disable=SC1090
    source "$G_ENV"

    ## ========================================================================
    ## PATH 环境变量配置
    ## 添加必要的二进制文件目录到 PATH，确保可以找到所需的工具
    ## ========================================================================
    mkdir -p "${G_DATA}/bin"
    local -a paths_append=(
        "/usr/local/sbin"                   # 系统管理员命令
        "/snap/bin"                         # Snap 包二进制文件
        "${G_PATH}/bin"                     # 项目脚本目录
        "${G_DATA}/bin"                     # 数据目录下的二进制文件
        "${G_DATA}/.acme.sh"                # acme.sh 脚本目录
        "$HOME/.local/bin"                  # 用户本地二进制文件
        "$HOME/.acme.sh"                    # 用户 acme.sh 目录
        "$HOME/.config/composer/vendor/bin" # Composer 全局包二进制文件
        "/home/linuxbrew/.linuxbrew/bin"    # Linuxbrew 二进制文件
    )
    for p in "${paths_append[@]}"; do
        if [[ -d "$p" && ":$PATH:" != *":$p:"* ]]; then
            PATH="${PATH:+"$PATH:"}$p"
        fi
    done
    export PATH
}

_load_project_build_deploy_config() {
    # 从项目配置加载构建/部署方式
    # 写入: PROJECT_BUILD_METHOD(auto/docker/system)、PROJECT_DEPLOY_METHOD(auto/k8s/docker/rsync)、
    #       PROJECT_PREFER_DOCKER、PROJECT_PREFER_K8S
    local config_file="${1:-}"
    [[ -z "$config_file" || ! -f "$config_file" ]] && return

    ## 读取构建配置
    if jq -e '.build' "$config_file" >/dev/null 2>&1; then
        PROJECT_BUILD_METHOD=$(jq -r 'if .build.method == null then "auto" else .build.method end' "$config_file")
        PROJECT_PREFER_DOCKER=$(jq -r 'if .build.prefer_docker == null then true else .build.prefer_docker end' "$config_file")
        export PROJECT_BUILD_METHOD PROJECT_PREFER_DOCKER
    else
        PROJECT_BUILD_METHOD="auto"
        PROJECT_PREFER_DOCKER=true
        export PROJECT_BUILD_METHOD PROJECT_PREFER_DOCKER
    fi

    ## 读取部署配置
    if jq -e '.deploy' "$config_file" >/dev/null 2>&1; then
        PROJECT_DEPLOY_METHOD=$(jq -r 'if .deploy.method == null then "auto" else .deploy.method end' "$config_file")
        PROJECT_PREFER_K8S=$(jq -r 'if .deploy.prefer_k8s == null then true else .deploy.prefer_k8s end' "$config_file")
        export PROJECT_DEPLOY_METHOD PROJECT_PREFER_K8S
    else
        PROJECT_DEPLOY_METHOD="auto"
        PROJECT_PREFER_K8S=true
        export PROJECT_DEPLOY_METHOD PROJECT_PREFER_K8S
    fi
}

config_deploy_setup() {
    # 设置部署环境：创建 SSH 密钥对、配置目录符号链接、设置文件权限
    ## dry-run: 不生成SSH密钥、不创建符号链接（仅本地环境配置，预览无意义）
    dry_run_skip "config_deploy_setup (ssh keys, $HOME symlinks)，dry-run 跳过" && return 0

    ## 需要创建符号链接的配置目录列表
    local conf_dirs=(".ssh" ".acme.sh" ".aws" ".kube" ".aliyun")

    ## ========================================================================
    ## SSH 密钥配置
    ## ========================================================================
    local ssh_dir="${G_DATA}/.ssh"
    if [[ ! -d "${ssh_dir}" ]]; then
        ## 创建SSH目录并设置权限（仅所有者可访问）
        mkdir -m 700 "${ssh_dir}"
        _msg warn "Generate ssh key file for gitlab-runner: ${ssh_dir}/id_ed25519"
        _msg note "Please: cat $ssh_dir/id_ed25519.pub >> [dest_server]:~/.ssh/authorized_keys"
        ## 生成ED25519 SSH密钥对（无密码）
        ssh-keygen -t ed25519 -N '' -f "${ssh_dir}/id_ed25519" || _msg error "Failed to generate SSH key"
    fi

    ## 确保用户主目录下的 .ssh 目录存在
    [[ -d "$HOME/.ssh" ]] || mkdir -m 700 "$HOME/.ssh"

    ## 将SSH密钥文件链接到用户主目录（如果不存在）
    if compgen -G "${ssh_dir}/*" >/dev/null; then
        for file in "$ssh_dir"/*; do
            [[ -f "$HOME/.ssh/$(basename "${file}")" ]] && continue
            echo "Link $file to $HOME/.ssh/"
            chmod 600 "${file}" # 设置适当的权限
            ln -s "${file}" "$HOME/.ssh/"
        done
    fi

    ## ========================================================================
    ## 配置文件目录链接
    ## 将数据目录下的配置目录链接到用户主目录，方便工具访问
    ## ========================================================================
    for dir in "${conf_dirs[@]}"; do
        [[ ! -d "$HOME/${dir}" && -d "${G_DATA}/${dir}" ]] && ln -sf "${G_DATA}/${dir}" "$HOME/"
    done

    ## 链接 glab 配置目录（GitLab CLI，替代 python-gitlab）；确保父目录存在
    if [[ ! -d "$HOME/.config/glab-cli" && -d "${G_DATA}/glab-cli" ]]; then
        mkdir -p "$HOME/.config"
        ln -sf "${G_DATA}/glab-cli" "$HOME/.config/glab-cli"
    fi

    return 0
}