#!/usr/bin/env bash

if [[ -f $gitlab_project_dir/build.gradle ]]; then
    echo_time_step "java build [gradle]..."
    gradle -q
else
    if [[ "${ENV_BUILD_JAVA_USE_MVN:-0}" = 1 ]]; then 
        echo_time_step "java build [maven]..."
        docker run -i --rm -v "$gitlab_project_dir":/usr/src/mymaven -w /usr/src/mymaven maven:3.3-jdk-8 mvn clean install
    fi
    # mvn clean install
fi
