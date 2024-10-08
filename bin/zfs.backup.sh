#!/usr/bin/env bash

_backup_zfs() {
    date +%Y%m%d-%u-%T.%3N
    local zfs_src="${1:-zfs01/share}"
    local zfs_dest="${2:-zfs02/share}"
    local snap
    snap="$(date +%s)"
    zfs list -t snapshot

    if zfs list -t snapshot -o name -s creation -H -r "${zfs_src}@now"; then
        if zfs list -t snapshot -o name -s creation -H -r "${zfs_src}@last"; then
            zfs rename "${zfs_src}@last" "${zfs_src}@${snap}"
        fi
        zfs rename "${zfs_src}@now" "${zfs_src}@last"
    fi
    if zfs list -t snapshot -o name -s creation -H -r "${zfs_dest}@now"; then
        if zfs list -t snapshot -o name -s creation -H -r "${zfs_dest}@last"; then
            zfs rename "${zfs_dest}@last" "${zfs_dest}@${snap}"
        fi
        zfs rename "${zfs_dest}@now" "${zfs_dest}@last"
    fi

    zfs snapshot "${zfs_src}@now"

    if command -v pv >/dev/null 2>&1; then
        local has_pv=1
    fi
    if zfs list -t snapshot -o name -s creation -H -r "${zfs_src}@last"; then
        if [[ "$has_pv" -eq 1 ]]; then
            zfs send -v -i "${zfs_src}@last" "${zfs_src}@now" | pv | zfs recv "${zfs_dest}"
        else
            zfs send -v -i "${zfs_src}@last" "${zfs_src}@now" | zfs recv "${zfs_dest}"
        fi
    else
        ## full backup
        zfs snapshot "${zfs_src}@last"
        if [[ "$has_pv" -eq 1 ]]; then
            zfs send -v "${zfs_src}@last" | pv | zfs recv "${zfs_dest}"
        else
            zfs send -v "${zfs_src}@last" | zfs recv "${zfs_dest}"
        fi
    fi
    ## clear snapshot
    zfs destroy "${zfs_src}@${snap}"
    zfs destroy "${zfs_dest}@${snap}"
    date +%Y%m%d-%u-%T.%3N
}

set -e

_backup_zfs "$@"
