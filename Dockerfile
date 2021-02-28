FROM ubuntu:20.04

# ARG GIT_BRANCH=dev
# ARG DEPLOY_DEBUG=-q

WORKDIR /gitlab-runner

COPY . .

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -xe \
    && apt-get update -yqq \
    && apt-get install -yqq gettext-base \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/lastlog /var/log/faillog