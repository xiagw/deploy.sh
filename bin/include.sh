# shellcheck shell=bash
# shellcheck disable=SC2034,SC1090,SC1091

# Use gdate if available, otherwise fallback to date command
cmd_date="$(command -v gdate || command -v date)"

_msg() {
    local color_on color_off='\033[0m'
    local time_hms="$((SECONDS / 3600))h$(((SECONDS / 60) % 60))m$((SECONDS % 60))s"
    local timestamp
    timestamp="$($cmd_date +%Y%m%d-%u-%T.%3N)"

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
        5) password_rand="$(echo "$RANDOM$($cmd_date)$RANDOM" | $cmd_hash | base64 | head -c"$bits" 2>/dev/null)" ;;
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
    if [ "$1" != "upgrade" ] && command -v ossutil >/dev/null; then
        return
    fi
    _check_distribution
    local os=${lsb_dist/ubuntu/linux}
    os=${os/centos/linux}
    os=${os/macos/mac}
    local url
    url="https://help.aliyun.com/zh/oss/developer-reference/install-ossutil$([[ $1 == 1 || $1 == v1 ]] && echo '' || echo '2')"
    local url_down
    url_down=$(curl -fsSL "$url" | grep -oE 'href="[^\"]+"' | grep -o "https.*ossutil.*${os}-amd64\.zip")
    curl -fLo ossu.zip "$url_down"
    unzip -o -j ossu.zip
    $use_sudo install -m 0755 ossutil /usr/local/bin/ossutil
    ossutil version
    rm -f ossu.zip
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
    $use_sudo install -m 0755 "$temp_dir/aliyun" /usr/local/bin/aliyun
    aliyun --version | head -n 1
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
        tar -C /tmp -xzf "$temp_file" flarectl
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

    _msg green "install jq cli..."
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
    local kver
    kver=$(curl -sL https://dl.k8s.io/release/stable.txt)
    curl -fsSLO "https://dl.k8s.io/release/${kver}/bin/linux/amd64/kubectl" \
        -fsSLO "https://dl.k8s.io/${kver}/bin/linux/amd64/kubectl.sha256"
    if echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check; then
        $use_sudo install -m 0755 kubectl /usr/local/bin/kubectl
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
    curl -fsSLo "$temp_file" https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
    export HELM_INSTALL_DIR=/usr/local/bin
    $use_sudo bash "$temp_file"
    rm -f "$temp_file"
}

_install_tencent_cli() {
    if [ "$1" != "upgrade" ] && command -v tccli >/dev/null; then
        return
    fi
    _msg green "install tencent cli..."
    _is_china && _set_mirror python
    python3 -m pip install tccli
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
    curl -fsSL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    $use_sudo install -m 0755 /tmp/eksctl /usr/local/bin/
}

_install_python_gitlab() {
    if [ "$1" != "upgrade" ] && command -v gitlab >/dev/null; then
        return
    fi
    _msg green "Installing python3 gitlab api..."
    _is_china && _set_mirror python
    if python3 -m pip install --user --upgrade python-gitlab; then
        _msg green "python-gitlab is installed successfully"
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
    rm -f "$temp_file"
}

_install_podman() {
    if [ "$1" != "upgrade" ] && command -v podman &>/dev/null; then
        return
    fi
    _msg green "Installing podman"
    $use_sudo apt-get update -qq
    $use_sudo apt-get install -yqq podman >/dev/null
}

_install_cron() {
    if [ "$1" != "upgrade" ] && command -v crontab &>/dev/null; then
        return
    fi
    _msg green "Installing cron"
    $use_sudo apt-get update -qq
    $use_sudo apt-get install -yqq cron >/dev/null
}

_notify_weixin_work() {
    local wechat_key="$1"
    local wechat_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${wechat_key}"
    curl -fsSL -X POST -H 'Content-Type: application/json' \
        -d '{"msgtype": "text", "text": {"content": "'"${g_msg_body-}"'"}}' "$wechat_api"
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
