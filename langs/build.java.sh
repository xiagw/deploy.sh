#!/usr/bin/env bash
# shellcheck disable=2154

path_for_rsync="jar_file"
MVN_PROFILE="${gitlab_project_branch}"
maven_cache="${me_path_data}"/cache.maven

if [[ -f "$gitlab_project_dir/build.gradle" ]]; then
    echo_msg step "[build] java build with gradle..."
    gradle -q
else
    echo_msg step "[build] java build with maven..."
    if [[ -f $gitlab_project_dir/settings.xml ]]; then
        MVN_SET='--settings settings.xml'
    else
        MVN_SET=
    fi
    [ -d "${maven_cache}" ] || mkdir -p "${maven_cache}"

    docker run -i --rm --user "$(id -u):$(id -g)" \
        -e MAVEN_CONFIG=/var/maven/.m2 \
        -v "$maven_cache":/var/maven/.m2:rw \
        -v "$gitlab_project_dir":/app:rw \
        -w /app \
        maven:3.6-jdk-8 \
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

if [ -f "$gitlab_project_dir/run.sh" ]; then
    cp -vf "$gitlab_project_dir/run.sh" "$path_for_rsync/"
else
    true
fi

echo_msg time "[build] java build ... end"