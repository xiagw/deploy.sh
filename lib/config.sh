#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2154

################################################################################
# 函数: find_project_config
# 描述: 查找项目配置文件，仅使用项目专用配置
# 参数:
#   $1 - project_path: 项目路径，格式为 "namespace/project_name"
# 返回: 配置文件路径（通过全局变量 G_CONF 返回）
# 说明:
#   - 仅使用项目专用配置: data/conf/namespace/project-name.json
#   - 如果配置文件不存在且模板存在，自动从模板创建
#   - 自动创建后支持auto或修改配置后都可以继续部署
#   优势:
#     - 支持成千上万项目，每个项目独立配置文件
#     - 避免单文件过大导致的性能问题
#     - 减少版本冲突，不同项目可以独立管理配置
#     - 更好的权限控制和安全性
################################################################################
find_project_config() {
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
        ## 读取构建和部署配置覆盖（如果存在）
        _load_project_build_deploy_config "${project_conf}"
    elif [[ -f "${template_file}" ]]; then
        ## 项目专用配置文件不存在，从模板创建默认配置
        command -v jq || _install_packages jq
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

################################################################################
# 函数: check_project_config_template
# 描述: 校验项目配置文件中是否残留模板示例值
# 说明:
#   - 模板示例值使用 RFC 5737 文档保留地址 192.0.2.2/192.0.2.3（全球不可路由）
#     与 RFC 2606 保留域名 *.example.com，物理上不可能被真实生产环境使用。
#   - 递归扫描全量字符串字段，覆盖 .host/.db_host 等任意位置的残留。
#   - 在 find_project_config 公共层拦截；当 deploy.method=auto 时降级为 warn（探测链路不读 hosts），
#     仅显式指定部署方式（k8s/rsync/docker/fc/ftp/sftp/oss）时残留值阻断上线。
# 参数:
#   $1 - config_file: 项目配置文件路径
# 返回: 模板残留时返回 1，否则返回 0
################################################################################
check_project_config_template() {
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

################################################################################
# 函数: config_deploy_init
# 描述: 初始化部署环境配置文件
# 参数: 无
# 返回: 无
# 全局变量:
#   - G_ENV: 环境变量配置文件路径
#   - G_DATA: 数据目录路径
#   - G_PATH: 脚本根目录路径
# 说明:
#   - 初始化环境变量配置文件（deploy.env）
#   - 注意: 此函数在项目路径确定之前调用
#   - 项目专用配置会在 config_deploy_vars 之后通过 find_project_config 查找并设置 G_CONF
################################################################################
config_deploy_init() {
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

################################################################################
# 函数: _load_project_build_deploy_config
# 描述: 从项目配置文件中加载构建和部署方式配置
# 参数:
#   $1 - config_file: 项目配置文件路径
# 返回: 无（设置全局变量）
# 全局变量:
#   - PROJECT_BUILD_METHOD: 构建方式 (auto/docker/system)
#   - PROJECT_DEPLOY_METHOD: 部署方式 (auto/k8s/docker/rsync)
#   - PROJECT_PREFER_DOCKER: 自动构建时是否优先 Docker (true/false)
#   - PROJECT_PREFER_K8S: 自动部署时是否优先 k8s (true/false)
################################################################################
_load_project_build_deploy_config() {
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

################################################################################
# 函数: config_deploy_setup
# 描述: 设置部署环境配置，包括SSH密钥、配置文件链接等
# 参数: 无
# 返回: 无
# 说明:
#   - 创建SSH密钥对（如果不存在）
#   - 创建配置目录的符号链接
#   - 设置适当的文件权限
################################################################################
config_deploy_setup() {
    ## dry-run: 不生成SSH密钥、不创建符号链接（仅本地环境配置，预览无意义）
    if ${G_DRY_RUN:-false}; then
        dry_run_note "config_deploy_setup (ssh keys, $HOME symlinks) — skipped in preview"
        return 0
    fi

    ## 需要创建符号链接的配置目录列表
    local conf_dirs=(".ssh" ".acme.sh" ".aws" ".kube" ".aliyun")
    local file_python_gitlab="${G_DATA}/.python-gitlab.cfg"

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

    ## 链接 python-gitlab 配置文件
    [[ ! -f "$HOME/.python-gitlab.cfg" && -f "${file_python_gitlab}" ]] && ln -sf "${file_python_gitlab}" "$HOME/"
}

################################################################################
# 函数: env_file_set
# 描述: 在 deploy.env 文件中设置环境变量，支持新增、更新、取消注释
# 参数:
#   $1 - KEY=VALUE 格式的键值对（VALUE 为原始值，不自动添加引号）
# 返回: 0=成功, 1=格式错误
# 说明:
#   - 如果 KEY 已存在（未注释），更新其值
#   - 如果 KEY 已存在但被注释，取消注释并更新值
#   - 如果 KEY 不存在，追加到文件末尾
#   - 含空格的值请自行加引号: deploy.sh set "ENV_FOO='bar baz'"
################################################################################
env_file_set() {
    ## CLI `set` 时由 parse 加入 RUN_TASKS 执行；防御性守卫 arg_env_set 为空则返回
    [[ ${#arg_env_set[@]} -gt 0 ]] || return 0
    local input key value tmp_file found skip_array line
    for input in "${arg_env_set[@]}"; do
        key="${input%%=*}"
        value="${input#*=}"

        if [[ "$key" == "$input" || -z "$key" ]]; then
            _msg error "Invalid format. Use: $0 set KEY=VALUE"
            exit 1
        fi

        ## 仅允许合法变量名，防止 key 中的正则元字符注入
        if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            _msg error "Invalid variable name: ${key}"
            exit 1
        fi

        tmp_file=$(mktemp)
        found=false
        skip_array=false

        if [[ -f "$G_ENV" ]]; then
            while IFS= read -r line || [[ -n "$line" ]]; do
                if $skip_array; then
                    if [[ "$line" =~ ^[[:space:]]*\) ]]; then
                        skip_array=false
                    fi
                    continue
                fi

                if ! $found && { [[ "$line" =~ ^${key}= ]] || [[ "$line" =~ ^#[[:space:]]*${key}= ]]; }; then
                    # 写入新的键值（保持用户传入的原始 value，不自动添加或删除引号）
                    echo "${key}=${value}" >>"$tmp_file"
                    found=true
                    # 如果原文件中该行是数组的开始（以 "=(" 结尾），则跳过后续直到 ")"
                    if [[ "$line" =~ =\($ ]]; then
                        skip_array=true
                    fi
                else
                    echo "$line" >>"$tmp_file"
                fi
            done <"$G_ENV"
            if ! $found; then
                echo "${key}=${value}" >>"$tmp_file"
            fi
        else
            # If G_ENV doesn't exist, just create it with the key
            echo "${key}=${value}" >"$tmp_file"
        fi

        mv "$tmp_file" "$G_ENV"
        _msg ok "Set ${key}=${value}"
    done
    exit 0
}

################################################################################
# 函数: env_file_get
# 描述: 获取环境变量的值（优先从已 source 的 shell 环境读取）
# 参数:
#   $1 - KEY: 变量名
# 返回: 0=成功（输出值到 stdout）, 1=变量不存在
################################################################################
env_file_get() {
    ## CLI `get` 时由 parse 加入 RUN_TASKS 执行；防御性守卫 arg_env_get 为空则返回
    [[ -n "${arg_env_get:-}" ]] || return 0
    local key="${arg_env_get}"

    if [[ -z "$key" ]]; then
        _msg error "Key name required. Use: $0 get KEY"
        exit 1
    fi

    ## 仅允许合法变量名，防止 key 中的正则元字符注入
    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        _msg error "Invalid variable name: ${key}"
        exit 1
    fi

    local value="${!key:-}"

    if [[ -n "$value" ]]; then
        echo "$value"
        exit 0
    fi

    if [[ -f "$G_ENV" ]]; then
        # shellcheck disable=SC1090
        source "$G_ENV"
    fi

    # 如果变量以数组形式存在，输出数组表示，使用 nameref 避免 eval 注入
    if declare -p "$key" &>/dev/null; then
        if declare -p "$key" 2>/dev/null | grep -q 'declare -a'; then
            local -n arr="$key"
            local first=true
            printf '('
            for item in "${arr[@]}"; do
                if [[ "$first" == true ]]; then
                    first=false
                else
                    printf ' '
                fi
                printf '%q' "$item"
            done
            printf ')\n'
            exit 0
        else
            echo "${!key}"
            exit 0
        fi
    fi

    if grep -q "^${key}=" "$G_ENV"; then
        echo ""
        exit 0
    fi

    _msg error "Variable ${key} not found"
    exit 1
}

################################################################################
# 函数: env_file_list
# 描述: 列出 deploy.env 中所有已启用的 ENV_ 变量
# 参数: 无
# 返回: 无（输出到标准输出）
################################################################################
env_file_list() {
    ## CLI `env|list` 时由 parse 加入 RUN_TASKS 执行；防御性守卫 arg_env_list 未置则返回
    [[ "${arg_env_list:-false}" == true ]] || return 0
    local line var in_array=false

    if [[ -f "$G_ENV" ]]; then
        # shellcheck disable=SC1090
        source "$G_ENV"
    fi

    echo "Listing enabled ENV_ variables from $G_ENV:"
    echo ""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$in_array" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]*\) ]]; then
                in_array=false
            fi
            continue
        fi

        if [[ "$line" =~ ^ENV_[A-Za-z_][A-Za-z0-9_]*= ]]; then
            var="${line%%=*}"
            if declare -p "$var" &>/dev/null; then
                # 数组类型处理
                if declare -p "$var" 2>/dev/null | grep -q 'declare -a'; then
                    # 使用 nameref 读取命名数组，避免 eval 注入
                    local -n ref="$var"
                    printf '%s=(' "$var"
                    local first=true
                    for item in "${ref[@]}"; do
                        if [[ "$first" == true ]]; then
                            first=false
                        else
                            printf ' '
                        fi
                        printf '%q' "$item"
                    done
                    printf ')\n'
                    # 如果原文件中是以声明数组开始的行，进入 in_array 模式以跳过后续行
                    if [[ "$line" =~ ^ENV_[A-Za-z_][A-Za-z0-9_]*=\($ ]]; then
                        in_array=true
                    fi
                    continue
                fi
                printf '%s=%s\n' "$var" "${!var}"
                continue
            fi
        fi
        echo "$line"
    done < <(
        grep -vE '^[[:space:]]*#' "$G_ENV" | grep -vE '^[[:space:]]*$'
    )
    exit $?
}
