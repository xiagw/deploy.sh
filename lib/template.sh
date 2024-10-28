#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# Global variables for commands
CMD_DATE=$(command -v gdate || command -v date)
CMD_GREP=$(command -v ggrep || command -v grep)
CMD_SED=$(command -v gsed || command -v sed)
CMD_READLINK=$(command -v greadlink || command -v readlink)
CMD_CURL=$(command -v /usr/local/opt/curl/bin/curl || command -v curl)

# Function definitions
_cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    # script cleanup here
    # rm -f "$file_temp"
}

_loading_rotate() {
    local pid frames
    sleep "${1:-10}" &
    pid=$!
    frames='/ - \ |'
    while kill -0 $pid >/dev/null 2>&1; do
        for frame in $frames; do
            printf '\r%s Loading...' "$frame"
            sleep 0.5
        done
    done
    printf '\n'
}

_loading_second() {
    local s i
    s="${1:-10}"
    for ((i=1; i<=s; i++)); do
        printf '\rLoading... %s/%s' "$i" "$s"
        sleep 1
    done
    printf '\n'
}

_loading_left_right() {
    trap 'return' INT TERM
    while true; do
        printf '\r< Loading...'
        sleep 0.5
        printf '\r> Loading...'
        sleep 0.5
    done
}

_msg_color() {
    local bold underline italic info error warn reset
    bold=$(tput bold)
    underline=$(tput smul)
    italic=$(tput sitm)
    info=$(tput setaf 2)
    error=$(tput setaf 160)
    warn=$(tput setaf 214)
    reset=$(tput sgr0)
    printf '%sINFO%s: This is an %sinfo%s message\n' "${info}" "${reset}" "${bold}" "${reset}"
    printf '%sERROR%s: This is an %serror%s message\n' "${error}" "${reset}" "${underline}" "${reset}"
    printf '%sWARN%s: This is a %swarning%s message\n' "${warn}" "${reset}" "${italic}" "${reset}"
}

_color() {
    if [[ -t 2 ]] && [[ -z "${no_color-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
        COLOROFF='\033[0m'
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        ORANGE='\033[0;33m'
        BLUE='\033[0;34m'
        PURPLE='\033[0;35m'
        CYAN='\033[0;36m'
        YELLOW='\033[1;33m'
    else
        COLOROFF='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
    fi
}

_msg() {
    echo >&2 -e "${1-}"
}

_log() {
    if [[ -n "${me_log-}" ]]; then
        echo "[$(${CMD_DATE} +%Y%m%d-%T)], $*" >>"$me_log"
    fi
}

_die() {
    local msg=$1
    local code=${2-1}
    _msg "$msg"
    exit "$code"
}

_get_confirm() {
    local confirm_choice
    read -rp "${1:-Do you want to proceed?} [y/N] " confirm_choice
    if [[ ${confirm_choice:-n} =~ ^[yY](es)?$ ]]; then
        return 0
    fi
    return 1
}

_parse_params() {
    local flag=0 param=''
    while :; do
        case "${1-}" in
            --no-color) no_color=1 ;;
            -h | --help) _usage ;;
            -f | --flag) flag=1 ;;
            -v | --verbose)
                set -x
                enable_log=1
                ;;
            -p | --param)
                [[ -z "${2-}" ]] && _die "Missing value for parameter: $1"
                param=$2
                shift
                ;;
            -?*) _die "Unknown option: $1" ;;
            *) break ;;
        esac
        shift
    done
    args=("$@")
    return 0
}

_usage() {
    cat <<EOF
Usage: ${me_name} [options] [Parameter]

Script description here.

Available options:

    -h, --help      Print this help and exit
    -v, --verbose   Print script debug info
    -f, --flag      Some flag description
    -p, --param     Some param description

Examples:
    $me_name -f -p param arg1 arg2
EOF
    exit 0
}

_myself() {
    me_name=$(basename "${BASH_SOURCE[0]}")
    me_path=$(dirname "$(${CMD_READLINK} -f "${BASH_SOURCE[0]}")")
    me_log="${me_path}/${me_name}.log"
    [[ ! -w "$me_path" ]] && me_log="/tmp/${me_name}.log"
    [[ "${enable_log-}" -eq 1 ]] && echo "Log file is \"$me_log\""
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

# Execute main function
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"