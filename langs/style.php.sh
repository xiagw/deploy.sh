#!/usr/bin/env bash
# shellcheck disable=2154,2034

## https://github.com/squizlabs/PHP_CodeSniffer
## install ESlint: yarn global add eslint ("$HOME/".yarn/bin/eslint)
_msg step 'code style [PHP Code Sniffer], < standard=PSR12 >...'
[[ "${github_action:-0}" -eq 1 ]] && return 0
if ! docker images | grep -q 'deploy/phpcs'; then
    DOCKER_BUILDKIT=1 docker build ${quiet_flag} -t deploy/phpcs -f "$script_dockerfile/Dockerfile.phpcs" "$script_dockerfile" >/dev/null
fi
phpcs_result=0
for i in $(git --no-pager diff --name-only HEAD^ | awk '/\.php$/{if (NR>0){print $0}}'); do
    if [ ! -f "$gitlab_project_dir/$i" ]; then
        echo_warn "$gitlab_project_dir/$i not exists."
        continue
    fi
    if ! $docker_run -v "$gitlab_project_dir":/project deploy/phpcs phpcs -n --standard=PSR12 --colors --report="${phpcs_report:-full}" "/project/$i"; then
        phpcs_result=$((phpcs_result + 1))
    fi
done
# [ "$phpcs_result" -ne "0" ] && exit $phpcs_result
