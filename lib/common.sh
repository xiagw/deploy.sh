# shellcheck shell=bash
# shellcheck disable=SC2034,SC1090,SC1091
# 兼容sh/bash/zsh，少使用新命令

# 定义全局命令变量
CMD_READLINK=$(command -v greadlink || command -v readlink)
CMD_DATE=$(command -v gdate || command -v date)
CMD_GREP=$(command -v ggrep || command -v grep)
CMD_SED=$(command -v gsed || command -v sed)
CMD_AWK=$(command -v gawk || command -v awk)
CMD_CURL=$(command -v /usr/local/opt/curl/bin/curl || command -v curl || :)

# 定义日志级别常量
LOG_LEVEL_ERROR=0
LOG_LEVEL_WARNING=1
LOG_LEVEL_INFO=2
LOG_LEVEL_SUCCESS=3
LOG_LEVEL_FILE=4

# 定义颜色代码
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[0;33m'
COLOR_GREEN='\033[0;32m'
COLOR_RESET='\033[0m'

_log() {
    local level=$1
    shift
    local message="$*"
    local level_name
    local color

    case $level in
    "$LOG_LEVEL_ERROR")
        level_name="ERROR"
        color="$COLOR_RED"
        ;;
    "$LOG_LEVEL_WARNING")
        level_name="WARNING"
        color="$COLOR_YELLOW"
        ;;
    "$LOG_LEVEL_INFO")
        level_name="INFO"
        color="$COLOR_RESET"
        ;;
    "$LOG_LEVEL_SUCCESS")
        level_name="SUCCESS"
        color="$COLOR_GREEN"
        ;;
    "$LOG_LEVEL_FILE")
        level_name="FILE"
        color="$COLOR_RESET"
        ;;
    *)
        level_name="UNKNOWN"
        color="$COLOR_RESET"
        ;;
    esac

    if [[ $CURRENT_LOG_LEVEL -ge $level ]]; then
        if [[ $level -eq $LOG_LEVEL_FILE ]]; then
            # 输出到日志文件，不使用颜色
            echo "[${level_name}] $(date '+%Y-%m-%d %H:%M:%S') - $message" >>"$LOG_FILE"
        else
            # 输出到终端，使用颜色
            echo -e "${color}[${level_name}] $(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET} - $message" >&2
        fi
    fi
}

_check_commands() {
    # 检查必要的命令是否可用
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            _log $LOG_LEVEL_ERROR "$cmd command not found. Please install $cmd."
            return 1
        fi
    done
}

_check_disk_space() {
    local required_space_gb=$1
    # 检查磁盘空间
    local available_space
    available_space=$(df -k . | awk 'NR==2 {print $4}')
    local required_space=$((required_space_gb * 1024 * 1024)) # 转换为 KB
    if [[ $available_space -lt $required_space ]]; then
        _log $LOG_LEVEL_ERROR "Not enough disk space. Required: ${required_space_gb}GB, Available: $((available_space / 1024 / 1024))GB"
        return 1
    fi
    _log $LOG_LEVEL_INFO "Sufficient disk space available. Required: ${required_space_gb}GB, Available: $((available_space / 1024 / 1024))GB"
}

_msg() {
    local color_on color_off='\033[0m'
    local time_hms="$((SECONDS / 3600))h$(((SECONDS / 60) % 60))m$((SECONDS % 60))s"
    local timestamp
    timestamp="$($CMD_DATE +%Y%m%d-%u-%T.%3N)"

    case "${1:-none}" in
    info) color_on='' ;;
    warn | warning | yellow) color_on='\033[0;33m' ;;
    error | err | red) color_on='\033[0;31m' ;;
    question | ques | purple) color_on='\033[0;35m' ;;
    success | green) color_on='\033[0;32m' ;;
    blue) color_on='\033[0;34m' ;;
    cyan) color_on='\033[0;36m' ;;
    orange) color_on='\033[1;33m' ;;
    step)
        ((++STEP))
        color_on="\033[0;36m$timestamp - [$STEP] \033[0m"
        color_off=" - [$time_hms]"
        ;;
    time)
        color_on="$timestamp - ${STEP:+[$STEP] }"
        color_off=" - [$time_hms]"
        ;;
    log)
        local log_file="$2"
        shift 2
        if [ -d "$(dirname "$log_file")" ]; then
            echo "$timestamp - $*" | tee -a "$log_file"
        else
            echo "$timestamp - $*"
        fi
        return
        ;;
    *) unset color_on color_off ;;
    esac

    [ "$#" -gt 1 ] && shift
    if [ "${silent_mode:-0}" -eq 0 ]; then
        printf "%b%s%b\n" "${color_on}" "$*" "${color_off}"
    else
        return 0
    fi
}

