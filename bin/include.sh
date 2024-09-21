# shellcheck shell=bash
# shellcheck disable=SC2034

cmd_date="$(command -v gdate || command -v date)"

_msg() {
    local color_on
    local color_off='\033[0m' # Text Reset
    time_hms="$((SECONDS / 3600))h$(((SECONDS / 60) % 60))m$((SECONDS % 60))s"
    timestamp="$(date +%Y%m%d-%u-%T.%3N)"

    case "${1:-none}" in
    info) color_on='' ;;
    yellow | warn | warning) color_on='\033[0;33m' ;;
    red | error | err) color_on='\033[0;31m' ;;
    purple | question | ques) color_on='\033[0;35m' ;;
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
        log_file="$2"
        shift 2
        echo "$timestamp - $*" | tee -a "$log_file"
        return
        ;;
    *)
        unset color_on color_off
        ;;
    esac
    [ "$#" -gt 1 ] && shift
    if [ "${silent_mode:-0}" -eq 1 ]; then
        return
    fi

    echo -e "${color_on}$*${color_off}"
}

_check_root() {
    case "$(id -u)" in
    0) unset use_sudo && return 0 ;;
    *) use_sudo=sudo && return 1 ;;
    esac
}

_get_yes_no() {
    read -rp "${1:-Confirm the action?} [y/N] " read_yes_no
    case ${read_yes_no:-n} in
    [Yy] | [Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
    esac
}

## global variable: password_rand
_get_random_password() {
    # dd if=/dev/urandom bs=1 count=15 | base64 -w 0 | head -c10
    cmd_hash=$(command -v md5sum)
    cmd_hash="${cmd_hash:-$(command -v sha256sum)}"
    cmd_hash="${cmd_hash:-$(command -v md5)}"
    password_bits=${1:-12}
    count=0
    while [ -z "$password_rand" ]; do
        ((++count))
        case $count in
        1) password_rand="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c"$password_bits")" ;;
        2) password_rand=$(openssl rand -base64 20 | tr -dc A-Za-z0-9 | head -c"$password_bits") ;;
        3) password_rand="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c"$password_bits")" ;;
        4) password_rand="$(echo "$RANDOM$($cmd_date)$RANDOM" | $cmd_hash | base64 | head -c"$password_bits")" ;;
        *) echo "${password_rand:?Failed to generate password}" && return 1 ;;
        esac
    done
}

## global variable: ip4_current, ip6_current
_get_ip_current() {
    ## get current ip from Internet API
    if [ "$(uname -o)" = Darwin ]; then
        # ip4_current=$($cmd cip.cc | awk '/^IP.*:/ {print $3}')
        ip4_current=$(curl -x '' -4 --connect-timeout 5 -fsSL 4.ipw.cn)
        ip6_current=$(curl -x '' -6 --connect-timeout 5 -fsSL 6.ipw.cn | tail -n 1)
        _msg "get current IPv6 from [6.ipw.cn ]: $ip6_current"
        if [ -z "$ip6_current" ]; then
            ip6_current=$(ifconfig en0 | awk '/inet6.*temporary/ {print $2}' | head -n 1)
            _msg "get current IPv6 from [Interface]: $ip6_current"
        fi
    elif grep -i -q 'ID="openwrt2"' /etc/os-release; then
        ## get current ip from Interface
        . /lib/functions/network.sh
        network_flush_cache
        IPV=4
        eval network_find_wan${IPV%4} NET_IF
        eval network_get_ipaddr${IPV%4} NET_ADDR "${NET_IF}"
        ip4_current="${NET_ADDR}"
        IPV=6
        eval network_find_wan${IPV%4} NET_IF
        eval network_get_ipaddr${IPV%4} NET_ADDR "${NET_IF}"
        ip6_current="${NET_ADDR}"
    else
        ip4_current=$(ip -4 addr list scope global "${wan_device:-pppoe-wan}" | awk '/inet/ {print $2}' | head -n 1)
        ip6_current=$(ip -6 addr list scope global "${wan_device:-pppoe-wan}" | awk '/inet6/ {print $2}' | head -n 1)
        # ip6_current=${ip6_current%%/*}
    fi
    _msg green "get IPv4: $ip4_current"
    _msg green "get IPv6: $ip6_current"
}

_check_distribution() {
    if [ -r /etc/os-release ]; then
        source /etc/os-release
        # shellcheck disable=SC1091,SC2153
        version_id="$VERSION_ID"
        lsb_dist="$ID"
        lsb_dist="${lsb_dist,,}"
    else
        case "$OSTYPE" in
        solaris*) lsb_dist="solaris" ;;
        darwin*) lsb_dist="macos" ;;
        linux*) lsb_dist="linux" ;;
        bsd*) lsb_dist="bsd" ;;
        msys*) lsb_dist="windows" ;;
        cygwin*) lsb_dist="alsowindows" ;;
        *) lsb_dist="unknown" ;;
        esac
    fi
    lsb_dist="${lsb_dist:-unknown}"
    _msg time "Your distribution is ${lsb_dist}."
}

_check_sudo() {
    ${already_check_sudo:-false} && return 0
    if ! _check_root; then
        if $use_sudo -l -U "$USER"; then
            _msg time "User $USER has permission to execute this script!"
        else
            _msg time "User $USER has no permission to execute this script!"
            _msg time "Please run visudo with root, and set sudo to $USER"
            return 1
        fi
    fi
    if _check_cmd apt; then
        cmd_pkg="$use_sudo apt-get"
        apt_update=1
    elif _check_cmd yum; then
        cmd_pkg="$use_sudo yum"
    elif _check_cmd dnf; then
        cmd_pkg="$use_sudo dnf"
    else
        _msg time "not found apt/yum/dnf, exit 1"
        return 1
    fi
    already_check_sudo=true
}

_install_ossutil() {
    url_html='https://help.aliyun.com/zh/oss/developer-reference/install-ossutil'
    {
        # echo "$url_html"
        echo "$url_html"2
    } | while read -r line; do
        if [ "$(uname -o)" = Darwin ]; then
            url_down=$(curl -fsSL "$line" | grep -o -E 'href="[^\"]+"' | grep -o 'https.*ossutil.*mac-amd64\.zip')
        else
            url_down=$(curl -fsSL "$line" | grep -o -E 'href="[^\"]+"' | grep -o 'https.*ossutil.*linux-amd64\.zip')
        fi
        curl -o ossutil.zip "$url_down"
        unzip -o -j ossutil.zip
        if [[ "$line" == *ossutil2 ]]; then
            install_path="/usr/local/bin/ossutil"
        else
            install_path="/usr/local/bin/ossutil-v1"
        fi
        sudo install -m 0755 ossutil $install_path
    done
    ossutil-v1 version
    ossutil version
}

_install_aliyun_cli() {
    if [ "$(uname -o)" = Darwin ]; then
        url_down=$(curl -fsSL 'https://help.aliyun.com/zh/cli/install-cli-on-macos' | grep -o -E 'href="[^\"]+"' | grep -o 'https.*aliyun.*macos.*\.tgz')
    else
        url_down=$(curl -fsSL 'https://help.aliyun.com/zh/cli/install-cli-on-linux' | grep -o -E 'href="[^\"]+"' | grep -o 'https.*aliyun-cli.*amd64.tgz')
    fi
    curl -o aliyun-cli.tgz "$url_down"
    tar xzvf aliyun-cli.tgz
    sudo install -m 0755 aliyun /usr/local/bin/aliyun
    aliyun --version | head -n 1
}
