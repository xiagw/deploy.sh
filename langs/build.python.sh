#!/usr/bin/env bash

echo_time_step "python install..."
python3 -m pip install -r requirements.txt
python manage.py test
