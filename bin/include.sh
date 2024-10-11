# shellcheck shell=bash
# shellcheck disable=SC2034

cmd_date="$(command -v gdate || command -v date)"

_msg() {
    local color_on color_off='\033[0m'
    local time_hms="$((SECONDS / 3600))h$(((SECONDS / 60) % 60))m$((SECONDS % 60))s"
    local timestamp
    timestamp="$(date +%Y%m%d-%u-%T.%3N)"

    case "${1:-none}" in
    info) color_on='' ;;
    warn | warning | yellow) color_on='\033[0;33m' ;;
    error | err | red) color_on='\033[0;31m' ;;
    question | ques | purple) color_on='\033[0;35m' ;;
    green) color_on='\033[0;32m' ;;
    blue) color_on='\033[0;34m' ;;
    cyan) color_on='\033[0;36m' ;;
    orange) color_on='\033[1;33m' ;;
    step)
        ((++STEP))
        color_on="\033[0;36m$timestamp - [$STEP] \033[0m"
        color_off=" - [$time_hms]"
        ;;
    time)
        color_on="$timestamp - [${STEP}] "
        color_off=" - [$time_hms]"
        ;;
    log)
        local log_file="$2"
        shift 2
        echo "$timestamp - $*" | tee -a "$log_file"
        return
        ;;
    *) unset color_on color_off ;;
    esac

    [ "$#" -gt 1 ] && shift
    [ "${silent_mode:-0}" -eq 0 ] && echo -e "${color_on}$*${color_off}"
}

_check_root() {
    case "$(id -u)" in
    0) unset use_sudo && return 0 ;;
    *) use_sudo=sudo && return 1 ;;
    esac
}

_get_yes_no() {
    # read -rp "${1:-Confirm the action?} [y/N] " -n 1 -s read_yes_no
    # [[ ${read_yes_no,,} == y ]] && return 0 || return 1
    read -rp "${1:-Confirm the action?} [y/N] " read_yes_no
    [[ ${read_yes_no,,} =~ ^y(es)?$ ]]
}

_get_random_password() {
    local cmd_hash bits=${1:-14}
    cmd_hash=$(command -v md5sum || command -v sha256sum || command -v md5 2>/dev/null)
    count=0
    while [ -z "$password_rand" ]; do
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

_get_ip_current() {
    _check_distribution
    case "$lsb_dist" in
    macos)
        ip4_current=$(curl -x '' -4 --connect-timeout 5 -fsSL 4.ipw.cn)
        ip6_current=$(curl -x '' -6 --connect-timeout 5 -fsSL 6.ipw.cn | tail -n 1)
        [ -z "$ip6_current" ] && ip6_current=$(ifconfig en0 | awk '/inet6.*temporary/ {print $2}' | head -n 1)
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
    _msg green "get IPv4: $ip4_current"
    _msg green "get IPv6: $ip6_current"
}

_check_distribution() {
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        version_id="${VERSION_ID-}"
        lsb_dist="${ID,,}"
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
    _msg time "Your distribution is ${lsb_dist}."
}

_check_sudo() {
    ${already_check_sudo:-false} && return 0
    if ! _check_root; then
        if ! $use_sudo -l -U "$USER" &>/dev/null; then
            _msg time "User $USER has no permission to execute this script!"
            _msg time "Please run visudo with root, and set sudo for ${USER}."
            return 1
        fi
        _msg time "User $USER has permission to execute this script!"
    fi

    for pkg_manager in apt yum dnf; do
        if command -v "$pkg_manager" &>/dev/null; then
            cmd_pkg="$use_sudo $pkg_manager"
            [[ $pkg_manager == apt ]] && apt_update=1
            already_check_sudo=true
            return 0
        fi
    done

    _msg time "Package manager (apt/yum/dnf) not found, exiting."
    return 1
}

_install_ossutil() {
    _check_distribution
    local url
    url="https://help.aliyun.com/zh/oss/developer-reference/install-ossutil$([[ $1 == 1 || $1 == v1 ]] && echo '' || echo '2')"
    local url_down
    url_down=$(curl -fsSL "$url" | grep -oE 'href="[^\"]+"' | grep -o "https.*ossutil.*${lsb_dist%os}-amd64\.zip")
    curl -fLo ossu.zip "$url_down"
    unzip -o -j ossu.zip
    sudo install -m 0755 ossutil /usr/local/bin/ossutil
    ossutil version
    rm -f ossu.zip
}

_install_aliyun_cli() {
    _check_distribution
    local url="https://help.aliyun.com/zh/cli/install-cli-on-${lsb_dist,,}"
    local url_down
    url_down=$(curl -fsSL "$url" | grep -oE 'href="[^\"]+"' | grep -o "https.*aliyun.*${lsb_dist,,}.*\.tgz")
    curl -fLo aly.tgz "$url_down"
    tar xzvf aly.tgz
    sudo install -m 0755 aliyun /usr/local/bin/aliyun
    aliyun --version | head -n 1
    rm -f aly.tgz
}

_notify_weixin_work() {
    local wechat_key="$1"
    local wechat_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${wechat_key}"
    curl -fsSL -X POST -H 'Content-Type: application/json' \
        -d '{"msgtype": "text", "text": {"content": "'"${g_msg_body-}"'"}}' "$wechat_api"
    echo
}
