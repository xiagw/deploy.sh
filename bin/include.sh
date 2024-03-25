# shellcheck shell=bash

cmd_date="$(command -v gdate)"
cmd_date="${cmd_date:-$(command -v date)}"

_msg() {
    local color_on=''
    local color_off='\033[0m' # Text Reset
    h_m_s="$((SECONDS / 3600))h$(((SECONDS / 60) % 60))m$((SECONDS % 60))s"
    time_now="$($cmd_date +%Y%m%d-%u-%T.%3N)"

    case "${1:-none}" in
    red | error | erro) color_on='\033[0;31m' ;;
    green | info) color_on='\033[0;32m' ;;
    yellow | warning | warn) color_on='\033[0;33m' ;;
    blue) color_on='\033[0;34m' ;;
    purple | question | ques) color_on='\033[0;35m' ;;
    cyan) color_on='\033[0;36m' ;;
    orange) color_on='\033[1;33m' ;;
    step)
        ((++STEP))
        color_on="\033[0;36m[${STEP}] $time_now \033[0m"
        color_off=" $h_m_s"
        ;;
    time)
        color_on="[${STEP}] $time_now "
        color_off=" $h_m_s"
        ;;
    log)
        log_file="$2"
        shift 2
        echo "$time_now $*" >>"$log_file"
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

    printf "%s\n" "$time_now ${color_on}$*${color_off}"
}

_get_root() {
    case "$(id -u)" in
    0)
        unset use_sudo
        return 0
        ;;
    *)
        use_sudo=sudo
        return 1
        ;;
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
        ip4_current=$(curl -x '' -fsSL 4.ipw.cn)
        ip6_current=$(curl -x '' -fsSL 6.ipw.cn | tail -n 1)
        _msg "ip6_current [6.ipw.cn ]: $ip6_current"
        ip6_current=$(ifconfig en0 | awk '/inet6.*temporary/ {print $2}' | head -n 1)
        _msg "ip6_current [Interface]: $ip6_current"
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
    _msg "ip4_current: $ip4_current"
    _msg "ip6_current: $ip6_current"
}

_get_distribution() {
    if [ -r /etc/os-release ]; then
        lsb_dist="$(. /etc/os-release && echo "$ID")"
        lsb_dist="${lsb_dist,,}"
    fi
    lsb_dist="${lsb_dist:-unknown}"
    _msg time "Your distribution is $lsb_dist"
}

_check_sudo() {
    ${already_check_sudo:-false} && return 0
    if ! _get_root; then
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