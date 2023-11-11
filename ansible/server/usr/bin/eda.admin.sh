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
        echo "$(date +%Y%m%d-%u-%H%M%S.%3N) $*" | tee -a "$me_log"
        return
        ;;
    logpass)
        shift
        echo "$(date +%Y%m%d-%u-%H%M%S.%3N) $*" | tee -a "$me_log_secret"
        return
        ;;
    *)
        unset color_on color_off
        ;;
    esac
    [[ "$#" -gt 1 ]] && shift
    echo -e "${color_on}$*${color_off}"
}

_check_root() {
    if [ "$(id -u)" -eq 0 ]; then
        _msg green "is root, continue..."
        return 0
    else
        _msg red "not root, run with \"sudo $0\" ..."
        return 1
    fi
}

_get_username() {
    _msg green "all existing users..."
    ls $path_home
    echo
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

_change_user_password() {
    _msg log "change password..."
    _get_username password
    if _get_yes_no "[ssh] Do you want change system password of ${user_name}?"; then
        echo "$user_pass_sys" | passwd --stdin "$user_name"
        _msg logpass "system password: $user_name / $user_pass_sys"
        [ -d /var/yp ] && make -C /var/yp
    else
        _msg warn "skip change system password"
    fi
    if _get_yes_no "[vnc] Do you want change vnc password of ${user_name}?"; then
        echo "$user_pass_vnc" | vncpasswd -f >"$file_vnc_passwd"
        _msg logpass "vnc password: $user_name / $user_pass_vnc"
    else
        _msg warn "skip change vnc password"
    fi
}

_disable_user() {
    _msg log "disable user..."
    _get_username disable
    if id "$user_name"; then
        usermod --lock "$user_name" && disabled=1
    fi
    if [ "${disabled:-0}" -eq 1 ]; then
        _msg logpass "disabled user: $user_name"
    else
        _msg red "ERR: disable(lock) user $user_name failed."
        return 1
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

_backup() {
    _msg log "start backup..."
    ssh_opt='ssh -o StrictHostKeyChecking=no -oConnectTimeout=10'
    rsync_opt=(
        /usr/bin/rsync
        -az
        --backup
        --suffix=".$(date +%Y%m%d-%u-%H%M%S.%3N)"
        --exclude={'.swp','*.log','CDS.log*','*panic.log*','matlab_crash_dump.*'}
    )

    rsync_exclude=$me_path/rsync.exclude.conf
    rsync_include=$me_path/rsync.include.conf
    [ -f "$rsync_exclude" ] && rsync_opt+=(--exclude-from="$rsync_exclude")
    [ -f "$rsync_include" ] && rsync_opt+=(--files-from="$rsync_include")

    src_dirs=(
        /eda
        /home2
    )
    dest_dir='/volume1/nas1/backup'

    pull_servers=(node11)
    push_nas=nas

    case "$1" in
    pull)
        ## pull files from SERVERS, run on NAS
        for svr in "${pull_servers[@]}"; do
            for dir in "${src_dirs[@]}"; do
                $ssh_opt "$svr" "test -d $dir" || continue
                _msg log "sync $dir"
                [ -d "$dest_dir$dir" ] || mkdir -p "$dest_dir$dir"
                "${rsync_opt[@]}" -e "$ssh_opt" "$svr:$dir"/ "$dest_dir$dir"/
            done
        done
        ;;
    push)
        ## push to NAS, run on SERVERS
        rsync_opt+=(--rsync-path=/bin/rsync)
        for dir in "${src_dirs[@]}"; do
            test -d "$dir" || continue
            _msg log "sync $dir"
            $ssh_opt $push_nas "[ -d $dest_dir$dir ] || mkdir -p $dest_dir$dir"
            "${rsync_opt[@]}" -e "$ssh_opt" "$dir"/ "$push_nas:$dest_dir$dir"/
        done
        ;;
    *)
        echo "$0  pull      pull files from SERVERS, run on NAS"
        echo "$0  push      push files to NAS, run on SERVERS"
        ;;
    esac
    _msg log "end backup."
}

_get_random_password() {
    # dd if=/dev/urandom bs=1 count=15 | base64 -w 0 | head -c10
    if command -v md5sum; then
        bin_hash=md5sum
    elif command -v sha256sum; then
        bin_hash=sha256sum
    elif command -v md5; then
        bin_hash=md5
    fi
    count=0
    while [ -z "$user_pass_sys" ]; do
        ((++count))
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
}

main() {
    _check_root || return 1
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_path_bin="$me_path/bin"
    me_path_conf="$me_path/conf"
    me_log="${me_path}/${me_name}.log"
    me_log_secret="${me_path}/.password.log"

    echo "$me_path_bin , $me_path_conf" >/dev/null
    path_home="/home2"
    user_shell=/bin/bash

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --backup-push | -b)
            _backup push
            return
            ;;
        --backup-pull | -bp)
            _backup pull
            return
            ;;
        *)
            _usage
            exit 1
            ;;
        esac
        shift
    done

    _get_random_password

    select choice in create_user change_password disable_user remove_user backup quit; do
        _msg "choice: ${choice:empty}"
        break
    done
    case $choice in
    create_user)
        _create_user
        ;;
    change_password)
        _change_user_password
        ;;
    disable_user)
        _disable_user
        ;;
    remove_user)
        _remove_user
        ;;
    *)
        _msg warn "unknown action: ${choice:empty}"
        return 1
        ;;
    esac
}

main "$@"
