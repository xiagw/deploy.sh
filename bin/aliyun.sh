#!/usr/bin/env bash
SCRIPT_DIR_0=$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")
exec "${SCRIPT_DIR_0}/lib/aliyun/main.sh" "$@"
