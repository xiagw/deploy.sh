#!/usr/bin/env bash

# https://docs.fastlane.tools/

_msg step "build android [fastlane]..."
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

# write shell function:
# 1, build android code
_build_android() {
    # Set the Android SDK and NDK paths
    export ANDROID_HOME=/path/to/android/sdk
    export ANDROID_NDK_HOME=/path/to/android/ndk

    # Set the build type and variant
    local build_type="${1:-debug}"
    local build_variant="${2:-dev}"

    # Set the project directory
    local project_dir="/path/to/android/project"

    # Build the project
    cd "$project_dir" && ./gradlew assemble${build_variant^}${build_type^}
}