_check_root() {
    case "$(id -u)" in
    0) unset use_sudo && return 0 ;;
    *) use_sudo=sudo && return 1 ;;
    esac
}

_check_distribution() {
    _msg time "Check distribution..."
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        version_id="${VERSION_ID:-}"
        # lsb_dist="${ID,,}"
        lsb_dist="$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')"
    else
        lsb_dist=$(
            case "$OSTYPE" in
            solaris*) echo "solaris" ;;
            darwin*) echo "macos" ;;
            linux*) echo "linux" ;;
            bsd*) echo "bsd" ;;
            msys*) echo "windows" ;;
            cygwin*) echo "alsowindows" ;;
            *) echo "unknown" ;;
            esac
        )
    fi
    lsb_dist="${lsb_dist:-unknown}"
    _msg time "Your distribution is ${lsb_dist}, ARCH is $(uname -m)."
}

_check_cmd() {
    if [[ "$1" == install ]]; then
        shift
        local updated=0
        for c in "$@"; do
            if ! command -v "$c" &>/dev/null; then
                if [[ $updated -eq 0 && "${apt_update:-0}" -eq 1 ]]; then
                    ${cmd_pkg-} update -yqq
                    updated=1
                fi
                pkg=$c
                [[ "$c" == strings ]] && pkg=binutils
                $cmd_pkg install -y "$pkg"
            fi
        done
    else
        command -v "$@"
    fi
}

_set_package_manager() {
    for pkg_manager in apt apt-get yum dnf microdnf pacman apk brew; do
        if command -v "$pkg_manager" &>/dev/null; then
            case $pkg_manager in
            apt | apt-get)
                cmd_pkg="$use_sudo apt-get"
                cmd_pkg_install="$cmd_pkg install -yqq"
                apt_update=1
                ;;
            yum | dnf | microdnf)
                cmd_pkg="$use_sudo $pkg_manager"
                cmd_pkg_install="$cmd_pkg install -y"
                ;;
            pacman)
                cmd_pkg="$use_sudo pacman"
                cmd_pkg_install="$cmd_pkg -S --noconfirm"
                ;;
            apk)
                cmd_pkg="$use_sudo apk"
                cmd_pkg_install="$cmd_pkg add --no-cache"
                ;;
            brew)
                cmd_pkg="brew"
                cmd_pkg_install="$cmd_pkg install"
                ;;
            esac
            return 0
        fi
    done
    _msg error "No supported package manager found."
    return 1
}

_install_packages() {
    [ "$#" -eq 0 ] && return 0
    _is_china && _set_mirror os
    if [[ "${apt_update:-0}" -eq 1 ]]; then
        $cmd_pkg update -yqq
        apt_update=0
    fi
    $cmd_pkg_install "${@}"
}

_check_sudo() {
    ${already_check_sudo:-false} && return 0
    if ! _check_root; then
        if ! $use_sudo -l -U "$USER" &>/dev/null; then
            _msg error "User $USER has no sudo permissions."
            _msg info "Please run visudo with root, and set sudo for ${USER}."
            return 1
        fi
        _msg success "User $USER has sudo permissions."
    fi

    if _set_package_manager; then
        already_check_sudo=true
        return 0
    fi
    return 1
}

_check_timezone() {
    ## change UTC to CST
    local time_zone='Asia/Shanghai'
    _msg step "Check timezone $time_zone."
    if timedatectl show --property=Timezone --value | grep -q "^$time_zone$"; then
        _msg time "Timezone is already set to $time_zone."
    else
        _msg time "Setting timezone to $time_zone."
        $use_sudo timedatectl set-timezone "$time_zone"
    fi
}

_get_yes_no() {
    read -rp "${1:-Confirm the action?} [y/N] " -n 1 read_yes_no
    [[ ${read_yes_no,,} == y ]] && return 0 || return 1
}

_get_random_password() {
    local cmd_hash bits=${1:-14}
    cmd_hash=$(command -v md5sum || command -v sha256sum || command -v md5 2>/dev/null)
    count=0
    while [ -z "$password_rand" ] || [ "${#password_rand}" -lt "$bits" ]; do
        ((++count))
        case $count in
        1) password_rand="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c"$bits" 2>/dev/null)" ;;
        2) password_rand="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c"$bits" 2>/dev/null)" ;;
        3) password_rand="$(dd if=/dev/urandom bs=1 count=15 | base64 | head -c"$bits" 2>/dev/null)" ;;
        4) password_rand=$(openssl rand -base64 20 | tr -dc A-Za-z0-9 | head -c"$bits" 2>/dev/null) ;;
        5) password_rand="$(echo "$RANDOM$($CMD_DATE)$RANDOM" | $cmd_hash | base64 | head -c"$bits" 2>/dev/null)" ;;
        *) echo "${password_rand:?Failed-to-generate-password}" && return 1 ;;
        esac
    done
    echo "$password_rand"
}

