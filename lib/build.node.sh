#!/usr/bin/env bash
# shellcheck disable=2154,2034

path_for_rsync='dist/'
file_json="${gitlab_project_dir}/package.json"
file_json_md5="$gitlab_project_path/$env_namespace/$(md5sum "$file_json" | awk '{print $1}')"
if grep -q "$file_json_md5" "${me_log}"; then
    echo "Same checksum for ${file_json}, skip yarn install."
else
    echo "New checksum for ${file_json}, run yarn install."
    yarn_install=true
fi
if [ ! -d "${gitlab_project_dir}/node_modules" ]; then
    yarn_install=true
fi

# https://github.com/nodesource/distributions#debinstall
_msg step "[build] yarn install"

# rm -f package-lock.json
${github_action:-false} && return 0

## create image: deploy/node
# if ! docker images | grep -q 'deploy/node'; then
#     $build_cmd build $build_cmd_opt --tag deploy/node --file "$me_dockerfile/Dockerfile.node" "$me_dockerfile"
# fi

## custome build? / 自定义构建？
if [ -f "$gitlab_project_dir/build.custom.sh" ]; then
    $run_cmd -v "${gitlab_project_dir}":/app -w /app "${build_image_from:-node:18-slim}" bash build.custom.sh
    return
fi

## yarn install (node_modules)
if ${yarn_install:-false}; then
    $run_cmd -v "${gitlab_project_dir}":/app -w /app "${build_image_from:-node:18-slim}" bash -c "yarn install" &&
        echo "$file_json_md5" >>"${me_log}"
else
    _msg time "skip yarn install..."
fi

## build
case $env_namespace in
*uat* | *test*)
    build_opt=build:stage
    ;;
*master* | *main* | *prod*)
    build_opt=build:prod
    ;;
esac

$run_cmd -v "${gitlab_project_dir}":/app -w /app "${build_image_from:-node:18-slim}" bash -c "yarn run ${build_opt:-build}"

if [ -d "${gitlab_project_dir}"/build ]; then
    rsync -a --delete "${gitlab_project_dir}"/build/ "${gitlab_project_dir}"/dist/
fi
_msg stepend "[build] yarn"
