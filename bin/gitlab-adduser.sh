#!/usr/bin/env bash

_new_user() {
    command -v md5sum >/dev/null && bin_hash=md5sum
    command -v sha256sum >/dev/null && bin_hash=sha256sum
    command -v md5 >/dev/null && bin_hash=md5
    ## generate password
    # password_rand="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
    password_rand=$(openssl rand -base64 20 | tr -dc A-Za-z0-9 | head -c10)
    if [ -z "$password_rand" ]; then
        password_rand="$(echo "$RANDOM$(date)$RANDOM" | $bin_hash | base64 | head -c10)"
    fi
    ## create user
    gitlab user create --name "$user_name" --username "$user_name" --password "$password_rand" --email "${user_name}@${domain_name}" --skip-confirmation 1  --can-create-group 0
    ## update password  user_name=zengming
    # gitlab user update --id $user_id --username "$user_name" --name "$user_name" --email "$user_name@domain_name" --skip-reconfirmation 1
    ## save to password file
    msg_user_pass="username=$user_name  /  password=$password_rand"
    echo "$msg_user_pass" | tee -a "$file_passwd"
}

_add_group_member() {
    echo "add to default group pms."
    default_group=$(gitlab group list | grep -B1 'name: pms$' | awk '/^id:/ {print $2}')
    gitlab group-member create --access-level 30 --group-id "$default_group" --user-id "$user_id"
    gitlab group list
    # read -rp "Enter group id: " group_id
    user_id="$(gitlab user list | grep -B1 "$user_name" | awk '/^id:/ {print $2}')"
    echo -e "\n################\n"
    select group_id in $(gitlab group list | awk '/^id:/ {print $2}') quit; do
        [ "${group_id:-quit}" == quit ] && break
        gitlab group-member create --access-level 30 --group-id "$group_id" --user-id "$user_id"
    done

}

_send_msg() {
    ## message body
    send_msg="
https://git.$domain_name
$msg_user_pass

https://docs.$domain_name
"
    api_weixin="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${ENV_WEIXIN_KEY:?ERR: empty api key}"
    curl -fsSL "$api_weixin" -H 'Content-Type: application/json' \
        -d '{"msgtype": "text", "text": {"content": "'$send_msg'"},"at": {"isAtAll": true}}'
}

_new_element_user() {
    cd ~/src/matrix-docker-ansible-deploy || exit 1
    file_secret=inventory/host_vars/matrix.example.com/user_pass.txt
    echo "username=${user_name}/password=${password_rand}" | tee -a $file_secret
    sed -i -e 's/^matrix.example1.com/#matrix.example2.com/' inventory/hosts
    ansible-playbook -i inventory/hosts setup.yml --extra-vars="username=$user_name password=$password_rand admin=no" --tags=register-user
    # ansible-playbook -i inventory/hosts setup.yml --extra-vars='username=fangzheng password=Eefaiyau6de1' --tags=update-user-password
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

    if [[ -z "$1" ]]; then
        read -rp 'Enter username: ' read_user_name
        read -rp 'Enter domain name: ' -e -i"${ENV_GITLAB_DOMAIN:-example.com}" read_domain_name
        user_name=${read_user_name:? ERR: empty user name}
        domain_name=${read_domain_name:? ERR: empty domain name}
    else
        user_name=${1}
        domain_name=${2}
    fi

    _new_user
    _add_group_member
    _send_msg
    # _new_element_user
}

main "$@"
