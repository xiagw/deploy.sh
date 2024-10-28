#!/usr/bin/env bash

_msg step "build C [make]..."
./configure
make

# write shell function:
# 1, build C code
# 2, using Makefile

build_c_code() {
    local makefile_path="$1"
    local target="$2"
    local build_dir="$3"

    # Make sure the build directory exists
    mkdir -p "$build_dir"

    # Change to the build directory
    cd "$build_dir" || return 1

    # Run make with the specified Makefile and target
    make -f "$makefile_path" "$target" || return 1
}
# build_c_code "path/to/Makefile" "my_target" "build_dir"
