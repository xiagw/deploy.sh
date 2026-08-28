#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2154
# -*- coding: utf-8 -*-
#
# System maintenance and cleanup operations module
# This module provides functions for system maintenance tasks like disk cleanup

# Check if the current commit has already been executed in crontab
# Returns:
#   0 if execution should continue
#   1 if execution should be skipped
check_crontab_execution() {
    local script_data="$1" repo_id="$2" commit_sha="$3"
    ## Install crontab if not exists
    command -v crontab &>/dev/null || _install_packages cron
    [[ -z "$script_data" || -z "$repo_id" || -z "$commit_sha" ]] && {
        _msg error "Missing required parameters for check_crontab_execution"
        return 1
    }

    local cron_save_file
    cron_save_file="$(find "${script_data}" -name "crontab.${repo_id}.*" -print -quit)"

    if [[ -n "$cron_save_file" ]]; then
        local cron_save_id="${cron_save_file##*.}"
        if [[ "${commit_sha}" == "$cron_save_id" ]]; then
            _msg warn "No code changes detected. Skipping execution."
            return 1
        else
            rm -f "${script_data}/crontab.${repo_id}".*
        fi
    fi

    # Create new execution record
    touch "${script_data}/crontab.${repo_id}.${commit_sha}"
    return 0
}

# Clean up disk space when usage exceeds threshold
# Returns:
#   0 if cleanup was successful or not needed
#   1 if cleanup failed to free up space
system_clean_disk() {
    local disk_usage clean_disk_threshold="${ENV_DISK_THRESHOLD:-80}" aggressive=false disk_usage_after

    # Get disk usage more reliably
    disk_usage=$(df -P / | awk 'NR==2 {print int($5)}')

    if ((disk_usage < clean_disk_threshold)); then
        return 0
    fi

    _msg warn "Disk usage (${disk_usage}%) exceeds threshold (${clean_disk_threshold}%). Starting cleanup..."

    # Determine if we should use aggressive cleaning
    if ((disk_usage >= clean_disk_threshold + 10)); then
        aggressive=true
        _msg warn "Disk usage is critically high. Using aggressive cleaning."
    fi

    # Show cleanup plan in dry-run mode
    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] system_clean_disk:"
        _msg note "   - docker image prune -f"
        _msg note "   - docker builder prune -f"
        _msg note "   - Remove images from ${ENV_DOCKER_REGISTRY}"
        $aggressive && _msg note "   - docker system prune -af --volumes (aggressive mode)"
        _msg note "2. Temporary files cleanup:"
        _msg note "   - Remove files older than 10 days from /tmp and /var/tmp"
        _msg note "3. Log files cleanup:"
        _msg note "   - Remove log files older than 30 days from /var/log"
        $aggressive && _msg note "4. Core dumps cleanup (aggressive mode):"
        $aggressive && _msg note "   - Remove all files from /var/crash"
        return 0
    fi

    # Clean up Docker images
    if command -v docker >/dev/null 2>&1; then
        _msg task "Cleaning up Docker resources..."
        docker image prune -f >/dev/null
        docker builder prune -f >/dev/null
        docker image ls --format '{{.Repository}}:{{.Tag}}' "${ENV_DOCKER_REGISTRY}" | grep -v '^$' | xargs docker rmi 2>/dev/null || true
        if $aggressive; then
            docker system prune -af --volumes >/dev/null
        fi
    fi

    # Clean up temporary files
    _msg task "Cleaning up temporary files..."
    ${use_sudo:-} find /tmp -type f -atime +10 -delete 2>/dev/null || true
    ${use_sudo:-} find /var/tmp -type f -atime +10 -delete 2>/dev/null || true

    # Clean up old log files
    _msg task "Cleaning up old log files..."
    ${use_sudo:-} find /var/log -type f -name "*.log" -mtime +30 -delete 2>/dev/null || true

    # Clean up old core dumps if aggressive
    if $aggressive; then
        _msg task "Cleaning up old core dumps..."
        ${use_sudo:-} find /var/crash -type f -delete 2>/dev/null || true
    fi

    # Final disk usage check
    disk_usage_after=$(df -P / | awk 'NR==2 {print int($5)}')

    if ((disk_usage_after >= disk_usage)); then
        _msg error "Cleanup did not free up space. Disk usage now: ${disk_usage_after}%"
    else
        _msg ok "Cleanup completed. Disk usage now: ${disk_usage_after}% (freed $((disk_usage - disk_usage_after))%)."
    fi
}

