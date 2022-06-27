#!/usr/bin/env bash
# shellcheck disable=2154,2034

file_json="${gitlab_project_dir}/composer.json"
file_json_md5="$gitlab_project_path/$env_namespace/$(md5sum "$file_json" | awk '{print $1}')"
if grep -q "$file_json_md5" "${script_log}"; then
    echo "The same checksum for ${file_json}, skip composer install."
else
    echo "New checksum for ${file_json}, run composer install."
    COMPOSER_INSTALL=1
fi
if [ ! -d "${gitlab_project_dir}/vendor" ]; then
    echo "Not found ${gitlab_project_dir}/vendor, run composer install."
    COMPOSER_INSTALL=1
fi

if [ -f "$gitlab_project_dir"/custom.build.sh ]; then
    echo "Found custom.build.sh, run it"
    bash "$gitlab_project_dir"/custom.build.sh
    return
fi

if [[ "${COMPOSER_INSTALL:-0}" -eq 1 ]]; then
    echo_msg step "build php [composer install]..."
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    # if ! docker images | grep -q "deploy/composer"; then
    #     DOCKER_BUILDKIT=1 docker build $quiet_flag --tag "deploy/composer" --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE}" \
    #         -f "$script_dockerfile/Dockerfile.composer" "$script_dockerfile" >/dev/null
    # fi
    # rm -rf "${gitlab_project_dir}"/vendor
    # shellcheck disable=2015
    $docker_run -v "$gitlab_project_dir:/app" -w /app "${build_image_from:-composer}" bash -c "composer install ${quiet_flag}" &&
        echo "$file_json_md5 ${file_json}" >>"${script_log}" || true
    [ -d "$gitlab_project_dir"/vendor ] && chown -R 1000:1000 "$gitlab_project_dir"/vendor
    echo_msg time "end php composer install."
else
    echo_msg time "skip php composer install."
fi
