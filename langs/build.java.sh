#!/usr/bin/env bash

if [[ -f $gitlab_project_dir/build.gradle ]]; then
    echo_time_step "java build [gradle]..."
    gradle -q
else
    echo_time_step "java build [maven]..."
    docker run -it --rm -v "$gitlab_project_dir":/usr/src/mymaven -w /usr/src/mymaven maven:3.3-jdk-8 mvn clean install
    # mvn clean install
fi
