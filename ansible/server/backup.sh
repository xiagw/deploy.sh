#!/bin/bash

# set -xe
me_name="$(basename "$0")"
me_path="$(dirname "$(readlink -f "$0")")"
me_log="${me_path}/${me_name}.log"

dirs=(
    /eda
    /home2
)

# rsync_opt="rsync -az --rsync-path=/bin/rsync"
rsync_opt="rsync -az"
rsync_exclude=$me_path/rsync.exclude.conf
rsync_include=$me_path/rsync.include.conf
rsync_src_host=node11
rsync_dest='/volume1/backup'

if [ -f "$rsync_exclude" ]; then
    rsync_opt="$rsync_opt --exclude-from=$rsync_exclude"
fi
if [ -f "$rsync_include" ]; then
    rsync_opt="$rsync_opt --files-from=$rsync_include"
fi

for dir in "${dirs[@]}"; do
    echo "$(date), $dir" >>"$me_log"
    $rsync_opt $rsync_src_host:"$dir"/ $rsync_dest"$dir"/
done