# 系统环境检查和设置
system_check() {
    local -a pkgs
    _check_distribution

    pkgs=()

    case "${lsb_dist:-}" in
    debian | ubuntu | linuxmint)
        export DEBIAN_FRONTEND=noninteractive
        ## fix gitlab-runner exit error / 修复 gitlab-runner 退出错误
        [[ -f "$HOME"/.bash_logout ]] && mv -f "$HOME"/.bash_logout "$HOME"/.bash_logout.bak

        command -v apt-extracttemplates >/dev/null || pkgs+=(apt-utils)
        command -v git >/dev/null || pkgs+=(git)
        git lfs version >/dev/null 2>&1 || pkgs+=(git-lfs)
        command -v curl >/dev/null || pkgs+=(curl)
        command -v unzip >/dev/null || pkgs+=(unzip)
        command -v rsync >/dev/null || pkgs+=(rsync)
        command -v pip3 >/dev/null || pkgs+=(python3-pip)
        command -v shc >/dev/null || pkgs+=(shc)
        ;;
    centos | amzn | rhel | fedora)
        rpm -q epel-release >/dev/null || {
            if [ "${lsb_dist:-}" = amzn ]; then
                ${use_sudo:-} amazon-linux-extras install -y epel >/dev/null
            else
                _install_packages epel-release >/dev/null
            fi
        }
        command -v git >/dev/null || pkgs+=(git2u)
        git lfs version >/dev/null 2>&1 || pkgs+=(git-lfs)
        command -v curl >/dev/null || pkgs+=(curl)
        command -v unzip >/dev/null || pkgs+=(unzip)
        command -v rsync >/dev/null || pkgs+=(rsync)
        ;;
    alpine)
        command -v openssl >/dev/null || pkgs+=(openssl)
        command -v git >/dev/null || pkgs+=(git)
        git lfs version >/dev/null 2>&1 || pkgs+=(git-lfs)
        command -v curl >/dev/null || pkgs+=(curl)
        command -v unzip >/dev/null || pkgs+=(unzip)
        command -v rsync >/dev/null || pkgs+=(rsync)
        ;;
    macos)
        command -v openssl >/dev/null || pkgs+=(openssl)
        command -v git >/dev/null || pkgs+=(git)
        git lfs version >/dev/null 2>&1 || pkgs+=(git-lfs)
        command -v curl >/dev/null || pkgs+=(curl)
        command -v unzip >/dev/null || pkgs+=(unzip)
        command -v rsync >/dev/null || pkgs+=(rsync)
        ;;
    *)
        _msg error "Unsupported OS distribution. Exiting."
        return 1
        ;;
    esac

    if [ ${#pkgs[@]} -gt 0 ]; then
        _install_packages "${pkgs[@]}" >/dev/null
    fi
}

# 设置系统代理
system_proxy() {
    case "$1" in
    0 | off | disable)
        _msg task "unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY"
        unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY
        ;;
    *)
        local default_no_proxy="localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
        _msg task "Set proxy environment variables"
        [ -n "$ENV_HTTP_PROXY" ] && export http_proxy="$ENV_HTTP_PROXY" HTTP_PROXY="$ENV_HTTP_PROXY"
        [ -n "$ENV_SOCK_PROXY" ] && export socks_proxy="$ENV_SOCK_PROXY" SOCKS_PROXY="$ENV_SOCK_PROXY"
        if [ -n "$ENV_NO_PROXY" ]; then
            export no_proxy="$ENV_NO_PROXY" NO_PROXY="$ENV_NO_PROXY"
        else
            export no_proxy="$default_no_proxy" NO_PROXY="$default_no_proxy"
        fi
        if [ -n "$ENV_HTTPS_PROXY" ]; then
            export https_proxy="$ENV_HTTPS_PROXY" HTTPS_PROXY="$ENV_HTTPS_PROXY"
        elif [ -n "$ENV_HTTP_PROXY" ]; then
            export https_proxy="$ENV_HTTP_PROXY" HTTPS_PROXY="$ENV_HTTP_PROXY"
        fi
        if [ -n "$ENV_ALL_PROXY" ]; then
            export all_proxy="$ENV_ALL_PROXY" ALL_PROXY="$ENV_ALL_PROXY"
        elif [ -n "$ENV_HTTP_PROXY" ]; then
            export all_proxy="$ENV_HTTP_PROXY" ALL_PROXY="$ENV_HTTP_PROXY"
        fi
        ;;
    esac
}

