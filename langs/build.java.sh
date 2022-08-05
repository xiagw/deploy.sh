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
    # docker run -i --rm -v "$gitlab_project_dir":/usr/src/mymaven -w /usr/src/mymaven maven:3.6-jdk-8 mvn clean -U package -DskipTests
    [ -d "$gitlab_project_dir"/maven_repository ] || mkdir "$gitlab_project_dir"/maven_repository
    docker run -i --rm -u 1000:1000 \
        -v "$gitlab_project_dir"/maven_repository:/maven_repository \
        -v "$gitlab_project_dir":/app \
        -w /app \
        maven:3.6-jdk-8 \
        mvn -T 1C clean --quiet \
        --update-snapshots package \
        --define skipTests \
        --define maven.compile.fork=true \
        --activate-profiles "$MVN_PROFILE" \
        --settings settings.xml
fi

[ -d $path_for_rsync ] || mkdir "$gitlab_project_dir/${path_for_rsync%/}"

find "${gitlab_project_dir}" -path "${gitlab_project_dir}/${path_for_rsync%/}" -prune -o -type f \
    -regextype egrep -iregex '.*SNAPSHOT.*\.jar' -exec cp {} "$gitlab_project_dir/$path_for_rsync" \;
