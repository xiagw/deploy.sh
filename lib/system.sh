#!/usr/bin/env bash
# shellcheck disable=SC1090
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
    command -v crontab &>/dev/null || _install_packages "$IS_CHINA" cron
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
    local disk_usage clean_disk_threshold=80 aggressive=false

    # Get disk usage more reliably
    disk_usage=$(df -P / | awk 'NR==2 {print int($5)}')

    if ((disk_usage < clean_disk_threshold)); then
        return 0
    fi

    _msg warning "Disk usage (${disk_usage}%) exceeds threshold (${clean_disk_threshold}%). Starting cleanup..."

    # Determine if we should use aggressive cleaning
    if ((disk_usage >= clean_disk_threshold + 10)); then
        aggressive=true
        _msg warning "Disk usage is critically high. Using aggressive cleaning."
    fi

    # Show cleanup plan in demo mode
    if is_demo_mode "system_clean_disk"; then
        _msg purple "Demo mode: would execute the following cleanup operations:"
        _msg purple "1. Docker cleanup:"
        _msg purple "   - docker image prune -f"
        _msg purple "   - docker builder prune -f"
        _msg purple "   - Remove images from ${ENV_DOCKER_REGISTRY}"
        $aggressive && _msg purple "   - docker system prune -af --volumes (aggressive mode)"
        _msg purple "2. Temporary files cleanup:"
        _msg purple "   - Remove files older than 10 days from /tmp and /var/tmp"
        _msg purple "3. Log files cleanup:"
        _msg purple "   - Remove log files older than 30 days from /var/log"
        $aggressive && _msg purple "4. Core dumps cleanup (aggressive mode):"
        $aggressive && _msg purple "   - Remove all files from /var/crash"
        return 0
    fi

    # Clean up Docker images
    if command -v docker >/dev/null 2>&1; then
        echo "Cleaning up Docker resources..."
        docker image prune -f
        docker builder prune -f
        docker image ls --format '{{.Repository}}:{{.Tag}}' "${ENV_DOCKER_REGISTRY}" | xargs -r docker rmi 2>/dev/null || true
        if $aggressive; then
            docker system prune -af --volumes
        fi
    fi

    # Clean up temporary files
    echo "Cleaning up temporary files..."
    ${use_sudo:-} find /tmp -type f -atime +10 -delete 2>/dev/null || true
    ${use_sudo:-} find /var/tmp -type f -atime +10 -delete 2>/dev/null || true

    # Clean up old log files
    echo "Cleaning up old log files..."
    ${use_sudo:-} find /var/log -type f -name "*.log" -mtime +30 -delete 2>/dev/null || true

    # Clean up old core dumps if aggressive
    if $aggressive; then
        echo "Cleaning up old core dumps..."
        ${use_sudo:-} find /var/crash -type f -delete 2>/dev/null || true
    fi

    # Final disk usage check
    disk_usage_after=$(df -P / | awk 'NR==2 {print int($5)}')
    echo "Cleanup completed. Disk usage now: ${disk_usage_after}%"

    if ((disk_usage_after >= disk_usage)); then
        _msg error "Warning: Cleanup did not free up space. Further investigation may be needed."
    else
        _msg success "Successfully freed up $((disk_usage - disk_usage_after))% of disk space."
    fi
}

# Update Nginx GeoIP database from Miyuru's mirror
# Requires:
#   - ENV_NGINX_IPS: Space-separated list of Nginx server IPs
# Returns:
#   0 if update was successful
#   1 if update failed
update_nginx_geoip_db() {
    local tmp_dir country_url city_url
    tmp_dir="$(mktemp -d)"
    country_url="https://dl.miyuru.lk/geoip/maxmind/country/maxmind.dat.gz"
    city_url="https://dl.miyuru.lk/geoip/maxmind/city/maxmind.dat.gz"

    _msg step "[geoip] Updating Nginx GeoIP database"

    _download_and_extract() {
        local url="$1" output="$2"
        if ! curl -LqsSf "$url" | gunzip -c >"$output"; then
            _msg error "Failed to download or extract $url"
            return 1
        fi
    }

    _download_and_extract "$country_url" "$tmp_dir/maxmind-Country.dat" || return 1
    _download_and_extract "$city_url" "$tmp_dir/maxmind-City.dat" || return 1

    echo "GeoIP databases downloaded successfully"

    _update_server() {
        local ip="$1"
        if rsync -av "${tmp_dir}/" "root@$ip:/etc/nginx/conf.d/"; then
            _msg success "Updated GeoIP database on $ip"
        else
            _msg error "Failed to update GeoIP database on $ip"
        fi
    }

    for ip in "${ENV_NGINX_IPS[@]}"; do
        _update_server "$ip" &
    done

    wait

    rm -rf "$tmp_dir"
    _msg success "Nginx GeoIP database update completed"
}

