#!/usr/bin/env bash

# set -eu

## Removes old revisions of snaps
## CLOSE ALL SNAPS BEFORE RUNNING THIS
LANG=en_US.UTF-8 snap list --all | awk '/disabled/{print $1, $3}' |
    while read -r snapname revision; do
        sudo snap remove "$snapname" --revision="$revision"
    done

## clean thinkphp runtime/log
find . -type d -iname runtime |
    while read -r line; do
        echo "$line"
        sudo rm -rf "$line"/log/*
        ## fix thinkphp runtime perm
        sudo chown -R 33:33 "$line"
    done

## clean mysql binary logs

## clean