#
# Certificate management module for deployment script
# Handles SSL certificate operations using acme.sh

# Internal function to renew SSL certificates
# This function handles the actual certificate renewal process
system_cert_renew() {
    ## RUN 单数组成员（-r/--renew-cert 触发，parse 组装），无守卫直接执行
    # 读取 ${HOME}/.acme.sh/account.conf.*.dns_* 账号文件；由 config_deploy_setup 在
    # G_DATA/.acme.sh 存在时链接 $HOME/.acme.sh，故 RUN 中须排在其之后
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        exit 0
    fi
    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] system_cert_renew:"
        _msg note "  install acme.sh + loop renew all certs (${acme_home:-~/.acme.sh})"
        exit 0
    fi

    _msg task "Renewing SSL certificates"

    local acme_home="${HOME}/.acme.sh"
    local acme_cmd="${acme_home}/acme.sh"
    local acme_cert_dest="${acme_home}/dest"
    local run_hook domains="" file dns_type random_minute api_head api_godaddy

    ## install acme.sh / 安装 acme.sh
    command -v crontab &>/dev/null || _install_packages cron
    _install_acme_official

    [ -d "$acme_cert_dest" ] || mkdir -p "$acme_cert_dest"

    ## 生成 reload.nginx 文件，用于触发 gitlab CI/CD 或自定义部署脚本
    local reload_nginx="$acme_home/reload.nginx"
    run_hook="$acme_home/hook.sh"
    echo "touch ${reload_nginx}" >"$run_hook"
    chmod +x "$run_hook"
    ## According to multiple different account files, loop renewal / 根据多个不同的账号文件,循环续签
    ## support multiple account.conf.* / 支持多账号
    ## 多个账号用文件名区分，例如： account.conf.xxx.dns_ali, account.conf.yyy.dns_cf
    for file in "${acme_home}"/account.conf.*.dns_*; do
        if [ -f "$file" ]; then
            _msg note "Found $file"
        else
            continue
        fi
        dns_type=${file##*.}
        source "$file"

        case "${dns_type}" in
        dns_gd)
            _msg warn "dns type: Godaddy"
            api_head="Authorization: sso-key ${SAVED_GD_Key:-none}:${SAVED_GD_Secret:-none}"
            api_godaddy="https://api.godaddy.com/v1/domains"
            if [[ -z "$SAVED_GD_Key" || -z "$SAVED_GD_Secret" ]]; then
                _msg error "Missing Godaddy credentials in $file"
                continue
            fi
            export GD_Key="${SAVED_GD_Key}"
            export GD_Secret="${SAVED_GD_Secret}"
            domains="$(
                curl -fsSL -X GET -H "$api_head" "$api_godaddy" | jq -r '.[].domain' || true
            )"
            ;;
        dns_cf)
            _msg warn "dns type: cloudflare"
            if [ -n "$SAVED_Ali_Key" ]; then
                export Ali_Key=$SAVED_Ali_Key
            fi
            if [ -n "$SAVED_Ali_Secret" ]; then
                export Ali_Secret=$SAVED_Ali_Secret
            fi
            if [[ -n "$SAVED_CF_API_TOKEN" ]]; then
                export CF_API_TOKEN="$SAVED_CF_API_TOKEN"
            elif [[ -n "$SAVED_CF_Token" && -n "$SAVED_CF_Account_ID" ]]; then
                export CF_Token="$SAVED_CF_Token"
                export CF_Account_ID="$SAVED_CF_Account_ID"
            else
                _msg error "Missing Cloudflare credentials in $file"
                continue
            fi
            domains="$(
                curl -fsSL -X GET "https://api.cloudflare.com/client/v4/zones" \
                    -H "Authorization: Bearer ${CF_API_TOKEN:-$CF_Token}" \
                    -H "Content-Type: application/json" | jq -r '.result[].name' || true
            )"
            ;;
        dns_ali)
            _msg warn "dns type: aliyun"
            local profile_name="deploy_${profile_name:-$RANDOM}"
            _install_aliyun_cli
            aliyun configure set \
                --mode AK \
                --profile "${profile_name}" \
                --region "${SAVED_Ali_region:-none}" \
                --access-key-id "${SAVED_Ali_Key:-none}" \
                --access-key-secret "${SAVED_Ali_Secret:-none}"
            export Ali_Key=$SAVED_Ali_Key
            export Ali_Secret=$SAVED_Ali_Secret
            domains="$(
                aliyun --profile "${profile_name}" domain QueryDomainList --PageNum 1 --PageSize 100 |
                    jq -r '.Data.Domain[].DomainName' || true
            )"
            ;;
        dns_tencent)
            _msg warn "dns type: tencent"
            _install_tencent_cli
            tccli configure set secretId "${SAVED_Tencent_SecretId:-none}" secretKey "${SAVED_Tencent_SecretKey:-none}"
            domains="$(
                tccli domain DescribeDomainNameList --output json | jq -r '.DomainSet[] | .DomainName' || true
            )"
            ;;
        dns_manual)
            _msg warn "get domains from ${file}"
            ## "${file}" 内有 domains="example1.com example2.com example3.com"
            ## 用 sed 提取，避免 grep -oP 在 BSD/macOS grep 上不可用
            domains="$(sed -n 's/^[[:space:]]*domains=[[:space:]]*//p' "$file" 2>/dev/null || true)"
            echo "$domains"
            ;;
        *)
            _msg warn "unknown dns type: $dns_type"
            continue
            ;;
        esac

        ## single account may have multiple domains / 单个账号可能有多个域名
        if [[ -z "$domains" ]]; then
            _msg warn "No domains found, skipping."
            continue
        fi
        acme_cmd="${acme_home}/acme.sh --accountconf ${file}"
        for domain in ${domains}; do
            _msg note "Checking domain: $domain"
            if ${acme_cmd} --list | grep -qw "$domain"; then
                ## renew cert / 续签证书
                ${acme_cmd} --renew -d "${domain}" --reloadcmd "$run_hook" || true
            else
                ## create cert / 创建证书
                ${acme_cmd} --issue -d "${domain}" -d "*.${domain}" --dns "$dns_type" --renew-hook "$run_hook" || true
            fi
            ## install cert / 安装证书
            ${acme_cmd} --install-cert -d "${domain}" \
                --key-file "${acme_cert_dest}/${domain}.key" \
                --fullchain-file "$acme_cert_dest/${domain}.pem" || true
            ## 随机停顿 5-30分钟
            local random_minute
            random_minute=$((RANDOM % 26 + 5))
            _msg ok "sleep ${random_minute} minutes"
            sleep "${random_minute}"m
        done
    done
    ## deploy with acme_deploy / 自定义部署方式
    if [[ -f "${acme_home}/custom_deploy.sh" ]]; then
        _msg note "Found ${acme_home}/custom_deploy.sh"
        bash "${acme_home}/custom_deploy.sh"
    fi
    ## deploy with gitlab CI/CD / gitlab CI/CD 部署方式（项目名包含 nginx 的项目）
    if [ -f "$reload_nginx" ]; then
        rm -f "$reload_nginx"
        _msg ok "found $reload_nginx"
        _install_python_gitlab ""
        ## 如果定义了变量数组 ENV_NGINX_PROJECT_ID，则使用该数组中的项目 ID 创建 GitLab pipeline
        if [[ -n "${ENV_NGINX_PROJECT_ID[*]:-}" ]]; then
            for id in "${ENV_NGINX_PROJECT_ID[@]}"; do
                _msg note "create gitlab pipeline, project id is $id"
                gitlab project-pipeline create --ref main --project-id "$id" || true
            done
        else
            ## 否则使用 gitlab 搜索 nginx 项目
            _msg note "search nginx project in gitlab project list"
            local id
            while read -r id; do
                _msg note "create gitlab pipeline, project id is $id"
                gitlab project-pipeline create --ref main --project-id "$id" || true
            done < <(gitlab -ojson project list --search "nginx" | jq -r '.[].id' || true)
        fi
    else
        _msg warn "not found $reload_nginx, skip create giltab pipeline"
    fi
    _msg task "Certificate renewal completed"
    echo '================================================================'

    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        exit 0
    fi
    if ${exec_single_job:-false}; then
        exit 0
    fi
    ## 续签成功即返回 0；此前 `exit $?` 会取到最后一个 if 条件（false）的状态恒为 1
    exit 0
}

