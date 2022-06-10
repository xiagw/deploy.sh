#!/usr/bin/env bash

if [[ -f $gitlab_project_dir/build.gradle ]]; then
    echo_msg step "java build [gradle]..."
    gradle -q
else
    if [[ "${ENV_BUILD_JAVA_USE_MVN:-0}" = 1 ]]; then
        echo_msg step "java build [maven]..."
        docker run -i --rm -v "$gitlab_project_dir":/usr/src/mymaven -w /usr/src/mymaven maven:3.6-jdk-8 mvn clean install -P"$MVN_PROFILE"
    fi
    # mvn clean install
fi
