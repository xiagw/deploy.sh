#!/usr/bin/env bash

echo "[+] Installing GitLab Runner..."
# Download the binary for your system
url_gr=https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
path_gr=/usr/local/bin/gitlab-runner
sudo curl -Lo $path_gr $url_gr
sudo chmod +x $path_gr

# Create a GitLab CI user
# sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash

# Install and run as service
# sudo $path_gr install --user=gitlab-runner --working-directory=/home/gitlab-runner
sudo $path_gr install --user="$USER" --working-directory="$HOME"/runner
sudo $path_gr start

git clone --depth 1 https://github.com/xiagw/deploy.sh.git "$HOME"/runner
## gitlab-runner register token from gitlab-admin-runner: register an instance runner
read -rp "[+] Enter your gitlab-runner token: " reg_token
# reg_token='xxxxxxxx'
# sudo $path_gr register --url "$DOMAIN_NAME_GIT_EXT" --registration-token "${reg_token:?empty var}" --executor docker --docker-image gitlab/gitlab-runner:latest --docker-volumes /var/run/docker.sock:/var/run/docker.sock --docker-privileged
#
# sudo /usr/local/bin/gitlab-runner register \
#     -n \
#     --url "https://git.mydomain.com" \
#     --registration-token "<my_token>" \
#     --executor shell \
#     --tag-list docker,linux \
#     --run-untagged \
#     --locked \
#     --access-level=not_protected

sudo $path_gr register \
    -n \
    --url "$DOMAIN_NAME_GIT_EXT" \
    --registration-token "${reg_token:?empty var}" \
    --executor shell \
    --tag-list docker,linux \
    --run-untagged \
    --locked \
    --access-level=not_protected

## create git project
# python3 -m pip install --upgrade pip
# python3 -m pip install --upgrade python-gitlab

# gitlab project create --name "pms"
# gitlab project create --name "devops"
