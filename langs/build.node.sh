#!/usr/bin/env bash
# shellcheck disable=2154,2034

path_for_rsync='dist/'
file_json="${gitlab_project_dir}/package.json"
file_json_md5="$gitlab_project_path/$env_namespace/$(md5sum "$file_json" | awk '{print $1}')"
if grep -q "$file_json_md5" "${me_log}"; then
    echo "The same checksum for ${file_json}, skip yarn install."
else
    echo "New checksum for ${file_json}, run yarn install."
    YARN_INSTALL=true
fi
if [ ! -d "${gitlab_project_dir}/node_modules" ]; then
    YARN_INSTALL=true
fi

# https://github.com/nodesource/distributions#debinstall
_msg step "[build] yarn..."

# rm -f package-lock.json
[[ "${github_action:-0}" -eq 1 ]] && return 0

if ! docker images | grep -q 'deploy/node'; then
    DOCKER_BUILDKIT=1 docker build ${quiet_flag} -t deploy/node \
        --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE}" \
        -f "$script_dockerfile/Dockerfile.nodebuild" "$script_dockerfile"
fi

## exist custome build? / 自定义构建？
if [ -f "$gitlab_project_dir"/custom.build.sh ]; then
    $docker_run -v "${gitlab_project_dir}":/app -w /app deploy/node bash custom.build.sh
    return
fi

if [[ ${YARN_INSTALL:-false} == 'true' ]]; then
    $docker_run -v "${gitlab_project_dir}":/app -w /app deploy/node bash -c "yarn install" &&
        echo "$file_json_md5" >>"${me_log}"
else
    _msg time "skip yarn install..."
fi

$docker_run -v "${gitlab_project_dir}":/app -w /app deploy/node bash -c "yarn run build"

[ -d "${gitlab_project_dir}"/build ] && rsync -a --delete "${gitlab_project_dir}"/build/ "${gitlab_project_dir}"/dist/

_msg time "[build] yarn"
