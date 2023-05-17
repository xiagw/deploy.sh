#!/usr/bin/bash

_log() {
    echo "[$(date +%F_%T)], $*" >>"$me_log"
}

_poweroff() {
    if [[ ${debug_mod:-0} == 1 ]]; then
        echo "[+] poweroff"
    else
        sudo poweroff
    fi
}

main() {
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="${me_path}/${me_name}.log"

    if [[ "$1" == 'debug' || "$1" == d ]]; then
        debug_mod=1
        play_minutes=1
        rest_minutes=2
    else
        play_minutes=40
        rest_minutes=120
    fi
    file_play="$me_path/${me_name}.$play_minutes"
    file_rest="$me_path/${me_name}.$rest_minutes"
    file_disable="$me_path/${me_name}.disable"

    ## manual cancel
    if [[ "$1" == c || -f $file_disable ]]; then
        rm -f "$file_rest" "$file_play"
        return
    fi
    ## study mode, program with vscode, but no minecraft
    if pgrep code >/dev/null 2>&1 && ! pgrep -f HMCL &>/dev/null; then
        [[ ${debug_mod:-0} == 1 ]] || return
    fi
    ## homework mode, week 1-4, after 19:10, always shut
    if (($(date +%u) < 5)) && (($(date +%H%M) > 1910)); then
        _poweroff
        [[ ${debug_mod:-0} == 1 ]] || return
    fi
    ## rest
    if [[ -f "$file_rest" ]]; then
        time_file_rest="$(stat -t -c %Y "$file_rest")"
        if [[ $(date +%s -d "$rest_minutes minutes ago") -gt "$time_file_rest" ]]; then
            rm -f "$file_rest" "$file_play"
        else
            _poweroff
            return
        fi
    fi
    ## play
    if [[ -f "$file_play" ]]; then
        time_file_play="$(stat -t -c %Y "$file_play")"
        if [[ $(date +%s -d "$rest_minutes minutes ago") -gt "$time_file_play" ]]; then
            touch "$file_play"
            return
        fi
        if [[ $(date +%s -d "$play_minutes minutes ago") -gt "$time_file_play" ]]; then
            touch "$file_rest"
            _poweroff
        fi
    else
        touch "$file_play"
    fi
}

main "$@"
