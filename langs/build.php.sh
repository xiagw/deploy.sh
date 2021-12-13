#!/usr/bin/env bash

file_lang="${gitlab_project_dir}/composer.json"
string_grep="$gitlab_project_path/$env_namespace/$(md5sum "$file_lang" | awk '{print $1}')"
if ! grep -q "$string_grep" "${script_log}"; then
    COMPOSER_INSTALL=1
fi
[ -d "${gitlab_project_dir}/vendor" ] || COMPOSER_INSTALL=1

if [ -f "$gitlab_project_dir"/custom.build.sh ]; then
    bash "$gitlab_project_dir"/custom.build.sh
    return
fi

if [[ "${COMPOSER_INSTALL:-0}" -eq 1 ]]; then
    echo_time_step "php composer install..."
    [[ "${github_action:-0}" -eq 1 ]] && return 0
    if ! docker images | grep -q "deploy/composer"; then
        DOCKER_BUILDKIT=1 docker build --quiet --tag "deploy/composer" --build-arg CHANGE_SOURCE="${ENV_CHANGE_SOURCE}" \
            -f "$script_dockerfile/Dockerfile.composer" "$script_dockerfile" >/dev/null
    fi
    # rm -rf "${gitlab_project_dir}"/vendor
    $docker_run -v "$gitlab_project_dir:/app" -w /app "${build_image_from:-deploy/composer}" bash -c "composer install ${quiet_flag}" &&
        echo "$string_grep ${file_lang}" >>"${script_log}" || true
    [ -d "$gitlab_project_dir"/vendor ] && chown -R 1000:1000 "$gitlab_project_dir"/vendor
    echo_time "end php composer install."
else
    echo_time "skip php composer install."
fi