_get_current_ip() {
    _check_distribution
    case "$lsb_dist" in
    macos)
        ip4_current=$(curl -x '' -4 --connect-timeout 10 -fsSL 4.ipw.cn)
        c=0
        while [ -z "$ip6_current" ]; do
            ((++c))
            case $c in
            1) ip6_current=$(curl -x '' -6 --connect-timeout 10 -fsSL 6.ipw.cn | tail -n 1) ;;
            2) ip6_current=$(ifconfig en0 | awk '/inet6.*temporary/ {print $2}' | head -n 1) ;;
            *) break ;;
            esac
        done
        ;;
    *)
        if grep -i -q 'ID="openwrt2"' /etc/os-release; then
            . /lib/functions/network.sh
            network_flush_cache
            network_find_wan NET_IF
            network_get_ipaddr NET_ADDR "${NET_IF}"
            ip4_current="${NET_ADDR}"
            network_find_wan6 NET_IF
            network_get_ipaddr6 NET_ADDR "${NET_IF}"
            ip6_current="${NET_ADDR}"
        else
            ip4_current=$(ip -4 addr list scope global "${wan_device:-pppoe-wan}" | awk '/inet/ {print $2}' | head -n 1)
            ip6_current=$(ip -6 addr list scope global "${wan_device:-pppoe-wan}" | awk '/inet6/ {print $2}' | head -n 1)
        fi
        ;;
    esac
    _msg green "get current IPv4: $ip4_current"
    _msg green "get current IPv6: $ip6_current"
}

_install_jmeter() {
    if [ "$1" != "upgrade" ] && command -v jmeter >/dev/null; then
        return
    fi
    _msg green "Installing JMeter..."
    local ver_jmeter='5.4.1'
    local temp_file
    temp_file=$(mktemp)

    ## 6. Asia, 31. Hong_Kong, 70. Shanghai
    if ! command -v java >/dev/null; then
        _msg green "Installing Java..."
        export DEBIAN_FRONTEND=noninteractive
        export DEBCONF_NONINTERACTIVE_SEEN=true
        export TZ=Asia/Shanghai

        # Set timezone
        echo "tzdata tzdata/Areas select Asia" | ${use_sudo:-} debconf-set-selections
        echo "tzdata tzdata/Zones/Asia select Shanghai" | $use_sudo debconf-set-selections

        # Update and install Java
        $use_sudo apt-get update -qq
        $use_sudo apt-get install -qq tzdata openjdk-17-jdk

        unset DEBIAN_FRONTEND DEBCONF_NONINTERACTIVE_SEEN TZ
    fi

    # Download and install JMeter
    local url="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${ver_jmeter}.zip"
    curl -sSL -o "$temp_file" "$url"
    $use_sudo unzip -q "$temp_file" -d /usr/local/
    $use_sudo ln -sf "/usr/local/apache-jmeter-${ver_jmeter}" /usr/local/jmeter
    rm -f "$temp_file"

    # Add JMeter to PATH
    echo "export PATH=\$PATH:/usr/local/jmeter/bin" | $use_sudo tee -a /etc/profile.d/jmeter.sh
    source /etc/profile.d/jmeter.sh
}

_install_wg() {
    if [ "$1" != "upgrade" ] && command -v wg >/dev/null; then
        return
    fi
    case "${lsb_dist-}" in
    centos | alinux | openEuler)
        ${cmd_pkg-} install -y epel-release elrepo-release
        $cmd_pkg install -y yum-plugin-elrepo
        $cmd_pkg install -y kmod-wireguard wireguard-tools
        ;;
    *)
        $cmd_pkg install -yqq wireguard wireguard-tools
        ;;
    esac
    $use_sudo modprobe wireguard
}

_install_ossutil() {
    # 如果已安装且不是升级则直接返回
    if [ "$1" != "upgrade" ] && command -v ossutil >/dev/null; then
        return
    fi

    # 确定版本和命令
    local ver=2 cmd=/usr/local/bin/ossutil
    if [[ "${2:-2}" = 1 || "${2:-2}" = v1 ]]; then
        local ver='' cmd=/usr/local/bin/ossutil1
    fi

    # 获取系统类型
    _check_distribution
    local os=${lsb_dist/ubuntu/linux}
    os=${os/centos/linux}
    os=${os/macos/mac}

    # 下载安装
    local url_doc="https://help.aliyun.com/zh/oss/developer-reference/install-ossutil$ver"
    local url_down
    url_down=$(curl -fsSL "$url_doc" | grep -oE 'href="[^\"]+"' | grep -o "https.*ossutil.*${os}-amd64\.zip")
    curl -fLo ossu.zip "$url_down" && unzip -qq -o -j ossu.zip
    _msg green "Installing to $cmd"
    $use_sudo install -m 0755 ossutil "$cmd"

    # 创建版本软链接
    _msg green "Creating symlink /usr/local/bin/oss${ver:-1} to $cmd"
    $use_sudo ln -sf "$cmd" "/usr/local/bin/oss${ver:-1}"

    # 清理并显示版本
    _msg green "Showing version"
    if [[ "${ver:-2}" = 2 ]]; then
        $cmd version
    else
        $cmd --version
    fi
    rm -f ossu.zip ossutil ossutil64 ossutilmac64
}

