#!/usr/bin/env bash
# shellcheck disable=2154

path_for_rsync="jar_file"
MVN_PROFILE="${gitlab_project_branch}"
maven_cache="${me_path_data}"/cache.maven

if [[ -f "$gitlab_project_dir/build.gradle" ]]; then
    _msg step "[build] with gradle"
    gradle -q
else
    _msg step "[build] with maven"
    if [[ -f $gitlab_project_dir/settings.xml ]]; then
        MVN_SET="--settings settings.xml"
    fi
    [ -d "${maven_cache}" ] || mkdir -p "${maven_cache}"

    docker run --rm -i --user "$(id -u):$(id -g)" \
        -e MAVEN_CONFIG=/var/maven/.m2 \
        -v "$maven_cache":/var/maven/.m2:rw \
        -v "$gitlab_project_dir":/app:rw \
        -w /app \
        maven:"${ENV_MAVEN_VER:-3.6-jdk-8}" \
        mvn -T 1C clean --quiet \
        --update-snapshots package \
        --define skipTests \
        --define user.home=/var/maven \
        --define maven.compile.fork=true \
        --activate-profiles "$MVN_PROFILE" $MVN_SET
fi

[ -d "$gitlab_project_dir/$path_for_rsync" ] || mkdir "$gitlab_project_dir/${path_for_rsync}"

find "${gitlab_project_dir}" -path "${path_for_rsync}" -prune -o -type f \
    -regextype egrep -iregex '.*SNAPSHOT.*\.(jar|war)' \
    -exec rsync -a --exclude='framework*' --exclude='gdp-module*' --exclude='sdk*.jar' --exclude='core*.jar' {} "$path_for_rsync/" \;

if [[ "${exec_deploy_k8s:-0}" -ne 1 ]]; then
    find "${gitlab_project_dir}" -path "${path_for_rsync}" -prune -o -type f \
        -regextype egrep -iregex ".*resources.*${gitlab_project_branch}.*\.(yml)" \
        -exec rsync -a {} "$path_for_rsync/" \;
fi

_msg stepend "[build] java build"
