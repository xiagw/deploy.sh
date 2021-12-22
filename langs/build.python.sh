#!/usr/bin/env bash

echo_time_step "build python [pip install]..."
if [[ "${project_docker:-0}" -eq 1 ]]; then
    echo "skip pip install, just build image."
else
    python3 -m pip install -r requirements.txt
    python manage.py test
fi