_install_aliyun_cli() {
    if [ "$1" != "upgrade" ] && command -v aliyun >/dev/null; then
        return
    fi
    _check_distribution
    local os=${lsb_dist/ubuntu/linux}
    os=${os/centos/linux}
    local url="https://help.aliyun.com/zh/cli/install-cli-on-${os}"
    local url_down
    url_down=$(curl -fsSL "$url" | grep -oE 'href="[^\"]+"' | grep -o "https.*aliyun-cli.*${os}.*\.tgz")
    local temp_dir
    temp_dir=$(mktemp -d)
    curl -fLo "$temp_dir/aly.tgz" "$url_down"
    tar -xzf "$temp_dir/aly.tgz" -C "$temp_dir"
    local cmd=/usr/local/bin/aliyun
    _msg green "Installing to $cmd"
    $use_sudo install -m 0755 "$temp_dir/aliyun" "$cmd"
    _msg green "Showing version"
    "$cmd" version | head -n 1
    rm -rf "$temp_dir"
}

_install_flarectl() {
    if [ "$1" != "upgrade" ] && command -v flarectl >/dev/null; then
        return
    fi
    _msg green "Installing flarectl"
    local ver='0.107.0'
    local temp_file
    temp_file="$(mktemp)"
    local url="https://github.com/cloudflare/cloudflare-go/releases/download/v${ver}/flarectl_${ver}_linux_amd64.tar.gz"

    if curl -fsSLo "$temp_file" $url; then
        _msg green "Extracting flarectl to /tmp"
        tar -C /tmp -xzf "$temp_file" flarectl
        _msg green "Installing to /usr/local/bin/flarectl"
        $use_sudo install -m 0755 /tmp/flarectl /usr/local/bin/flarectl
        _msg success "flarectl installed successfully"
    else
        _msg error "failed to download and install flarectl"
        return 1
    fi
    rm -f "$temp_file" /tmp/flarectl
}

_install_jq_cli() {
    if [ "$1" != "upgrade" ] && command -v jq >/dev/null; then
        return
    fi

    _msg green "Installing jq cli..."
    case "$lsb_dist" in
    debian | ubuntu | linuxmint | linux)
        $use_sudo apt-get update -qq
        $use_sudo apt-get install -yqq jq >/dev/null
        ;;
    centos | amzn | rhel | fedora)
        $use_sudo yum install -y jq >/dev/null
        ;;
    alpine)
        $use_sudo apk add --no-cache jq >/dev/null
        ;;
    *)
        echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2 or Arch Linux system"
        _msg error "Unsupported. exit."
        return 1
        ;;
    esac
}

