#!/usr/bin/bash

# set -x

_get_yes_no() {
    read -rp "${1:-Confirm the action?} [y/N]" read_yes_no
    case ${read_yes_no:-n} in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) return 1 ;;
    esac
}

_msg() {
    color_off='\033[0m' # Text Reset
    case "$1" in
    red | error | erro) color_on='\033[0;31m' ;;       # Red
    green | info) color_on='\033[0;32m' ;;             # Green
    yellow | warning | warn) color_on='\033[0;33m' ;;  # Yellow
    blue) color_on='\033[0;34m' ;;                     # Blue
    purple | question | ques) color_on='\033[0;35m' ;; # Purple
    cyan) color_on='\033[0;36m' ;;                     # Cyan
    log)
        shift
        echo "$(date +%Y%m%d-%u-%T.%3N) $*" | tee -a "$me_log"
        return
        ;;
    logpass)
        shift
        echo "$(date +%Y%m%d-%u-%T.%3N) $*" | tee -a "$password_log"
        return
        ;;
    *) unset color_on color_off ;;
    esac
    [ "$#" -gt 1 ] && shift
    echo -e "${color_on}$*${color_off}"
}

_get_username() {
    read -rp "[$1] Input <USER> name: " read_user_name
    # read -rp "[$1] Input <GROUP> name: " read_user_group
    user_name=${read_user_name:?empty var}
    user_group=${read_user_group:-$user_name}
    path_vnc_home="$path_home/$user_name/.vnc"
    file_vnc_passwd="$path_vnc_home/passwd"
}

_create_user() {
    _get_username create
    if ! id "$user_name"; then
        # useradd -p $(openssl passwd -crypt $user_pass_sys) test1
        useradd -m -s "$user_shell" -b $path_home "$user_name" && create_ok=1
        echo "$user_pass_sys" | passwd --stdin "$user_name"
    else
        _msg warn "sys user $user_name exists, skip."
        return 1
    fi
    if [ "${create_ok:-0}" -eq 1 ]; then
        [ -d /var/yp ] && make -C /var/yp
        _msg logpass "system password: $user_name / $user_pass_sys"
        if [ ! -d "$path_vnc_home" ]; then
            mkdir -p "$path_vnc_home"
        fi
        if [ ! -f "$file_vnc_passwd" ]; then
            echo "$user_pass_vnc" | vncpasswd -f >"$file_vnc_passwd"
            chmod 600 "$file_vnc_passwd"
            chown -R "$user_name:$user_group" "$path_vnc_home"
            _msg logpass "vnc password: $user_name / $user_pass_vnc"
        fi
    else
        _msg red "ERR: create system user $user_name failed."
        return 1
    fi

}

_change_password() {
    _msg log "change password..."
    _get_username password
    if _get_yes_no "[ssh] Do you want change system password of ${user_name}?"; then
        echo "$user_pass_sys" | passwd --stdin "$user_name"
        _msg logpass "system password: $user_name / $user_pass_sys"
        [ -d /var/yp ] && make -C /var/yp
    else
        _msg warn "give up. (change system password)"
    fi
    if _get_yes_no "[vnc] Do you want change vnc password of ${user_name}?"; then
        echo "$user_pass_vnc" | vncpasswd -f >"$file_vnc_passwd"
        _msg logpass "vnc password: $user_name / $user_pass_vnc"
    else
        _msg warn "give up. (change vnc password)"
    fi
}

_remove_user() {
    _msg log "remove user..."
    _get_username remove
    cmd_del=userdel
    # if _get_yes_no "[remove] Do you want remove user HOME dir?"; then
    #     cmd_del='userdel -r'
    # fi
    if id "$user_name"; then
        $cmd_del "$user_name" && removed=1
        if [[ "${removed:-0}" -eq 1 ]]; then
            [ -d /var/yp ] && make -C /var/yp
        else
            _msg red "Remove user $user_name failed!"
            echo "try \`ps -ef | grep $user_name\` on all servers, maybe help you"
        fi
    else
        _msg warn "sys user $user_name not exists, skip."
    fi
}

main() {
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_path_bin="$me_path/bin"
    me_path_data="$me_path/data"
    me_path_conf="$me_path/conf"
    me_log="${me_path_data}/${me_name}.log"
    password_log="${me_path_data}/password.log"

    [ -d "${me_path_data}" ] || mkdir "${me_path_data}"
    echo "$me_path_bin , $me_path_conf" >/dev/null
    path_home="/home2"
    user_shell=/bin/bash

    # dd if=/dev/urandom bs=1 count=15 | base64 -w 0 | head -c10
    ## user_password
    command -v md5sum && bin_hash=md5sum
    command -v sha256sum && bin_hash=sha256sum
    command -v md5 && bin_hash=md5
    count=0
    while [ -z "$user_pass_sys" ]; do
        count=$((count + 1))
        case $count in
        1)
            user_pass_sys="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
            user_pass_vnc="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
            ;;
        2)
            user_pass_sys=$(openssl rand -base64 20 | tr -dc A-Za-z0-9 | head -c10)
            user_pass_vnc=$(openssl rand -base64 20 | tr -dc A-Za-z0-9 | head -c10)
            ;;
        3)
            user_pass_sys="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
            user_pass_vnc="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
            ;;
        4)
            user_pass_sys="$(echo "$RANDOM$(date)$RANDOM" | $bin_hash | base64 | head -c10)"
            user_pass_vnc="$(echo "$RANDOM$(date)$RANDOM" | $bin_hash | base64 | head -c10)"
            ;;
        *)
            echo "Failed to generate password, exit 1"
            return 1
            ;;
        esac
    done

    echo -e "\nList all existing users...\n"
    ls $path_home
    echo

    select choice in create_user change_password remove_user quit; do
        case $choice in
        create_user)
            _create_user
            ;;
        change_password)
            _change_password
            ;;
        remove_user)
            _remove_user
            ;;
        esac
        break
    done
}

main "$@"
