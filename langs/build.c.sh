#!/usr/bin/env bash

echo_time_step "build C [make]..."
if [[ "${project_docker:-0}" -eq 1 ]]; then
    echo "skip pip install, just build image."
else
    make
fi
