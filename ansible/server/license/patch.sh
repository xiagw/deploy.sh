#!/bin/bash

me_path="$(dirname "$(readlink -f "$0")")"

bin_verify=$me_path/pubkey_verify
bin_check=$me_path/synopsys_checksum

## exec
[ -x "$bin_verify" ] || chmod +x "$bin_verify"
[ -x "$bin_check" ] || chmod +x "$bin_check"

if [[ -z "${1}" ]]; then
    echo "Empty input, use current dir: . "
    patch_dir=$PWD
else
    echo "Patch dir is: $1"
    patch_dir="$1"
fi

## patch
if [ -d "$patch_dir" ]; then
    echo "directory \"$\" exists"
    cd "$patch_dir" && $bin_verify -y
    ## if synopsys
    if [[ "${patch_dir}" == *synopsys* ]]; then
        $bin_check -y
    fi
else
    echo "directory \"$patch_dir\" not exists, exit 1."
    exit 1
fi