_install_kubectl() {
    if [ "$1" != "upgrade" ] && command -v kubectl >/dev/null; then
        return
    fi
    _msg green "Installing kubectl..."
    local ver
    ver=$(curl -sL https://dl.k8s.io/release/stable.txt)
    local cmd=/usr/local/bin/kubectl
    curl -fsSLO "https://dl.k8s.io/release/${ver}/bin/linux/amd64/kubectl" \
        -fsSLO "https://dl.k8s.io/${ver}/bin/linux/amd64/kubectl.sha256"
    if echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check; then
        _msg green "Installing to $cmd"
        $use_sudo install -m 0755 kubectl "$cmd"
        _msg green "Showing version"
        "$cmd" version --client
        rm -f kubectl kubectl.sha256
    else
        _msg error "failed to install kubectl"
        return 1
    fi
}

_install_helm() {
    if [ "$1" != "upgrade" ] && command -v helm >/dev/null; then
        return
    fi
    _msg green "Installing helm..."
    local temp_file
    temp_file="$(mktemp)"
    local cmd=/usr/local/bin/helm
    curl -fsSLo "$temp_file" https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
    export HELM_INSTALL_DIR=/usr/local/bin
    $use_sudo bash "$temp_file"
    rm -f "$temp_file"
    _msg green "Showing version"
    "$cmd" version
}

_install_tencent_cli() {
    if [ "$1" != "upgrade" ] && command -v tccli >/dev/null; then
        return
    fi
    _msg green "install tencent cli..."
    _is_china && _set_mirror python
    python3 -m pip install tccli
    _msg green "Showing version"
    tccli --version
}

_install_terraform() {
    if [ "$1" != "upgrade" ] && command -v terraform >/dev/null; then
        return
    fi
    _msg green "Installing terraform..."
    $use_sudo apt-get update -qq && $use_sudo apt-get install -yqq gnupg software-properties-common curl
    curl -fsSL https://apt.releases.hashicorp.com/gpg |
        gpg --dearmor |
        $use_sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null 2>&1
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" |
        $use_sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null 2>&1
    $use_sudo apt-get update -qq
    $use_sudo apt-get install -yqq terraform >/dev/null
    # terraform version
    _msg green "terraform installed successfully!"
    _msg green "Showing version"
    terraform version
}

_install_aws() {
    if [ "$1" != "upgrade" ] && command -v aws >/dev/null; then
        return
    fi
    _msg green "Installing aws cli..."
    local temp_file
    temp_file=$(mktemp)
    curl -fsSLo "$temp_file" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    unzip -qq "$temp_file" -d /tmp
    $use_sudo /tmp/aws/install --bin-dir /usr/local/bin/ --install-dir /usr/local/ --update
    rm -rf /tmp/aws "$temp_file"
    ## install eksctl / 安装 eksctl
    local cmd=/usr/local/bin/eksctl
    curl -fsSL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    _msg green "Installing to $cmd"
    $use_sudo install -m 0755 /tmp/eksctl "$cmd"
    _msg green "Showing version"
    "$cmd" version
}

_install_python_gitlab() {
    if [ "$1" != "upgrade" ] && command -v gitlab >/dev/null; then
        return
    fi
    _msg green "Installing python3 gitlab api..."
    _is_china && _set_mirror python
    if python3 -m pip install --user --upgrade python-gitlab; then
        _msg green "python-gitlab is installed successfully"
        _msg green "Showing version"
        /root/.local/bin/gitlab --version
    else
        _msg error "failed to install python-gitlab"
    fi
}

_install_python_element() {
    if [ "$1" != "upgrade" ] && python3 -m pip list 2>/dev/null | grep -q matrix-nio; then
        return
    fi
    _msg green "Installing python3 element api..."
    _is_china && _set_mirror python
    if python3 -m pip install --user --upgrade matrix-nio; then
        _msg green "matrix-nio is installed successfully"
    else
        _msg error "failed to install matrix-nio"
    fi
}

_install_docker() {
    if [ "$1" != "upgrade" ] && command -v docker &>/dev/null; then
        return
    fi
    _msg green "Installing docker"
    local temp_file
    temp_file=$(mktemp)
    curl -fsSLo "$temp_file" https://get.docker.com
    $use_sudo bash "$temp_file" "$@"
    _msg green "Showing version"
    docker --version
    rm -f "$temp_file"
}

_install_podman() {
    if [ "$1" != "upgrade" ] && command -v podman &>/dev/null; then
        return
    fi
    _msg green "Installing podman"
    $use_sudo apt-get update -qq
    $use_sudo apt-get install -yqq podman >/dev/null
    _msg green "Showing version"
    podman --version
}

_install_cron() {
    if [ "$1" != "upgrade" ] && command -v crontab &>/dev/null; then
        return
    fi
    _msg green "Installing cron"
    $use_sudo apt-get update -qq
    $use_sudo apt-get install -yqq cron >/dev/null
}

_notify_wecom() {
    local wecom_key="$1"
    local g_msg_body="$2"
    local wecom_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${wecom_key}"
    curl -fsSL -X POST -H 'Content-Type: application/json' \
        -d '{"msgtype": "text", "text": {"content": "'"${g_msg_body:-g_msg_body undefined}"'"}}' "$wecom_api"
    echo
}

_set_mirror() {
    case ${1:-none} in
    os)
        ## OS ubuntu:22.04 php
        if [ -f /etc/apt/sources.list ]; then
            $use_sudo sed -i -e 's/deb.debian.org/mirrors.ustc.edu.cn/g' \
                -e 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
        ## OS Debian
        elif [ -f /etc/apt/sources.list.d/debian.sources ]; then
            $use_sudo sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources
        ## OS alpine, nginx:alpine
        elif [ -f /etc/apk/repositories ]; then
            # sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories
            $use_sudo sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
        fi
        ;;
    maven)
        local m2_path=/root/.m2
        local settings_url=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/settings.xml
        mkdir -p $m2_path
        ## 项目内自带 settings.xml docs/settings.xml
        if [ -f settings.xml ]; then
            cp -vf settings.xml $m2_path/
        elif [ -f docs/settings.xml ]; then
            cp -vf docs/settings.xml $m2_path/
        elif [ -f /opt/settings.xml ]; then
            mv -vf /opt/settings.xml $m2_path/
        else
            curl -Lo $m2_path/settings.xml $settings_url
        fi
        ;;
    composer)
        _check_root || return
        composer config -g repo.packagist composer https://mirrors.aliyun.com/composer/
        mkdir -p /var/www/.composer /.composer
        chown -R 1000:1000 /var/www/.composer /.composer /tmp/cache /tmp/config.json /tmp/auth.json
        ;;
    node)
        # npm_mirror=https://mirrors.ustc.edu.cn/node/
        # npm_mirror=http://mirrors.cloud.tencent.com/npm/
        # npm_mirror=https://mirrors.huaweicloud.com/repository/npm/
        npm_mirror=https://registry.npmmirror.com/
        yarn config set registry $npm_mirror
        npm config set registry $npm_mirror
        ;;
    python)
        pip_mirror=https://pypi.tuna.tsinghua.edu.cn/simple
        python3 -m pip config set global.index-url $pip_mirror
        ;;
    *)
        echo "Nothing to do."
        ;;
    esac
}

