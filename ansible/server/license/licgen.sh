#!/usr/bin/env bash

me_path="$(dirname "$(readlink -f "$0")")"
cmd=$me_path/lmcrypt.exe
if [ -f "$cmd" ]; then
    chmod +x "$cmd"
    $cmd -i "$me_path"/cadence.txt -o "$me_path"/license.dat -r
fi