# Install base tools (jq) unconditionally.
# In CI (GITHUB_ACTIONS=true), install all dependencies for validation
# (jmeter/docker skipped since CI runs inside a container).
# Other tools are installed on-demand via _install_* at point of use
# (each _install_* function is idempotent — skips if already present).
# Returns:
#   0 if all installations were successful
#   1 if any installation failed
system_install_tools() {
    ## 基础工具安装
    command -v jq >/dev/null || _install_packages jq

    ## CI 测试：安装所有依赖组件（容器内跳过 jmeter/docker）
    if ${GITHUB_ACTIONS:-false}; then
        _install_aws
        _install_aliyun_cli
        _install_terraform
        _install_kubectl
        _install_helm
        _install_python_element
        _install_python_gitlab
    fi
}

################################################################################
# 函数: check_docker_available
# 描述: 检查 Docker 是否可用
# 返回: 0=Docker可用, 1=Docker不可用
################################################################################
check_docker_available() {
    if ! command -v docker &>/dev/null; then
        return 1
    fi
    # 检查 Docker daemon 是否运行
    if ! docker info &>/dev/null; then
        return 1
    fi
    return 0
}

################################################################################
# 函数: check_k8s_available
# 描述: 检查 Kubernetes 环境是否可用（kubectl 和 helm）
# 返回: 0=k8s可用, 1=k8s不可用
################################################################################
check_k8s_available() {
    # 检查 kubectl 是否可用
    if ! command -v kubectl &>/dev/null; then
        return 1
    fi
    # 检查 kubectl 是否能连接到集群
    if ! kubectl cluster-info &>/dev/null; then
        return 1
    fi
    # 检查 helm 是否可用（可选，但推荐）
    if ! command -v helm &>/dev/null; then
        _msg warn "Helm is not installed, but kubectl is available" >&2
        return 0 # kubectl 可用即可
    fi
    return 0
}

