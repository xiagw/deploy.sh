#!/bin/bash

# set -xe
me_name="$(basename "$0")"
me_path="$(dirname "$(readlink -f "$0")")"
me_log="${me_path}/${me_name}.log"

dirs=(
    /eda
    /home2
)
servers=(
    node11
)
# rsync_opt="rsync -az --rsync-path=/bin/rsync"
rsync_opt="rsync -az"
rsync_exclude=$me_path/rsync.exclude.conf
rsync_include=$me_path/rsync.include.conf
rsync_dest='/volume1/nas1/backup'
host_nas=nas

if [ -f "$rsync_exclude" ]; then
    rsync_opt="$rsync_opt --exclude-from=$rsync_exclude"
fi
if [ -f "$rsync_include" ]; then
    rsync_opt="$rsync_opt --files-from=$rsync_include"
fi

case "$1" in
pull)
    ## pull from servers
    for s in "${servers[@]}"; do
        for d in "${dirs[@]}"; do
            ssh "$s" "test -d $d" || continue
            echo "$(date +%Y%m%d-%u-%T.%3N), sync $d" >>"$me_log"
            $rsync_opt "$s:$d"/ "$rsync_dest$d"/
        done
    done
    ;;
push)
    ## push to nas
    for d in "${dirs[@]}"; do
        test -d "$d" || continue
        echo "$(date +%Y%m%d-%u-%T.%3N), sync $d" >>"$me_log"
        $rsync_opt --rsync-path=/bin/rsync "$d"/ "$host_nas:$rsync_dest$d"/
    done
    ;;
*)
    echo "$0  pull, run on NAS and pull files from SERVERS."
    echo "$0  push, run on SERVERS and push files to NAS."
    ;;
esac

# threads=24
# src=/src2/
# dest=/dest2/
# rsync -aL -f"+ */" -f"- *" $src $dest &&
#     (
#         cd $src || exit 1
#         find . -type f -print0 | xargs -0 -n1 -P$threads -I% rsync -az % $dest/%
#     )
