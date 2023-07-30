#!/usr/bin/env bash
# shellcheck disable=2154

MVN_PROFILE="${gitlab_project_branch}"
jars_path="jars"
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

    docker run $ENV_ADD_HOST --rm -i --user "$(id -u):$(id -g)" \
        -e MAVEN_CONFIG=/var/maven/.m2 \
        -v "$maven_cache":/var/maven/.m2:rw \
        -v "$gitlab_project_dir":/src:rw \
        -w /src \
        maven:"${ENV_MAVEN_VER:-3.6-jdk-8}" \
        mvn -T 1C clean --quiet \
        --update-snapshots package \
        --define skipTests \
        --define user.home=/var/maven \
        --define maven.compile.fork=true \
        --activate-profiles "$MVN_PROFILE" $MVN_SET
fi

[ -d "$gitlab_project_dir/$jars_path" ] || mkdir "$gitlab_project_dir/${jars_path}"

find "${gitlab_project_dir}" -path "${jars_path}" -prune -o -type f \
    -regextype egrep -iregex '.*SNAPSHOT.*\.(jar|war)' \
    -exec rsync -a --exclude='framework*' --exclude='gdp-module*' --exclude='sdk*.jar' --exclude='core*.jar' {} "$jars_path/" \;

## copy *.yml
if [[ "${exec_deploy_k8s:-0}" -ne 1 ]]; then
    find "${gitlab_project_dir}" -path "${jars_path}" -prune -o -type f \
        -regextype egrep -iregex ".*resources.*${gitlab_project_branch}.*\.(yml)" \
        -exec rsync -a {} "$jars_path/" \;
fi

_msg stepend "[build] java build"
