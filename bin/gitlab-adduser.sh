#!/usr/bin/env bash
# shellcheck disable=1090

_add_account() {
    gitlab user create --name "$user_name" --username "$user_name" --password "$user_password" --email "${user_name}@${domain_name}" --skip-confirmation 1 --can-create-group 0
    # gitlab user update --id $user_id --username "$user_name" --name "$user_name" --email "$user_name@domain_name" --skip-reconfirmation 1
    ## save to password file
    msg_user_pass="username=$user_name/password=$user_password"
    echo "$msg_user_pass" | tee -a "$file_save_pass"
}

_add_group_member() {
    echo "add to default group \"pms\"."
    default_group_id=$(gitlab group list --search pms | grep -B1 'name: pms$' | awk '/^id:/ {print $2}')
    # read -rp "Enter group id: " group_id
    user_id="$(gitlab user list --search "$user_name" | grep -B1 "$user_name" | awk '/^id:/ {print $2}')"
    gitlab group-member create --access-level 30 --group-id "$default_group_id" --user-id "$user_id"
    gitlab group list
    echo -e "\n################\n"
    select group_id in $(gitlab group list | awk '/^id:/ {print $2}') quit; do
        [ "${group_id:-quit}" == quit ] && break
        gitlab group-member create --access-level 30 --group-id "$group_id" --user-id "$user_id"
    done

}

_send_msg() {
    ## message body
    send_msg="https://git.$domain_name /  $msg_user_pass  /  https://docs.$domain_name"
    if [[ -z "$ENV_WEIXIN_KEY" ]]; then
        read -rp 'Enter weixin api key: ' read_weixin_api
        wechat_api_key=$read_weixin_api
    else
        wechat_api_key=$ENV_WEIXIN_KEY
    fi
    wechat_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${wechat_api_key}"
    curl -fsSL "$wechat_api" -H 'Content-Type: application/json' -d '{"msgtype": "text", "text": {"content": "'$send_msg'"},"at": {"isAtAll": true}}'
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
    bin_readlink=readlink
    [[ $OSTYPE == darwin* ]] && bin_readlink=greadlink
    me_path="$(dirname "$($bin_readlink -f "$0")")"
    me_name="$(basename "$0")"
    data_path="$me_path/../data"
    file_save_pass="$data_path/${me_name}.txt"
    file_deploy_env="$data_path/deploy.env"
    if [ -f "$file_deploy_env" ]; then
        source <(grep -E 'ENV_GITLAB_DOMAIN|ENV_WEIXIN_KEY' "$file_deploy_env")
    fi

    ## user_name and domain_name
    if [[ -z "$1" ]]; then
        read -rp 'Enter username: ' read_user_name
        read -rp 'Enter domain name: ' -e -i"${ENV_GITLAB_DOMAIN:-example.com}" read_domain_name
        user_name=${read_user_name:? ERR: empty user name}
        domain_name=${read_domain_name:? ERR: empty domain name}
    else
        user_name=${1}
        domain_name=${2}
    fi
    # if grep -q "=$user_name/" "$file_save_pass"; then
    if gitlab user list --search "$user_name" | grep "name: ${user_name}$"; then
        echo "user $user_name exists, exit 1."
        return 1
    fi
    ## user_password
    command -v md5sum && bin_hash=md5sum
    command -v sha256sum && bin_hash=sha256sum
    command -v md5 && bin_hash=md5
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

    _add_account
    _add_group_member
    _send_msg
    # _new_element_user
}

main "$@"
