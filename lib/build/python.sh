#!/usr/bin/env bash

_msg step "build python [pip install]..."

python3 -m pip install -r requirements.txt
python manage.py test
