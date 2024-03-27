#!/usr/bin/env bash
# shellcheck disable=1090

_add_account() {
    if _get_yes_no "update $user_name password?"; then
        user_id=$($cmd_gitlab user list --username "$user_name" | jq -r '.[].id')
        $cmd_gitlab user update --id "${user_id}" --username "$user_name" --name "$user_name" --email "$user_name@${domain_name}" --skip-reconfirmation 1
        return
    fi

    if $cmd_gitlab user list --username "$user_name" | jq -r '.[].name' | grep -q -m "$user_name"; then
        echo "user $user_name exists, exit 1."
        return 1
    fi

    $cmd_gitlab user create --name "$user_name" --username "$user_name" --password "${password_rand:? empty password}" --email "${user_name}@${domain_name}" --skip-confirmation 1 --can-create-group 0
    _msg log "$me_log" "username=$user_name / password=$password_rand"

    _msg "add to default group \"pms\"."
    pms_group_id=$($cmd_gitlab group list --search pms | jq -r '.[] | select (.name == "pms") | .id')
    user_id="$($cmd_gitlab user list --username "$user_name" | jq -r '.[].id')"
    $cmd_gitlab group-member create --access-level 30 --group-id "$pms_group_id" --user-id "$user_id"

    $cmd_gitlab group list --skip-groups 2,"$pms_group_id" | jq -r '.[] | (.id | tostring) + "\t" + .name'
    select group_id in $($cmd_gitlab group list --skip-groups 2,"$pms_group_id" | jq -r '.[].id') quit; do
        [ "${group_id:-quit}" == quit ] && break
        $cmd_gitlab group-member create --access-level 30 --group-id "$group_id" --user-id "$user_id"
    done
}

_send_msg() {
    ## message body
    send_msg="https://git.$domain_name /  username=$user_name / password=$password_rand"
    if [[ -z "$gitlab_weixin_key" ]]; then
        read -rp 'Enter weixin api key: ' read_weixin_key
        wechat_api_key=$read_weixin_key
    else
        wechat_api_key=$gitlab_weixin_key
    fi
    wechat_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${wechat_api_key}"
    curl -fsSL "$wechat_api" -H 'Content-Type: application/json' -d '{"msgtype": "text", "text": {"content": "'"$send_msg"'"},"at": {"isAtAll": true}}'
}

_new_element_user() {
    cd ~/src/matrix-docker-ansible-deploy || exit 1
    # file_secret=inventory/host_vars/matrix.example.com/user_pass.txt
    _msg log "$me_log" "username=${user_name} / password=${password_rand}"
    sed -i -e 's/^matrix.example1.com/#matrix.example2.com/' inventory/hosts
    ansible-playbook -i inventory/hosts setup.yml --extra-vars="username=$user_name password=$password_rand admin=no" --tags=register-user
    # ansible-playbook -i inventory/hosts setup.yml --extra-vars='username=fangzheng password=Eefaiyau6de1' --tags=update-user-password
}

main() {
    set -e
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
    cmd_readlink="$(command -v greadlink)"
    me_path="$(dirname "$(${cmd_readlink:-readlink} -f "$0")")"
    me_data_path="$me_path/../data"
    me_name="$(basename "$0")"
    me_log="$me_data_path/${me_name}.log"
    me_env="$me_data_path/${me_name}.env"

    source "$me_path"/include.sh

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
    cmd_gitlab="gitlab --gitlab $gitlab_profile -o json"

    ## user_name and domain_name
    if [[ -z "$1" ]]; then
        read -rp 'Enter gitlab username: ' read_user_name
        user_name=${read_user_name:? ERR: empty user name}
        domain_name=${gitlab_domain:? ERR: empty domain name}
    else
        user_name=${1}
        domain_name=${2}
    fi

    _get_random_password
    _add_account
    _send_msg
    # _new_element_user
}

main "$@"
