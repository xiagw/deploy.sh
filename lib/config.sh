#!/usr/bin/env bash
# -*- coding: utf-8 -*-

################################################################################
# 函数: is_demo_mode
# 描述: 检查当前是否处于演示模式
# 参数:
#   $1 - skip_msg: 要跳过的操作描述信息
# 返回: 0=演示模式（跳过操作）, 1=非演示模式（继续执行）
# 说明: 演示模式用于在不实际执行操作的情况下展示命令
################################################################################
is_demo_mode() {
    local skip_msg="$1"

    ## 检查是否为演示模式
    ## 判断条件:
    ##   1. 环境变量 ENV_DEMO_MODE=true
    ##   2. deploy.env 文件中包含示例配置（your_password/your_username）
    if [[ "${ENV_DEMO_MODE:-false}" == "true" ]] || { [[ -f "$G_ENV" ]] && grep -qE '=your_(password|username)' "$G_ENV"; }; then
        ## 如果通过旧方式检测到演示模式，提示用户使用新的环境变量方式
        if [[ "${ENV_DEMO_MODE:-false}" != "true" ]]; then
            _msg warning "demo mode detected. Please set ENV_DEMO_MODE=false in your deploy.env instead"
        fi
        _msg purple "[Demo] Operation skipped: $skip_msg"
        return 0
    fi

    return 1
}

################################################################################
# 函数: config_deploy_file
# 描述: 初始化部署配置文件，优先使用JSON格式，YAML作为备选
# 参数: 无
# 返回: 无（设置全局变量 G_CONF）
# 全局变量:
#   - G_CONF: 部署配置文件路径（JSON或YAML格式）
#   - G_ENV: 环境变量配置文件路径
#   - G_DATA: 数据目录路径
#   - G_PATH: 脚本根目录路径
# 说明: 
#   - 优先使用 JSON 格式配置文件（deploy.json）
#   - 如果 JSON 文件不存在，则使用 YAML 格式（deploy.yaml）
#   - 如果都不存在，则从示例文件复制创建
################################################################################
config_deploy_file() {
    ## 初始化环境变量配置文件
    [[ ! -f "${G_ENV}" ]] && cp -v "${G_PATH}/conf/example-deploy.env" "${G_ENV}"

    ## 初始化部署配置文件（优先使用JSON格式）
    ## 检查逻辑:
    ##   1. 如果 G_CONF 已指向的文件存在，则使用它
    ##   2. 如果不存在，优先尝试 JSON 格式
    ##   3. 如果 JSON 不存在，则使用 YAML 格式作为备选
    if [[ ! -f "${G_CONF}" ]]; then
        ## 优先使用 JSON 格式配置文件
        local json_conf="${G_DATA}/deploy.json"
        local yaml_conf="${G_DATA}/deploy.yaml"

        if [[ -f "${json_conf}" ]]; then
            ## 如果 JSON 文件已存在，使用它
            G_CONF="${json_conf}"
        elif [[ -f "${yaml_conf}" ]]; then
            ## 如果 YAML 文件已存在，使用它
            G_CONF="${yaml_conf}"
        else
            ## 如果都不存在，优先创建 JSON 格式的配置文件
            G_CONF="${json_conf}"
            cp -v "${G_PATH}/conf/example-deploy.json" "${G_CONF}"
        fi
    fi

    ## ========================================================================
    ## PATH 环境变量配置
    ## 添加必要的二进制文件目录到 PATH，确保可以找到所需的工具
    ## ========================================================================
    mkdir -p "${G_DATA}/bin"
    local -a paths_append=(
        "/usr/local/sbin"                          # 系统管理员命令
        "/snap/bin"                                # Snap 包二进制文件
        "${G_PATH}/bin"                            # 项目脚本目录
        "${G_DATA}/bin"                            # 数据目录下的二进制文件
        "${G_DATA}/.acme.sh"                       # acme.sh 脚本目录
        "$HOME/.local/bin"                         # 用户本地二进制文件
        "$HOME/.acme.sh"                           # 用户 acme.sh 目录
        "$HOME/.config/composer/vendor/bin"        # Composer 全局包二进制文件
        "/home/linuxbrew/.linuxbrew/bin"           # Linuxbrew 二进制文件
    )
    for p in "${paths_append[@]}"; do
        if [[ -d "$p" && ! ":$PATH:" =~ :$p: ]]; then
            PATH="${PATH:+"$PATH:"}$p"
        fi
    done
    export PATH
}

################################################################################
# 函数: config_deploy_env
# 描述: 设置部署环境配置，包括SSH密钥、配置文件链接等
# 参数: 无
# 返回: 无
# 说明: 
#   - 创建SSH密钥对（如果不存在）
#   - 创建配置目录的符号链接
#   - 设置适当的文件权限
################################################################################
config_deploy_env() {
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
        _msg purple "Please: cat $ssh_dir/id_ed25519.pub >> [dest_server]:~/.ssh/authorized_keys"
        ## 生成ED25519 SSH密钥对（无密码）
        ssh-keygen -t ed25519 -N '' -f "${ssh_dir}/id_ed25519" || _msg error "Failed to generate SSH key"
    fi

    ## 确保用户主目录下的 .ssh 目录存在
    [[ -d "$HOME/.ssh" ]] || mkdir -m 700 "$HOME/.ssh"

    ## 将SSH密钥文件链接到用户主目录（如果不存在）
    for file in "$ssh_dir"/*; do
        [[ -f "$HOME/.ssh/$(basename "${file}")" ]] && continue
        echo "Link $file to $HOME/.ssh/"
        chmod 600 "${file}"  # 设置适当的权限
        ln -s "${file}" "$HOME/.ssh/"
    done

    ## ========================================================================
    ## 配置文件目录链接
    ## 将数据目录下的配置目录链接到用户主目录，方便工具访问
    ## ========================================================================
    for dir in "${conf_dirs[@]}"; do
        [[ ! -d "$HOME/${dir}" && -d "${G_DATA}/${dir}" ]] && ln -sf "${G_DATA}/${dir}" "$HOME/"
    done

    ## 链接 python-gitlab 配置文件
    [[ ! -f "$HOME/.python-gitlab.cfg" && -f "${file_python_gitlab}" ]] && ln -sf "${file_python_gitlab}" "$HOME/"

    _msg green "Deployment environment setup completed"
}

################################################################################
# 函数: config_deploy_depend
# 描述: 配置部署依赖，包括文件配置和环境配置
# 参数:
#   $1 - type: 配置类型 ("file" 或 "env")
# 返回: 无
# 说明:
#   - type="file": 初始化配置文件
#   - type="env": 设置部署环境（SSH、工具配置等）
#   - 同时设置 IS_CHINA 环境变量（用于判断是否在中国地区）
################################################################################
config_deploy_depend() {
    local type="$1"
    shift

    ## 检查是否在中国地区
    ## 判断优先级:
    ##   1. deploy.env 文件中的 ENV_IN_CHINA=true
    ##   2. 环境变量 ENV_IN_CHINA=true
    ##   3. 环境变量 CHANGE_SOURCE=true（兼容旧配置）
    if grep -q 'ENV_IN_CHINA=true' "$G_ENV" || ${ENV_IN_CHINA:-false} || ${CHANGE_SOURCE:-false}; then
        export IS_CHINA=true
    else
        export IS_CHINA=false
    fi

    ## 根据类型执行相应的配置函数
    case "$type" in
    file) config_deploy_file ;;
    env) config_deploy_env ;;
    esac
}
