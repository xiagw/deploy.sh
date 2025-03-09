#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 检查是否为演示模式
is_demo_mode() {
    local skip_msg="$1"

    # 检查是否为演示模式（环境变量或旧的配置方式）
    if [[ "${ENV_DEMO_MODE:-false}" == "true" ]] || { [[ -f "$G_ENV" ]] && grep -qE '=your_(password|username)' "$G_ENV"; }; then
        if [[ "${ENV_DEMO_MODE:-false}" != "true" ]]; then
            _msg warning "Legacy demo mode detected. Please set ENV_DEMO_MODE=true in your deploy.env instead"
        fi
        _msg purple "[Demo] Operation skipped: $skip_msg"
        return 0
    fi

    return 1
}

# 基础配置文件管理
config_deploy_file() {
    local path="$G_PATH" data="$G_DATA"

    [[ -f "${data}/deploy.json" ]] || cp -v "${path}/conf/example-deploy.json" "${data}/deploy.json"
    [[ -f "${data}/deploy.env" ]] || cp -v "${path}/conf/example-deploy.env" "${data}/deploy.env"

    # PATH 环境变量设置
    local path="$G_PATH" data="$G_DATA"

    mkdir -p "${data}/bin"
    local -a paths_append=(
        "/usr/local/sbin"
        "/snap/bin"
        "${path}/bin"
        "${data}/bin"
        "${data}/.acme.sh"
        "$HOME/.local/bin"
        "$HOME/.acme.sh"
        "$HOME/.config/composer/vendor/bin"
        "/home/linuxbrew/.linuxbrew/bin"
    )
    for p in "${paths_append[@]}"; do
        if [[ -d "$p" && ! ":$PATH:" =~ :$p: ]]; then
            PATH="${PATH:+"$PATH:"}$p"
        fi
    done
    export PATH
}

# 设置部署环境配置
config_deploy_env() {
    local path="${G_DATA}"
    local conf_dirs=(".ssh" ".acme.sh" ".aws" ".kube" ".aliyun")
    local file_python_gitlab="${path}/.python-gitlab.cfg"

    # Create and set permissions for SSH directory
    local ssh_dir="${path}/.ssh"
    if [[ ! -d "${ssh_dir}" ]]; then
        mkdir -m 700 "${ssh_dir}"
        _msg warn "Generate ssh key file for gitlab-runner: ${ssh_dir}/id_ed25519"
        _msg purple "Please: cat $ssh_dir/id_ed25519.pub >> [dest_server]:~/.ssh/authorized_keys"
        ssh-keygen -t ed25519 -N '' -f "${ssh_dir}/id_ed25519" || _msg error "Failed to generate SSH key"
    fi

    # Ensure HOME .ssh directory exists
    [[ -d "$HOME/.ssh" ]] || mkdir -m 700 "$HOME/.ssh"

    # Link SSH files
    for file in "$ssh_dir"/*; do
        [[ -f "$HOME/.ssh/$(basename "${file}")" ]] && continue
        echo "Link $file to $HOME/.ssh/"
        chmod 600 "${file}"
        ln -s "${file}" "$HOME/.ssh/"
    done

    # Link configuration directories
    for dir in "${conf_dirs[@]}"; do
        [[ ! -d "$HOME/${dir}" && -d "${path}/${dir}" ]] && ln -sf "${path}/${dir}" "$HOME/"
    done

    # Link python-gitlab config file
    [[ ! -f "$HOME/.python-gitlab.cfg" && -f "${file_python_gitlab}" ]] && ln -sf "${file_python_gitlab}" "$HOME/"

    _msg green "Deployment environment setup completed"
}

config_deploy_depend() {
    local conf_type="$1"
    shift
    # Check ENV file first, then fallback to environment variables
    if grep -q 'ENV_IN_CHINA=true' "$G_ENV" || ${ENV_IN_CHINA:-false} || ${CHANGE_SOURCE:-false}; then
        export IS_CHINA=true
    else
        export IS_CHINA=false
    fi
    case "$conf_type" in
    file) config_deploy_file ;;
    env) config_deploy_env ;;
    esac
}
