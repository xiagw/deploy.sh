#!/usr/bin/env bash

_get_yes_no() {
    read -rp "${1:-Confirm the action? [y/N]} " read_yes_no
    if [[ ${read_yes_no:-n} =~ ^(y|Y|yes|YES)$ ]]; then
        return 0
    else
        return 1
    fi
}

if _get_yes_no "[+] Do you want install the latest version of gitlab-runner?"; then
    echo "[+] Installing GitLab Runner..."
    ## Download the binary for your system
    url_gr=https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
    path_gr=/usr/local/bin/gitlab-runner
    sudo curl -Lo $path_gr $url_gr
    sudo chmod +x $path_gr
fi

## Create a GitLab CI user
## Install and run as service
if _get_yes_no "[+] Do you want create CI user for gitlab-runner?"; then
    sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
    sudo $path_gr install --user=gitlab-runner --working-directory=/home/gitlab-runner
else
    echo "[+] Use current user $USER"
    ## Or use current user
    sudo $path_gr install --user="$USER" --working-directory="$HOME"/runner
    sudo $path_gr start
fi

# git clone --depth 1 https://gitee.com/xiagw/deploy.sh.git "$HOME"/runner
git clone --depth 1 https://github.com/xiagw/deploy.sh.git "$HOME"/runner

read -rp "[+] Enter your gitlab url [https://git.example.com]: " reg_url
read -rp "[+] Enter your gitlab-runner token: " reg_token

sudo $path_gr register \
    --non-interactive \
    --url "${reg_url:?empty url}" \
    --registration-token "${reg_token:?empty token}" \
    --executor shell \
    --tag-list docker,linux \
    --run-untagged \
    --locked \
    --access-level=not_protected

## create git project
if _get_yes_no "[+] Do you want install python-gitlab? "; then
    python3 -m pip install --upgrade pip
    python3 -m pip install --upgrade python-gitlab
    ## config ~/.python-gitlab.cfg
    if [ ! -f ~/.python-gitlab.cfg ]; then
        cat >~/.python-gitlab.cfg <<EOF
[global]
default = abc
ssl_verify = true
timeout = 5

[abc]
url = $reg_url
private_token = $reg_token
api_version = 4
per_page = 100
EOF
    fi
fi
if _get_yes_no "[+] Do you want create a project [devops] in $reg_url ? "; then
    gitlab project create --name "devops"
fi
if _get_yes_no "[+] Do you want create a project [pms] in $reg_url ? "; then
    gitlab project create --name "pms"
fi
