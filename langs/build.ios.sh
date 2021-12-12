#!/usr/bin/env bash

# https://docs.fastlane.tools/

case $gitlab_project_branch in
main | master)
    fastlane release
    ;;
*)
    fastlane tests
    fastlane beta
    ;;
esac