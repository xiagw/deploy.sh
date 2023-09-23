#!/usr/bin/env bash
# shellcheck disable=2154,2034

## https://github.com/squizlabs/PHP_CodeSniffer
## install ESlint: yarn global add eslint ("$HOME/".yarn/bin/eslint)
_msg step 'code style [PHP Code Sniffer], < standard=PSR12 >...'
[[ "${github_action:-0}" -eq 1 ]] && return 0
if ! docker images | grep -q 'deploy/phpcs'; then
    DOCKER_BUILDKIT=1 docker build ${quiet_flag} -t deploy/phpcs -f "$me_dockerfile/Dockerfile.phpcs" "$me_dockerfile" >/dev/null
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

# write shell function:
# 1, check code style for php code
# 2, using docker


_check_php_code_style() {
  _msg step "[style] check PHP code style"

  # Check if the pipeline code style variable is set to 1
  if [[ "${PIPELINE_CODE_STYLE:-0}" -ne 1 ]]; then
    _msg info "Skipping PHP code style check."
    return
  fi

  # Define the paths to the PHP source code and the PHP CodeSniffer configuration file
  php_path="/path/to/php/source/code"
  phpcs_config="/path/to/phpcs.xml"

  # Run the PHP CodeSniffer tool using Docker, passing in the source code and configuration file paths
  docker run --rm -v "$php_path:/app" -v "$phpcs_config:/phpcs.xml" \
    "squizlabs/php_codesniffer" --standard=PSR2 /app

  _msg stepend "[style] check PHP code style"
}
