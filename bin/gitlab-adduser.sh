#!/usr/bin/env bash

_create_user() {
    if [[ -z "$1" ]]; then
        read -rp 'Enter username: ' -e -i 'user001' read_user_name
        read -rp 'Enter domain name: ' -e -i"${ENV_GITLAB_DOMAIN:-example.com}" read_domain_name
        user_name=${read_user_name:? ERR: empty user name}
        domain_name=${read_domain_name:? ERR: empty domain name}
    else
        user_name="$1"
        domain_name="${2:-example.com}"
    fi
    ## generate password
    password_rand="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
    ## create user
    gitlab user create \
        --name "$user_name" \
        --username "$user_name" \
        --password "$password_rand" \
        --email "${user_name}@${domain_name}" \
        --skip-confirmation 1
    ## update password  user_name=zengming
    # gitlab user update --id $user_id --username "$user_name" --name "$user_name" --email "$user_name@domain_name" --skip-reconfirmation 1
    ## save to password file
    msg_user_pass="username=$user_name  /  password=$password_rand"
    echo "$msg_user_pass" | tee -a "$file_passwd"
    ## message body
    url_git="https://git.$domain_name"
    url_wiki="https://docs.$domain_name"
    send_msg="
$url_git  /  $msg_user_pass

must-read for newcomers:  $url_wiki
"
    ## add to group
    gitlab group list
    read -rp "Enter group id: " group_id

    user_id="$(gitlab user list | grep -B1 "$user_name" | awk '/^id:/ {print $2}')"
    gitlab group-member create --group-id "${group_id:? ERR: empty group id}" --access-level 30 --user-id "$user_id"
}

_send_msg() {
    api_key=${ENV_WEIXIN_KEY:? ERR: empty api key}
    api_weixin="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$api_key"
    curl -s "$api_weixin" -H 'Content-Type: application/json' -d "{
        \"msgtype\": \"text\",
        \"text\": {
            \"content\": \"$send_msg\"
        },
        \"at\": {
            \"isAtAll\": true
        }
    }"
}

main() {
    bin_readlink=readlink
    [[ $OSTYPE == darwin* ]] && bin_readlink=greadlink
    me_path="$(dirname "$($bin_readlink -f "$0")")"
    me_name="$(basename "$0")"
    data_path="$me_path/../data"
    file_passwd="$data_path/${me_name}.txt"
    file_deploy_env="$data_path/deploy.env"
    [ -f "$file_deploy_env" ] && source "$file_deploy_env"

    _create_user "$@"
    _send_msg
}

main "$@"
