#!/usr/bin/env bash

_backup_zfs() {
    date
    zfs_src=zfs01/share
    zfs_dest=zfs02/share
    zfs list -t snapshot
    snapshot_date="$(date +%s)"
    if zfs list -t snapshot -o name -s creation -H -r ${zfs_src} | grep -q "${zfs_src}@now$"; then
        if zfs list -t snapshot -o name -s creation -H -r ${zfs_src} | grep -q "${zfs_src}@last$"; then
            zfs rename ${zfs_src}@last "${zfs_src}@${snapshot_date}"
        fi
        zfs rename ${zfs_src}@now ${zfs_src}@last
    fi
    if zfs list -t snapshot -o name -s creation -H -r ${zfs_dest} | grep -q "${zfs_dest}@now$"; then
        if zfs list -t snapshot -o name -s creation -H -r ${zfs_dest} | grep -q "${zfs_dest}@last$"; then
            zfs rename ${zfs_dest}@last "${zfs_dest}@${snapshot_date}"
        fi
        zfs rename ${zfs_dest}@now ${zfs_dest}@last
    fi

    zfs snapshot ${zfs_src}@now

    if zfs list -t snapshot -o name -s creation -H -r ${zfs_src} | grep -q "${zfs_src}@last$"; then
        if command -v pv >/dev/null 2>&1; then
            zfs send -i ${zfs_src}@last ${zfs_src}@now | pv | zfs recv ${zfs_dest}
        else
            zfs send -i ${zfs_src}@last ${zfs_src}@now | zfs recv ${zfs_dest}
        fi
    else
        ## full backup
        zfs snapshot ${zfs_src}@last
        if command -v pv >/dev/null 2>&1; then
            zfs send ${zfs_src}@last | pv | zfs recv ${zfs_dest}
        else
            zfs send ${zfs_src}@last | zfs recv ${zfs_dest}
        fi
    fi
    ## clear snapshot
    zfs destroy "${zfs_src}@${snapshot_date}"
    zfs destroy "${zfs_dest}@${snapshot_date}"
    date
}

set -e

_backup_zfs
