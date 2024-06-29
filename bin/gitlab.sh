#!/usr/bin/env bash
# shellcheck disable=1090

_add_account() {

    if $cmd_gitlab user list --username "$user_name" | jq -r '.[].name' | grep -q -w "$user_name"; then
        if _get_yes_no "user $user_name exists, update $user_name password?"; then
            user_id=$($cmd_gitlab user list --username "$user_name" | jq -r '.[].id')
            $cmd_gitlab user update --id "${user_id}" --username "$user_name" --password "${password_rand:? empty password}" --name "$user_name" --email "$user_name@${gitlab_domain}" --skip-reconfirmation 1
            return
        fi
        return 1
    fi

    $cmd_gitlab user create --name "$user_name" --username "$user_name" --password "${password_rand:? empty password}" --email "${user_name}@${gitlab_domain}" --skip-confirmation 1 --can-create-group 0
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
    send_msg="https://git.$gitlab_domain /  username=$user_name / password=$password_rand"
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

_install_gitlab_runner() {
    bin_runner=$(command -v gitlab-runner)
    if _get_yes_no "[+] Do you want install the latest version of gitlab-runner?"; then
        if pgrep gitlab-runner; then
            sudo "$bin_runner" stop
        fi
        echo "[+] Downloading gitlab-runner..."
        curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
        sudo apt install -y gitlab-runner
    fi

    ## Install and run as service
    if _get_yes_no "[+] Do you want create CI user for gitlab-runner?"; then
        user_name=ops
        user_home=/home/ops
        sudo useradd --comment 'GitLab Runner' --shell /bin/bash --create-home $user_name
    else
        echo "current user: $USER"
        user_name=$USER
        user_home=$HOME
    fi

    if _get_yes_no "[+] Do you want install as service?"; then
        sudo "$bin_runner" install --user "$user_name" --working-directory "$user_home"/runner
        sudo "$bin_runner" start
    fi

    if _get_yes_no "[+] Do you want git clone deploy.sh? "; then
        if [ -d "$HOME"/runner ]; then
            echo "Found $HOME/runner, skip."
        else
            if _get_yes_no "IN_CHINA=true ?"; then
                git clone --depth 1 https://gitee.com/xiagw/deploy.sh.git "$HOME"/runner
            else
                git clone --depth 1 https://github.com/xiagw/deploy.sh.git "$HOME"/runner
            fi
        fi
    fi

    read -rp "[+] Enter your gitlab url [https://git.example.com]: " read_url_git
    url_git="${read_url_git:? ERR read_url_git}"
    if _get_yes_no "[+] Do you want register gitlab-runner? "; then
        read -rp "[+] Enter your gitlab-runner token: " read_token
        reg_token="${read_token:? ERR read_token}"
        sudo "$bin_runner" register \
            --non-interactive \
            --url "${url_git:?empty url}" \
            --registration-token "${reg_token:?empty token}" \
            --executor shell \
            --tag-list docker,linux \
            --run-untagged \
            --locked \
            --access-level=not_protected
    fi

    ## install python-gitlab (GitLab API)
    if _get_yes_no "[+] Do you want install python-gitlab? "; then
        read -rp "[+] Enter your Access Token: " read_access_token
        access_token="${read_access_token:? ERR read_access_token}"
        sudo python3 -m pip install --upgrade pip
        python3 -m pip install --upgrade python-gitlab
        python_gitlab_conf="$HOME/.python-gitlab.cfg"
        if [ -f "$python_gitlab_conf" ]; then
            cp -vf "$python_gitlab_conf" "${python_gitlab_conf}.$(date +%s)"
        fi
        cat >"$python_gitlab_conf" <<EOF
[global]
default = example
ssl_verify = true
timeout = 5

[example]
url = $url_git
private_token = $access_token
api_version = 4
per_page = 100
EOF
    fi

    ## create git project
    if _get_yes_no "[+] Do you want create a project [devops] in $url_git ? "; then
        gitlab project create --name "devops"
    fi

    if _get_yes_no "[+] Do you want create a project [pms] in $url_git ? "; then
        gitlab project create --name "pms"
        git clone git@"${url_git#*//}":root/pms.git
        mkdir pms/templates
        cp conf/gitlab-ci.yml pms/templates
        (
            cd pms || exit 1
            git add .
            git commit -m 'add templates file'
            git push origin main
        )
    fi
}

main() {
    set -e
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
    cmd_readlink="$(command -v greadlink || command -v readlink)"
    me_path="$(dirname "$(${cmd_readlink:-readlink} -f "$0")")"
    me_data_path="$me_path/../data"
    me_name="$(basename "$0")"
    me_log="$me_data_path/${me_name}.log"
    me_env="$me_data_path/${me_name}.env"
    source "$me_path"/include.sh

    case "$1" in
    install)
        _install_gitlab_runner
        return
        ;;
    *)
        ## user_name and gitlab_domain
        user_name=${1}
        gitlab_domain=${2}
        ;;
    esac

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
    if [[ -z "$user_name" ]]; then
        read -rp 'Enter gitlab username: ' read_user_name
        user_name=${read_user_name:? ERR: empty user name}
    fi
    if [[ -z "$gitlab_domain" ]]; then
        read -rp 'Enter gitlab domain: ' gitlab_domain
        gitlab_domain=${gitlab_domain:? ERR: empty domain name}
    fi

    _get_random_password
    _add_account
    _send_msg
    # _new_element_user
}

main "$@"
