#!/usr/bin/env bash

_cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    # script cleanup here
    # rm -f $file_temp
}

_loading_rotate() {
    sleep "${1:-10}" &
    pid=$!
    frames='/ - \ |'
    while kill -0 $pid >/dev/null 2>&1; do
        for frame in $frames; do
            printf "\r%s Loading..." "$frame"
            sleep 0.5
        done
    done
    printf "\n"
}

_loading_second() {
    s="${1:-10}"
    for i in $(seq 1 "$s"); do
        printf "\rLoading... %s/$s" "$i"
        sleep 1
    done
    printf "\n"
}

_loading_left_right() {
    while true; do
        # Frame #1
        printf "\r< Loading..."
        sleep 0.5
        # Frame #2
        printf "\r> Loading..."
        sleep 0.5
    done
}

_msg_color() {
    bold=$(tput bold)
    underline=$(tput smul)
    italic=$(tput sitm)
    info=$(tput setaf 2)
    error=$(tput setaf 160)
    warn=$(tput setaf 214)
    reset=$(tput sgr0)
    echo "${info}INFO${reset}: This is an ${bold}info${reset} message"
    echo "${error}ERROR${reset}: This is an ${underline}error${reset} message"
    echo "${warn}WARN${reset}: This is a ${italic}warning${reset} message"
}

_color() {
    if [[ -t 2 ]] && [[ -z "${no_color-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
        COLOROFF='\033[0m'
        RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
    else
        unset COLOROFF RED GREEN ORANGE BLUE PURPLE CYAN YELLOW
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

_get_confirm() {
    read -rp "${1:-Do you want to proceed?} [y/N] " confirm_choice
    if [[ ${confirm_choice:-n} =~ ^(y|Y|yes|YES)$ ]]; then
        return 0 # true
    else
        return 1 # false
    fi
}

_parse_params() {
    # default values of variables set from params
    flag=0
    param=''
    while :; do
        case "${1-}" in
        --no-color) no_color=1 ;;
        -h | --help) usage ;;
        -f | --flag) flag=1 ;; # example flag
        -v | --verbose)
            set -x
            enable_log=1
            ;;
        -p | --param) # example named parameter
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
Usage: $me_name [options] [Parameter]

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
    me_name="$(basename "${BASH_SOURCE[0]}")"
    me_path="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    me_log="${me_path}/${me_name}.log"
    [ -w "$me_path" ] || me_log="/tmp/${me_name}.log"
    [[ "$enable_log" -eq 1 ]] && echo "Log file is \"$me_log\""
}

_func_demo() {
    _msg "demo function 1."
    _msg "${RED}Read parameters:${COLOROFF}"
    _msg "  - ${YELLOW}flag${COLOROFF}: ${flag}"
    _msg "  - ${BLUE}param:${COLOROFF} ${param}"
    _msg "  - ${GREEN}arguments:${COLOROFF} ${args[*]-}"
    _msg "  - ${ORANGE}ORANGE text contents${COLOROFF}"
    _msg "  - ${PURPLE}PURPLE text contents${COLOROFF}"
    _msg "  - ${CYAN}CYAN text contents${COLOROFF}"
    # _loading_rotate 10
    # _loading_left_right
    _loading_second 12
}

main() {
    _color
    _parse_params "$@"
    _myself
    set -Eeuo pipefail
    trap _cleanup SIGINT SIGTERM ERR EXIT

    ## script logic here
    _func_demo
}

main "$@"
