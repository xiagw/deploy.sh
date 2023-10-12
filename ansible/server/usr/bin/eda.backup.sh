#!/bin/bash

# set -xe
_get_time() {
    if [[ "$(uname)" == Darwin ]]; then
        gdate +%Y%m%d-%u-%H%M%S.%3N
    else
        date +%Y%m%d-%u-%H%M%S.%3N
    fi
}

if [[ $(id -u) -ne 0 ]]; then
    echo "Need root. exit."
    exit 1
fi
me_name="$(basename "$0")"
me_path="$(dirname "$(readlink -f "$0")")"
me_log="${me_path}/${me_name}.log"

rsync_opt=(
    rsync
    -az
    --backup
    --suffix=".$(_get_time)"
    --exclude={'.swp','*.log','CDS.log*','*panic.log*','matlab_crash_dump.*'}
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
    ## pull files from SERVERS, run on NAS
    for svr in "${dest_servers[@]}"; do
        for dir in "${src_dirs[@]}"; do
            ssh "$svr" "test -d $dir" || continue
            echo "$(_get_time)  sync $dir" >>"$me_log"
            "${rsync_opt[@]}" "$svr:$dir"/ "$dest_dir$dir"/
        done
    done
    ;;
push)
    ## push to NAS, run on SERVERS
    rsync_opt+=(--rsync-path=/bin/rsync)
    for dir in "${src_dirs[@]}"; do
        test -d "$dir" || continue
        echo "$(_get_time)  sync $dir" >>"$me_log"
        "${rsync_opt[@]}" "$dir"/ "$host_nas:$dest_dir$dir"/
    done
    ;;
*)
    echo "$0  pull      pull files from SERVERS, run on NAS"
    echo "$0  push      push files to NAS, run on SERVERS"
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
