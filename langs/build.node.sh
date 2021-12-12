#!/usr/bin/env bash

path_for_rsync='dist/'
file_lang="${gitlab_project_dir}/package.json"
string_grep="$gitlab_project_path/$env_namespace/$(md5sum "$file_lang" | awk '{print $1}')"
if ! grep -q "$string_grep" "${script_log}"; then
    echo "$string_grep ${file_lang}" >>"${script_log}"
    YARN_INSTALL=true
fi
[ -d "${gitlab_project_dir}/node_modules" ] || YARN_INSTALL=true

# https://github.com/nodesource/distributions#debinstall
echo_time_step "node yarn build..."
# rm -f package-lock.json
[[ "${github_action:-0}" -eq 1 ]] && return 0
if docker images | grep -q 'deploy/node'; then
    true
else
    DOCKER_BUILDKIT=1 docker build ${quiet_flag} -t deploy/node --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE}" \
        -f "$script_dockerfile/Dockerfile.nodebuild" "$script_dockerfile"
fi
if [[ ${YARN_INSTALL:-false} == 'true' ]]; then
    $docker_run -v "${gitlab_project_dir}":/app -w /app 'deploy/node' bash -c "yarn install"
fi
$docker_run -v "${gitlab_project_dir}":/app -w /app 'deploy/node' bash -c "yarn run build"
[ -d "${gitlab_project_dir}"/build ] && rsync -a --delete "${gitlab_project_dir}"/build/ "${gitlab_project_dir}"/dist/
echo_time "end node yarn build."