# 系统环境检查和设置
system_check() {
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
                _install_packages "$IS_CHINA" epel-release >/dev/null
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
        _install_packages "$IS_CHINA" "${pkgs[@]}" >/dev/null
    fi
}

# 设置系统代理
system_proxy() {
    case "$1" in
    0 | off | disable)
        _msg time "unset http_proxy https_proxy all_proxy"
        unset http_proxy https_proxy all_proxy
        ;;
    1 | on | enable)
        if [ -z "$ENV_HTTP_PROXY" ]; then
            _msg warn "empty var ENV_HTTP_PROXY"
        else
            _msg time "set http_proxy https_proxy all_proxy"
            export http_proxy="$ENV_HTTP_PROXY"
            export https_proxy="$ENV_HTTP_PROXY"
            export all_proxy="$ENV_HTTP_PROXY"
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
    # Check if certificate renewal is needed
    if [[ "${GH_ACTION:-false}" = true ]]; then
        return 0
    fi

    _msg step "[cert] renewing SSL certificates"
    exec_single_job=true

    local acme_home="${HOME}/.acme.sh"
    local acme_cmd="${acme_home}/acme.sh"
    local acme_cert_dest="${ENV_CERT_INSTALL:-${acme_home}}/dest"
    local reload_nginx="$acme_home/reload.nginx"

    ## install acme.sh / 安装 acme.sh
    command -v crontab &>/dev/null || _install_packages "$IS_CHINA" cron
    _install_acme_official

    [ -d "$acme_cert_dest" ] || mkdir -p "$acme_cert_dest"

    run_touch_file="$acme_home/hook.sh"
    echo "touch ${reload_nginx}" >"$run_touch_file"
    chmod +x "$run_touch_file"
    ## According to multiple different account files, loop renewal / 根据多个不同的账号文件,循环续签
    ## support multiple account.conf.* / 支持多账号
    ## 多个账号用文件名区分，例如： account.conf.xxx.dns_ali, account.conf.yyy.dns_cf
    for file in "${acme_home}"/account.conf.*.dns_*; do
        if [ -f "$file" ]; then
            _msg blue "Found $file"
        else
            continue
        fi
        source "$file"
        dns_type=${file##*.}
        profile_name=${file%.dns_*}
        profile_name=${profile_name##*.}
        system_proxy on
        case "${dns_type}" in
        dns_gd)
            _msg yellow "dns type: Goddady"
            api_head="Authorization: sso-key ${SAVED_GD_Key:-none}:${SAVED_GD_Secret:-none}"
            api_goddady="https://api.godaddy.com/v1/domains"
            domains="$(curl -fsSL -X GET -H "$api_head" "$api_goddady" | jq -r '.[].domain' || true)"
            export GD_Key="${SAVED_GD_Key:-none}"
            export GD_Secret="${SAVED_GD_Secret:-none}"
            ;;
        dns_cf)
            _msg yellow "dns type: cloudflare"
            _install_flarectl
            domains="$(flarectl zone list | awk '/active/ {print $3}' || true)"
            export CF_Token="${SAVED_CF_Token:-none}"
            export CF_Account_ID="${SAVED_CF_Account_ID:-none}"
            ;;
        dns_ali)
            _msg yellow "dns type: aliyun"
            _install_aliyun_cli
            aliyun configure set \
                --mode AK \
                --profile "deploy_${profile_name}" \
                --region "${SAVED_Ali_region:-none}" \
                --access-key-id "${SAVED_Ali_Key:-none}" \
                --access-key-secret "${SAVED_Ali_Secret:-none}"
            domains="$(aliyun --profile "deploy_${profile_name}" domain QueryDomainList --PageNum 1 --PageSize 100 | jq -r '.Data.Domain[].DomainName' || true)"
            export Ali_Key=$SAVED_Ali_Key
            export Ali_Secret=$SAVED_Ali_Secret
            ;;
        dns_tencent)
            _msg yellow "dns type: tencent"
            _install_tencent_cli
            tccli configure set secretId "${SAVED_Tencent_SecretId:-none}" secretKey "${SAVED_Tencent_SecretKey:-none}"
            domains="$(tccli domain DescribeDomainNameList --output json | jq -r '.DomainSet[] | .DomainName' || true)"
            ;;
        from_env)
            _msg yellow "get domains from env file"
            source "$file"
            ;;
        *)
            _msg yellow "unknown dns type: $dns_type"
            continue
            ;;
        esac

        ## single account may have multiple domains / 单个账号可能有多个域名
        for domain in ${domains}; do
            _msg orange "Checking domain: $domain"
            if "${acme_cmd}" list | grep -qw "$domain"; then
                ## renew cert / 续签证书
                "${acme_cmd}" --accountconf "$file" --renew -d "${domain}" --reloadcmd "$run_touch_file" || true
            else
                ## create cert / 创建证书
                "${acme_cmd}" --accountconf "$file" --issue -d "${domain}" -d "*.${domain}" --dns "$dns_type" --renew-hook "$run_touch_file" || true
            fi
            "${acme_cmd}" --accountconf "$file" -d "${domain}" --install-cert --key-file "$acme_cert_dest/${domain}.key" --fullchain-file "$acme_cert_dest/${domain}.pem" || true
            "${acme_cmd}" --accountconf "$file" -d "${domain}" --install-cert --key-file "${acme_home}/dest/${domain}.key" --fullchain-file "${acme_home}/dest/${domain}.pem" || true
        done
    done
    ## deploy with gitlab CI/CD,
    if [ -f "$reload_nginx" ]; then
        _msg green "found $reload_nginx"
        for id in "${ENV_NGINX_PROJECT_ID[@]}"; do
            _msg "gitlab create pipeline, project id is $id"
            gitlab project-pipeline create --ref main --project-id "$id"
        done
        rm -f "$reload_nginx"
    else
        _msg warn "not found $reload_nginx"
    fi
    ## deploy with custom method / 自定义部署方式
    if [[ -f "${acme_home}/custom.acme.sh" ]]; then
        echo "Found ${acme_home}/custom.acme.sh"
        bash "${acme_home}/custom.acme.sh"
    fi
    _msg time "[cert] completed"

    if ${GH_ACTION:-false}; then
        return 0
    fi
    if ${exec_single_job:-false}; then
        exit 0
    fi
}

