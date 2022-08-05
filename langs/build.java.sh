#!/usr/bin/env bash

if [[ "${project_docker}" -eq 1 ]]; then
    return 0
fi

path_for_rsync='jar_file/'
MVN_PROFILE="${gitlab_project_branch}"

if [[ -f "$gitlab_project_dir/build.gradle" ]]; then
    echo_msg step "java build [gradle]..."
    gradle -q
else
    echo_msg step "java build [maven]..."
    if [[ -f settings.xml ]]; then
        MVN_SET='--settings settings.xml'
    else
        MVN_SET=''
    fi
    [ -d "${script_path_data}"/maven ] || mkdir -p "${script_path_data}"/maven

    docker run -i --rm --user "$(id -u):$(id -g)" \
        -e MAVEN_CONFIG=/var/maven/.m2 \
        -v "$script_path_data"/maven:/var/maven/.m2:rw \
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

[ -d $path_for_rsync ] || mkdir "$gitlab_project_dir/${path_for_rsync%/}"

find "${gitlab_project_dir}" -path "${gitlab_project_dir}/${path_for_rsync%/}" -prune -o -type f \
    -regextype egrep -iregex '.*SNAPSHOT.*\.(jar|war)' -exec cp {} "$gitlab_project_dir/$path_for_rsync" \;
