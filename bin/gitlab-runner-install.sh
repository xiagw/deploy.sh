#!/usr/bin/env bash

cmd_readlink="$(command -v greadlink)"
me_path="$(dirname "$(${cmd_readlink:-readlink} -f "$0")")"
me_path_data="${me_path}/../data"
me_name="$(basename "$0")"
me_env="${me_path_data}/${me_name}.env"
me_log="${me_path_data}/${me_name}.log"

me_include=$me_path/include.sh
source "$me_include"

bin_runner=/usr/local/bin/gitlab-runner
if _get_yes_no "[+] Do you want install the latest version of gitlab-runner?"; then
    if pgrep gitlab-runner; then
        sudo $bin_runner stop
    fi
    echo "[+] Downloading gitlab-runner..."
    curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
    sudo apt install -y gitlab-runner
fi

## Install and run as service
if _get_yes_no "[+] Do you want create CI user for gitlab-runner?"; then
    sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
    user_name=gitlab-runner
    user_home=/home/gitlab-runner
else
    echo "current user: $USER"
    user_name=$USER
    user_home=$HOME
fi

if _get_yes_no "[+] Do you want install as service?"; then
    sudo $bin_runner install --user "$user_name" --working-directory "$user_home"/runner
    sudo $bin_runner start
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
    sudo $bin_runner register \
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
