#!/usr/bin/env bash

path_for_rsync='jar_file/'
MVN_PROFILE="${gitlab_project_branch}"

if [[ -f "$gitlab_project_dir/build.gradle" ]]; then
    echo_msg step "java build [gradle]..."
    gradle -q
else
    echo_msg step "java build [maven]..."
    # docker run -i --rm -v "$gitlab_project_dir":/usr/src/mymaven -w /usr/src/mymaven maven:3.6-jdk-8 mvn clean -U package -DskipTests
    docker run -i --rm -v "$gitlab_project_dir":/usr/src/mymaven \
        -w /usr/src/mymaven maven:3.6-jdk-8 mvn clean -U package -DskipTests --activate-profiles "$MVN_PROFILE"
fi

[ -d $path_for_rsync ] || mkdir "$gitlab_project_dir/${path_for_rsync%/}"

find "${gitlab_project_dir}" -path "./${path_for_rsync%/}" -prune -o -type f \
    -regextype egrep -iregex '.*SNAPSHOT.*\.jar' -exec cp {} "$gitlab_project_dir/$path_for_rsync" \;

