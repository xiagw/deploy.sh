#!/bin/bash

me_path="$(dirname "$(readlink -f "$0")")"

bin_verify=$me_path/pubkey_verify
bin_check=$me_path/synopsys_checksum
[ -x "$bin_verify" ] || chmod +x "$bin_verify"
[ -x "$bin_check" ] || chmod +x "$bin_check"

echo "Current dir is: $PWD"

## patch all files
$bin_verify -y

## patch synopsys files
if [[ "${1:-n}" == *synopsys* || "$PWD" == *synopsys* ]]; then
    $bin_check -y
fi
