#!/usr/bin/env bash

# set -x
_get_yes_no() {
    read -rp "${1:-Confirm the action?} [y/N]" read_yes_no
    case ${read_yes_no:-n} in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) return 1 ;;
    esac
}

_msg() {
    local color_off='\033[0m' # Text Reset
    local color_on
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
        echo "$(date +%Y%m%d-%u-%H%M%S.%3N) $*" | tee -a "$me_log"
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
    ls "$path_home"
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
    # 生成密码
    user_pass_sys=$(_get_random_password)
    user_pass_vnc=$(_get_random_password)
    if ! id "$user_name"; then
        # useradd -p $(openssl passwd -crypt $user_pass_sys) test1
        useradd -m -s "$user_shell" -b "$path_home" "$user_name" && create_ok=1
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
    # 生成密码
    user_pass_sys=$(_get_random_password)
    user_pass_vnc=$(_get_random_password)
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

_backup_rsync() {
    _msg log "start backup..."
    local ssh_opt='ssh -o StrictHostKeyChecking=no -oConnectTimeout=10'
    local rsync_opt=(
        /usr/bin/rsync
        -az
        --backup
        --suffix=".$(date +%Y%m%d-%u-%H%M%S.%3N)"
        --exclude={'Trash','.swp','*.log','CDS.log*','libManager.log.*','simulation','*panic.log*','matlab_crash_dump.*','.recycle','.DS_Store'}
    )

    local rsync_exclude=$me_path/rsync.exclude.conf
    local rsync_include=$me_path/rsync.include.conf
    [ -f "$rsync_exclude" ] && rsync_opt+=(--exclude-from="$rsync_exclude")
    [ -f "$rsync_include" ] && rsync_opt+=(--files-from="$rsync_include")

    local src_dirs=(
        "$path_eda"
        "$path_home"
    )
    local dest_dir='/volume1/backup'

    local pull_servers=(node11)
    local push_server=nas

    case "$1" in
    pull)
        ## run on NAS, pull files from SERVERS
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
        ## run on SERVERS, push files to NAS
        rsync_opt+=(--rsync-path=/bin/rsync)
        for dir in "${src_dirs[@]}"; do
            test -d "$dir" || continue
            _msg log "sync $dir"
            $ssh_opt $push_server "[ -d $dest_dir$dir ] || mkdir -p $dest_dir$dir"
            "${rsync_opt[@]}" -e "$ssh_opt" "$dir"/ "$push_server:$dest_dir$dir"/
        done
        ;;
    *)
        echo "$0  pull      run on NAS, pull files from SERVERS"
        echo "$0  push      run on SERVERS, push files to NAS"
        ;;
    esac
    _msg log "end backup."
}

_backup_borg() {
    set -e
    local borg_opt=(borg create)
    if [ "${backup_borg_debug:-0}" -eq 1 ]; then
        borg_opt+=(
            --verbose
            --filter AME
            --list
            --stats
            --show-rc
            --compression lz4
            --exclude-caches
        )
    fi
    [ -f "$me_path/borg_exclude" ] && borg_opt+=(--exclude-from "$me_path/borg_exclude")
    borg_opt+=(
        --exclude '/home/*/simulation/'
        --exclude '/home/*/.cache/*'
        --exclude '/home/*/.nfs*'
        --exclude '/home/*/.local/share/Trash/'
        --exclude '/home2/*/simulation/'
        --exclude '/home2/*/.cache/*'
        --exclude '/home2/*/.nfs*'
        --exclude '/home2/*/.local/share/Trash/'
        --exclude '*/.swp'
        --exclude '*/*.log'
        --exclude '*/CDS.log.*'
        --exclude '*/libManager.log.*'
        --exclude '*/*panic.log*'
        --exclude '*/matlab_crash_dump.*'
        --exclude '*/.recycle'
        --exclude '*/.cdslck'
        --exclude '*/.DS_Store'
    )

    local remote_host="${1:-nas}"
    local remote_path="${2:-/volume1/backup-borg}"
    shift 2
    IFS=" " read -r -a local_path <<<"${*}"

    local repo_url
    # Check if remote_host is "local" for local backup
    if [ "$remote_host" = "local" ]; then
        repo_url="$remote_path"
        if [ ! -f "$remote_path/config" ]; then
            borg init --encryption=none "$repo_url"
        fi
    else
        # Remote backup configuration
        borg_opt+=(--remote-path /usr/bin/borg)
        repo_url="ssh://$remote_host$remote_path"
        # shellcheck disable=SC2029
        if ssh "$remote_host" true; then
            if ssh "$remote_host" "test -f $remote_path/config"; then
                :
            else
                borg init --encryption=none "$repo_url"
            fi
        else
            echo "fail ssh to $remote_host"
            return 1
        fi
    fi

    _msg log "borg backup start..."
    _msg log "$repo_url::{now} ${local_path[*]}"
    "${borg_opt[@]}" "$repo_url::{now}" "${local_path[@]}"
    # borg prune --keep-weekly=4 --keep-monthly=3 "$repo_url"
    # borg compact "$repo_url"
    _msg log "borg backup end."
}

