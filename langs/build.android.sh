#!/usr/bin/env bash

# https://docs.fastlane.tools/

case $gitlab_project_branch in
main | master)
    fastlane playstore
    fastlane action gradle
    fastlane action upload_to_play_store
    ;;
*)
    fastlane tests
    fastlane beta
    ;;
esac