################################################################################
# 函数: check_helm_charts_exist
# 描述: 检查 Helm charts 目录是否存在
# 参数:
#   $1 - release_name: Release 名称（可选）
# 返回: 0=存在, 1=不存在
# 说明: 检查多个可能的 Helm charts 目录位置
################################################################################
check_helm_charts_exist() {
    local release_name="${1:-}"
    local helm_dirs

    # 如果没有提供 release_name，尝试从环境变量获取
    [[ -z "$release_name" && -n "${G_REPO_NAME:-}" ]] && release_name="$(format_release_name 2>/dev/null || echo "${G_REPO_NAME}")"

    # 定义可能的 Helm charts 目录
    helm_dirs=(
        "${G_REPO_DIR}/helm/${release_name}"
        "${G_REPO_DIR}/docs/helm/${release_name}"
        "${G_REPO_DIR}/doc/helm/${release_name}"
        "${G_DATA}/helm/${G_REPO_GROUP_PATH_SLUG:-}/${G_NAMESPACE:-}/${release_name}"
        "${G_DATA}/helm/${G_REPO_GROUP_PATH_SLUG:-}/${release_name}"
        "${G_DATA}/helm/${release_name}"
    )

    # 检查是否有目录存在
    for dir in "${helm_dirs[@]}"; do
        [[ -n "$dir" && -d "$dir" ]] && return 0
    done

    return 1
}
