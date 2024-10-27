#!/usr/bin/env bash
# shellcheck disable=2154,2034

file_json="${gitlab_project_dir}/composer.json"
file_json_md5="$gitlab_project_path/$env_namespace/$(md5sum "$file_json" | awk '{print $1}')"
if grep -q "$file_json_md5" "${me_log}"; then
    _msg time "The same checksum for ${file_json}, skip composer install."
else
    _msg time "New checksum for ${file_json}, run composer install."
    COMPOSER_INSTALL=true
fi
if [ ! -d "${gitlab_project_dir}/vendor" ]; then
    _msg time "Not found ${gitlab_project_dir}/vendor, run composer install."
    COMPOSER_INSTALL=true
fi

if [ -f "$gitlab_project_dir"/build.custom.sh ]; then
    _msg time "Found $gitlab_project_dir/build.custom.sh, run it"
    bash "$gitlab_project_dir"/build.custom.sh
    return
fi

if ${COMPOSER_INSTALL:-false}; then
    _msg step "[build] php composer install"
    ${github_action:-false} && return 0
    # if ! docker images | grep -q "deploy/composer"; then
    #     DOCKER_BUILDKIT=1 docker build $quiet_flag --tag "deploy/composer" --build-arg IN_CHINA="${ENV_IN_CHINA}" \
    #         -f "$me_dockerfile/Dockerfile.composer" "$me_dockerfile" >/dev/null
    # fi
    # rm -rf "${gitlab_project_dir}"/vendor
    if $run_cmd -v "$gitlab_project_dir:/app" -w /app "${build_image_from:-composer}" bash -c "composer install ${quiet_flag}"; then
        echo "$file_json_md5 ${file_json}" >>"${me_log}"
    fi
    [ -d "$gitlab_project_dir"/vendor ] && chown -R "$(id -u):$(id -g)" "$gitlab_project_dir"/vendor
    _msg stepend "[build] php composer install"
else
    _msg time "skip php composer install."
fi
