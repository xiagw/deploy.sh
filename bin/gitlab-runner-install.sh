#!/usr/bin/env bash

_get_yes_no() {
    read -rp "${1:-Confirm the action?} [y/N]" read_yes_no
    if [[ ${read_yes_no:-n} =~ ^(y|Y|yes|YES)$ ]]; then
        return 0
    else
        return 1
    fi
}

bin_runner=/usr/local/bin/gitlab-runner
if _get_yes_no "[+] Do you want install the latest version of gitlab-runner?"; then
    echo "[+] Installing GitLab Runner..."
    ## Download the binary for your system
    url_runner=https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
    bin_runner=/usr/local/bin/gitlab-runner
    sudo curl -Lo $bin_runner $url_runner
    sudo chmod +x $bin_runner
fi

## Create a GitLab CI user
## Install and run as service
if _get_yes_no "[+] Do you want create CI user for gitlab-runner?"; then
    sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
    sudo $bin_runner install --user gitlab-runner --working-directory /home/gitlab-runner
else
    echo "[+] Use current user $USER"
    ## Or use current user
    sudo $bin_runner install --user "$USER" --working-directory "$HOME"/runner
    sudo $bin_runner start
fi

# git clone --depth 1 https://gitee.com/xiagw/deploy.sh.git "$HOME"/runner
git clone --depth 1 https://github.com/xiagw/deploy.sh.git "$HOME"/runner

read -rp "[+] Enter your gitlab url [https://git.example.com]: " read_url_git
read -rp "[+] Enter your gitlab-runner token: " read_token
url_git="${read_url_git:? ERR read_url_git}"
reg_token="${read_token:? Err read_token}"
sudo $bin_runner register \
    --non-interactive \
    --url "${url_git:?empty url}" \
    --registration-token "${reg_token:?empty token}" \
    --executor shell \
    --tag-list docker,linux \
    --run-untagged \
    --locked \
    --access-level=not_protected

## install python-gitlab (GitLab API)
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
url = $url_git
private_token = $reg_token
api_version = 4
per_page = 100
EOF
    fi
fi

## create git project
if _get_yes_no "[+] Do you want create a project [devops] in $url_git ? "; then
    gitlab project create --name "devops"
fi
if _get_yes_no "[+] Do you want create a project [pms] in $url_git ? "; then
    gitlab project create --name "pms"
fi
