#!/usr/bin/env bash

# set -eu

## Removes old revisions of snaps
## CLOSE ALL SNAPS BEFORE RUNNING THIS
while read -r snapname revision; do
    sudo snap remove "$snapname" --revision="$revision"
done < <(LANG=en_US.UTF-8 snap list --all | awk '/disabled/{print $1, $3}')

## clean thinkphp runtime/log
while read -r line; do
    echo "$line"
    sudo rm -rf "$line"/log/*
    ## fix thinkphp runtime perm
    sudo chown -R 33:33 "$line"
done < <(find . -type d -iname runtime)

## clean mysql binary logs

## clean
