_msg() {
    local color_on=''
    local color_off='\033[0m' # Text Reset
    duration=$SECONDS
    h_m_s="$((duration / 3600))h$(((duration / 60) % 60))m$((duration % 60))s"
    bin_date="$(command -v gdate)"
    bin_date="${bin_date:-$(command -v date)}"
    time_now="$($bin_date +%Y%m%d-%u-%T.%3N)"

    case "${1:-none}" in
    red | error | erro) color_on='\033[0;31m' ;;       # Red
    green | info) color_on='\033[0;32m' ;;             # Green
    yellow | warning | warn) color_on='\033[0;33m' ;;  # Yellow
    blue) color_on='\033[0;34m' ;;                     # Blue
    purple | question | ques) color_on='\033[0;35m' ;; # Purple
    cyan) color_on='\033[0;36m' ;;                     # Cyan
    orange) color_on='\033[1;33m' ;;                   # Orange
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
    printf "$time_now ${color_on}$*${color_off}\n"
}

_get_root() {
    if [ "$(id -u)" -eq 0 ]; then
        unset use_sudo
        return 0
    else
        use_sudo=sudo
        return 1
    fi
}

_get_yes_no() {
    read -rp "${1:-Confirm the action?} [y/N] " read_yes_no
    case ${read_yes_no:-n} in
    [Yy] | [Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
    esac
}

_get_random_password() {
    # dd if=/dev/urandom bs=1 count=15 | base64 -w 0 | head -c10
    bin_hash=$(command -v md5sum)
    bin_hash="${bin_hash:-$(command -v sha256sum)}"
    bin_hash="${bin_hash:-$(command -v md5)}"
    password_bits=${1:-12}
    count=0
    while [ -z "$password_rand" ]; do
        ((++count))
        case $count in
        1) password_rand="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c"$password_bits")" ;;
        2) password_rand=$(openssl rand -base64 20 | tr -dc A-Za-z0-9 | head -c"$password_bits") ;;
        3) password_rand="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c"$password_bits")" ;;
        4) password_rand="$(echo "$RANDOM$($bin_date)$RANDOM" | $bin_hash | base64 | head -c"$password_bits")" ;;
        *) echo "${password_rand:?Failed to generate password}" && return 1 ;;
        esac
    done
}
