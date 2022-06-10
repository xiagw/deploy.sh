#!/usr/bin/env bash

echo_msg step "[TODO] golang code style..."
gofmt $gitlab_project_dir/*.go
