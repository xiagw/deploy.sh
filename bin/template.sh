#!/usr/bin/env bash

_cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    # script cleanup here
    # rm -f $file_temp
}

_color() {
    if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
        NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m'
        BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
    else
        NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
    fi
}

_msg() {
    echo >&2 -e "${1-}"
}

_log() {
    echo "[$(date +%Y%m%d-%T)], $*" >>"$me_log"
}

_die() {
    local msg=$1
    local code=${2-1} # default exit status 1
    _msg "$msg"
    exit "$code"
}

_parse_params() {
    # default values of variables set from params
    flag=0
    param=''
    while :; do
        case "${1-}" in
        -h | --help) usage ;;
        -v | --verbose) set -x ;;
        --no-color) NO_COLOR=1 ;;
        -f | --flag) flag=1 ;; # example flag
        -p | --param)          # example named parameter
            param="${2-}"
            shift
            ;;
        -?*) _die "Unknown option: $1" ;;
        *) break ;;
        esac
        shift
    done
    args=("$@")
    # check required params and arguments
    # [[ -z "${param-}" ]] && _die "Missing required parameter: param"
    # [[ ${#args[@]} -eq 0 ]] && _die "Missing script arguments"
    return 0
}

_usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [options] [Parameter]

Script description here.

Available options:

    -h, --help      Print this help and exit
    -v, --verbose   Print script debug info
    -f, --flag      Some flag description
    -p, --param     Some param description

Examples:
    $0 -f -p param arg1 arg2
EOF
    exit
}

_myself() {
    # script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    if [ -w "$me_path" ]; then
        me_log="${me_path}/${me_name}.log"
    else
        me_log="/tmp/${me_name}.log"
    fi
    echo "Log file is \"$me_log\""
}

_demo() {
    _msg "demo function."
    _msg "${RED}Read parameters:${NOFORMAT}"
    _msg "  - ${YELLOW}flag${NOFORMAT}: ${flag}"
    _msg "  - ${BLUE}param:${NOFORMAT} ${param}"
    _msg "  - ${GREEN}arguments:${NOFORMAT} ${args[*]-}"
}

main() {
    _parse_params "$@"
    _color
    _myself
    set -Eeuo pipefail
    trap _cleanup SIGINT SIGTERM ERR EXIT

    ## script logic here
    _demo

}

main "$@"
