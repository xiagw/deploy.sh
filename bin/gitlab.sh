#!/usr/bin/env bash
# shellcheck disable=1090

_add_account() {
    if gitlab user list --search "$user_name" | grep "name: ${user_name}$"; then
        echo "user $user_name exists, exit 1."
        return 1
    fi

    gitlab user create --name "$user_name" --username "$user_name" --password "$user_password" --email "${user_name}@${domain_name}" --skip-confirmation 1 --can-create-group 0
    # gitlab user update --id $user_id --username "$user_name" --name "$user_name" --email "$user_name@domain_name" --skip-reconfirmation 1
    ## save to password file
    msg_user_pass="username=$user_name/password=$user_password"
    # echo "$msg_user_pass" | tee -a "$me_log"
    _msg log "$me_log" "$msg_user_pass"
}

_add_group_member() {
    _msg "add to default group \"pms\"."
    default_group_id=$(gitlab group list --search pms | grep -B1 'name: pms$' | awk '/^id:/ {print $2}')
    # read -rp "Enter group id: " group_id
    user_id="$(gitlab user list --search "$user_name" | grep -B1 "$user_name" | awk '/^id:/ {print $2}')"
    gitlab group-member create --access-level 30 --group-id "$default_group_id" --user-id "$user_id"
    gitlab group list
    select group_id in $(gitlab group list | awk '/^id:/ {print $2}') quit; do
        [ "${group_id:-quit}" == quit ] && break
        gitlab group-member create --access-level 30 --group-id "$group_id" --user-id "$user_id"
    done

}

_send_msg() {
    ## message body
    send_msg="https://git.$domain_name /  $msg_user_pass"
    if [[ -z "$gitlab_weixin_key" ]]; then
        read -rp 'Enter weixin api key: ' read_weixin_api
        wechat_api_key=$read_weixin_api
    else
        wechat_api_key=$gitlab_weixin_key
    fi
    wechat_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${wechat_api_key}"
    curl -fsSL "$wechat_api" -H 'Content-Type: application/json' -d '{"msgtype": "text", "text": {"content": "'"$send_msg"'"},"at": {"isAtAll": true}}'
}

_new_element_user() {
    cd ~/src/matrix-docker-ansible-deploy || exit 1
    file_secret=inventory/host_vars/matrix.example.com/user_pass.txt
    echo "username=${user_name}/password=${user_password}" | tee -a $file_secret
    sed -i -e 's/^matrix.example1.com/#matrix.example2.com/' inventory/hosts
    ansible-playbook -i inventory/hosts setup.yml --extra-vars="username=$user_name password=$user_password admin=no" --tags=register-user
    # ansible-playbook -i inventory/hosts setup.yml --extra-vars='username=fangzheng password=Eefaiyau6de1' --tags=update-user-password
}

main() {
    set -e
    bin_readlink=readlink
    [[ $OSTYPE == darwin* ]] && bin_readlink=greadlink
    me_path="$(dirname "$($bin_readlink -f "$0")")"
    me_name="$(basename "$0")"
    me_data_path="$me_path/../data"
    me_log="$me_data_path/${me_name}.log"
    me_env="$me_data_path/${me_name}.env"

    me_include=$me_path/include.sh
    source "$me_include"

    ## python-gitlab config
    if [[ -f "$HOME/.python-gitlab.cfg" ]]; then
        gitlab_python_config="$HOME/.python-gitlab.cfg"
    elif [[ -f "$HOME/.config/python-gitlab.cfg" ]]; then
        gitlab_python_config="$HOME/.config/python-gitlab.cfg"
    fi
    select f in $(grep '^\[' "$gitlab_python_config" | grep -v 'global' | sed -e 's/\[//g; s/\]//g'); do
        gitlab_profile=$f
        break
    done
    . "$me_env" "$gitlab_profile"
    _msg "gitlab profile is: $gitlab_profile"

    ## user_name and domain_name
    if [[ -z "$1" ]]; then
        read -rp 'Enter gitlab username: ' read_user_name
        user_name=${read_user_name:? ERR: empty user name}
        domain_name=${gitlab_domain:? ERR: empty domain name}
    else
        user_name=${1}
        domain_name=${2}
    fi

    ## user_password
    if command -v md5sum; then
        bin_hash=md5sum
    elif command -v sha256sum; then
        bin_hash=sha256sum
    elif command -v md5; then
        bin_hash=md5
    else
        echo "No hash command found, exit 1"
    fi
    count=0
    while [ -z "$user_password" ]; do
        count=$((count + 1))
        case $count in
        1) user_password="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)" ;;
        2) user_password=$(openssl rand -base64 20 | tr -dc A-Za-z0-9 | head -c10) ;;
        3) user_password="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c10)" ;;
        4) user_password="$(echo "$RANDOM$(date)$RANDOM" | $bin_hash | base64 | head -c10)" ;;
        *) echo "Failed to generate password, exit 1" && return 1 ;;
        esac
    done
    sed -i -e "s/^default.*/default = $gitlab_profile/" "$gitlab_python_config"
    _add_account
    _add_group_member
    _send_msg
    # _new_element_user
}

main "$@"
