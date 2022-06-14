#!/usr/bin/env bash

echo "[+] Installing GitLab Runner..."
# Download the binary for your system
sudo curl -L --output /usr/local/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64

# Give it permissions to execute
sudo chmod +x /usr/local/bin/gitlab-runner

# Create a GitLab CI user
# sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash

# Install and run as service
# sudo /usr/local/bin/gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
sudo /usr/local/bin/gitlab-runner install --user="$USER" --working-directory="$HOME"/runner
sudo /usr/local/bin/gitlab-runner start

git clone https://github.com/xiagw/deploy.sh.git "$HOME"/runner
## gitlab-runner register token from gitlab-admin-runner: register an instance runner
read -rp "Enter your gitlab-runner token: " reg_token
# reg_token='xxxxxxxx'
# sudo /usr/local/bin/gitlab-runner register --url "$DOMAIN_NAME_GIT_EXT" --registration-token "${reg_token:?empty var}" --executor docker --docker-image gitlab/gitlab-runner:latest --docker-volumes /var/run/docker.sock:/var/run/docker.sock --docker-privileged
sudo /usr/local/bin/gitlab-runner register --url "$DOMAIN_NAME_GIT_EXT" --registration-token "${reg_token:?empty var}" --executor shell --tag-list docker,linux --run-untagged --locked --access-level=not_protected -n

## create git project
# python3 -m pip install --upgrade pip
# python3 -m pip install --upgrade python-gitlab

# gitlab project create --name "pms"
# gitlab project create --name "devops"