get_oom_score() {
    while read -r proc; do
        printf "%2d      %5d       %s\n" \
            "$(cat "$proc"/oom_score)" \
            "$(basename "$proc")" \
            "$(tr '\0' ' ' <"$proc"/cmdline | head -c 50)"
    done < <(find /proc -maxdepth 1 -regex '/proc/[0-9]+' 2>/dev/null | sort -nr | head -n 15)
}

clean_snap() {
    ## Removes old revisions of snaps
    ## CLOSE ALL SNAPS BEFORE RUNNING THIS
    while read -r snapname revision; do
        sudo snap remove "$snapname" --revision="$revision"
    done < <(LANG=en_US.UTF-8 snap list --all | awk '/disabled/{print $1, $3}')
}

clean_runtime() {
    ## clean thinkphp runtime/log
    while read -r line; do
        echo "$line"
        sudo rm -rf "$line"/log/*
        ## fix thinkphp runtime perm
        sudo chown -R 33:33 "$line"
    done < <(find . -type d -iname runtime)
}

# 获取 GitHub 仓库的最新发布版本下载链接
get_github_latest_download() {
    local repo="$1"
    local source_only="false" # 是否只获取源码包
    local arch="amd64"        # 架构，默认amd64
    local os="linux"          # 操作系统，默认linux

    # 解析命名参数
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
        source_only=*) source_only="${1#*=}" ;;
        arch=*) arch="${1#*=}" ;;
        os=*) os="${1#*=}" ;;
        *) _msg warning "Unknown parameter: $1" ;;
        esac
        shift
    done

    # 标准化操作系统名称（使用 tr 替代 ${var,,}）
    os=$(echo "$os" | tr '[:upper:]' '[:lower:]')
    case "$os" in
    mac* | darwin*) os="darwin" ;;
    win*) os="windows" ;;
    linux*) os="linux" ;;
    freebsd*) os="freebsd" ;;
    openbsd*) os="openbsd" ;;
    *) _msg warning "Unknown OS: $os, using linux" && os="linux" ;;
    esac

    # 标准化架构名称
    arch=$(echo "$arch" | tr '[:upper:]' '[:lower:]')
    case "$arch" in
    x86_64 | x64 | amd64) arch="amd64" ;; # 把 amd64 也放在这里
    x86 | 386) arch="386" ;;
    aarch64 | arm64) arch="arm64" ;; # 把 arm64 也放在这里
    armv*) ;;                        # 保持原样 armv6/armv7 等
    *)
        if [ "$arch" != "amd64" ]; then
            _msg warning "Unknown architecture: $arch, using amd64"
            arch="amd64"
        fi
        ;;
    esac

    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local latest_ver
    local download_url

    # 获取最新版本信息并处理可能的错误
    local release_info
    release_info=$(curl -sS -H "Accept: application/vnd.github.v3+json" "$api_url")
    if [ $? -ne 0 ] || [ -z "$release_info" ]; then
        _msg warning "Failed to fetch release info from GitHub API"
        echo "https://github.com/$repo/archive/refs/heads/master.tar.gz"
        return
    fi

    # 使用 grep 和 sed 来提取版本号，避免 JSON 解析问题
    latest_ver=$(echo "$release_info" | grep -o '"tag_name": *"[^"]*"' | sed 's/.*": *"//;s/"//')
    if [ -z "$latest_ver" ]; then
        _msg warning "Failed to parse release version"
        echo "https://github.com/$repo/archive/refs/heads/master.tar.gz"
        return
    fi

    if [ "$source_only" = "false" ]; then
        # 构建操作系统名称的搜索模式
        local os_pattern
        case "$os" in
        darwin) os_pattern="darwin\|mac\|macos" ;;
        windows) os_pattern="windows\|win" ;;
        linux) os_pattern="linux" ;;
        freebsd) os_pattern="freebsd" ;;
        openbsd) os_pattern="openbsd" ;;
        *) os_pattern="$os" ;;
        esac

        # 使用 grep 和 sed 来提取下载链接，避免 JSON 解析问题
        # 使用不区分大小写的匹配和扩展的操作系统名称模式
        pattern="\"browser_download_url\": *\"[^\"]*\(${os_pattern}\)[^\"]*${arch}[^\"]*\""
        download_url=$(echo "$release_info" | grep -io "$pattern" |
            sed 's/.*": *"//;s/"//' | head -n 1)
        if [ -n "$download_url" ]; then
            echo "$download_url"
            return
        fi

        # 如果没找到，尝试反向顺序（架构在前，系统在后）的匹配
        pattern="\"browser_download_url\": *\"[^\"]*${arch}[^\"]*\(${os_pattern}\)[^\"]*\""
        download_url=$(echo "$release_info" | grep -io "$pattern" |
            sed 's/.*": *"//;s/"//' | head -n 1)
        if [ -n "$download_url" ]; then
            echo "$download_url"
            return
        fi
    fi

    # 如果没有二进制包或指定只要源码包，返回源码包链接
    echo "https://github.com/$repo/archive/refs/tags/${latest_ver}.tar.gz"
}

# 安装或升级 acme.sh with official
_install_acme_official() {
    local force=${1:-}
    local cmd_acme="$HOME/.acme.sh/acme.sh"
    if [ "$force" != "upgrade" ] && [ -x "$cmd_acme" ]; then
        return
    fi

    _msg green "Installing acme.sh..."
    if ${IN_CHINA:-false}; then
        git clone --depth 1 https://gitee.com/neilpang/acme.sh.git
        cd acme.sh && ./acme.sh --install --accountemail deploy@deploy.sh
    else
        curl https://get.acme.sh | bash -s email=deploy@deploy.sh
    fi
    _msg green "Showing version"
    "$cmd_acme" --version
}

# 安装或升级 acme.sh via source code on github
_install_acme_github() {
    local force=${1:-}
    if [ "$force" != "upgrade" ] && command -v acme.sh >/dev/null; then
        return
    fi
    _msg green "Installing acme.sh..."
    local temp_dir
    temp_dir=$(mktemp -d)
    local download_url
    download_url=$(get_github_latest_download "acmesh-official/acme.sh" source_only=true)

    curl -fsSL "$download_url" | tar xz -C "$temp_dir" --strip-components=1
    cd "$temp_dir" || exit
    ./acme.sh --install --accountemail deploy@deploy.sh

    cd - || exit
    rm -rf "$temp_dir"

    # 显示版本
    _msg green "Showing version"
    "$HOME/.acme.sh/acme.sh" --version
}

# 压缩 PDF 文件的内部函数
_compress_pdf_with_gs() {
    local input_pdf="$1"
    local output_pdf="$2"
    local quality="${3:-ebook}"
    local compatibility="${4:-1.4}"

    # 验证兼容性级别参数
    case "$compatibility" in
        1.4|1.5|1.6|1.7) ;;
        *)
            _msg warning "Invalid compatibility level: $compatibility, using 1.4"
            compatibility="1.4"
            ;;
    esac

    # 设置压缩质量参数
    local resolution
    local image_downsample
    local color_image_quality
    local gray_image_quality
    local mono_image_quality

    case "$quality" in
        screen)  # 最大压缩率
            resolution=72
            image_downsample=72
            color_image_quality=25
            gray_image_quality=25
            mono_image_quality=25
            ;;
        ebook)   # 平衡模式
            resolution=150
            image_downsample=150
            color_image_quality=60
            gray_image_quality=60
            mono_image_quality=60
            ;;
        printer) # 较好质量
            resolution=300
            image_downsample=300
            color_image_quality=90
            gray_image_quality=90
            mono_image_quality=90
            ;;
        prepress) # 最佳质量
            resolution=600
            image_downsample=600
            color_image_quality=100
            gray_image_quality=100
            mono_image_quality=100
            ;;
        *)
            _msg warning "Invalid quality level: $quality, using ebook"
            resolution=150
            image_downsample=150
            color_image_quality=60
            gray_image_quality=60
            mono_image_quality=60
            ;;
    esac

    gs -sDEVICE=pdfwrite \
        -dCompatibilityLevel="$compatibility" \
        -dPDFSETTINGS=/"$quality" \
        -dNOPAUSE -dQUIET -dBATCH \
        -dDownsampleColorImages=true \
        -dColorImageDownsampleType=/Bicubic \
        -dColorImageResolution="$resolution" \
        -dDownsampleGrayImages=true \
        -dGrayImageDownsampleType=/Bicubic \
        -dGrayImageResolution="$resolution" \
        -dDownsampleMonoImages=true \
        -dMonoImageDownsampleType=/Bicubic \
        -dMonoImageResolution="$resolution" \
        -dColorImageDownsampleThreshold=1.0 \
        -dGrayImageDownsampleThreshold=1.0 \
        -dMonoImageDownsampleThreshold=1.0 \
        -dCompressPages=true \
        -dUseFlateCompression=true \
        -dEmbedAllFonts=true \
        -dSubsetFonts=true \
        -dDetectDuplicateImages=true \
        -dOptimize=true \
        -dAutoFilterColorImages=true \
        -dAutoFilterGrayImages=true \
        -dColorImageFilter=/DCTEncode \
        -dGrayImageFilter=/DCTEncode \
        -dColorConversionStrategy=/sRGB \
        -dCompatibilityLevel="$compatibility" \
        -dProcessColorModel=/DeviceRGB \
        -dConvertCMYKImagesToRGB=true \
        -dCompressFonts=true \
        -dUseCIEColor=true \
        -dPrinted=false \
        -dCannotEmbedFontPolicy=/Warning \
        -sOutputFile="$output_pdf" \
        "$input_pdf"

    local ret=$?
    if [ $ret -eq 0 ]; then
        local original_size
        local compressed_size
        original_size=$(du -h "$input_pdf" | cut -f1)
        compressed_size=$(du -h "$output_pdf" | cut -f1)
        local original_bytes
        local compressed_bytes
        original_bytes=$(stat -f%z "$input_pdf" 2>/dev/null || stat -c%s "$input_pdf")
        compressed_bytes=$(stat -f%z "$output_pdf" 2>/dev/null || stat -c%s "$output_pdf")
        local compression_ratio
        compression_ratio=$(awk "BEGIN {printf \"%.2f\", ($compressed_bytes/$original_bytes)*100}")

        _msg success "PDF compression completed:"
        _msg info "Original size: $original_size"
        _msg info "Compressed size: $compressed_size"
        _msg info "Compression ratio: ${compression_ratio}%"
        _msg info "Output file: $output_pdf"
        return 0
    else
        _msg error "PDF compression failed"
        return 1
    fi
}

_compress_document() {
    local input_file="$1"
    local output_file="${2:-}"
    local quality="${3:-ebook}"
    local compatibility="${4:-1.4}"  # 新增参数

    # 检查输入文件是否存在
    if [ ! -f "$input_file" ]; then
        _msg error "Input file does not exist: $input_file"
        return 1
    fi

    # 检查必要的命令
    if ! _check_commands gs libreoffice; then
        _msg info "Installing required packages..."
        _install_packages ghostscript libreoffice
    fi

    # 获取文件扩展名
    local ext="${input_file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    case "$ext" in
    pdf)
        # 如果没有指定输出文件，则使用原文件名加上 _compressed 后缀
        if [ -z "$output_file" ]; then
            output_file="${input_file%.*}_compressed.pdf"
        fi
        _compress_pdf_with_gs "$input_file" "$output_file" "$quality" "$compatibility"
        ;;

    ppt | pptx)
        # 如果没有指定输出文件，则使用原文件名加上 _compressed 后缀
        if [ -z "$output_file" ]; then
            output_file="${input_file%.*}_compressed.pdf"
        fi

        # 创建临时目录
        local temp_dir
        temp_dir=$(mktemp -d)

        # 使用 LibreOffice 转换为 PDF
        _msg info "Converting PPT to PDF..."
        libreoffice --headless --convert-to pdf --outdir "$temp_dir" "$input_file"
        local ret="$?"

        if [ "$ret" -eq 0 ]; then
            local temp_pdf
            temp_pdf="$temp_dir/$(basename "${input_file%.*}").pdf"

            # 使用抽取的函数压缩 PDF
            _msg info "Compressing converted PDF..."
            if ! _compress_pdf_with_gs "$temp_pdf" "$output_file" "$quality" "$compatibility"; then
                rm -rf "$temp_dir"
                return 1
            fi
        else
            _msg error "PPT to PDF conversion failed"
            rm -rf "$temp_dir"
            return 1
        fi

        # 清理临时文件
        rm -rf "$temp_dir"
        ;;

    *)
        _msg error "Unsupported file format: $ext"
        _msg info "Supported formats: pdf, ppt, pptx"
        return 1
        ;;
    esac
}
