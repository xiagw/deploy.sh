#!/usr/bin/env bash

# set -eu

## Removes old revisions of snaps
## CLOSE ALL SNAPS BEFORE RUNNING THIS
LANG=en_US.UTF-8 snap list --all | awk '/disabled/{print $1, $3}' |
    while read -r snapname revision; do
        sudo snap remove "$snapname" --revision="$revision"
    done

## clean thinkphp runtime/log

## clean mysql binary logs

## clean