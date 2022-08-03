#!/usr/bin/env bash

path_for_rsync='jar_file/'
if [[ -f "$gitlab_project_dir/build.gradle" ]]; then
    echo_msg step "java build [gradle]..."
    gradle -q
else
    echo_msg step "java build [maven]..."
    # docker run -i --rm -v "$gitlab_project_dir":/usr/src/mymaven -w /usr/src/mymaven maven:3.6-jdk-8 mvn clean -U package -DskipTests
    docker run -i --rm \
        -v "$gitlab_project_dir":/usr/src/mymaven \
        -w /usr/src/mymaven maven:3.6-jdk-8 mvn clean -U package -DskipTests -P"$MVN_PROFILE"
fi

files_jar="$(find "${gitlab_project_dir}" -type f -regextype egrep -iregex '.*SNAPSHOT.*\.jar' -print0)"
[ -d $path_for_rsync ] || mkdir "$gitlab_project_dir/${path_for_rsync%/}"
for i in $files_jar; do
    cp -f "$i" "$gitlab_project_dir/$path_for_rsync"
done
