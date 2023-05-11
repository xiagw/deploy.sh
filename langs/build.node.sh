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
_msg step "[build] yarn build"

# rm -f package-lock.json
[[ "${github_action:-0}" -eq 1 ]] && return 0

## create image: deploy/node
if ! docker images | grep -q 'deploy/node'; then
    DOCKER_BUILDKIT=1 docker build ${quiet_flag} --tag deploy/node \
        --build-arg IN_CHINA="${ENV_IN_CHINA}" \
        --file "$me_dockerfile/Dockerfile.node" "$me_dockerfile"
fi

## custome build? / 自定义构建？
if [ -f "$gitlab_project_dir"/custom.build.sh ]; then
    $docker_run -v "${gitlab_project_dir}":/app -w /app deploy/node bash custom.build.sh
    return
fi

## yarn install (node_modules)
if [[ ${YARN_INSTALL:-false} == 'true' ]]; then
    $docker_run -v "${gitlab_project_dir}":/app -w /app deploy/node bash -c "yarn install" &&
        echo "$file_json_md5" >>"${me_log}"
else
    _msg time "skip yarn install..."
fi

## build
# "${gitlab_project_dir}/.env.development"
# "${gitlab_project_dir}/.env.dev"
# "${gitlab_project_dir}/.env.develop"
env_dev_files=(
    "${gitlab_project_dir}/.env.production"
    "${gitlab_project_dir}/.env.prod"
    "${gitlab_project_dir}/.env.main"
    "${gitlab_project_dir}/.env.testing"
    "${gitlab_project_dir}/.env.test"
    "${gitlab_project_dir}/.env.uat"
)
for env_file in "${env_dev_files[@]}"; do
    if [[ -f $env_file ]]; then
        if [[ $env_namespace == *uat* || $env_namespace == *test* ]]; then
            build_opt=build:stage
            break
        fi
        if [[ $env_namespace == *master* || $env_namespace == *main* || $env_namespace == *prod* ]]; then
            build_opt=build:prod
            break
        fi
    fi
done

$docker_run -v "${gitlab_project_dir}":/app -w /app deploy/node bash -c "yarn run ${build_opt:-build}"

[ -d "${gitlab_project_dir}"/build ] && rsync -a --delete "${gitlab_project_dir}"/build/ "${gitlab_project_dir}"/dist/

_msg time "[build] yarn"
