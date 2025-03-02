#!/usr/bin/env bash

_msg step "[TODO] golang code style..."
gofmt "${gitlab_project_dir:-}"/*.go
