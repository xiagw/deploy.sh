#!/usr/bin/env bash

_get_yes_no() {
    read -rp "${1:-Confirm the action?} [y/N]" read_yes_no
    case ${read_yes_no:-n} in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) return 1 ;;
    esac
}

bin_runner=/usr/local/bin/gitlab-runner
if _get_yes_no "[+] Do you want install the latest version of gitlab-runner?"; then
    if pgrep gitlab-runner; then sudo $bin_runner stop; fi
    echo "[+] Downloading gitlab-runner..."
    url_runner=https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
    curl -LO $bin_runner $url_runner
    sudo install -m 0755 gitlab-runner-linux-amd64 $bin_runner
    rm -f gitlab-runner-linux-amd64
fi

## Install and run as service
if _get_yes_no "[+] Do you want create CI user for gitlab-runner?"; then
    sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
    user_name=gitlab-runner
    user_home=/home/gitlab-runner
else
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

if _get_yes_no "[+] Do you want register gitlab-runner? "; then
    read -rp "[+] Enter your gitlab url [https://git.example.com]: " read_url_git
    read -rp "[+] Enter your gitlab-runner token: " read_token
    url_git="${read_url_git:? ERR read_url_git}"
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
    read -rp "[+] Enter your gitlab url [https://git.example.com]: " read_url_git
    read -rp "[+] Enter your Access Token: " read_access_token
    url_git="${read_url_git:? ERR read_url_git}"
    access_token="${read_access_token:? ERR read_access_token}"
    python3 -m pip install --upgrade pip
    python3 -m pip install --upgrade python-gitlab
    ## config ~/.python-gitlab.cfg
    if [ ! -f ~/.python-gitlab.cfg ]; then
        cat >~/.python-gitlab.cfg <<EOF
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
fi

## create git project
if _get_yes_no "[+] Do you want create a project [devops] in $url_git ? "; then
    gitlab project create --name "devops"
fi

if _get_yes_no "[+] Do you want create a project [pms] in $url_git ? "; then
    gitlab project create --name "pms"
fi