_get_random_password() {
    local length=10
    # 优先使用 openssl，这是最可靠的方法
    if command -v openssl >/dev/null 2>&1; then
        pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c "$length")
        echo "$pass" && return
    fi
    # 备选方案：/dev/urandom
    if [ -r "/dev/urandom" ]; then
        pass=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "$length")
        echo "$pass" && return
    fi
    # 最后的备选方案
    pass=$(echo "$(date +%s%N)${RANDOM}${RANDOM}" | md5sum | head -c "$length")
    echo "$pass"
}

_set_vncserver() {
    local id="$1"
    local account="$2"
    local vnc_users=/etc/sysconfig/vncusers
    if grep -q "^:${id}=${account}=" $vnc_users; then
        echo "found :${id}=${account}= in $vnc_users"
    else
        _msg log "not found :${id}=${account}= in $vnc_users, insert it..."
        echo ":${id}=${account}=" >>$vnc_users
    fi
    _msg log "enable vncserver :$id for $account on $(hostname)..."
    systemctl enable --now "vncserver@:${id}.service"
}

_get_help() {
    local NOFORMAT='\033[0m'
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    echo -e "${RED}Connecting to stunnel server...${NOFORMAT}"
    sleep 0.5
    echo -e "${GREEN}OK.${NOFORMAT}"
}

_usage() {
    echo "Usage: "
    echo "  $0 --backup-push, run on server, push file to nas"
    echo "  $0 --backup-pull, run on nas, pull file from server"
    echo "  $0 --backup-borg <local_path> <remote_host> <remote_path>, run on server, push file to nas"
    exit 1
}

main() {
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_path_bin="$me_path/bin"
    me_path_conf="$me_path/conf"
    me_log="${me_path}/.${me_name}.log"

    echo "$me_path_bin , $me_path_conf" >/dev/null
    path_eda="/eda"
    path_home="/home2"
    user_shell=/bin/bash

    if [[ "$#" -eq 0 ]]; then
        select choice in create_user change_password disable_user remove_user quit; do
            _msg "choice: ${choice:? ERR: choice empty}"
            break
        done
        case "$choice" in
        create_user) create_user=1 ;;
        change_password) change_password=1 ;;
        disable_user) disable_user=1 ;;
        remove_user) remove_user=1 ;;
        quit) show_help=1 ;;
        esac
    fi
    borg_local_path=()
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        -s | --backup-push) backup_push=1 ;;
        -l | --backup-pull) backup_pull=1 ;;
        -b | --backup-borg) backup_borg=1 ;;
        --debug) backup_borg_debug=1 ;;
        --no-root) no_root=1 ;;
        --local-path)
            borg_local_path+=("$2")
            shift
            ;;
        --remote-host)
            borg_host="$2"
            shift
            ;;
        --remote-path)
            borg_remote_path="$2"
            shift
            ;;
        --set-vnc)
            set_vnc=1
            shift
            IFS=" " read -r -a set_vnc_args <<<"$*"
            ;;
        --get-help) get_help=1 ;;
        -h | --help | help) show_help=1 ;;
        esac
        shift
    done

    # Only check root if --no-root is not specified
    [ "${no_root:-0}" -eq 0 ] && _check_root || return 1

    [ "$show_help" = 1 ] && _usage

    [ "$create_user" = 1 ] && _create_user
    [ "$change_password" = 1 ] && _change_user_password
    [ "$disable_user" = 1 ] && _disable_user
    [ "$remove_user" = 1 ] && _remove_user
    [ "$backup_push" = 1 ] && _backup_rsync push
    [ "$backup_pull" = 1 ] && _backup_rsync pull
    [ "$backup_borg" = 1 ] && _backup_borg "$borg_host" "$borg_remote_path" "${borg_local_path[@]}"
    [ "$set_vnc" = 1 ] && _set_vncserver "${set_vnc_args[@]}"
    [ "$get_help" = 1 ] && _get_help
}

main "$@"

# Synology DS920+
# /etc/sysconfig/network-scripts/ifcfg-eth0:1
# NAME=eth0:1
# DEVICE=eth0:1
# BOOTPROTO=static
# IPADDR=192.168.7.10
# PREFIX=24
# ONBOOT=yes
# /etc/sysconfig/network-scripts/ifcfg-eth1:1
# NAME=eth1:1
# DEVICE=eth1:1
# BOOTPROTO=static
# IPADDR=192.168.7.9
# PREFIX=24
# ONBOOT=yes