# Install required tools based on environment variables
# Returns:
#   0 if all installations were successful
#   1 if any installation failed
system_install_tools() {
    local install_result=0

    ## 基础工具安装
    if ! command -v jq &>/dev/null; then
        _check_sudo
        _install_packages "$IS_CHINA" jq || ((install_result++))
    fi
    if ! command -v yq &>/dev/null; then
        _check_sudo
        case "$(uname -s)" in
        Linux)
            if curl -fLo /tmp/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64; then
                $use_sudo install -m 0755 /tmp/yq /usr/local/bin/yq || ((install_result++))
            else
                ((install_result++))
            fi
            ;;
        Darwin)
            if command -v brew &>/dev/null; then
                brew install yq || ((install_result++))
            else
                if curl -fLo /tmp/yq https://github.com/mikefarah/yq/releases/latest/download/yq_darwin_amd64; then
                    $use_sudo install -m 0755 /tmp/yq /usr/local/bin/yq || ((install_result++))
                else
                    ((install_result++))
                fi
            fi
            ;;
        *)
            _msg error "Unsupported operating system for yq installation"
            ((install_result++))
            ;;
        esac
    fi

    ## 云服务工具安装
    ([ "${ENV_DOCKER_LOGIN_TYPE:-}" = aws ] || ${ENV_INSTALL_AWS:-false}) && _install_aws
    ${ENV_INSTALL_ALIYUN:-false} && _install_aliyun_cli

    ## 基础设施工具安装
    ${ENV_INSTALL_TERRAFORM:-false} && _install_terraform
    ${ENV_INSTALL_KUBECTL:-false} && _install_kubectl
    ${ENV_INSTALL_HELM:-false} && _install_helm

    ## 集成工具安装
    ${ENV_INSTALL_PYTHON_ELEMENT:-false} && _install_python_element "$@" "$IS_CHINA"
    ${ENV_INSTALL_PYTHON_GITLAB:-false} && _install_python_gitlab "$@" "$IS_CHINA"
    ${ENV_INSTALL_JMETER:-false} && _install_jmeter
    ${ENV_INSTALL_FLARECTL:-false} && _install_flarectl

    ## 容器工具安装
    ${ENV_INSTALL_DOCKER:-false} && _install_docker "$([[ "$IS_CHINA" == "true" ]] && echo "--mirror Aliyun" || echo "")"
    ${ENV_INSTALL_PODMAN:-false} && _install_podman

    return "$install_result"
}
