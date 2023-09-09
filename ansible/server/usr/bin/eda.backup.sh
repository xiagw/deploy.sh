#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "Need root. exit."
    exit 1
fi
# set -xe
me_name="$(basename "$0")"
me_path="$(dirname "$(readlink -f "$0")")"
me_log="${me_path}/${me_name}.log"

rsync_opt=(
    -az
    --backup
    --suffix=".$(date +%Y%m%d-%u-%H%M%S.%3N)"
    --exclude='.swp'
    --exclude='*.log'
    --exclude='CDS.log*'
    --exclude='*panic.log*'
    --exclude='matlab_crash_dump.*'
    )

rsync_exclude=$me_path/rsync.exclude.conf
rsync_include=$me_path/rsync.include.conf
[ -f "$rsync_exclude" ] && rsync_opt+=(--exclude-from="$rsync_exclude")
[ -f "$rsync_include" ] && rsync_opt+=(--files-from="$rsync_include")

src_dirs=(
    /eda
    /home2
)
dest_servers=(
    node11
)
dest_dir='/volume1/nas1/backup'
host_nas=nas

case "$1" in
pull)
    ## run on NAS and pull from SERVERS
    for s in "${dest_servers[@]}"; do
        for d in "${src_dirs[@]}"; do
            ssh "$s" "test -d $d" || continue
            echo "$(date +%Y%m%d-%u-%H%M%S.%3N)  sync $d" >>"$me_log"
            rsync ${rsync_opt[*]} "$s:$d"/ "$dest_dir$d"/
        done
    done
    ;;
push)
    ## run on SERVERS and push to NAS
    rsync_opt+=(--rsync-path=/bin/rsync)
    for d in "${src_dirs[@]}"; do
        test -d "$d" || continue
        echo "$(date +%Y%m%d-%u-%H%M%S.%3N)  sync $d" >>"$me_log"
        rsync ${rsync_opt[*]} "$d"/ "$host_nas:$dest_dir$d"/
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
