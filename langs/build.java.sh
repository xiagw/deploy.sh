#!/usr/bin/env bash

if [[ -f $gitlab_project_dir/build.gradle ]]; then
    echo_time_step "java build [gradle]..."
    gradle -q
else
    echo_time_step "java build [maven]..."
    mvn clean install
fi
